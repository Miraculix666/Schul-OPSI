# Filename: Apply_Hardening.ps1
# Description: Windows 11 Master-Hardening, Debloating & Optimization V10.0
# Compatibility: PowerShell 5.1+, Windows 10/11
# Usage: Standalone, OPSI, Unattended
# History: Konsolidiert aus V1-V9 (Image_Anpassung) + OPSI-Paket

<#
.SYNOPSIS
    Umfassendes Hardening-Skript fuer Windows 11 Enterprise-Umgebungen (V10.0).
.DESCRIPTION
    Fuehrt BSI-konforme Haertung durch, deaktiviert Telemetrie, entfernt Bloatware,
    konfiguriert Remote-Zugriff, Energie und UI. Optimiert fuer OPSI-Deployment.

    Module:
      A) Privacy & Telemetrie (BSI/nLite-konform)
      B) Defender-Steuerung (Deaktivierung mit Warnung)
      C) Sicherheit (LSA, Credential Guard, ASR)
      D) Remote & Netzwerk (RDP, WinRM, Firewall, WOL)
      E) Dienste & Store deaktivieren
      F) Permanentes Debloating (AppX + Capabilities)
      G) UI-Anpassungen & Explorer
      H) Energie & System
      I) Treiber-Injektion

.PARAMETER EnableDefender
    Wenn gesetzt, bleibt Defender aktiv (ASR im Block-Modus). Standard: Defender wird deaktiviert.
.PARAMETER DriversPathSource
    Pfad zu den zu injizierenden Treibern (Standard: C:\Drivers_Temp).
.PARAMETER SkipDriverInstall
    Ueberspringt die Treiber-Installation via PnPUtil.
.PARAMETER SilentMode
    Deaktiviert interaktive Bestaetigungen (fuer OPSI/Unattended).
.PARAMETER SkipRemoteSetup
    Ueberspringt RDP/WinRM/Firewall-Konfiguration.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)][switch]$EnableDefender = $false,
    [Parameter(Mandatory=$false)][string]$DriversPathSource = "C:\Drivers_Temp",
    [Parameter(Mandatory=$false)][switch]$SkipDriverInstall = $false,
    [Parameter(Mandatory=$false)][switch]$SilentMode = $false,
    [Parameter(Mandatory=$false)][switch]$SkipRemoteSetup = $false
)

# --- Initialisierung ---
$ErrorActionPreference = 'Continue'
$VerbosePreference = 'Continue'
$Global:LogFile = Join-Path $env:TEMP "Win11_Hardening_V10_0.log"
$Global:Stats = @{ Success = 0; Warnings = 0; Errors = 0 }
$HKLM = "HKLM:\SOFTWARE"
$HKCU = "HKCU:\SOFTWARE"

# --- Hilfsfunktionen ---
function Write-LogEntry {
    param([string]$Message, [string]$Type = "INFO")
    $Timestamp = Get-Date -Format "HH:mm:ss"
    $LogMsg = "[$Timestamp] [$Type] $Message"
    switch ($Type) {
        "ERROR"   { Write-Error $Message; $Global:Stats.Errors++ }
        "WARNING" { Write-Warning $Message; $Global:Stats.Warnings++ }
        "SUCCESS" { Write-Host "  [OK] $Message" -ForegroundColor Green; $Global:Stats.Success++ }
        "INFO"    { Write-Verbose "INFO: $Message" }
        "HEAD"    { Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
    }
    try { $LogMsg | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Set-RegValue {
    param($Path, $Name, $Value, $Type = "DWord", $Description = "")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force | Out-Null
        Write-LogEntry "Registry: $Description ($Name=$Value)" "SUCCESS"
        return $true
    } catch {
        Write-LogEntry "Registry-Fehler $Name : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# MODUL A: Privacy & Telemetrie
# ============================================================================
function Invoke-PrivacyHardening {
    Write-LogEntry "Modul A: Privacy & Telemetrie (BSI-konform)" "HEAD"
    @(
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowTelemetry'; Value = 0; Desc = 'Telemetrie deaktiviert' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'LimitDiagnosticLogCollection'; Value = 1; Desc = 'Diagnoseprotokoll begrenzt' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'DisableOneSettingsDownloads'; Value = 1; Desc = 'OneSettings aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'DoNotShowFeedbackNotifications'; Value = 1; Desc = 'Feedback-Popups aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowCommercialDataPipeline'; Value = 0; Desc = 'Commercial Pipeline aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\AdvertisingInfo"; Name = 'DisabledByGroupPolicy'; Value = 1; Desc = 'Werbe-ID deaktiviert' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DeliveryOptimization"; Name = 'DODownloadMode'; Value = 99; Desc = 'Uebermittlungsoptimierung aus' },
        @{ Path = "$HKLM\Policies\Microsoft\MRT"; Name = 'DontReportInfectionInformation'; Value = 1; Desc = 'MRT Telemetrie aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\WcmSvc\Local"; Name = 'AllowWiFiHotSpotReporting'; Value = 0; Desc = 'WiFi Sense aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\Windows Search"; Name = 'AllowCortana'; Value = 0; Desc = 'Cortana aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\Windows Search"; Name = 'ConnectedSearchUseWeb'; Value = 0; Desc = 'Websuche aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\CloudContent"; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Desc = 'Consumer Features aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\CloudContent"; Name = 'DisableWindowsSpotlightFeatures'; Value = 1; Desc = 'Spotlight aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\LocationAndSensors"; Name = 'DisableLocation'; Value = 1; Desc = 'Standortdienst aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\System"; Name = 'EnableActivityFeed'; Value = 0; Desc = 'Activity Feed aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\System"; Name = 'PublishUserActivities'; Value = 0; Desc = 'User Activities aus' },
        @{ Path = "$HKLM\Policies\Microsoft\SQMClient\Windows"; Name = 'CEIPEnable'; Value = 0; Desc = 'CEIP aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\AppCompat"; Name = 'AITEnable'; Value = 0; Desc = 'App-Telemetrie aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\AppCompat"; Name = 'DisableInventory'; Value = 1; Desc = 'Inventory Collector aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\Windows Error Reporting"; Name = 'Disabled'; Value = 1; Desc = 'WER deaktiviert' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\OneDrive"; Name = 'DisableFileSyncNGSC'; Value = 1; Desc = 'OneDrive aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Edge"; Name = 'ExperimentationAndConfigurationServiceControl'; Value = 1; Desc = 'Edge Experimentation aus' }
    ) | ForEach-Object { Set-RegValue -Path $_.Path -Name $_.Name -Value $_.Value -Desc $_.Desc }
}

# ============================================================================
# MODUL B: Defender-Steuerung
# ============================================================================
function Invoke-DefenderControl {
    Write-LogEntry "Modul B: Windows Defender Steuerung" "HEAD"

    if ($EnableDefender) {
        Write-LogEntry "Defender bleibt AKTIVIERT (Hardening-Modus)." "INFO"
        return
    }

    # WARNUNG anzeigen - auch im Silent-Modus als Popup
    $warnMsg = @"
ACHTUNG: Windows Defender wird DEAKTIVIERT!

Dies ist nur fuer folgende Szenarien vorgesehen:
  - Lab-/Test-Umgebungen ohne Netzwerkzugang
  - Systeme mit alternativer AV-Software

Ohne Virenscanner ist das System UNGESCHUETZT!
"@
    Write-Host "`n$warnMsg" -ForegroundColor Red

    # Popup-Warnung (auch bei OPSI sichtbar beim naechsten Login)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            $warnMsg,
            "Defender Deaktivierung - Sicherheitswarnung",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    } catch {
        Write-LogEntry "Popup konnte nicht angezeigt werden (headless)" "INFO"
    }

    $DefPath = "$HKLM\Policies\Microsoft\Windows Defender"
    $RTPath = "$HKLM\Policies\Microsoft\Windows Defender\Real-Time Protection"
    Set-RegValue -Path $DefPath -Name "DisableAntiSpyware" -Value 1 -Desc "Defender Dienst aus"
    Set-RegValue -Path $DefPath -Name "DisableAntiVirus" -Value 1 -Desc "AV aus"
    Set-RegValue -Path $RTPath -Name "DisableRealtimeMonitoring" -Value 1 -Desc "Echtzeitschutz aus"
    Set-RegValue -Path $RTPath -Name "DisableBehaviorMonitoring" -Value 1 -Desc "Verhaltensschutz aus"
    Set-RegValue -Path $RTPath -Name "DisableOnAccessProtection" -Value 1 -Desc "On-Access aus"
    Set-RegValue -Path $RTPath -Name "DisableScanOnRealtimeEnable" -Value 1 -Desc "Scan-bei-Aktivierung aus"
    Write-LogEntry "Defender vollstaendig deaktiviert (Lab-Modus)" "WARNING"
}

# ============================================================================
# MODUL C: Erweiterte Sicherheit (LSA, CG, ASR)
# ============================================================================
function Invoke-SecurityHardening {
    Write-LogEntry "Modul C: Erweiterte Sicherheit (LSA, CG, ASR)" "HEAD"

    # LSA Protection
    Set-RegValue -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'RunAsPPL' -Value 1 -Desc 'LSA Protection aktiv'

    # Credential Guard - OHNE Hardware-Check (User-Vorgabe)
    Set-RegValue -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'LsaCfgFlags' -Value 1 -Desc 'Credential Guard aktiviert'
    Write-LogEntry "Credential Guard aktiviert (kein HW-Check)" "SUCCESS"

    # ASR Regeln (Audit-Modus, da Defender ggf. aus)
    $ASRMode = if ($EnableDefender) { "1" } else { "2" }
    $ASRPath = "$HKLM\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"
    @("be9ba2d9-53ea-4cdc-84e5-9b1eeee46550", "d4f940ab-401b-4efc-aadc-ad5f3c50688a", "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2") | ForEach-Object {
        Set-RegValue -Path $ASRPath -Name $_ -Value $ASRMode -Type "String" -Desc "ASR Regel $_"
    }
}

# ============================================================================
# MODUL D: Remote & Netzwerk (aus V3)
# ============================================================================
function Invoke-RemoteSetup {
    if ($SkipRemoteSetup) { Write-LogEntry "Remote-Setup uebersprungen (-SkipRemoteSetup)" "INFO"; return }
    Write-LogEntry "Modul D: Remote-Zugriff & Netzwerk" "HEAD"

    # RDP aktivieren
    try {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 -Type DWord -Force
        Write-LogEntry "RDP aktiviert (NLA erzwungen)" "SUCCESS"
    } catch { Write-LogEntry "RDP-Fehler: $($_.Exception.Message)" "ERROR" }

    # WinRM aktivieren
    try {
        Set-Service -Name "WinRM" -StartupType Automatic -ErrorAction Stop
        Start-Service -Name "WinRM" -ErrorAction SilentlyContinue
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
        Write-LogEntry "WinRM und PS RemoteSigned aktiviert" "SUCCESS"
    } catch { Write-LogEntry "WinRM-Fehler: $($_.Exception.Message)" "WARNING" }

    # Firewall: Ping, RDP, WinRM
    try {
        Get-NetFirewallRule -DisplayGroup "Remotedesktop" -ErrorAction SilentlyContinue | Enable-NetFirewallRule -ErrorAction SilentlyContinue
        Get-NetFirewallRule -Name "*echo*" -ErrorAction SilentlyContinue | Enable-NetFirewallRule -ErrorAction SilentlyContinue
        Write-LogEntry "Firewall: RDP + Ping aktiviert" "SUCCESS"
    } catch { Write-LogEntry "Firewall-Fehler: $($_.Exception.Message)" "WARNING" }

    # WOL - Wake-Timer erlauben
    try {
        powercfg /SETACVALUEINDEX SCHEME_CURRENT 238c9fa8-0aaa-4286-a941-30fd9d27a4a2 bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 1 2>$null
        Write-LogEntry "Wake-on-LAN Timer aktiviert" "SUCCESS"
    } catch { Write-LogEntry "WOL-Fehler: $($_.Exception.Message)" "WARNING" }
}

# ============================================================================
# MODUL E: Dienste & Store deaktivieren
# ============================================================================
function Invoke-ServiceHardening {
    Write-LogEntry "Modul E: Dienste & Store deaktivieren" "HEAD"

    # Telemetrie-Dienste stoppen und deaktivieren
    @("DiagTrack", "dmwappushservice", "WpnService") | ForEach-Object {
        try {
            $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
            if ($svc) {
                if ($svc.Status -ne 'Stopped') { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }
                Set-Service -Name $_ -StartupType Disabled -ErrorAction Stop
                Write-LogEntry "Dienst $_ deaktiviert" "SUCCESS"
            }
        } catch { Write-LogEntry "Dienst $_ : $($_.Exception.Message)" "WARNING" }
    }

    # Windows Store deaktivieren
    Set-RegValue -Path "$HKLM\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -Value 2 -Desc "Store Auto-Download aus"
    Set-RegValue -Path "$HKLM\Policies\Microsoft\WindowsStore" -Name "RemoveWindowsStore" -Value 1 -Desc "Store deaktiviert"
    Set-RegValue -Path "$HKLM\Policies\Microsoft\WindowsStore" -Name "DisableStoreApps" -Value 1 -Desc "Store-Apps aus"
    Write-LogEntry "Windows Store vollstaendig deaktiviert" "SUCCESS"
}

# ============================================================================
# MODUL F: Permanentes Debloating (AppX + Capabilities)
# ============================================================================
function Invoke-Debloating {
    Write-LogEntry "Modul F: Permanentes Debloating" "HEAD"

    $AppList = @(
        "*Teams*", "*Xbox*", "*Copilot*", "*Clipchamp*", "*OneDrive*",
        "*OneNote*", "*News*", "*Weather*", "*Zune*", "*Bing*",
        "*Solitaire*", "*People*", "*CommunicationsApps*", "*Outlook*",
        "*SkypeApp*", "*WindowsFeedbackHub*", "*GetHelp*", "*Getstarted*",
        "*Maps*", "*Messaging*", "*MicrosoftOfficeHub*", "*MixedReality*",
        "*Paint3D*", "*SoundRecorder*", "*Todos*", "*Wallet*",
        "*WebExperience*", "*YourPhone*", "*WindowsStore*"
    )

    # 1. Provisioned Packages
    $Prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($Pattern in $AppList) {
        $Prov | Where-Object { $_.DisplayName -like $Pattern } | ForEach-Object {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-LogEntry "Provisioned entfernt: $($_.DisplayName)" "INFO"
        }
    }

    # 2. Installierte Pakete
    foreach ($Pattern in $AppList) {
        Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $Pattern } | ForEach-Object {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # 3. Win32 Teams Cleanup
    try { taskkill /f /im Teams.exe 2>$null | Out-Null } catch {}
    Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("Public", "Default", "All Users") } | ForEach-Object {
        $upd = Join-Path $_.FullName "AppData\Local\Microsoft\Teams\Update.exe"
        if (Test-Path $upd) { Start-Process -FilePath $upd -ArgumentList "--uninstall -s" -Wait -ErrorAction SilentlyContinue }
    }

    # 4. Windows Capabilities entfernen (aus V3)
    @("App.Support.QuickAssist*", "App.StepsRecorder*", "Browser.InternetExplorer*",
      "MathRecognizer*", "Microsoft.Windows.Wordpad*", "Print.Fax.Scan*") | ForEach-Object {
        Get-WindowsCapability -Online -Name $_ -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Installed' } | ForEach-Object {
                Remove-WindowsCapability -Online -Name $_.Name -ErrorAction SilentlyContinue | Out-Null
                Write-LogEntry "Capability entfernt: $($_.Name)" "INFO"
            }
    }

    Write-LogEntry "Debloating abgeschlossen" "SUCCESS"
}

# ============================================================================
# MODUL G: UI-Anpassungen & Explorer
# ============================================================================
function Invoke-UISetup {
    Write-LogEntry "Modul G: UI-Anpassungen & Explorer" "HEAD"
    @(
        # Classic Context Menu
        @{ Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name = ''; Value = ''; Type = 'String'; Desc = 'Classic Context Menu' },
        # Explorer
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Start_TaskbarAlignment'; Value = 0; Desc = 'Taskbar links' },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Hidden'; Value = 1; Desc = 'Versteckte Dateien an' },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'HideFileExt'; Value = 0; Desc = 'Dateiendungen an' },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'NavPaneExpandToCurrentFolder'; Value = 1; Desc = 'Nav aktueller Ordner' },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'DontUsePowerShellOnWinX'; Value = 0; Desc = 'PS im Win+X' },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name = 'ShowDriveLettersFirst'; Value = 4; Desc = 'LW-Buchstabe zuerst' },
        # Dark Mode
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = 'AppsUseLightTheme'; Value = 0; Desc = 'Dark Mode Apps' },
        # Clipboard History
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Clipboard"; Name = 'EnableClipboardHistory'; Value = 1; Desc = 'Clipboard History' },
        # Edge Hardening (aus V3)
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Edge"; Name = 'MetricsReportingEnabled'; Value = 0; Desc = 'Edge Metriken aus' },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Edge"; Name = 'HideFirstRunExperience'; Value = 1; Desc = 'Edge Onboarding aus' },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Edge"; Name = 'PersonalizationDataCollectionEnabled'; Value = 0; Desc = 'Edge Personalisierung aus' },
        @{ Path = "HKCU:\SOFTWARE\Policies\Microsoft\Edge"; Name = 'ShoppingAssistantEnabled'; Value = 0; Desc = 'Edge Shopping aus' },
        # Telemetrie HKCU
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Input\TIPC"; Name = 'Enabled'; Value = 0; Desc = 'Eingabe-Telemetrie aus' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"; Name = 'BingSearchEnabled'; Value = 0; Desc = 'Bing-Suche aus' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = 'SilentInstalledAppsEnabled'; Value = 0; Desc = 'Vorgeschlagene Apps aus' }
    ) | ForEach-Object { Set-RegValue -Path $_.Path -Name $_.Name -Value $_.Value -Type $(if ($_.Type) { $_.Type } else { "DWord" }) -Desc $_.Desc }

    # Windows Terminal als Standard
    Set-RegValue -Path "HKCU:\Console\%%Startup" -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -Type "String" -Desc "Windows Terminal Standard"
}

# ============================================================================
# MODUL H: Energie & System
# ============================================================================
function Invoke-SystemSetup {
    Write-LogEntry "Modul H: Energie & System" "HEAD"

    # Fast Boot aus (OPSI-Vorgabe)
    Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name 'HiberbootEnabled' -Value 0 -Desc "Fastboot aus"
    Set-RegValue -Path "$HKLM\Policies\Microsoft\Windows\Personalization" -Name 'NoLockScreen' -Value 1 -Desc "Lock Screen aus"

    # Power Timeouts
    try {
        powercfg /CHANGE MONITOR-TIMEOUT-AC 30 2>$null
        powercfg /CHANGE MONITOR-TIMEOUT-DC 30 2>$null
        powercfg /CHANGE STANDBY-TIMEOUT-AC 480 2>$null
        powercfg /CHANGE STANDBY-TIMEOUT-DC 480 2>$null
        Write-LogEntry "Energieplan: Monitor 30 / Standby 480 Min" "SUCCESS"
    } catch { Write-LogEntry "Energieplan-Fehler: $($_.Exception.Message)" "WARNING" }
}

# ============================================================================
# MODUL I: Treiber-Injektion
# ============================================================================
function Invoke-DriverInstall {
    if ($SkipDriverInstall) { Write-LogEntry "Treiber-Installation uebersprungen" "INFO"; return }
    if (-not (Test-Path $DriversPathSource)) { Write-LogEntry "Treiber-Pfad nicht gefunden: $DriversPathSource" "INFO"; return }

    Write-LogEntry "Modul I: Treiber-Injektion" "HEAD"
    try {
        pnputil /add-driver "$DriversPathSource\*.inf" /install /subdirs | Out-Null
        Write-LogEntry "Treiber aus $DriversPathSource injiziert" "SUCCESS"
    } catch { Write-LogEntry "Treiber-Fehler: $($_.Exception.Message)" "WARNING" }
}

# ============================================================================
# HAUPTAUSFUEHRUNG
# ============================================================================
function Main {
    Write-Host "`n--- Windows 11 Enterprise Hardening Suite V10.0 ---" -ForegroundColor Cyan
    Write-Host "    Konsolidiert: BSI + nLite + OPSI + Lab-Modus" -ForegroundColor Gray
    Write-LogEntry "Skriptstart auf $(hostname) durch $(whoami)"

    if (-not $SilentMode) {
        Write-Host "`nDieses Skript aendert tiefgreifende Systemeinstellungen:" -ForegroundColor Yellow
        Write-Host "  - Telemetrie wird deaktiviert" -ForegroundColor Gray
        Write-Host "  - Windows Store wird deaktiviert" -ForegroundColor Gray
        Write-Host "  - Bloatware wird permanent entfernt" -ForegroundColor Gray
        if (-not $EnableDefender) { Write-Host "  - Windows Defender wird DEAKTIVIERT" -ForegroundColor Red }
        $Confirm = Read-Host "`nFortfahren? (J/N)"
        if ($Confirm -ne "J") { Write-LogEntry "Abbruch durch Benutzer." "WARNING"; return }
    }

    Invoke-PrivacyHardening
    Invoke-DefenderControl
    Invoke-SecurityHardening
    Invoke-RemoteSetup
    Invoke-ServiceHardening
    Invoke-Debloating
    Invoke-UISetup
    Invoke-SystemSetup
    Invoke-DriverInstall

    Write-Host "`n--- Zusammenfassung ---" -ForegroundColor Cyan
    Write-Host "Erfolgreich: $($Global:Stats.Success)" -ForegroundColor Green
    Write-Host "Warnungen:   $($Global:Stats.Warnings)" -ForegroundColor Yellow
    Write-Host "Fehler:      $($Global:Stats.Errors)" -ForegroundColor Red
    Write-Host "Logdatei:    $Global:LogFile"

    if ($Global:Stats.Errors -eq 0) { exit 0 } else { exit 1 }
}

Clear-Host
Main
