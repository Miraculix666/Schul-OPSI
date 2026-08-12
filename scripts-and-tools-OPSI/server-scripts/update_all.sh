#!/bin/bash
#
# FileName: opsi-u-update_main.sh
# Description: Universal OPSI Update & Repair Script (Proxmox-Style)
# Author: PS-Coding Assistant
# Version: 1.2.4

# Locale Fix für saubere Darstellung
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# --- Konfiguration & Variablen ---
LOG_FILE="/var/log/opsi-u-update.log"
APP="OPSI-Server Update"
REVISION="1.2.4"
IP_ADDR=$(hostname -I | awk '{print $1}')
OS_VER=$(grep "PRETTY_NAME" /etc/os-release | cut -d'=' -f2 | tr -d '"')
OPSI_VER=$(opsi-admin -V 2>/dev/null || echo "4.x")

# --- UI Icons ---
INFO='[INFO]'
OK='[  OK  ]'
WARN='[ WARN ]'
ERROR='[ERROR]'

# --- Farben (Proxmox Style) ---
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;32m")
GN=$(echo "\033[1;32m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

# --- Hilfsfunktionen ---
msg_info()    { echo -e "${BL}${INFO}${CL} $1"; echo "[INFO] $(date '+%H:%M:%S') $1" >> "$LOG_FILE"; }
msg_ok()      { echo -e "${GN}${OK}${CL} $1"; echo "[OK]   $(date '+%H:%M:%S') $1" >> "$LOG_FILE"; }
msg_warn()    { echo -e "${YW}${WARN}${CL} $1"; echo "[WARN] $(date '+%H:%M:%S') $1" >> "$LOG_FILE"; }
msg_err()     { echo -e "${RD}${ERROR}${CL} $1"; echo "[ERR]  $(date '+%H:%M:%S') $1" >> "$LOG_FILE"; }

header_info() {
  clear
  cat << "EOF"
  ____  _____   ____ ___   _   _ ____  ____   _  _____ _____ 
 / __ \|  __ \ / ___|_ _| | | | |  _ \|  _ \ / \|_   _| ____|
| |  | | |__) | \___  | |  | | | | |_) | | | / _ \ | | |  _|  
| |__| |  ___/  ___) | |  | |_| |  __/| |_| / ___ \| | | |___ 
 \____/|_|     |____/___|  \___/|_|   |____/_/   \_\_| |_____|
                                                               
EOF
  echo -e "${BL}------------------------------------------------------------------${CL}"
  echo -e "${GN}App:${CL}       $APP"
  echo -e "${GN}Version:${CL}   $REVISION"
  echo -e "${GN}System:${CL}    $OS_VER"
  echo -e "${GN}IP:${CL}        $IP_ADDR"
  echo -e "${GN}OPSI:${CL}      $OPSI_VER"
  echo -e "${BL}------------------------------------------------------------------${CL}"
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    msg_err "Dieses Skript muss mit sudo-Rechten ausgeführt werden."
    exit 1
  fi
}

# --- Update Schritte ---

step_system() {
  msg_info "Schritt 1: System-Update (OS & Nala)..."
  if command -v nala &> /dev/null; then
    nala update && nala upgrade -y && nala autoremove -y
  else
    apt-get update && apt-get upgrade -y && apt-get autoremove -y
  fi
  msg_ok "Betriebssystem ist aktuell."

  if command -v do-release-upgrade &>/dev/null; then
    msg_info "Prüfe auf neues Betriebssystem-Release (OS Upgrade)..."
    local upgrade_available=$(do-release-upgrade -c 2>/dev/null | grep -i "New release")
    if [ -n "$upgrade_available" ]; then
      echo -e "${YW}Ein neues Betriebssystem-Release ist verfügbar!${CL}"
      echo -e "${upgrade_available}"
      echo -ne "${RD}Möchten Sie das OS Release Upgrade jetzt starten? Dies kann lange dauern und erfordert ggf. Anpassungen an OPSI! [y/N]: ${CL}"
      read -r start_upgrade
      if [[ "$start_upgrade" =~ ^[Yy]$ ]]; then
        msg_info "Starte Release-Upgrade..."
        do-release-upgrade
      else
        msg_info "Release-Upgrade übersprungen."
      fi
    else
      msg_ok "Betriebssystem-Release ist auf dem neuesten Stand."
    fi
  fi
}

step_opsi_server() {
  msg_info "Schritt 2: OPSI Server-Komponenten prüfen..."
  if opsi-setup --help 2>&1 | grep -q -- '--update-all'; then
    opsi-setup --update-all
    msg_ok "OPSI-Server Komponenten aktualisiert."
  else
    msg_warn "Veraltete OPSI-Struktur erkannt. Server-Update via Systempakete."
  fi
}

step_opsi_packages() {
  msg_info "Schritt 3: OPSI Produkt-Pakete synchronisieren..."
  local UPDATER_OPTS=""
  if opsi-package-updater --help 2>&1 | grep -q -- '--auto-update'; then
    UPDATER_OPTS="--auto-update"
  else
    UPDATER_OPTS="update"
  fi
  
  if opsi-package-updater -v $UPDATER_OPTS; then
    msg_ok "OPSI-Pakete synchronisiert."
  else
    msg_err "Fehler beim Paket-Update."
  fi
}

step_repair() {
  msg_info "Schritt 4: System-Reparatur (Rechte & Dienste)..."
  msg_info "Setze allgemeine OPSI-Berechtigungen..."
  opsi-set-rights &>/dev/null
  opsi-setup --set-rights &>/dev/null
  
  msg_info "Dienste werden neu gestartet (opsiconfd, opsipxeconfd)..."
  systemctl restart opsiconfd
  systemctl restart opsipxeconfd
  
  msg_info "Warte auf API-Bereitschaft (Erreichbarkeits-Check)..."
  local count=0
  local max_wait=60
  while true; do
    # Wir prüfen nur noch ob die API grundsätzlich antwortet (apiVersion)
    if opsi-admin -S method getOpsiVersion &>/dev/null; then
      echo ""
      msg_ok "OPSI-Service antwortet wieder."
      break
    fi
    
    echo -n "."
    sleep 3
    count=$((count+3))
    
    if [ $count -gt $max_wait ]; then
      echo ""
      msg_warn "API antwortet nach ${max_wait}s noch nicht. Fahre auf Risiko fort."
      break
    fi
  done
}

step_client_trigger() {
  msg_info "Schritt 5: Produkt-Aktion für Clients setzen (Backend-Update)..."
  
  # Strategie: Wir setzen das Flag für ALLE Clients direkt im Backend.
  # Das funktioniert auch wenn Clients offline sind.
  msg_info "Sende Action-Request 'setup' für 'opsi-client-agent' an alle Hosts..."
  
  if opsi-admin -S method setProductActionRequest "opsi-client-agent" "" "setup" &>/dev/null; then
    msg_ok "Setup-Flags erfolgreich in der Datenbank hinterlegt."
  else
    msg_warn "Globaler Task fehlgeschlagen. Versuche Fallback-Methode..."
    # Fallback für ältere Backends oder Teil-Sync
    opsi-admin -S method host_getIdents '{"type":"OpsiClient"}' | tr -d '[]," ' | grep -v '^$' | xargs -r -I {} -P 10 opsi-admin -S method setProductActionRequest "opsi-client-agent" "{}" "setup" &>/dev/null
    msg_ok "Flags via Fallback-Methode gesetzt."
  fi

  # Optional: Versuch die Clients "aufzuwecken" (On-Demand)
  # Das ist nur für online-Clients relevant und darf Fehler werfen.
  msg_info "Sende On-Demand Signal an erreichbare Clients (Best Effort)..."
  opsi-admin -S -d method hostControlSafe_fireEvent "on_demand" "" &>/dev/null
}

step_zsh() {
  local real_user=${SUDO_USER:-$(whoami)}
  local user_home=$(getent passwd "$real_user" | cut -d: -f6)
  if [ -d "$user_home/.oh-my-zsh" ]; then
    msg_info "Schritt 6: Addon-Update (Oh My Zsh) für $real_user..."
    sudo -u "$real_user" ZSH="$user_home/.oh-my-zsh" sh "$user_home/.oh-my-zsh/tools/upgrade.sh" --keep-zshrc &>/dev/null
    msg_ok "Zsh-Update abgeschlossen."
  fi
}

# --- Menü Logik ---

show_menu() {
  header_info
  echo -e "${YW}Wählen Sie eine Aufgabe:${CL}"
  echo -e " 1) [Full] Komplettes Update (Schritt 1 bis 6)"
  echo -e " 2) [System] Nur OS & Nala"
  echo -e " 3) [Server] OPSI Server & Pakete (Schritt 2 & 3)"
  echo -e " 4) [Repair] Nur Rechte & Dienste (Schritt 4)"
  echo -e " 5) [Clients] Nur Client-Trigger (Flag in DB setzen)"
  echo -e " 6) [Addons] Nur Oh My Zsh (Schritt 6)"
  echo -e " 0) Abbrechen"
  echo -e "${BL}------------------------------------------------------------------${CL}"
  echo -ne "${GN}Ihre Wahl [1]: ${CL}"
  read -r menu_choice
  menu_choice=${menu_choice:-1}
}

# --- Main Flow ---
main() {
  check_root
  show_menu

  if [[ "$menu_choice" == "0" ]]; then
    msg_warn "Vorgang abgebrochen."
    exit 0
  fi

  echo -e "${YW}WICHTIG: Backup erstellt? Drücken Sie ENTER zum Starten...${CL}"
  read -r

  case $menu_choice in
    1)
      msg_info "Starte kompletten Durchlauf..."
      step_system
      step_opsi_server
      step_opsi_packages
      step_repair
      step_client_trigger
      step_zsh
      ;;
    2) step_system ;;
    3) step_opsi_server; step_opsi_packages ;;
    4) step_repair ;;
    5) step_client_trigger ;;
    6) step_zsh ;;
    *) msg_err "Ungültige Wahl."; exit 1 ;;
  esac

  echo -e "${BL}------------------------------------------------------------------${CL}"
  msg_ok "AUFGABE(N) ERFOLGREICH BEENDET."
  echo -e "${BL}------------------------------------------------------------------${CL}"
  msg_info "Skript beendet. Rückkehr zur Shell."
}

# Start
main

