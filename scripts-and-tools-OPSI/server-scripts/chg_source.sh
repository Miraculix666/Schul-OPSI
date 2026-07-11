#!/bin/bash

# --- Konfiguration ---
OPSI_REPO_URL="https://download.uib.de/opsi4.3/stable/products"
UBUNTU_VERSION="jammy"
SOURCES_FILE="/etc/apt/sources.list.d/opsi.list"
# --- Ende Konfiguration ---

echo "Starte Korrektur der OPSI Paketquellen für Ubuntu ${UBUNTU_VERSION}..."

# 1. Entferne alte OPSI-Quellen-Datei, falls vorhanden
if [ -f "$SOURCES_FILE" ]; then
    echo "Alte Quellen-Datei $SOURCES_FILE gefunden und wird entfernt."
    sudo rm -f "$SOURCES_FILE"
fi

# 2. Füge den offiziellen uib GPG Schlüssel hinzu (Wichtig für die Paket-Authentizität)
echo "Importiere uib GPG Schlüssel..."
if ! sudo wget -O /etc/apt/trusted.gpg.d/opsi.gpg https://download.uib.de/opsi_pub.key 2>/dev/null; then
    echo "FEHLER: Konnte den GPG Schlüssel nicht per wget herunterladen. Versuche per curl..."
    if ! sudo curl -sS https://download.uib.de/opsi_pub.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/opsi.gpg; then
        echo "FEHLER: Der Import des GPG-Schlüssels ist fehlgeschlagen. Bitte manuell prüfen."
        exit 1
    fi
fi
echo "GPG Schlüssel erfolgreich importiert."

# 3. Füge die offizielle OPSI-Quelle für Ubuntu Jammy hinzu
echo "Füge offizielle OPSI-Quelle für ${UBUNTU_VERSION} hinzu..."
sudo tee "$SOURCES_FILE" > /dev/null <<EOF
# OPSI-Repository von uib gmbh - stabil
deb [signed-by=/etc/apt/trusted.gpg.d/opsi.gpg] $OPSI_REPO_URL/stable/apt $UBUNTU_VERSION main
EOF

# 4. Aktualisiere die Paketlisten
echo "Aktualisiere die lokalen Paketlisten..."
sudo apt update

echo "✅ Korrektur abgeschlossen. Ihre OPSI-Quellen sind nun offiziell."
echo "Sie können nun 'sudo apt install opsi' oder 'sudo apt upgrade' verwenden, um Ihre OPSI-Pakete zu verwalten."
