# Filename: Apply_Harden_Policies.ps1
<#
.SYNOPSIS
    Windows 11 Master-Hardening Script V8.4 (Ultimate Edition).
.DESCRIPTION
    SINN: Dieses Skript ist das administrative Herzstück der Suite. Es führt die 
    Härtung (BSI/Matrix), das Debloating (nLite/Teams-Win32) und UI-Anpassungen durch.
    
    VERWENDUNG: Wird von OPSI in Phase 2 auf dem Zielsystem ausgeführt.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)][switch]$EnableDefender = $false,
    [Parameter(Mandatory=$false)][string]$DriversPathSource = "C:\Drivers_Temp",
    [Parameter(Mandatory=$false)][switch]$SkipDriverInstall = $false
)

# Standard-Konfiguration
$VerbosePreference = 'Continue'
$Global:LogFile = "$env:TEMP\Win11_Hardening_V8_4.log"
$Global:Stats = @{ Success = 0; Warnings = 0; Errors = 0 }
$HKLM = "HKLM:\SOFTWARE"
$HKCU = "HKCU:\SOFTWARE"

# --- Hilfsfunktionen für Robustheit ---
function Write-LogEntry {
    param([string]$Message, [string]$Type = "INFO")
    $Timestamp = Get-Date -Format "HH:mm:ss"
    $LogMsg = "[$Timestamp] [$Type] $Message"
    if ($Type -eq "ERROR") { Write-Error $Message }
    elseif ($Type -eq "WARNING") { Write-Warning $Message }
    else { Write-Verbose "${Type}: $Message" }
    try { $LogMsg | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    switch ($Type) { "SUCCESS" { $Global:Stats.Success++ } "WARNING" { $Global:Stats.Warnings++ } "ERROR" { $Global:Stats.Errors++ } }
}

function Set-RegSafe {
    param($Path, $Name, $Value, $Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}

# ============================================================================
# MODULE (V8.4)
# ============================================================================

function Set-PrivacyAndNLite {
    Write-LogEntry "Modul A: Privacy & nLite Sync..."
    $S = @(
        # Telemetrie & Data Collection (Matrix-konform)
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowTelemetry'; Value = 0; Desc = 'Telemetrie aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\AdvertisingInfo"; Name = 'DisabledByGroupPolicy'; Value = 1; Desc = 'Ad-ID aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DeliveryOptimization"; Name = 'DODownloadMode'; Value = 2; Desc = 'DO Peer-to-Peer' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\WindowsUpdate"; Name = 'DeferFeatureUpdatesPeriodInDays'; Value = 365; Desc = 'Update Deferral 365d' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\WindowsUpdate"; Name = 'DeferQualityUpdatesPeriodInDays'; Value = 30; Desc = 'Update Deferral 30d' },
        # nLite Spezifika
        @{ Path = "$HKLM\Policies\Microsoft\MRT"; Name = 'DontReportInfectionInformation'; Value = 1; Desc = 'MRT Telemetrie aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\WcmSvc\Local"; Name = 'AllowWiFiHotSpotReporting'; Value = 0; Desc = 'WiFi Sense aus' },
        @{ Path = "$HKLM\Policies\Microsoft\Edge"; Name = 'ExperimentationAndConfigurationServiceControl'; Value = 1; Desc = 'Edge Experimentation aus' }
    )
    foreach ($item in $S) { 
        if (Set-RegSafe -Path $item.Path -Name $item.Name -Value $item.Value) { Write-LogEntry "Erfolg: $($item.Desc)" "SUCCESS" } 
    }
}

function Set-AdvancedSecurity {
    Write-LogEntry "Modul B: Advanced Security (LSA & CG)..."
    Set-RegSafe -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'RunAsPPL' -Value 1 | Out-Null
    
    # Credential Guard Hardware-Validierung
    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName MSFT_DeviceGuard
        if ($dg.VirtualizationBasedSecurityStatus -ge 1) {
            Set-RegSafe -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'LsaCfgFlags' -Value 1 | Out-Null
            Write-LogEntry "Credential Guard hardware-validiert aktiviert." "SUCCESS"
        }
    } catch { Write-LogEntry "HW-Check für Credential Guard übersprungen." "WARNING" }

    # ASR Regeln (Block/Audit je nach Parameter)
    $asr = "$HKLM\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"
    $mode = if ($EnableDefender) { "1" } else { "2" }
    @("be9ba2d9-53ea-4cdc-84e5-9b1eeee46550", "d4f940ab-401b-4efc-aadc-ad5f3c50688a", "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2") | ForEach-Object {
        Set-RegSafe -Path $asr -Name $_ -Value $mode -Type "String" | Out-Null
    }
}

function Remove-AggressiveDebloat {
    Write-LogEntry "Modul D: Aggressives Debloating (Teams Win32 Fix)..."
    try { taskkill /f /im Teams.exe 2>$null | Out-Null } catch {}
    
    # Per-User Teams Win32 Cleanup (Sucht in jedem Benutzerprofil)
    Get-ChildItem -Path "C:\Users" -Directory | Where-Object { $_.Name -notin @("Public", "Default", "All Users") } | ForEach-Object {
        $upd = Join-Path $_.FullName "AppData\Local\Microsoft\Teams\Update.exe"
        if (Test-Path $upd) { 
            Write-LogEntry "Deinstalliere Win32 Teams für $($_.Name)..." "INFO"
            Start-Process -FilePath $upd -ArgumentList "--uninstall -s" -Wait 
        }
    }
    
    # nLite-basierte AppX Liste
    $List = @("*Teams*", "*Xbox*", "*Copilot*", "*Clipchamp*", "*OneDrive*", "*WindowsStore*", "*OneNote*", "*News*", "*Weather*")
    $Prov = Get-AppxProvisionedPackage -Online; $Inst = Get-AppxPackage -AllUsers
    foreach ($App in $List) {
        $Prov | Where-Object { $_.DisplayName -like $App } | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
        $Inst | Where-Object { $_.Name -like $App } | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
    }
}

function Set-ExpertUI {
    Write-LogEntry "Modul E: Experten-UI & Terminal..."
    $S = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Clipboard"; Name = 'EnableClipboardHistory'; Value = 1; Desc = 'Clipboard Historie' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = 'AppsUseLightTheme'; Value = 0; Desc = 'Dark Mode Apps' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Start_TaskbarAlignment'; Value = 0; Desc = 'Startmenü links' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Hidden'; Value = 1; Desc = 'Versteckte Dateien an' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"; Name = 'ShowDriveLettersFirst'; Value = 4; Desc = 'LW-Buchstabe zuerst' },
        # Classic Context Menu (Win10 Style)
        @{ Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name = ''; Value = ''; Type = 'String'; Desc = 'Classic Context Menu' }
    )
    foreach ($item in $S) { Set-RegSafe -Path $item.Path -Name $item.Name -Value $item.Value -Type ($item.Type ?: "DWord") | Out-Null }
    
    # Windows Terminal als Standard registrieren
    Set-RegSafe -Path "HKCU:\Console\%%Startup" -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -Type "String" | Out-Null
}

function Set-SystemAndPower {
    Write-LogEntry "Modul F: System & Energie (OPSI-Sync)..."
    # Fast Boot aus (OPSI Vorgabe) & Lock Screen aus
    Set-RegSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name 'HiberbootEnabled' -Value 0 | Out-Null
    Set-RegSafe -Path "$HKLM\Policies\Microsoft\Windows\Personalization" -Name 'NoLockScreen' -Value 1 | Out-Null
    
    # Power Timeouts robust setzen
    $Guid = (powercfg /GETACTIVESCHEME) -replace '.*GUID: ([\w-]+).*','$1'
    if ($Guid) {
        powercfg /CHANGE MONITOR-TIMEOUT-AC 30 | Out-Null
        powercfg /CHANGE MONITOR-TIMEOUT-DC 30 | Out-Null
        powercfg /CHANGE STANDBY-TIMEOUT-AC 480 | Out-Null
        Write-LogEntry "Energieplan 30/480 Min harmonisiert." "SUCCESS"
    }
}

# ============================================================================
# EXECUTION
# ============================================================================

function Start-Hardening {
    Write-LogEntry "=== BEGINN MASTER-HARDENING V8.4 ===" "INFO"
    Set-PrivacyAndNLite
    Set-AdvancedSecurity
    Set-ExpertUI
    Set-SystemAndPower
    Remove-AggressiveDebloat
    
    # Multi-Monitor (Sysnative Fallback)
    $ds = Join-Path $env:SystemRoot "System32\DisplaySwitch.exe"
    if (-not (Test-Path $ds)) { $ds = Join-Path $env:SystemRoot "Sysnative\DisplaySwitch.exe" }
    if (Test-Path $ds) { Start-Process $ds "/extend" -Wait }

    # Treiber Injektion
    if (-not $SkipDriverInstall -and (Test-Path $DriversPathSource)) {
        pnputil /add-driver "$DriversPathSource\*.inf" /install /subdirs | Out-Null
    }

    Write-Host "`nHärtung V8.4 abgeschlossen. Erfolge: $($Global:Stats.Success).`nLog: $Global:LogFile" -ForegroundColor Green
}

# Start-Logik
Clear-Host
Write-Host "🛡️ Windows 11 Enterprise Hardening Suite V8.4" -ForegroundColor Magenta
Start-Hardening
exit 0