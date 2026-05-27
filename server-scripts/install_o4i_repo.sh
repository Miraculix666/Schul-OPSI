#!/bin/bash
#
# Script to install the o4i (DFN) Public Repository for OPSI
# This enables automatic updates for standard software (Firefox, Chrome, Java, etc.)

REPO_FILE="/etc/opsi/package-updater.repos.d/o4i_public.repo"

echo "[INFO] Erstelle o4i Public Repository Konfiguration..."

cat <<EOF | sudo tee "$REPO_FILE" > /dev/null
[repository_o4i_public]
active = true
baseUrl = https://repo.o4i.org/public
dirs = /
autoInstall = true
autoUpdate = true
autoSetup = false
onlyDownload = false
EOF

echo "[INFO] Setze Rechte für $REPO_FILE..."
sudo chmod 644 "$REPO_FILE"
sudo chown opsi:opsi "$REPO_FILE" 2>/dev/null || sudo chown opsiconfd:opsiadmin "$REPO_FILE" 2>/dev/null

echo "[INFO] Teste Verbindung zum o4i Repository..."
sudo opsi-package-updater -v list --updatable

echo "[  OK  ] Das o4i (DFN) Repository wurde erfolgreich eingerichtet!"
echo "[INFO] Du kannst nun Standard-Software installieren, z.B. mit:"
echo "       opsi-package-updater -v install firefox"
echo "       opsi-package-updater -v install google-chrome"
