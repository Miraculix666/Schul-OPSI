#!/bin/bash
#
# Script to set OPSI Package Properties to Hardening Defaults
# Sets telemetry to off, language to de-DE, and unattended mode.

echo "[INFO] Setze globale OPSI Properties für Hardening & Unattended..."

# Funktion zum sicheren Setzen von Properties (ignoriert Fehler wenn das Paket/die Property nicht existiert)
set_property() {
    local product=$1
    local prop=$2
    local val=$3
    echo -n " -> $product: $prop = $val ... "
    # OPSI 4.2/4.3 Syntax
    if opsi-admin -S method setProductProperty_hash "$product" "$prop" "$val" &>/dev/null; then
        echo "[OK]"
    else
        echo "[SKIPPED/NOT FOUND]"
    fi
}

# Windows 11 Paket (win11-x64)
set_property "win11-x64" "imagename" "Windows 11 Enterprise LTSC 2024"
set_property "win11-x64" "system_keyboard_layout" "0407:00000407"
set_property "win11-x64" "system_language" "de-DE"
set_property "win11-x64" "system_timezone" "W. Europe Standard Time"

# Standard Software Eigenschaften (falls im Repo/Paket vorhanden)
# Oft genutzt: telemetry, auto_update, desktop_icon
set_property "firefox" "telemetry" "false"
set_property "firefox" "desktop_icon" "false"

set_property "google-chrome" "telemetry" "false"
set_property "google-chrome" "desktop_icon" "false"

set_property "msoffice" "desktop_icon" "false"

# Client Agent Härtung (optional, z.B. kein Kiosk oder reduziertes Logging)
set_property "opsi-client-agent" "log_level" "4"

echo "[  OK  ] Alle anwendbaren Properties wurden gesetzt!"
