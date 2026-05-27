#!/bin/bash
# Filename: register_custom_package.sh
# SINN: Tteck-Style Automatisierung zum Packen und Installieren von OPSI-Paketen.
# OPTIMIERUNG: Behebt den Hangup bei der Depot-Validierung.

set -e

# --- Farben & Style ---
INFO='\033[0;36m'
OK='\033[0;32m'
ERR='\033[0;31m'
WARN='\033[1;33m'
NC='\033[0m'

echo -e "${INFO}------------------------------------------------------------------${NC}"
echo -e "?? OPSI Package Manager & Hardening Suite V8.4.1"
echo -e "${INFO}------------------------------------------------------------------${NC}"

# Root Check
[ "$EUID" -ne 0 ] && { echo -e "${ERR}[ERROR]${NC} Dieses Skript benötigt Root-Rechte (sudo)."; exit 1; }

# Ziel-Ermittlung
TARGET=${1:-"win11-hardening"}
BASE_DIR="/var/lib/opsi/depot"

if [ -f "OPSI/control" ]; then PKG_DIR=$(pwd)
elif [ -f "$BASE_DIR/$TARGET/OPSI/control" ]; then PKG_DIR="$BASE_DIR/$TARGET"
else echo -e "${ERR}[ERROR]${NC} Paket '$TARGET' nicht gefunden (Pfad: $BASE_DIR/$TARGET/OPSI/control fehlt)."; exit 1; fi

cd "$PKG_DIR"
echo -e "${INFO}[INFO]${NC} Verarbeite Paket in: $PKG_DIR"

# Step 1: Rechte (Essenziell)
echo -n -e "Step 1: Setze OPSI-Berechtigungen... "
opsi-set-rights . >/dev/null 2>&1
echo -e "${OK}[ OK ]${NC}"

# Step 2: Depot-Validierung (Optimiert gegen Hangups)
# Wir führen dies nur aus, wenn es explizit gewünscht ist oder nutzen einen schnellen Check.
echo -n -e "Step 2: Prüfe Depot-Konfiguration... "
if opsi-admin -d method getDepotIds_list | grep -q "$(hostname -f)" >/dev/null 2>&1; then
    echo -e "${OK}[ BEREITS REGISTRIERT ]${NC}"
else
    echo -e "${WARN}[ REGISTERING... ]${NC}"
    opsiconfd setup --non-interactive --register-depot >/dev/null 2>&1 || true
fi

# Step 3: Packen
echo -n -e "Step 3: Paket bereinigen & packen... "
rm -f *.opsi *.md5 *.zsync
opsi-makepackage >/dev/null
echo -e "${OK}[ OK ]${NC}"

# Step 4: Installation
echo -e "Step 4: Installiere Paket am lokalen Depot..."
PACKAGE_FILE=$(ls *.opsi | head -n 1)
if [ -n "$PACKAGE_FILE" ]; then
    opsi-package-manager -i "$PACKAGE_FILE"
    echo -e "${INFO}------------------------------------------------------------------${NC}"
    echo -e "${OK}? ERFOLGREICH: $PACKAGE_FILE ist nun im opsi-configed verfügbar.${NC}"
else
    echo -e "${ERR}[ERROR]${NC} Keine .opsi Datei gefunden."
    exit 1
fi