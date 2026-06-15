#!/bin/bash
# migrate_opsi_depot_v7.sh: OPSI depot migration and optimization script.
# This script formats a new drive with XFS, enables deduplication,
# migrates the existing OPSI depot, and sets up a scheduled dedup job.
# The migration process is resumable and space-efficient by deleting after each copy.
#
# USAGE:
#   Automatic detection: sudo ./migrate_opsi_depot_v7.sh [--dry-run] [--checksum]
#   Manual target disk:  sudo ./migrate_opsi_depot_v7.sh /dev/sdX [--dry-run]
#   Manual target part:  sudo ./migrate_opsi_depot_v7.sh /dev/sdX1 [--dry-run]
#
# PARAMETERS:
#   /dev/sdX    : (Optional) Path to the target device (disk or partition).
#   --dry-run   : Simulate all actions without making any changes.
#   --checksum  : Use rsync's slower but more thorough checksum verification.

# --- Configuration Variables ---
OPSI_DEPOT_PATH="/var/lib/opsi/depot"
TEMP_MOUNT_PATH="/mnt/opsi_new_depot"
FSTAB_BACKUP="/etc/fstab.backup.$(date +%F-%H%M%S)"

# --- Script Header and Color Definitions ---
trap 'error_handler' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Functions ---

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNUNG]${NC} $1"; }
log_error() { echo -e "${RED}[FEHLER]${NC} $1"; }

error_handler() {
    log_error "Ein unerwarteter Fehler ist in Zeile $LINENO aufgetreten."
    log_error "Die Ausführung des Skripts wurde angehalten."
    read -p "Drücken Sie [Enter] zum Beenden oder geben Sie 'debug' für eine Shell ein..." response
    if [[ "$response" == "debug" ]]; then
        bash
    fi
    exit 1
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Dieses Skript muss mit root-Rechten (sudo) ausgeführt werden."
        exit 1
    fi
}

confirm() {
    while true; do
        read -p "$(echo -e "${YELLOW}[BESTÄTIGUNG]${NC} $1 [j/n]: ")" jn
        case $jn in
            [Jj]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Bitte antworten Sie mit Ja oder Nein.";;
        esac
    done
}

# --- Main Script Logic ---

# 1. Parameter Parsing
DRY_RUN=0
USE_CHECKSUM=0
TARGET_DEVICE=""
while (( "$#" )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --checksum)
      USE_CHECKSUM=1
      shift
      ;;
    /dev/*)
      if [ -b "$1" ]; then
        TARGET_DEVICE=$1
      else
        log_error "Das angegebene Gerät '$1' ist kein gültiges Blockgerät."
        exit 1
      fi
      shift
      ;;
    *) # ignore unknown arguments
      shift
      ;;
  esac
done

if [ $DRY_RUN -eq 1 ]; then
    log_warn "Dry-Run Modus ist aktiviert. Es werden keine Änderungen vorgenommen."
fi

# 2. Initial Checks
check_root

log_info "Überprüfe auf benötigte Pakete..."
REQUIRED_PACKAGES=("gdisk" "xfsprogs" "rsync" "duperemove")
PACKAGES_TO_INSTALL=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    log_warn "Die folgenden Pakete fehlen: ${PACKAGES_TO_INSTALL[*]}"
    if confirm "Sollen diese jetzt installiert werden?"; then
        apt-get update && apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
    else
        log_error "Ohne die benötigten Pakete kann das Skript nicht fortfahren. Abbruch."
        exit 1
    fi
else
    log_info "Alle benötigten Pakete sind installiert."
fi

# 3. Select Target Drive
if [ -z "$TARGET_DEVICE" ]; then
    log_info "Kein Zielgerät angegeben. Suche nach unpartitionierten Laufwerken..."
    mapfile -t UNPARTITIONED_DRIVES < <(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}' | while read -r disk; do if ! sfdisk -l "$disk" 2>/dev/null | grep -q "^${disk}"; then echo "$disk"; fi; done)
    if [ ${#UNPARTITIONED_DRIVES[@]} -eq 0 ]; then
        log_error "Keine unpartitionierten Laufwerke gefunden. Bitte geben Sie ein Ziellaufwerk als Parameter an (z.B. /dev/sda)."
        exit 1
    fi
    echo "Bitte wählen Sie das Ziellaufwerk für das neue OPSI-Depot:"
    select TARGET_DEVICE in "${UNPARTITIONED_DRIVES[@]}"; do
        if [[ -n "$TARGET_DEVICE" ]]; then break; else echo "Ungültige Auswahl."; fi
    done
else
    log_info "Manuelles Zielgerät ausgewählt: $TARGET_DEVICE"
fi

# 4. Partition and Format Logic
SKIP_FORMATTING=0
PARTITION_NAME=""

# Determine the potential partition name to check
if [[ "$TARGET_DEVICE" =~ [0-9]$ || "$TARGET_DEVICE" =~ p[0-9]$ ]]; then
    PARTITION_NAME=$TARGET_DEVICE
else
    PARTITION_NAME="${TARGET_DEVICE}1"
    if [[ $TARGET_DEVICE == /dev/nvme* ]]; then PARTITION_NAME="${TARGET_DEVICE}p1"; fi
fi

# Check if the partition seems to be prepared already
if blkid -L OPSI_DEPOT "$PARTITION_NAME" &>/dev/null && blkid -s TYPE -o value "$PARTITION_NAME" 2>/dev/null | grep -q "xfs"; then
    log_warn "Das Gerät '$PARTITION_NAME' scheint bereits als OPSI-Depot formatiert zu sein."
    if confirm "Möchten Sie die Formatierung überspringen und direkt mit der Migration fortfahren?"; then
        SKIP_FORMATTING=1
        log_info "Formatierung wird übersprungen. Das Skript wird versuchen, die Migration fortzusetzen."
    else
        log_info "Der Benutzer hat entschieden, die Formatierung nicht zu überspringen."
    fi
fi

if [ $SKIP_FORMATTING -eq 0 ]; then
    IS_PARTITION=0
    if [[ "$TARGET_DEVICE" =~ [0-9]$ || "$TARGET_DEVICE" =~ p[0-9]$ ]]; then
        IS_PARTITION=1
        PARTITION_NAME=$TARGET_DEVICE
    fi

    if [ $IS_PARTITION -eq 0 ]; then
        if ! confirm "Sie haben eine ganze Festplatte ($TARGET_DEVICE) ausgewählt. ALLE DATEN werden GELÖSCHT. Fortfahren?"; then log_info "Vorgang abgebrochen."; exit 0; fi
        log_info "Partitioniere $TARGET_DEVICE..."
        if [ $DRY_RUN -eq 0 ]; then
            sgdisk --zap-all "$TARGET_DEVICE"; sgdisk --new=1:0:0 --typecode=1:8300 "$TARGET_DEVICE"; sleep 3
            PARTITION_NAME="${TARGET_DEVICE}1"
            if [[ $TARGET_DEVICE == /dev/nvme* ]]; then PARTITION_NAME="${TARGET_DEVICE}p1"; fi
        else
            log_warn "[DRY-RUN] Hätte $TARGET_DEVICE partitioniert."; PARTITION_NAME="${TARGET_DEVICE}1"
        fi
        log_info "Neue Partition: $PARTITION_NAME"
        log_info "Formatiere $PARTITION_NAME mit XFS..."
        if [ $DRY_RUN -eq 0 ]; then mkfs.xfs -f -L OPSI_DEPOT "$PARTITION_NAME"; else log_warn "[DRY-RUN] Hätte $PARTITION_NAME formatiert."; fi
    else
        if ! confirm "Sie haben eine Partition ($PARTITION_NAME) ausgewählt. ALLE DATEN darauf werden GELÖSCHT. Fortfahren?"; then log_info "Vorgang abgebrochen."; exit 0; fi
        log_info "Formatiere Partition $PARTITION_NAME mit XFS..."
        if [ $DRY_RUN -eq 0 ]; then mkfs.xfs -f -L OPSI_DEPOT "$PARTITION_NAME"; else log_warn "[DRY-RUN] Hätte $PARTITION_NAME formatiert."; fi
    fi
fi


# 5. Stop OPSI Services
log_info "Stoppe OPSI-Dienste..."
OPSI_SERVICES=("opsiconfd" "opsipxeconfd" "opsi-tftpd-hpa")
for service in "${OPSI_SERVICES[@]}"; do
    if systemctl is-active --quiet "$service"; then
        if [ $DRY_RUN -eq 0 ]; then systemctl stop "$service"; fi
        log_info "Dienst $service gestoppt."
    else
        log_warn "Dienst $service lief nicht."
    fi
done

# 6. Data Migration (Resumable and Space-Efficient)
log_info "Starte Datenmigration..."
if [ $DRY_RUN -eq 0 ]; then
    mkdir -p "$TEMP_MOUNT_PATH"
    if ! mountpoint -q "$TEMP_MOUNT_PATH"; then
      mount "$PARTITION_NAME" "$TEMP_MOUNT_PATH"
    fi
else
    log_warn "[DRY-RUN] Hätte $TEMP_MOUNT_PATH erstellt und $PARTITION_NAME dort gemountet."
fi

if [ "$(ls -A $TEMP_MOUNT_PATH 2>/dev/null)" ]; then
    log_warn "Bestehende Daten im temporären Ziel gefunden. Eine frühere Migration wurde möglicherweise unterbrochen."
    if ! confirm "Möchten Sie versuchen, die Migration fortzusetzen?"; then
        log_info "Vorgang abgebrochen."
        if [ $DRY_RUN -eq 0 ]; then umount "$TEMP_MOUNT_PATH"; rmdir "$TEMP_MOUNT_PATH"; fi
        exit 0
    fi
    log_info "Setze Migration fort..."
fi

rsync_opts=('-a' '--info=progress2')
if [ $USE_CHECKSUM -eq 1 ]; then
    log_info "Verwende rsync mit CHECKSUM-Verifizierung (langsamer, aber gründlicher)."
    rsync_opts+=('--checksum')
else
    log_info "Verwende rsync mit Standard Zeit/Größen-Prüfung (schneller)."
fi

log_info "Starte Kopiervorgang: Kopieren, Deduplizieren und sofortiges Löschen der Quelle..."
find "$OPSI_DEPOT_PATH" -mindepth 1 -maxdepth 1 -print0 | while IFS= read -r -d '' item; do
    item_name=$(basename "$item")
    log_info "--> Verarbeite: $item_name"
    if [ $DRY_RUN -eq 0 ]; then
        # Schritt 1: Kopiere das Element
        rsync "${rsync_opts[@]}" "$item" "$TEMP_MOUNT_PATH/"
        log_info "    Kopieren für $item_name erfolgreich."

        # Schritt 2: Dedupliziere das neue Element
        log_info "    Führe Deduplizierung für '$TEMP_MOUNT_PATH/$item_name' aus..."
        duperemove -hdr --hashfile=/tmp/opsi_dedup.hash "$TEMP_MOUNT_PATH/$item_name"

        # Schritt 3: Lösche das Original, um Platz freizugeben
        log_info "    Lösche Original '$item' um Platz freizugeben..."
        rm -rf "$item"
        log_info "    Original '$item_name' gelöscht."
    else
        log_warn "[DRY-RUN] Hätte '$item_name' kopiert, dedupliziert und das Original gelöscht."
    fi
done

log_info "Datenmigration abgeschlossen."


# 7. Unmount Temp and Configure fstab
if [ $DRY_RUN -eq 0 ]; then
    # Only unmount if it's actually mounted
    if mountpoint -q "$TEMP_MOUNT_PATH"; then
        umount "$TEMP_MOUNT_PATH"
        rmdir "$TEMP_MOUNT_PATH"
        log_info "Temporärer Mount-Punkt bereinigt."
    fi
else
    log_warn "[DRY-RUN] Hätte temporäres Verzeichnis ungemountet und entfernt."
fi

log_info "Konfiguriere /etc/fstab..."
PARTITION_UUID=$(blkid -s UUID -o value "$PARTITION_NAME" 2>/dev/null)
if [ -z "$PARTITION_UUID" ]; then
    log_error "Konnte die UUID für $PARTITION_NAME nicht ermitteln. Abbruch."
    exit 1
fi
FSTAB_ENTRY="UUID=$PARTITION_UUID  $OPSI_DEPOT_PATH  xfs  defaults  0  2"
if [ $DRY_RUN -eq 0 ]; then
    if findmnt -rno SOURCE "$OPSI_DEPOT_PATH"; then umount "$OPSI_DEPOT_PATH"; fi
    cp /etc/fstab "$FSTAB_BACKUP"
    log_info "Backup von /etc/fstab nach $FSTAB_BACKUP erstellt."
    # Prevent duplicate entries
    if ! grep -q "UUID=$PARTITION_UUID" /etc/fstab; then
        echo "$FSTAB_ENTRY" >> /etc/fstab
        log_info "Neuer Eintrag wurde zu /etc/fstab hinzugefügt."
    else
        log_warn "fstab-Eintrag für diese UUID existiert bereits. Nichts zu tun."
    fi
else
    log_warn "[DRY-RUN] Hätte folgende Zeile zu /etc/fstab hinzugefügt:"
    echo "    $FSTAB_ENTRY"
fi

# 8. Final Mount and Restart Services
log_info "Mounte das neue Depot-Laufwerk unter $OPSI_DEPOT_PATH..."
if [ $DRY_RUN -eq 0 ]; then mount -a; fi
log_info "Starte OPSI-Dienste neu..."
for service in "${OPSI_SERVICES[@]}"; do
    if [ $DRY_RUN -eq 0 ]; then systemctl start "$service"; fi
    log_info "Dienst $service gestartet."
done

# 9. Setup Scheduled Deduplication
log_info "Einrichtung der regelmäßigen Deduplizierung."
CRON_FILE="/etc/cron.d/opsi-dedup"
if confirm "Soll ein täglicher Cron-Job für die Deduplizierung um 20:00 Uhr eingerichtet werden?"; then
    if [ -f "$CRON_FILE" ]; then
        log_warn "Ein Cron-Job existiert bereits unter $CRON_FILE. Es werden keine Änderungen vorgenommen."
    else
        log_info "Erstelle Cron-Job für die tägliche Deduplizierung..."
        CRON_JOB="0 20 * * * root /usr/bin/duperemove -hdr --hashfile=/tmp/opsi_dedup.hash ${OPSI_DEPOT_PATH} &> /var/log/opsi_dedup.log"
        if [ $DRY_RUN -eq 0 ]; then
            echo "$CRON_JOB" > "$CRON_FILE"
            chmod 0644 "$CRON_FILE"
            log_info "Cron-Job wurde erfolgreich in $CRON_FILE erstellt."
        else
            log_warn "[DRY-RUN] Hätte den folgenden Cron-Job in $CRON_FILE erstellt:"
            echo "    $CRON_JOB"
        fi
    fi
fi

log_info "${GREEN}Migration abgeschlossen! Das OPSI-Depot läuft jetzt auf dem neuen XFS-Laufwerk.${NC}"
log_info "Bitte überprüfen Sie die Funktionalität aller OPSI-Dienste."
exit 0

