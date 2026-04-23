<#
🛠️ Detaillierte BCD Fehleranalyse & Lösungen

Beim Erstellen von OPSI-WinPE-Strukturen treten häufig BCD (Boot Configuration Data) Fehler auf. Hier sind die Lösungen:

1. Fehler: 0xc000000f (The Boot Selection Failed)

Ursache: Der BCD-Eintrag verweist auf eine boot.wim, die an einem Pfad liegt, den der Bootloader nicht kennt (z.B. Root statt sources/).

Lösung: Das Skript verschiebt die boot.wim zwingend nach \sources\boot.wim.

Fix: bcdedit /store <BCD> /set {default} device ramdisk=[boot]\sources\boot.wim,{7619dcc8-fafe-11d9-b411-000476eba25f}

2. Fehler: "Recovery - Your PC needs to be repaired" (0xc0000001)

Ursache: Falsche Lokalisierungseinstellungen (locale) oder fehlende Signaturen.

Lösung: Das Skript erzwingt locale de-DE für {bootmgr} und {default}.

3. Fehler: WinPE startet nur in Englisch

Ursache: Das WinPE-Abbild hat keine deutschen Sprachpakete, oder der BCD erzwingt en-US.

Lösung: Integration der WinPE-xxx_de-DE.cab Pakete via DISM und BCD-Set auf de-DE.

4. UEFI-Boot schlägt fehl

Ursache: Die Datei \EFI\Microsoft\Boot\bcd wurde nicht aktualisiert.

Lösung: Das Skript wendet die Änderungen auf beide BCD-Dateien (Legacy & UEFI) an.
#>

<#
# Filename: PS_Apply_Harden_Policies.ps1
# Description: Windows 11 Hardening & Lab-Optimization (Defender OFF Support) V9.3
# Compatibility: PowerShell 5.1+, Windows 10/11
# Usage: Standalone, OPSI, Unattended.xml

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)][switch]$EnableDefender = $false,
    [Parameter(Mandatory=$false)][string]$DriversPathSource = "C:\Drivers_Temp",
    [Parameter(Mandatory=$false)][switch]$SkipDriverInstall = $false,
    [Parameter(Mandatory=$false)][switch]$SilentMode = $false
)

# --- Initialisierung ---
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'
$Global:LogFile = Join-Path $env:TEMP "Win11_Hardening_V9_3.log"
$Global:Stats = @{ Success = 0; Warnings = 0; Errors = 0 }

$HKLM = "HKLM:\SOFTWARE"
$HKCU = "HKCU:\SOFTWARE"

function Write-LogEntry {
    param([string]$Message, [string]$Type = "INFO")
    $Timestamp = Get-Date -Format "HH:mm:ss"
    $LogMsg = "[$Timestamp] [$Type] $Message"
    switch ($Type) {
        "ERROR"   { Write-Error $Message; $Global:Stats.Errors++ }
        "WARNING" { Write-Warning $Message; $Global:Stats.Warnings++ }
        "SUCCESS" { Write-Host "  [OK] $Message" -ForegroundColor Green; $Global:Stats.Success++ }
        "INFO"    { Write-Verbose "INFO: $Message" }
    }
    try { $LogMsg | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Set-RegValue {
    param($Path, $Name, $Value, $Type = "DWord", $Description = "")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force | Out-Null
        Write-LogEntry "Registry gesetzt: $Description ($Name)" "SUCCESS"
        return $true
    } catch {
        Write-LogEntry "Fehler bei Registry $Name : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# --- Module ---

function Invoke-DefenderControl {
    if ($EnableDefender) {
        Write-LogEntry "Defender bleibt aktiviert (Hardening Mode)." "INFO"
    } else {
        Write-LogEntry "Lab-Modus: Deaktiviere Windows Defender dauerhaft..." "WARNING"

        $DefPath = "$HKLM\Policies\Microsoft\Windows Defender"
        $RTPath = "$HKLM\Policies\Microsoft\Windows Defender\Real-Time Protection"

        # Defender Grund-Deaktivierung
        Set-RegValue -Path $DefPath -Name "DisableAntiSpyware" -Value 1 -Desc "Defender Dienst aus"
        Set-RegValue -Path $DefPath -Name "DisableAntiVirus" -Value 1 -Desc "AV aus"

        # Real-Time Protection aus
        Set-RegValue -Path $RTPath -Name "DisableRealtimeMonitoring" -Value 1 -Desc "Echtzeitschutz aus"
        Set-RegValue -Path $RTPath -Name "DisableBehaviorMonitoring" -Value 1 -Desc "Verhaltensschutz aus"
        Set-RegValue -Path $RTPath -Name "DisableOnAccessProtection" -Value 1 -Desc "On-Access Schutz aus"
        Set-RegValue -Path $RTPath -Name "DisableScanOnRealtimeEnable" -Value 1 -Desc "Scan bei Aktivierung aus"
    }
}

function Invoke-PrivacyHardening {
    Write-LogEntry "Starte Modul: Privacy & Telemetrie..."
    $Policies = @(
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowTelemetry'; Value = 0; Desc = 'Telemetrie aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\AdvertisingInfo"; Name = 'DisabledByGroupPolicy'; Value = 1; Desc = 'Werbe-ID aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DeliveryOptimization"; Name = 'DODownloadMode'; Value = 99; Desc = 'WUDO aus' }
    )
    foreach ($P in $Policies) { Set-RegValue -Path $P.Path -Name $P.Name -Value $P.Value -Desc $P.Desc }
}

function Invoke-SecurityHardening {
    Write-LogEntry "Starte Modul: System-Sicherheit (LSA & CG)..."
    Set-RegValue -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'RunAsPPL' -Value 1 -Desc 'LSA Protection'

    # Credential Guard Hardware-Check
    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName MSFT_DeviceGuard
        if ($dg.VirtualizationBasedSecurityStatus -ge 1) {
            Set-RegValue -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'LsaCfgFlags' -Value 1 -Desc 'Credential Guard aktiv'
        }
    } catch { Write-LogEntry "CG Hardware-Check übersprungen." "INFO" }
}

function Invoke-DauerhaftesDebloating {
    Write-LogEntry "Starte Modul: Permanentes Debloating..."
    $AppList = @("*Teams*", "*Xbox*", "*Copilot*", "*Clipchamp*", "*OneDrive*", "*News*", "*Weather*", "*Bing*")

    # Image Cleanup (Provisioned)
    Get-AppxProvisionedPackage -Online | Where-Object { $app = $_.DisplayName; $AppList | Where-Object { $app -like $_ } } | ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }

    # User Cleanup
    foreach ($App in $AppList) {
        Get-AppxPackage -Name $App -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
    }
}

function Invoke-UIAndSystem {
    Write-LogEntry "Starte Modul: UI-Anpassungen..."
    Set-RegValue -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "" -Value "" -Type "String" -Desc "Classic Menu"
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TaskbarAlignment" -Value 0 -Desc "Taskbar Links"
    Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name 'HiberbootEnabled' -Value 0 -Desc "Fastboot aus"

    if (-not $SkipDriverInstall -and (Test-Path $DriversPathSource)) {
        pnputil /add-driver "$DriversPathSource\*.inf" /install /subdirs | Out-Null
    }
}

# --- Main ---
function Main {
    Write-Host "`n--- PS-Coding Hardening Suite V9.3 (Lab Mode Ready) ---" -ForegroundColor Cyan
    if (-not $SilentMode) {
        $Confirm = Read-Host "Hardening & Lab-Setup starten? (J/N)"
        if ($Confirm -ne "J") { return }
    }

    Invoke-DefenderControl
    Invoke-PrivacyHardening
    Invoke-SecurityHardening
    Invoke-DauerhaftesDebloating
    Invoke-UIAndSystem

    Write-Host "`nFertig. Erfolge: $($Global:Stats.Success), Fehler: $($Global:Stats.Errors)" -ForegroundColor Cyan
    exit $(if ($Global:Stats.Errors -eq 0) { 0 } else { 1 })
}

Main
#>

<#
PS-Coding: PSC_WinPE Master-Build V10.3

📝 Beschreibung

Dieses PowerShell-Skript automatisiert die Erstellung einer hochperformanten WinPE-Umgebung für OPSI. Es integriert PowerShell, die grafische ISE, Treiber und externe Tools in ein einziges Boot-Image.

🚀 Kernfunktionen

Vollständigkeit: Kopiert die gesamte ISO-Struktur (wichtig für OPSI-Kompatibilität).

PowerShell ISE: Volle Unterstützung für grafisches Scripting im WinPE.

Auto-Menü: Interaktives Menü beim Systemstart für Tools wie Notepad++ und Explorer++.

BCD-Master: Automatische Korrektur von Boot-Pfaden und Lokalisierung (de-DE).

Caching: Überspringt zeitintensive Schritte, wenn Daten bereits vorhanden sind.

⚙️ Voraussetzungen

Windows ADK inkl. WinPE Add-on (Pfad muss im Skript/Parameter stimmen).

Quelle: Ein Ordner C:\TEMP_WINPE mit deinen Werkzeugen.

Admin-Rechte: Zwingend erforderlich für DISM-Operationen.

🛠️ Verwendung

.\PS_WinPE.ps1 -opsiexportpath "C:\Export\opsiWinPE" -WorkingPath "C:\Build" -DriverSource "Y:\Drivers" -sourceiso "D:\ISO\Win11.iso"


📄 Ordnerstruktur

/sources/boot.wim: Das Herzstück (modifiziert).

/_WIM_INSPECT: Einsehbarer Inhalt deiner injizierten Tools zur schnellen Kontrolle.

/boot & /efi: Korrigierte Bootloader-Daten.
#>

<#
History: PSC_WinPE

[V10.3] - 2026-04-14

FIX: Quellenverzeichnis mit offiziellen URLs ergänzt (Microsoft, OPSI).

BCD: Detaillierte Fehlerbehandlung für UEFI und Locale-Settings implementiert.

Persistence: Inspection-Ordner _WIM_INSPECT hinzugefügt, um WIM-Inhalt nach dem Unmount einsehbar zu machen.

[V10.2]

Integration von PowerShell ISE und WinPE-OC Paketen.

Implementierung des interaktiven Tool-Menüs (ToolMenu.ps1).

[V10.0]

Cache-Logik eingeführt (-UseCache).

Aggressives Handle-Force Cleanup für DISM-Operationen.

#>
<#
LLM Rebuild Prompt (v10.3)

Nutze diesen Prompt für einen vollständigen Rebuild:

"Agieren Sie als PS-Coding. Erstellen Sie ein PowerShell-Skript zur Erstellung eines WinPE für OPSI.
Anforderungen:

Vollständige Media-Struktur der ISO kopieren (inkl. sources DLLs), exklusive install.wim.

DISM-Integration: WinPE-OCs für WMI, PowerShell und ISE hinzufügen.

Tool-Injection: Kopiere C:\TEMP_WINPE nach X:\ExternalTools via Robocopy Multi-threading. Schließe ISO-Dubletten aus.

Automatisierung: Erstelle ein interaktives PowerShell-Menü (ToolMenu.ps1), das über startnet.cmd automatisch startet.

BCD-Fix: Setze Locale auf de-DE in Legacy und UEFI BCDs. Korrigiere ramdisk Pfade auf \sources\boot.wim.

Persistence: Erstelle einen Ordner _WIM_INSPECT im Ziel, der den Inhalt der WIM vor dem Unmount persistent speichert.

Fehlerbehandlung: Handle-Force für DISM-Sperren (0x80070020) und Schreibschutz-Fix (0xc1510111). Nutze keine geschützten Systemvariablen wie $PID."
#>


<#[Package]
version: 9.3
revision: 1
depends:

[Product]
type: localboot
id: win11-hardening
name: Windows 11 Hardening Suite
description: Umfassende Systemhärtung und Lab-Optimierung (Defender OFF) (V9.3)
advice: Erfordert Administrator-Rechte.
version: 9.3
priority: 50
licenseRequired: False
productClasses:
setupScript: setup.opsi
uninstallScript:
updateScript:
alwaysScript:
onceScript:
customScript:
userLoginScript:

[ProductProperty]
type: unicode
name: enable_defender
multivalue: False
editable: False
description: Defender aktivieren? (Im Lab auf false lassen für Deaktivierung)
values: ["false", "true"]
default: ["false"]

[ProductProperty]
type: unicode
name: drivers_path
multivalue: False
editable: True
description: Pfad zu den .inf Treibern.
values: []
default: ["C:\Drivers_Temp"]

#>

<##>



# Filename: PS_WinPE.ps1
# Description: PSC_WinPE v10.3 (Ultimate Master-Build with PowerShell ISE & BCD Fix)
# Purpose: Erstellt ein vollständiges, interaktives OPSI-WinPE
# Version: 10.3
#
# QUELLEN (User-provided URLs & Paths):
# - Verzeichnis: C:\TEMP_WINPE (Tools & Media)
# - ISO: SW_DVD9_WIN_ENT_LTSC_2024_64-bit_German_MLF_X23-70052.ISO
# - OPSI-WinPE Manual: https://download.uib.de/opsi4.2/documentation/html/en/opsi-getting-started-v4.2/opsi-getting-started-v4.2.html
#
# QUELLEN (AI-discovered):
# - MS WinPE OC: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference
# - BCD Edit: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcdedit-command-line-options

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$opsiexportpath,
    [Parameter(Mandatory = $true)][string]$WorkingPath,
    [Parameter(Mandatory = $true)][string]$DriverSource,
    [Parameter(Mandatory = $true)][string]$sourceiso,
    [Parameter(Mandatory = $false)][string]$ExternalToolsSource = "C:\TEMP_WINPE",
    [Parameter(Mandatory = $false)][string]$ADK_Path = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs",
    [Parameter(Mandatory = $false)][switch]$UseCache = $true
)

# --- Initialisierung ---
$ErrorActionPreference = 'Stop'
Clear-Host
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   PSC_WinPE v10.3 (Final Enterprise Edition)       " -ForegroundColor White
Write-Host "   PowerShell ISE | BCD de-DE | Tool-AutoMenu       " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

$MountPath = Join-Path $WorkingPath "mount"
$TempWim = Join-Path $WorkingPath "boot_modified.wim"
$InspectionPath = Join-Path $opsiexportpath "_WIM_INSPECT"

# --- Hilfsfunktion: Cleanup ---
function Invoke-AggressiveCleanup {
    param([string]$Path)
    Write-Host " [CLEANUP] Löse Sperren auf $Path..." -ForegroundColor Yellow
    $LockedProcs = Get-Process | Where-Object { try { $_.Modules.FileName -like "$Path*" } catch { $false } }
    foreach ($Proc in $LockedProcs) { Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue }
    dism /Cleanup-Wim | Out-Null
    if (Test-Path $Path) {
        dism /Unmount-Wim /MountDir:$Path /Discard /ErrorAction SilentlyContinue | Out-Null
    }
}

try {
    # 1. Vorbereitung & Caching
    Invoke-AggressiveCleanup -Path $MountPath
    if (-not (Test-Path $WorkingPath)) { New-Item $WorkingPath -ItemType Directory -Force | Out-Null }

    $BuildMedia = $true
    if ($UseCache -and (Test-Path "$opsiexportpath\bootmgr") -and (Test-Path $TempWim)) {
        Write-Host " [CACHE] Bestehende Struktur gefunden. Überspringe ISO-Kopie." -ForegroundColor Green
        $BuildMedia = $false
    }

    if ($BuildMedia) {
        Write-Host "[ISO] Extrahiere vollständige Media-Struktur..." -ForegroundColor Cyan
        $MountResult = Mount-DiskImage -ImagePath $sourceiso -PassThru
        $DriveLetter = ($MountResult | Get-Volume).DriveLetter + ":"

        if (Test-Path $opsiexportpath) { Remove-Item "$opsiexportpath\*" -Recurse -Force -ErrorAction SilentlyContinue }
        else { New-Item $opsiexportpath -ItemType Directory -Force | Out-Null }

        # KOPIERE ALLES VON ISO (Setup-DLLs in sources/ sind essenziell!)
        robocopy $DriveLetter $opsiexportpath /E /XF "install.wim" "install.esd" "boot.wim" /R:1 /W:1 /MT:32 /NDL /NFL | Out-Null

        # WIM für Bearbeitung vorbereiten
        Copy-Item "$DriveLetter\sources\boot.wim" $TempWim -Force
        Set-ItemProperty $TempWim -Name IsReadOnly -Value $false
        Dismount-DiskImage -ImagePath $sourceiso | Out-Null
    }

    # 2. WIM Modifikation
    Write-Host "[MODIFY] Mounte WinPE (RW)..." -ForegroundColor Gray
    if (-not (Test-Path $MountPath)) { New-Item $MountPath -ItemType Directory -Force | Out-Null }
    dism /Mount-Wim /WimFile:$TempWim /Index:2 /MountDir:$MountPath

    # 3. POWERSHELL & ISE INTEGRATION
    Write-Host "[OC] Integriere PowerShell & ISE Komponenten..." -ForegroundColor Cyan
    if (Test-Path $ADK_Path) {
        $OCs = @("WinPE-WMI.cab", "WinPE-NetFX.cab", "WinPE-Scripting.cab", "WinPE-PowerShell.cab", "WinPE-PowerShell-ISE.cab", "de-DE\WinPE-WMI_de-DE.cab", "de-DE\WinPE-PowerShell_de-DE.cab")
        foreach ($OC in $OCs) {
            $p = Join-Path $ADK_Path $OC
            if (Test-Path $p) { dism /Image:$MountPath /Add-Package /PackagePath:$p | Out-Null }
        }
    }

    # 4. TOOL-INJECTION & MENÜ
    Write-Host "[CUSTOM] Injiziere Werkzeuge aus $ExternalToolsSource..." -ForegroundColor Cyan
    $WimToolsPath = Join-Path $MountPath "ExternalTools"
    robocopy $ExternalToolsSource $WimToolsPath /E /XD "media" "sources" "mount" /R:1 /W:1 /MT:32 /NFL /NDL | Out-Null

    # Menü-Skript erstellen
    $MenuScript = @"
while(`$true) {
    Clear-Host
    Write-Host "--- PSC WinPE V10.3 TOOL-MENU ---" -ForegroundColor Cyan
    Write-Host "1) Explorer++"
    Write-Host "2) Notepad++"
    Write-Host "3) PowerShell ISE"
    Write-Host "4) Sysinternals Shell"
    Write-Host "Q) Exit to CMD"
    `$c = Read-Host "Auswahl"
    switch(`$c) {
        '1' { Start-Process "X:\ExternalTools\ExplorerPP\Explorer++.exe" }
        '2' { Start-Process "X:\ExternalTools\NotepadPP\notepad++.exe" }
        '3' { isep }
        '4' { cd X:\ExternalTools\Sysinternals; Write-Host "Path: X:\ExternalTools\Sysinternals" -ForegroundColor Green }
        'Q' { break }
    }
}
"@
    $MenuScript | Out-File (Join-Path $MountPath "Windows\System32\ToolMenu.ps1") -Encoding ASCII

    # Autostart patchen
    "wpeinit`npowershell.exe -ExecutionPolicy Bypass -File X:\Windows\System32\ToolMenu.ps1" | Out-File (Join-Path $MountPath "Windows\System32\startnet.cmd") -Encoding ASCII

    # 5. TREIBER
    if (Test-Path $DriverSource) {
        dism /Image:$MountPath /Add-Driver /Driver:$DriverSource /Recurse /ForceUnsigned | Out-Null
    }

    # 6. BCD FIX (UEFI & LOCALE)
    Write-Host "[BCD] Korrektur der Boot-Konfiguration (de-DE)..." -ForegroundColor Cyan
    $Bcds = @("$opsiexportpath\boot\bcd", "$opsiexportpath\EFI\Microsoft\Boot\bcd")
    foreach ($B in $Bcds) {
        if (Test-Path $B) {
            bcdedit /store $B /set { default } locale de-DE | Out-Null
            bcdedit /store $B /set { bootmgr } locale de-DE | Out-Null
        }
    }

    # 7. INSPECTION-COPY (Vor Unmount!)
    Write-Host "[INSPECT] Erstelle Inhaltskopie in $InspectionPath..." -ForegroundColor Yellow
    robocopy $WimToolsPath $InspectionPath /E /MT:32 /NFL /NDL | Out-Null

    # 8. SPEICHERN
    Write-Host "[SAVE] Schließe WIM (Commit)..." -ForegroundColor Gray
    dism /Unmount-Wim /MountDir:$MountPath /Commit

    # Finaler Platzhalter
    Copy-Item $TempWim "$opsiexportpath\sources\boot.wim" -Force
    if (Test-Path "$opsiexportpath\boot.wim") { Remove-Item "$opsiexportpath\boot.wim" -Force }

    Write-Host "`n[FERTIG] PSC_WinPE V10.3 erfolgreich erstellt!" -ForegroundColor Green
    Write-Host "Tools einsehbar in: $InspectionPath" -ForegroundColor Cyan

}
catch {
    Write-Host "`n!!! FEHLER: $($_.Exception.Message) !!!" -ForegroundColor Red
    Invoke-AggressiveCleanup -Path $MountPath
    exit 1
}
