#!/bin/bash
set -euo pipefail
LOG=/tmp/build_packages.log
exec > >(tee -a $LOG) 2>&1

echo "[INFO] === Build started $(date) ==="

# ──────────────────────────────────────────────
# Xournal++ Version + korrekter Dateiname von GitHub ermitteln
# ──────────────────────────────────────────────
echo "[INFO] Fetching Xournal++ release info..."
RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/xournalpp/xournalpp/releases/latest)
XVTAG=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
XVNUM=$(echo "$XVTAG" | sed 's/^v//')
# Hole den echten AMD64 Setup-Dateinamen
XURL=$(echo "$RELEASE_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
assets=[a['browser_download_url'] for a in data['assets'] if 'windows-setup-AMD64' in a['name']]
print(assets[0] if assets else '')
")
echo "[INFO] Xournal++ $XVTAG -> $XURL"

# ──────────────────────────────────────────────
# Xournal++ Workbench aufbauen
# ──────────────────────────────────────────────
XDIR=/var/lib/opsi/workbench/xournalpp
mkdir -p "$XDIR/OPSI" "$XDIR/CLIENT_DATA"

cat > "$XDIR/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: xournalpp
name: Xournal++
description: Handwriting note-taking software with PDF annotation support
advice:
version: ${XVNUM}
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
updateScript:
alwaysScript:
onceScript:
customScript:
userLoginScript:
EOF

cat > "$XDIR/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
requiredWinstVersion >= "4.12.0.16"
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\xournalpp-setup.exe"
Message "Installing Xournal++ ..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
"$Installer$" /S

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Setup failed with exit code " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

cat > "$XDIR/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $ExitCode$
Message "Uninstalling Xournal++ ..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
"%ProgramFiles%\Xournal++\uninstall.exe" /S

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Uninstall failed: " + $ExitCode$
    isFatalError "Uninstall failed"
endif
EOF

echo "[INFO] Downloading Xournal++ installer..."
wget -q --show-progress -O "$XDIR/CLIENT_DATA/xournalpp-setup.exe" "$XURL"
echo "[OK] Download: $(du -sh "$XDIR/CLIENT_DATA/xournalpp-setup.exe" | cut -f1)"

# ──────────────────────────────────────────────
# EuroOffice Paket-Skeleton
# ──────────────────────────────────────────────
EODIR=/var/lib/opsi/workbench/eurooffice
mkdir -p "$EODIR/OPSI" "$EODIR/CLIENT_DATA"

cat > "$EODIR/OPSI/control" <<'EOF'
[Package]
version: 1
depends:

[Product]
type: localboot
id: eurooffice
name: EuroOffice
description: EuroOffice - LibreOffice-based Office Suite. Place installer as CLIENT_DATA/eurooffice-setup.exe
advice: Download from https://github.com/Euro-Office/ and place eurooffice-setup.exe in CLIENT_DATA
version: 1.0
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
updateScript:
alwaysScript:
onceScript:
customScript:
userLoginScript:
EOF

cat > "$EODIR/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
requiredWinstVersion >= "4.12.0.16"
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\eurooffice-setup.exe"
Message "Installing EuroOffice ..."

if FileExists($Installer$)
    Winbatch_install
    Sub_check_exitcode
else
    LogError "Installer not found: " + $Installer$
    LogError "Place eurooffice-setup.exe in CLIENT_DATA on the OPSI depot."
    isFatalError "Installer missing"
endif

[Winbatch_install]
"$Installer$" /S /VERYSILENT /SUPPRESSMSGBOXES /NORESTART

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Setup failed with exit code " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

cat > "$EODIR/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $ExitCode$
Message "Uninstalling EuroOffice ..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
"%ProgramFiles%\EuroOffice\uninstall.exe" /S

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Uninstall failed: " + $ExitCode$
    isFatalError "Uninstall failed"
endif
EOF

# ──────────────────────────────────────────────
# Rechte, Pakete bauen und installieren
# ──────────────────────────────────────────────
opsi-set-rights "$XDIR" 2>/dev/null || true
opsi-set-rights "$EODIR" 2>/dev/null || true

echo "[INFO] Building xournalpp..."
cd "$XDIR"
opsi-makepackage -q
XOPSI=$(ls *.opsi 2>/dev/null | head -1)
if [ -n "$XOPSI" ]; then
    opsi-package-manager -q -i "$XOPSI"
    echo "[OK] xournalpp installed: $XOPSI"
else
    echo "[ERR] No .opsi file found in $XDIR"
fi

echo "[INFO] Building eurooffice..."
cd "$EODIR"
opsi-makepackage -q
EOPSI=$(ls *.opsi 2>/dev/null | head -1)
if [ -n "$EOPSI" ]; then
    opsi-package-manager -q -i "$EOPSI"
    echo "[OK] eurooffice installed: $EOPSI"
else
    echo "[ERR] No .opsi file found in $EODIR"
fi

# ──────────────────────────────────────────────
# Office Beschreibung anpassen
# ──────────────────────────────────────────────
echo "[INFO] Updating msoffice2013 metadata..."
python3 - <<'PYEOF'
import json, subprocess
try:
    raw = subprocess.check_output(
        ['opsi-admin', '-S', 'method', 'product_getObjects', '', '{"id":"msoffice2013"}'],
        stderr=subprocess.DEVNULL
    )
    objs = json.loads(raw.decode())
    if objs:
        obj = objs[0]
        obj['name'] = 'MS OFFICE'
        obj['description'] = 'MS OFFICE'
        subprocess.check_call(
            ['opsi-admin', '-S', 'method', 'product_updateObject', json.dumps(obj)],
            stderr=subprocess.DEVNULL
        )
        print('[OK] msoffice2013 updated: name/description = "MS OFFICE"')
    else:
        print('[WARN] msoffice2013 not found in backend')
except Exception as e:
    print('[WARN]', e)
PYEOF

# ──────────────────────────────────────────────
# Win11 Dirs wiederherstellen
# ──────────────────────────────────────────────
DEPOT=/var/lib/opsi/depot/win11-x64
for subdir in custom installfiles; do
    if [ -d "${DEPOT}-backup-${subdir}" ]; then
        echo "[INFO] Restoring $subdir..."
        rm -rf "$DEPOT/$subdir"
        mv "${DEPOT}-backup-${subdir}" "$DEPOT/$subdir"
        echo "[OK] $subdir restored"
    fi
done

[ -f "$DEPOT/custom/unattend.xml" ] && echo "[OK] unattend.xml OK" || echo "[WARN] unattend.xml not found"
[ -f "$DEPOT/installfiles/sources/install.wim" ] && echo "[OK] install.wim found" || echo "[WARN] install.wim not found"

opsi-set-rights "$DEPOT" 2>/dev/null || true

echo ""
echo "=============================================="
echo "FERTIG: $(date)"
echo "  - xournalpp $XVNUM: gebaut und installiert"
echo "  - eurooffice 1.0: Skeleton gebaut (Installer fehlt noch)"
echo "  - msoffice2013: Name/Beschreibung aktualisiert"
echo "  - win11-x64: Verzeichnisse geprüft"
echo "=============================================="
