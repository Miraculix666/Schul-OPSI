#!/bin/bash
set -euo pipefail
LOG=/tmp/eurooffice_update.log
exec > >(tee -a $LOG) 2>&1

echo "[INFO] === EuroOffice (ONLYOFFICE) Update started $(date) ==="

# ONLYOFFICE URL
EURL="https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v9.3.1/DesktopEditors_x64.exe"
EVNUM="9.3.1"

# Workbench Verzeichnis
EODIR=/var/lib/opsi/workbench/eurooffice
mkdir -p "$EODIR/OPSI" "$EODIR/CLIENT_DATA"

cat > "$EODIR/OPSI/control" <<EOF
[Package]
version: 2
depends:

[Product]
type: localboot
id: eurooffice
name: ONLYOFFICE Desktop Editors
description: ONLYOFFICE Desktop Editors (formerly EuroOffice recommendation)
advice:
version: ${EVNUM}
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
Set $Installer$ = "%ScriptPath%\desktopeditors-setup.exe"

Message "Installing ONLYOFFICE Desktop Editors ..."

if FileExists($Installer$)
    Winbatch_install
    Sub_check_exitcode
else
    LogError "Installer not found: " + $Installer$
    isFatalError "Installer missing"
fi

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
Message "Uninstalling ONLYOFFICE Desktop Editors ..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
"%ProgramFiles%\ONLYOFFICE\DesktopEditors\uninstall.exe" /S

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Uninstall failed: " + $ExitCode$
    isFatalError "Uninstall failed"
endif
EOF

echo "[INFO] Downloading ONLYOFFICE installer..."
wget -q --show-progress -O "$EODIR/CLIENT_DATA/desktopeditors-setup.exe" "$EURL"
echo "[OK] Download complete: $(du -sh "$EODIR/CLIENT_DATA/desktopeditors-setup.exe" | cut -f1)"

# Rechte und Build
opsi-set-rights "$EODIR" 2>/dev/null || true

echo "[INFO] Building eurooffice package..."
cd "$EODIR"
opsi-makepackage -q
EOPSI=$(ls *.opsi 2>/dev/null | head -1)
if [ -n "$EOPSI" ]; then
    opsi-package-manager -q -i "$EOPSI"
    echo "[OK] eurooffice installed: $EOPSI"
else
    echo "[ERR] No .opsi file found in $EODIR"
fi

echo "DONE."
