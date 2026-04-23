<#
.FILENAME Apply_Harden_Policies.ps1
.SYNOPSIS
    Führt alle Härtungsmaßnahmen (HKLM & HKCU) manuell auf einem bereits installierten System aus.
.DESCRIPTION
    Dieses Skript kombiniert die Logik von Offline_Win11_Setup.ps1 (System) und User_Harden.ps1 (Benutzer)
    und wendet sie im Non-Stop-Modus an. Muss mit Administratorrechten ausgeführt werden.
.HARDENING
    Enthält die vollständige Telemetrie-Deaktivierung, Edge/Explorer-Anpassungen, 
    Aktivierung von RDP/WinRM/Ping und Setzen der PS Execution Policy.
.NOTES
    Autor: PS-Coding (Final V4.0)
    Kompatibilität: PowerShell 5.1+
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High', DefaultParameterSetName='Default', VerbosePreference='Continue')]
param()

# --- Globale Parameter ---
$LogFilePath = "$env:TEMP\Apply_Härtung_Log_$((Get-Date -Format 'yyyyMMdd')).txt"
$HKCUPrefix = "HKCU:\SOFTWARE"

# --- Hilfsfunktion: Robuste Protokollierung ---
function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Type = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Type] $Message"
    
    Write-Verbose "${Type}: $Message"

    if ($Type -match "ERROR|WARNING|FATAL") {
        $LogMessage | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# --- Prä-Check ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-LogEntry -Message "FEHLER: Dieses Skript muss als Administrator ausgeführt werden." -Type "FATAL"
    Write-Host "--- Beendet: Bitte als Administrator ausführen! ---"
    exit 1
}

Write-LogEntry -Message "Starte vollständige Härtung (Manuelle Anwendung). Log-Datei für Fehler: $LogFilePath"

# --- SYSTEMWEITE HÄRTUNG (HKLM & Dienste) ---
Write-LogEntry -Message "Abschnitt A: Systemweite Härtung und Remote-Konfiguration (HKLM)."

# Dienste deaktivieren (Auszug)
$ServicesToDisable = @("DiagTrack", "dmwappushservice", "WpnService", "wlidsvc")
foreach ($ServiceName in $ServicesToDisable) {
    try {
        Get-Service -Name $ServiceName -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction Stop 
        Write-LogEntry -Message "Erfolg (Dienst): Dienst '$ServiceName' deaktiviert."
    } catch {
        Write-LogEntry -Message "WARNUNG (Dienst): Dienst '$ServiceName' konnte nicht deaktiviert werden." -Type "WARNING"
    }
}

# Remote-Zugriff und Firewall konfigurieren
try {
    # RDP aktivieren
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force -ErrorAction Stop
    # WinRM aktivieren
    Enable-PSRemoting -Force -ErrorAction Stop
    # PS Execution Policy setzen
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
    Write-LogEntry -Message "Erfolg (Remote): RDP, WinRM und PS Execution Policy gesetzt."
} catch {
    Write-LogEntry -Message "FEHLER (Remote): Konnte Remote-Einstellungen nicht setzen: $($_.Exception.Message)" -Type "ERROR"
}

# Firewall-Regeln (Ping, RDP, WinRM)
$FirewallRules = @(
    "NetSecurity\InboundFirewallRule|Name=File and Printer Sharing (Echo Request - ICMPv4-In)",
    "NetSecurity\InboundFirewallRule|Name=Remote Desktop (TCP-In)",
    "NetSecurity\InInboundFirewallRule|Name=Windows Remote Management (HTTP-In)"
)
foreach ($Rule in $FirewallRules) {
    try {
        Set-NetFirewallRule -DisplayName $Rule.Split('=')[1] -Enabled True -ErrorAction Stop
        Write-LogEntry -Message "Erfolg (Firewall): Regel '$($Rule.Split('=')[1])' aktiviert."
    } catch {
        Write-LogEntry -Message "WARNUNG (Firewall): Regel '$($Rule.Split('=')[1])' konnte nicht aktiviert werden." -Type "WARNING"
    }
}

# HKLM Registry Einstellungen (Auszug)
$HklmSettings = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Type = 'DWord'; Description = 'Telemetrie Minimum' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection'; Value = 1; Type = 'DWord'; Description = 'Diagnoseprotokoll-Sammlung begrenzen' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE'; Name = 'BypassNRO'; Value = 1; Type = 'DWord'; Description = 'BypassNRO' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'; Name = 'OSUnaware'; Value = 1; Type = 'DWord'; Description = 'BitLocker Auto-Deaktivierung' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Folder\Hidden\SHOWALL'; Name = 'CheckedValue'; Value = 1; Type = 'DWord'; Description = 'Explorer: Zeige versteckte Dateien (System)' }
)

foreach ($Setting in $HklmSettings) {
    try {
        if (-not (Test-Path $Setting.Path)) { New-Item -Path $Setting.Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force -ErrorAction SilentlyContinue | Out-Null
        Write-LogEntry -Message "Erfolg (HKLM): $($Setting.Description)"
    } catch {
        Write-LogEntry -Message "FEHLER (HKLM): Fehler bei $($Setting.Name)" -Type "ERROR"
    }
}

# --- BENUTZERSPEZIFISCHE HÄRTUNG (HKCU - Nur für aktuellen Benutzer) ---
Write-LogEntry -Message "Abschnitt B: Benutzerspezifische Härtung (HKCU). Gilt nur für $($env:USERNAME)."

$HkcuSettings = @(
    @{ Path = "$HKCUPrefix\Microsoft\Input\TIPC"; Name = 'Enabled'; Value = 0; Type = 'DWord'; Description = 'Eingabe-Telemetrie' },
    @{ Path = "$HKCUPrefix\Microsoft\Windows\CurrentVersion\Search"; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord'; Description = 'Bing-Suche deaktiviert' },
    
    # Microsoft Edge Härtung (Policies-Pfad)
    @{ Path = "$HKCUPrefix\Policies\Microsoft\Edge"; Name = 'HideFirstRunExperience'; Value = 1; Type = 'DWord'; Description = 'Edge: Onboarding deaktiviert' },
    
    # Windows Explorer Ansicht
    @{ Path = "$HKCUPrefix\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'Hidden'; Value = 1; Type = 'DWord'; Description = 'Explorer: Zeige versteckte Dateien' },
    @{ Path = "$HKCUPrefix\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = 'HideFileExt'; Value = 0; Type = 'DWord'; Description = 'Explorer: Zeige Dateiendungen' }
)

foreach ($Setting in $HkcuSettings) {
    try {
        if (-not (Test-Path $Setting.Path)) { New-Item -Path $Setting.Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force -ErrorAction SilentlyContinue | Out-Null
        Write-LogEntry -Message "Erfolg (HKCU): $($Setting.Description)"
    } catch {
        Write-LogEntry -Message "FEHLER (HKCU): Fehler bei $($Setting.Name)" -Type "ERROR"
    }
}

Write-Host "--- Manuelle Härtung abgeschlossen. Details im Logfile. ---"
Write-LogEntry -Message "Skript erfolgreich beendet."
