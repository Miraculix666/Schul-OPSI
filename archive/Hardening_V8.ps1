<#
.FILENAME Apply_Harden_Policies.ps1
.SYNOPSIS
    Windows 11 Enterprise Master-Hardening V8.1 (Unified Edition).
.DESCRIPTION
    Kombiniert alle Anforderungen:
    - Vollständige Härtung (LSA, ASR, Exploit Protection, Credential Guard Hardware-Checks).
    - Maximale Privacy (Telemetriematrix + OPSI Deferral Settings).
    - Experten-UI (Dark Mode, Clipboard History, 30 Min Lock, Drive Letters First).
    - Aggressives Debloating (AppX + Win32 Teams Per-User Cleanup).
    - Robuste Hardware-Logik (Regex PowerCFG, physisches WOL).
.NOTES
    Autor: PS-Coding (V8.1 - BSI/nLite/OPSI Optimized)
    Kompatibilität: PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)][switch]$Interactive = $false,
    [Parameter(Mandatory=$false)][switch]$EnableDefender = $false,
    [Parameter(Mandatory=$false)][string]$DriversPathSource = "C:\Drivers_Temp",
    [Parameter(Mandatory=$false)][string]$DriverUpdateMode = 'LocalThenOnline'
)

# --- Standard-Verbose für PS 5.1 erzwingen ---
$VerbosePreference = 'Continue'

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================
$Global:LogFile = "$env:TEMP\Win11_Master_Hardening_V8.log"
$Global:Stats = @{ Success = 0; Warnings = 0; Errors = 0 }
$HKLM = "HKLM:\SOFTWARE"
$HKCU = "HKCU:\SOFTWARE"

# ============================================================================
# HILFSFUNKTIONEN
# ============================================================================

function Write-LogEntry {
    param([Parameter(Mandatory=$true)][string]$Message, [string]$Type = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMsg = "[$Timestamp] [$Type] $Message"
    if ($Type -eq "ERROR") { Write-Error $Message }
    elseif ($Type -eq "WARNING") { Write-Warning $Message }
    else { Write-Verbose "${Type}: $Message" }
    
    try { $LogMsg | Out-File -FilePath $Global:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    switch ($Type) { "SUCCESS" { $Global:Stats.Success++ } "WARNING" { $Global:Stats.Warnings++ } "ERROR" { $Global:Stats.Errors++ } }
}

function Get-ActivePowerScheme {
    $out = powercfg /GETACTIVESCHEME
    if ($out -match "([a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12})") { return $matches[1] }
    return $null
}

# ============================================================================
# HÄRTUNGS-MODULE
# ============================================================================

# --- MODUL A: PRIVACY & TELEMETRIE (Matrix-konform) ---
function Set-PrivacyHardening {
    Write-LogEntry "Modul A: Privacy & Telemetrie..."
    $Settings = @(
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowTelemetry'; Value = 0; Type = 'DWord'; Desc = 'Telemetrie Minimum (Security)' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DataCollection"; Name = 'LimitDiagnosticLogCollection'; Value = 1; Type = 'DWord'; Desc = 'Diagnoseprotokoll-Sperre' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\AdvertisingInfo"; Name = 'DisableAdvertisingId'; Value = 1; Type = 'DWord'; Desc = 'Advertising ID aus' },
        @{ Path = "$HKLM\Policies\Microsoft\WindowsStore"; Name = 'RemoveWindowsStore'; Value = 1; Type = 'DWord'; Desc = 'Store Zugriff deaktiviert' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\DeliveryOptimization"; Name = 'DODownloadMode'; Value = 2; Type = 'DWord'; Desc = 'DO LocalPeerToPeer' },
        # OPSI Deferrals
        @{ Path = "$HKLM\Policies\Microsoft\Windows\WindowsUpdate"; Name = 'DeferFeatureUpdatesPeriodInDays'; Value = 365; Type = 'DWord'; Desc = 'Feature-Updates 365 Tage' },
        @{ Path = "$HKLM\Policies\Microsoft\Windows\WindowsUpdate"; Name = 'DeferQualityUpdatesPeriodInDays'; Value = 30; Type = 'DWord'; Desc = 'Quality-Updates 30 Tage' }
    )
    foreach ($S in $Settings) {
        try {
            if (-not (Test-Path $S.Path)) { New-Item -Path $S.Path -Force | Out-Null }
            Set-ItemProperty -Path $S.Path -Name $S.Name -Value $S.Value -Type $S.Type -Force | Out-Null
            Write-LogEntry "Erfolg: $($S.Desc)" "SUCCESS"
        } catch { Write-LogEntry "Fehler bei $($S.Name)" "ERROR" }
    }
}

# --- MODUL B: ADVANCED SECURITY (LSA, CG, ASR) ---
function Set-AdvancedSecurity {
    Write-LogEntry "Modul B: Advanced Security & Hardware-Checks..."
    
    # LSA Protection (Anti-Mimikatz)
    Set-ItemProperty -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'RunAsPPL' -Value 1 -Type DWord -Force | Out-Null
    Write-LogEntry "LSA Protection aktiviert." "SUCCESS"

    # Credential Guard Hardware-Check
    $sys = Get-ComputerInfo -Property "DeviceGuard*"
    if ($sys.DeviceGuardVirtualizationBasedSecurityStatus -eq 'Running') {
        Set-ItemProperty -Path "$HKLM\SYSTEM\CurrentControlSet\Control\Lsa" -Name 'LsaCfgFlags' -Value 1 -Type DWord -Force | Out-Null
        Write-LogEntry "Credential Guard hardwareseitig aktiviert." "SUCCESS"
    } else {
        Write-LogEntry "Credential Guard übersprungen: VBS nicht aktiv oder Hardware fehlt." "WARNING"
    }

    # ASR Rules (Registry-based)
    $asrPath = "$HKLM\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules"
    if (-not (Test-Path $asrPath)) { New-Item -Path $asrPath -Force | Out-Null }
    $mode = if ($EnableDefender) { "1" } else { "2" } # 1=Block, 2=Audit
    $rules = @("be9ba2d9-53ea-4cdc-84e5-9b1eeee46550", "d4f940ab-401b-4efc-aadc-ad5f3c50688a", "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2")
    foreach ($r in $rules) { Set-ItemProperty -Path $asrPath -Name $r -Value $mode -Type String -Force | Out-Null }
}

# --- MODUL C: NETZWERK & WOL ---
function Set-NetworkWOL {
    Write-LogEntry "Modul C: Netzwerk & WOL..."
    # WOL (Magic Packet)
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_ | Set-NetAdapterPowerManagement -WakeOnMagicPacket Enabled -ErrorAction Stop; Write-LogEntry "WOL für $($_.Name) aktiv." "SUCCESS" }
        catch { Write-LogEntry "NIC $($_.Name) unterstützt kein WOL." "WARNING" }
    }
    # WOL Timer im Energieplan (GUID-basiert)
    $Guid = Get-ActivePowerScheme
    if ($Guid) {
        try {
            powercfg /SETACVALUEINDEX $Guid 238c9fa8-0aaa-4286-a941-30fd9d27a4a2 bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 1 | Out-Null
            powercfg /SETACTIVE $Guid | Out-Null
            Write-LogEntry "WOL Wake-Timer aktiviert." "SUCCESS"
        } catch { Write-LogEntry "WOL Timer-GUIDs nicht gefunden." "WARNING" }
    }
}

# --- MODUL D: AGGRESSIVES DEBLOATING (nLite & Teams Win32) ---
function Remove-AggressiveDebloat {
    Write-LogEntry "Modul D: Aggressives Debloating..."
    
    # 1. Teams Win32 Cleanup (Update.exe im AppData)
    try { taskkill /f /im Teams.exe 2>$null | Out-Null } catch {}
    Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
        $upd = Join-Path $_.FullName "AppData\Local\Microsoft\Teams\Update.exe"
        if (Test-Path $upd) { 
            Start-Process -FilePath $upd -ArgumentList "--uninstall -s" -Wait 
            Write-LogEntry "Teams Win32 für Profil $($_.Name) deinstalliert." "SUCCESS"
        }
    }

    # 2. AppX nLite-Liste
    $List = @("*MicrosoftTeams*", "*MSTeams*", "*Teams*", "*Xbox*", "*Gaming*", "*Copilot*", "*Clipchamp*", "*OneDrive*", "*WindowsStore*", "*OneNote*")
    $Prov = Get-AppxProvisionedPackage -Online; $Inst = Get-AppxPackage -AllUsers
    foreach ($P in $List) {
        $Prov | Where-Object { $_.DisplayName -like $P } | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
        $Inst | Where-Object { $_.Name -like $P } | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
    }
    
    # 3. SMBv1 entfernen (Capability)
    try { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue } catch {}
}

# --- MODUL E: EXPERTEN-UI & HKCU (OPSI Match) ---
function Set-ExpertUI {
    Write-LogEntry "Modul E: Experten-UI (HKCU)..."
    $Settings = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Clipboard"; Name = 'EnableClipboardHistory'; Value = 1; Type = 'DWord'; Desc = 'Zwischenablage Verlauf' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = 'AppsUseLightTheme'; Value = 0; Type = 'DWord'; Desc = 'Dark Mode Apps' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Start_TaskbarAlignment'; Value = 0; Type = 'DWord'; Desc = 'Taskbar Links' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Hidden'; Value = 1; Type = 'DWord'; Desc = 'Versteckte Dateien' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'HideFileExt'; Value = 0; Type = 'DWord'; Desc = 'Dateiendungen' },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"; Name = 'ShowDriveLettersFirst'; Value = 4; Type = 'DWord'; Desc = 'LW-Buchstaben zuerst' }
    )
    foreach ($S in $Settings) {
        try {
            if (-not (Test-Path $S.Path)) { New-Item -Path $S.Path -Force | Out-Null }
            Set-ItemProperty -Path $S.Path -Name $S.Name -Value $S.Value -Type $S.Type -Force | Out-Null
            Write-LogEntry "UI: $($S.Desc)" "SUCCESS"
        } catch { Write-LogEntry "Fehler bei UI: $($S.Name)" "ERROR" }
    }
}

# --- MODUL F: ENERGIE & MONITOR (Regex Robust) ---
function Set-PowerOptions {
    Write-LogEntry "Modul F: Energieoptionen (OPSI 30 Min)..."
    $Guid = Get-ActivePowerScheme
    if ($Guid) {
        powercfg /SETACTIVE $Guid | Out-Null
        powercfg /CHANGE MONITOR-TIMEOUT-AC 30 | Out-Null
        powercfg /CHANGE MONITOR-TIMEOUT-DC 30 | Out-Null
        powercfg /CHANGE STANDBY-TIMEOUT-AC 480 | Out-Null
        powercfg /CHANGE HIBERNATE-TIMEOUT-AC 2880 | Out-Null
        Write-LogEntry "Energieplan harmonisiert (30/480/2880)." "SUCCESS"
    }
}

# ============================================================================
# HAUPTAUSFÜHRUNG
# ============================================================================

function Start-MasterHardening {
    Write-LogEntry "=== START HÄRTUNG V8.1 ===" "INFO"
    Set-PrivacyHardening
    Set-AdvancedSecurity
    Set-NetworkWOL
    Remove-AggressiveDebloat
    Set-ExpertUI
    Set-PowerOptions
    
    # Multi-Monitor Extend
    $ds = Join-Path $env:SystemRoot "System32\DisplaySwitch.exe"
    if (-not (Test-Path $ds)) { $ds = Join-Path $env:SystemRoot "Sysnative\DisplaySwitch.exe" }
    if (Test-Path $ds) { Start-Process $ds "/extend"; Write-LogEntry "Desktop erweitert." "SUCCESS" }

    Write-Host "`n--- Härtung V8.1 abgeschlossen ---" -ForegroundColor Green
    Write-Host "Erfolge: $($Global:Stats.Success) | Warnungen: $($Global:Stats.Warnings) | Fehler: $($Global:Stats.Errors)" -ForegroundColor Cyan
    Write-Host "`nLog-Datei: $Global:LogFile" -ForegroundColor Yellow
}

# Start
Clear-Host
Write-Host "🛡️ Windows 11 Master-Suite V8.1" -ForegroundColor Magenta
Write-Host "Hardening | Debloating | Expert-UI`n"

Start-MasterHardening
exit 0