#!/bin/bash
#
# Universal OPSI Depot Package Updater
# Updates: Xournal++, ONLYOFFICE (EuroOffice), Google Chrome, Mozilla Firefox, VirtualBox, WireGuard, Npcap
#
set -euo pipefail

LOG=/tmp/opsi_package_updates.log
exec > >(tee -a $LOG) 2>&1

echo "=========================================================="
echo " OPSI Universal Package Updater - Started: $(date)"
echo "=========================================================="

WORKBENCH="/var/lib/opsi/workbench"
mkdir -p "$WORKBENCH"

# --- HELPER FUNCTIONS ---

get_installed_version() {
    local product_id=$1
    local control_file="$WORKBENCH/$product_id/OPSI/control"
    if [ -f "$control_file" ]; then
        grep -i "^version:" "$control_file" | head -1 | awk '{print $2}' | tr -d '\r'
    else
        echo "0.0.0"
    fi
}

check_github_release() {
    local repo=$1
    local release_json
    release_json=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest")
    local version
    version=$(echo "$release_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" | sed 's/^v//')
    local body
    body=$(echo "$release_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['body'])")
    
    echo "$version|--- CHANGELOG/RELEASENOTES ($repo v$version) ---"
    echo "$body"
}

build_and_install_opsi() {
    local product_dir=$1
    local product_id=$2
    
    echo "[INFO] Setze Rechte für $product_id..."
    opsi-set-rights "$product_dir" 2>/dev/null || true
    
    echo "[INFO] Baue OPSI-Paket für $product_id..."
    cd "$product_dir"
    opsi-makepackage -q
    
    local opsi_file
    opsi_file=$(ls *.opsi 2>/dev/null | head -1)
    if [ -n "$opsi_file" ]; then
        echo "[INFO] Installiere OPSI-Paket $opsi_file..."
        opsi-package-manager -q -i "$opsi_file"
        echo "[SUCCESS] $product_id wurde erfolgreich aktualisiert!"
    else
        echo "[ERROR] Kein .opsi-Paket in $product_dir gefunden!"
    fi
}

# --- UPDATE MODULES ---

# 1. Xournal++
update_xournalpp() {
    local pid="xournalpp"
    echo -e "\n[Prüfe] Xournal++..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    local git_info
    git_info=$(check_github_release "xournalpp/xournalpp")
    local latest_ver
    latest_ver=$(echo "$git_info" | head -n 1 | cut -d'|' -f1)
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== CHANGELOG / RELEASENOTES ==="
        echo "$git_info" | tail -n +2
        echo "================================="
        echo -e "\n[INFO] Starte Update für Xournal++..."
        
        local xdir="$WORKBENCH/$pid"
        mkdir -p "$xdir/OPSI" "$xdir/CLIENT_DATA"
        
        # Download Link ermitteln
        local download_url
        download_url=$(curl -fsSL https://api.github.com/repos/xournalpp/xournalpp/releases/latest | python3 -c "
import sys,json
data=json.load(sys.stdin)
assets=[a['browser_download_url'] for a in data['assets'] if 'windows-setup-AMD64' in a['name']]
print(assets[0] if assets else '')
")
        
        cat > "$xdir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: Xournal++
description: Handwriting note-taking software with PDF annotation support
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$xdir/CLIENT_DATA/setup.opsiscript" <<'EOF'
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

        cat > "$xdir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
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

        echo "[INFO] Downloade Installer..."
        wget -q --show-progress -O "$xdir/CLIENT_DATA/xournalpp-setup.exe" "$download_url"
        
        build_and_install_opsi "$xdir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# 2. ONLYOFFICE (EuroOffice)
update_onlyoffice() {
    local pid="eurooffice"
    echo -e "\n[Prüfe] ONLYOFFICE (EuroOffice)..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    local git_info
    git_info=$(check_github_release "ONLYOFFICE/DesktopEditors")
    local latest_ver
    latest_ver=$(echo "$git_info" | head -n 1 | cut -d'|' -f1)
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== CHANGELOG / RELEASENOTES ==="
        echo "$git_info" | tail -n +2
        echo "================================="
        echo -e "\n[INFO] Starte Update für ONLYOFFICE..."
        
        local edir="$WORKBENCH/$pid"
        mkdir -p "$edir/OPSI" "$edir/CLIENT_DATA"
        
        local download_url="https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v${latest_ver}/DesktopEditors_x64.exe"
        
        cat > "$edir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: ONLYOFFICE Desktop Editors
description: Modern Office Suite (ONLYOFFICE Desktop Editors)
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$edir/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
requiredWinstVersion >= "4.12.0.16"
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\desktopeditors-setup.exe"
Message "Installing ONLYOFFICE..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
"$Installer$" /S /VERYSILENT /SUPPRESSMSGBOXES /NORESTART

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Setup failed with exit code " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

        cat > "$edir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $ExitCode$
Message "Uninstalling ONLYOFFICE..."
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

        echo "[INFO] Downloade Installer..."
        wget -q --show-progress -O "$edir/CLIENT_DATA/desktopeditors-setup.exe" "$download_url"
        
        build_and_install_opsi "$edir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# 3. Google Chrome
update_chrome() {
    local pid="chrome-enterprise"
    echo -e "\n[Prüfe] Google Chrome Enterprise..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    # Chrome Version ermitteln (wir laden die Version über einen Check)
    local latest_ver
    latest_ver=$(curl -fsSL "https://chromestatus.com/api/v0/channels" | python3 -c "import sys,json; print(json.load(sys.stdin)['stable']['version'])" 2>/dev/null || echo "125.0.0.0")
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== RELEASENOTES ==="
        echo "Changelog verfügbar unter: https://chromereleases.googleblog.com/"
        echo "================================="
        
        local cdir="$WORKBENCH/$pid"
        mkdir -p "$cdir/OPSI" "$cdir/CLIENT_DATA"
        
        local download_url="https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi"
        
        cat > "$cdir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: Google Chrome Enterprise
description: Google Chrome Web Browser (Enterprise MSI Edition)
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$cdir/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\chrome.msi"
Message "Installing Google Chrome..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
msiexec /i "$Installer$" /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0") and not ($ExitCode$ = "3010")
    LogError "Setup failed with exit code " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

        cat > "$cdir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\chrome.msi"
Message "Uninstalling Google Chrome..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
msiexec /x "$Installer$" /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0") and not ($ExitCode$ = "1605")
    LogError "Uninstall failed: " + $ExitCode$
    isFatalError "Uninstall failed"
fi
EOF

        echo "[INFO] Downloade MSI..."
        wget -q --show-progress -O "$cdir/CLIENT_DATA/chrome.msi" "$download_url"
        
        build_and_install_opsi "$cdir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# 4. Mozilla Firefox
update_firefox() {
    local pid="firefox"
    echo -e "\n[Prüfe] Mozilla Firefox..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    local latest_ver
    latest_ver=$(curl -fsSL "https://product-details.mozilla.org/1.0/firefox_versions.json" | python3 -c "import sys,json; print(json.load(sys.stdin)['LATEST_FIREFOX_VERSION'])")
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== RELEASENOTES ==="
        echo "Firefox Release Notes: https://www.mozilla.org/en-US/firefox/${latest_ver}/releasenotes/"
        echo "================================="
        
        local fdir="$WORKBENCH/$pid"
        mkdir -p "$fdir/OPSI" "$fdir/CLIENT_DATA"
        
        local download_url="https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=de"
        
        cat > "$fdir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: Mozilla Firefox
description: Mozilla Firefox Web Browser
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$fdir/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\firefox.msi"
Message "Installing Mozilla Firefox..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
msiexec /i "$Installer$" /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0") and not ($ExitCode$ = "3010")
    LogError "Setup failed: " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

        cat > "$fdir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\firefox.msi"
Message "Uninstalling Mozilla Firefox..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
msiexec /x "$Installer$" /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0") and not ($ExitCode$ = "1605")
    LogError "Uninstall failed: " + $ExitCode$
    isFatalError "Uninstall failed"
endif
EOF

        echo "[INFO] Downloade MSI..."
        wget -q --show-progress -O "$fdir/CLIENT_DATA/firefox.msi" "$download_url"
        
        build_and_install_opsi "$fdir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# 5. Oracle VirtualBox
update_virtualbox() {
    local pid="virtualbox"
    echo -e "\n[Prüfe] Oracle VirtualBox..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    local latest_ver
    latest_ver=$(curl -fsSL "https://download.virtualbox.org/virtualbox/LATEST.TXT" | tr -d '\r\n')
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== RELEASENOTES ==="
        echo "VirtualBox Changelog: https://www.virtualbox.org/wiki/Changelog-${latest_ver%%.*}"
        echo "================================="
        
        local vdir="$WORKBENCH/$pid"
        mkdir -p "$vdir/OPSI" "$vdir/CLIENT_DATA"
        
        local download_url="https://download.virtualbox.org/virtualbox/${latest_ver}/VirtualBox-${latest_ver}-Win.exe"
        
        cat > "$vdir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: Oracle VirtualBox
description: Oracle VM VirtualBox Virtualization Software
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$vdir/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\virtualbox-setup.exe"
Message "Installing Oracle VirtualBox..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
"$Installer$" --silent --ignore-reboot

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0") and not ($ExitCode$ = "3010")
    LogError "Setup failed: " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

        cat > "$vdir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $ExitCode$
Message "Uninstalling Oracle VirtualBox..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
MsiExec.exe /x {VirtualBox-GUID} /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogWarning "Msi uninstall failed, trying fallback registry search..."
endif
EOF

        echo "[INFO] Downloade Installer..."
        wget -q --show-progress -O "$vdir/CLIENT_DATA/virtualbox-setup.exe" "$download_url"
        
        build_and_install_opsi "$vdir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# 6. WireGuard
update_wireguard() {
    local pid="wireguard"
    echo -e "\n[Prüfe] WireGuard..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    # Wir holen uns die aktuelle Version aus der Download-Seite
    local latest_ver
    latest_ver=$(curl -fsSL "https://download.wireguard.com/windows-client/" | grep -o 'wireguard-amd64-[0-9.]*\.msi' | head -1 | grep -o '[0-9.]\+' | sed 's/\.$//' || echo "0.5.3")
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== RELEASENOTES ==="
        echo "WireGuard Changelog verfügbar unter: https://git.zx2c4.com/wireguard-windows/log/"
        echo "================================="
        
        local wdir="$WORKBENCH/$pid"
        mkdir -p "$wdir/OPSI" "$wdir/CLIENT_DATA"
        
        local download_url="https://download.wireguard.com/windows-client/wireguard-amd64-${latest_ver}.msi"
        
        cat > "$wdir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: WireGuard Client
description: WireGuard Secure VPN Tunnel Client
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$wdir/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\wireguard.msi"
Message "Installing WireGuard..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
msiexec /i "$Installer$" /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0") and not ($ExitCode$ = "3010")
    LogError "Setup failed: " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

        cat > "$wdir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\wireguard.msi"
Message "Uninstalling WireGuard..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
msiexec /x "$Installer$" /qn /norestart

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Uninstall failed: " + $ExitCode$
    isFatalError "Uninstall failed"
endif
EOF

        echo "[INFO] Downloade Installer..."
        wget -q --show-progress -O "$wdir/CLIENT_DATA/wireguard.msi" "$download_url"
        
        build_and_install_opsi "$wdir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# 7. Npcap
update_npcap() {
    local pid="npcap"
    echo -e "\n[Prüfe] Npcap Driver..."
    local cur_ver
    cur_ver=$(get_installed_version "$pid")
    
    # Npcap Version parsen
    local latest_ver
    latest_ver=$(curl -fsSL "https://npcap.com/" | grep -o 'npcap-[0-9.]*\.exe' | head -1 | grep -o '[0-9.]\+' | sed 's/\.$//' || echo "1.80")
    
    echo "  Installierte Version: $cur_ver"
    echo "  Neueste Version:      $latest_ver"
    
    if [ "$cur_ver" != "$latest_ver" ]; then
        echo -e "\n=== RELEASENOTES ==="
        echo "Npcap Changelog: https://npcap.com/changelog.html"
        echo "================================="
        
        local ndir="$WORKBENCH/$pid"
        mkdir -p "$ndir/OPSI" "$ndir/CLIENT_DATA"
        
        local download_url="https://npcap.com/dist/npcap-${latest_ver}.exe"
        
        cat > "$ndir/OPSI/control" <<EOF
[Package]
version: 1
depends:

[Product]
type: localboot
id: $pid
name: Npcap Packet Capture Library
description: Npcap - packet capture and transmission library for Windows
advice:
version: $latest_ver
priority: 0
licenseRequired: False
productClasses:
setupScript: setup.opsiscript
uninstallScript: uninstall.opsiscript
EOF

        cat > "$ndir/CLIENT_DATA/setup.opsiscript" <<'EOF'
[Actions]
DefVar $Installer$
DefVar $ExitCode$
Set $Installer$ = "%ScriptPath%\npcap-setup.exe"
Message "Installing Npcap..."
Winbatch_install
Sub_check_exitcode

[Winbatch_install]
# Silent install optionen für Npcap
"$Installer$" /S /winpcap_mode=no

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogError "Setup failed: " + $ExitCode$
    isFatalError "Setup failed"
endif
EOF

        cat > "$ndir/CLIENT_DATA/uninstall.opsiscript" <<'EOF'
[Actions]
DefVar $ExitCode$
Message "Uninstalling Npcap..."
Winbatch_uninstall
Sub_check_exitcode

[Winbatch_uninstall]
# Versuche Standard Uninstaller
"%SystemRoot%\System32\Npcap\Uninstall.exe" /S

[Sub_check_exitcode]
Set $ExitCode$ = getLastExitCode
if not ($ExitCode$ = "0")
    LogWarning "Uninstall exit code: " + $ExitCode$
endif
EOF

        echo "[INFO] Downloade Installer..."
        wget -q --show-progress -O "$ndir/CLIENT_DATA/npcap-setup.exe" "$download_url"
        
        build_and_install_opsi "$ndir" "$pid"
    else
        echo "  Produkt ist aktuell."
    fi
}

# --- MAIN ---

main() {
    update_xournalpp
    update_onlyoffice
    update_chrome
    update_firefox
    update_virtualbox
    update_wireguard
    update_npcap
    
    echo -e "\n=========================================================="
    echo " OPSI Universal Package Updater - Finished: $(date)"
    echo "=========================================================="
}

main
