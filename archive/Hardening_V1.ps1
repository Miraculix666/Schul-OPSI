<#
.FILENAME Apply_Harden_Policies.ps1
.SYNOPSIS
    Führt die vollständige System- und Benutzerhärtung (HKLM und HKCU) auf einem bereits installierten 
    Windows 11 Client aus. Dieses Skript ist für die nachträgliche Anwendung vorgesehen.
    
.DESCRIPTION
    Fokus: Non-Stop-Ausführung (Fehler werden geloggt, aber das Skript stoppt nicht).
    ACHTUNG: Die AppX-Entfernung wird hier NICHT unterstützt.
    
.PARAMETER Verbose
    Aktiviert die detaillierte Konsolenausgabe.
    
.NOTES
    Autor: PS-Coding
    Version: 1.1 (Non-Stop-Ausführung und detaillierte Fehlerprotokollierung)
    Ausführung: Muss als Administrator ausgeführt werden!
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium', DefaultParameterSetName='Default', VerbosePreference='Continue')]
param()

# --- Globale Variablen ---
$LogFilePath = "$env:TEMP\Apply_Härtung_Log_$((Get-Date -Format 'yyyyMMdd_HHmmss')).txt"

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
        # Versucht, ins Logfile zu schreiben (kann fehlschlagen, wenn keine Admin-Rechte)
        try {
            $LogMessage | Out-File -FilePath $LogFilePath -Append -Encoding UTF8
        } catch {}
    }
}

# --- 1. HKLM / Systemweite Einstellungen (Muss als Admin laufen) ---
function ApplySystemHarden {
    Write-LogEntry -Message "Starte HKLM Systemhärtung (Registry, Dienste, Energie)." -Type "HEAD"
    
    # Dienste deaktivieren
    $ServicesToDisable = @("DiagTrack", "dmwappushservice", "WpnService", "wlidsvc")
    foreach ($ServiceName in $ServicesToDisable) {
        try {
            Get-Service -Name $ServiceName -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction Stop
            Write-LogEntry -Message "Erfolg: Dienst '$ServiceName' deaktiviert."
        } catch {
            Write-LogEntry -Message "WARNUNG: Dienst '$ServiceName' konnte nicht deaktiviert werden." -Type "WARNING"
        }
    }

    # HKLM Registry Settings
    $RegistrySettingsHKLM = @(
        # Telemetrie (Policies)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Value = 0; Type = 'DWord' },
        # ... (Andere HKLM Registry-Einstellungen)
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection'; Value = 1; Type = 'DWord' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableOneSettingsDownloads'; Value = 1; Type = 'DWord' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Value = 1; Type = 'DWord' },
        # CEIP / Anwendungstelemetrie
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable'; Value = 0; Type = 'DWord' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Value = 0; Type = 'DWord' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Value = 1; Type = 'DWord' },
        # BitLocker Autodeaktivierung 
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'; Name = 'OSUnaware'; Value = 1; Type = 'DWord' }
    )

    foreach ($Setting in $RegistrySettingsHKLM) {
        try {
            if (-not (Test-Path $Setting.Path)) { New-Item -Path $Setting.Path -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force -ErrorAction SilentlyContinue | Out-Null
            Write-LogEntry -Message "HKLM: $($Setting.Name) auf $($Setting.Value) gesetzt."
        } catch {
            Write-LogEntry -Message "FEHLER HKLM: $($_.Exception.Message)" -Type "ERROR"
        }
    }

    # Energiespareinstellungen 
    $ScreensaverPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (-not (Test-Path $ScreensaverPath)) { New-Item -Path $ScreensaverPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $ScreensaverPath -Name "ScreenSaverIsSecure" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $ScreensaverPath -Name "ScreenSaverTimeOut" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
        powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT 238c9fa8-0aaa-4286-a491-30fd927a4a2c 29f6c1db-86da-48c5-9fdb-f2b67b1f4452 0 -ErrorAction Stop
        powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT 238c9fa8-0aaa-4286-a491-30fd927a4a2c 29f6c1db-86da-48c5-9fdb-f2b67b1f4452 0 -ErrorAction Stop
        Write-LogEntry -Message "System-Ruhezustand auf 'Nie' gesetzt."
    } catch {
        Write-LogEntry -Message "FEHLER bei Power-Einstellungen: $($_.Exception.Message)" -Type "ERROR"
    }
}

# --- 2. HKCU / Benutzerspezifische Einstellungen ---
function ApplyUserHarden {
    Write-LogEntry -Message "Starte HKCU Benutzerhärtung (Registry: Edge, Explorer)." -Type "HEAD"

    # HKCU Registry Settings
    $RegistrySettingsHKCU = @(
        # ... (HKCU Registry-Einstellungen)
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Input\TIPC'; Name = 'Enabled'; Value = 0; Type = 'DWord' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord' },
        # Edge Härtung
        @{ Path = 'HKCU:\Policies\Microsoft\Edge'; Name = 'MetricsReportingEnabled'; Value = 0; Type = 'DWord' },
        @{ Path = 'HKCU:\Policies\Microsoft\Edge'; Name = 'HideFirstRunExperience'; Value = 1; Type = 'DWord' },
        @{ Path = 'HKCU:\Policies\Microsoft\Edge'; Name = 'PersonalizationDataCollectionEnabled'; Value = 0; Type = 'DWord' },
        # Explorer Ansicht
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Value = 1; Type = 'DWord' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = 0; Type = 'DWord' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneExpandAll'; Value = 1; Type = 'DWord' }
    )

    foreach ($Setting in $RegistrySettingsHKCU) {
        try {
            if (-not (Test-Path $Setting.Path)) { New-Item -Path $Setting.Path -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force -ErrorAction SilentlyContinue | Out-Null
            Write-LogEntry -Message "HKCU: $($Setting.Name) auf $($Setting.Value) gesetzt."
        } catch {
            Write-LogEntry -Message "FEHLER HKCU: $($_.Exception.Message)" -Type "ERROR"
        }
    }
}

# --- 3. Hauptausführung ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-LogEntry -Message "FEHLER: Skript muss mit Administrator-Rechten ausgeführt werden." -Type "FATAL"
    Write-Host "`n`nFEHLER: Dieses Skript muss als Administrator ausgeführt werden!`n`n" -ForegroundColor Red
    exit 1
}

if ($PSCmdlet.ShouldProcess("System- und Benutzerhärtung anwenden", "Starten")) {
    ApplySystemHarden
    ApplyUserHarden # Führt HKCU für den aktuellen Admin-Benutzer aus
    Write-LogEntry -Message "Härtung abgeschlossen. Bitte das System neu starten, um alle Änderungen zu übernehmen. Siehe '$LogFilePath' für Fehler." -Type "SUCCESS"
}
