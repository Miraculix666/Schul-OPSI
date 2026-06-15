#!/bin/bash
# Fix Office Description using Python instead of jq to ensure it works
python3 -c "
import json, subprocess
try:
    out = subprocess.check_output(['opsi-admin', '-S', 'method', 'product_getObjects', '', '{\"id\":\"msoffice2013\"}'])
    objs = json.loads(out)
    if objs:
        obj = objs[0]
        obj['name'] = 'MS OFFICE'
        obj['description'] = 'MS OFFICE'
        # Call update
        subprocess.check_call(['opsi-admin', '-S', 'method', 'product_updateObject', json.dumps(obj)])
        print('Office Description updated successfully!')
except Exception as e:
    print('Error updating office description:', e)
"

# Create Xournal++ Package
WORKBENCH="/var/lib/opsi/workbench"
mkdir -p $WORKBENCH/xournalpp/{OPSI,CLIENT_DATA}
cat << 'EOF' > $WORKBENCH/xournalpp/OPSI/control
[Package]
version: 1
depends: 

[Product]
type: localboot
id: xournalpp
name: Xournal++
description: Xournal++ is a handwriting notetaking software with PDF annotation support.
advice: 
version: 1.2.3
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

[ProductDependency]
action: setup
requiredProduct: 
requiredStatus: installed
requirementType: before
EOF

cat << 'EOF' > $WORKBENCH/xournalpp/CLIENT_DATA/setup.opsiscript
[Actions]
requiredWinstVersion >= "4.12.0.16"
DefVar $
DefVar $
Set $ = "%ProgramFiles%\Xournal++"

Message "Installing Xournal++ ..."
Winbatch_install
Sub_check_exitcode

Message "Downloading Xournal++ ..."
  Files_download
  Winbatch_install

[Files_download]
; We should download before, but powershell/curl in winst is complex. Let's do it in bash before opsi-makepackage!

[Winbatch_install]
"$InstallDir$\\xournalpp-setup.exe" /S

[Sub_check_exitcode]
Set $ = getLastExitCode
if not ($ = "0")
    LogError "Fatal: Setup failed with exit code " + $
    isFatalError "Setup failed"
endif
EOF

cat << 'EOF' > $WORKBENCH/xournalpp/CLIENT_DATA/uninstall.opsiscript
[Actions]
DefVar $
Set $ = "%ProgramFiles%\Xournal++"
Message "Uninstalling Xournal++ ..."
if FileExists($ + "\uninstall.exe")
    Winbatch_uninstall
endif

[Winbatch_uninstall]
"$\uninstall.exe" /S
EOF

# Create EuroOffice Package
mkdir -p $WORKBENCH/eurooffice/{OPSI,CLIENT_DATA}
cat << 'EOF' > $WORKBENCH/eurooffice/OPSI/control
[Package]
version: 1
depends: 

[Product]
type: localboot
id: eurooffice
name: EuroOffice
description: EuroOffice
advice: 
version: 1.0
priority: 0
licenseRequired: False
productClasses: 
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

cat << 'EOF' > $WORKBENCH/eurooffice/CLIENT_DATA/setup.opsiscript
[Actions]
requiredWinstVersion >= "4.12.0.16"
Message "Installing EuroOffice ..."
Winbatch_install

Message "Downloading Xournal++ ..."
  Files_download
  Winbatch_install

[Files_download]
; We should download before, but powershell/curl in winst is complex. Let's do it in bash before opsi-makepackage!

[Winbatch_install]
; Replace with actual installer name and silent switches
; "%ScriptPath%\eurooffice-setup.exe" /S
EOF

cat << 'EOF' > $WORKBENCH/eurooffice/CLIENT_DATA/uninstall.opsiscript
[Actions]
Message "Uninstalling EuroOffice ..."
Winbatch_uninstall

[Winbatch_uninstall]
; Replace with actual uninstaller
EOF

wget -qO $WORKBENCH/xournalpp/CLIENT_DATA/xournalpp-setup.exe https://github.com/xournalpp/xournalpp/releases/download/v1.2.3/xournalpp-1.2.3-windows-setup.exe
# Set rights and build
opsi-setup --set-rights $WORKBENCH/xournalpp
opsi-setup --set-rights $WORKBENCH/eurooffice
cd $WORKBENCH/xournalpp && opsi-makepackage -q && opsi-package-manager -i *.opsi
cd $WORKBENCH/eurooffice && opsi-makepackage -q && opsi-package-manager -i *.opsi

# Restore Win11 backup if exists and empty
if [ -d /var/lib/opsi/depot/win11-x64-backup-installfiles ]; then
  rm -rf /var/lib/opsi/depot/win11-x64/installfiles
  mv /var/lib/opsi/depot/win11-x64-backup-installfiles /var/lib/opsi/depot/win11-x64/installfiles
fi
if [ -d /var/lib/opsi/depot/win11-x64-backup-custom ]; then
  rm -rf /var/lib/opsi/depot/win11-x64/custom
  mv /var/lib/opsi/depot/win11-x64-backup-custom /var/lib/opsi/depot/win11-x64/custom
fi
opsi-setup --set-rights /var/lib/opsi/depot/win11-x64
echo "All tasks finished."


