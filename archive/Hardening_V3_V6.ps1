<#
.FILENAME ö
.SYNOPSIS
    Master-Skript zur nachträglichen Härtung und Konfiguration von Windows 11 (V6.0).
.DESCRIPTION
    Wird als OPSI-Softwarepaket nach der OS-Installation ausgeführt.
    Kombiniert alle Anforderungen: Tiefe Härtung (BSI/nLite-orientiert), Remote-Zugriff, 
    detaillierte Energieoptionen, Windows Update-Steuerung, Explorer-Anpassungen, 
    Teams-Entfernung und Online-Treiberinstallation (inkl. optionaler Online-Suche).
    Läuft im "Non-Stop"-Modus: Fehler werden geloggt, das Skript läuft weiter.
.PREPARATION (OPSI-Paket)
    1. Erstellen Sie ein OPSI-Softwarepaket (z.B. 'win11-hardening').
    2. Legen Sie dieses Skript (Apply_Harden_Policies.ps1) in das Paket-Root.
    3. Erstellen Sie einen Unterordner 'Drivers' im Paket (z.B. CLIENT_DATA\Drivers\).
    4. Legen Sie alle Online-Treiber (Grafik, Audio, NIC etc.) in diesen 'Drivers'-Ordner.
    5. Passen Sie die Variable '$DriversPathSource' in diesem Skript ggf. an den OPSI-Pfad an (Standard: "C:\Drivers_Temp").
    6. Rufen Sie dieses Skript im OPSI setup.opsiscript auf (siehe README.md für Beispiel).
.NOTES
    Autor: PS-Coding (Final V6.0 - OPSI-Entkoppelt)
    Kompatibilität: PowerShell 5.1+
    Quellen: AI-discovered sources, User-provided sources (diverse Chats, OPSI Logs, BSI, Telemetriematrix)
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High', DefaultParameterSetName='Default', VerbosePreference='Continue')]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('LocalOnly', 'LocalThenOnline', 'OnlineOnly')]
    [string]$DriverUpdateMode = 'LocalThenOnline', # Standard: Erst lokale Treiber, dann online suchen

    [Parameter(Mandatory=$false)]
    [string]$DriversPathSource = "C:\Drivers_Temp" # Pfad, wohin OPSI die Treiber kopiert
)

# --- Globale Parameter ---
$LogFilePath = "$env:TEMP\Apply_Härtung_Log_$((Get-Date -Format 'yyyyMMdd_HHmmss')).txt" # Zeitstempel für Eindeutigkeit
$HKCUPrefix = "HKCU:\SOFTWARE"
$HKLMprefix = "HKLM:\SOFTWARE"

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
        try {
            $LogMessage | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Warning "Konnte Logeintrag nicht schreiben: $($_.Exception.Message)"
        }
    }
}

# --- Prä-Check: Administratorrechte ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-LogEntry -Message "FEHLER: Dieses Skript muss als Administrator ausgeführt werden." -Type "FATAL"
    Write-Host "--- Beendet: Bitte als Administrator ausführen! ---" -ForegroundColor Red
    if (-not $env:PSIse) { Read-Host "Drücken Sie Enter zum Beenden." }
    exit 1
}

Write-LogEntry -Message "Starte vollständige Härtung & Konfiguration (V6.0). Log-Datei für Fehler: $LogFilePath"
Write-LogEntry -Message "Treiber-Update-Modus: $DriverUpdateMode"
Write-LogEntry -Message "Treiber-Quellpfad (lokal): $DriversPathSource"

# === ABSCHNITT A: SYSTEM-KONFIGURATION (REMOTE, UPDATE, WOL) ===
Write-LogEntry -Message "Abschnitt A: Konfiguriere Remote-Zugriff, Windows Update und WOL."

# --- 1. Remote-Zugriff und PowerShell-Scripting ---
if ($PSCmdlet.ShouldProcess("System", "Remote-Zugriff und PS-Scripting aktivieren")) {
    try {
        # 1.1 RDP aktivieren
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 -Type DWord -Force -ErrorAction Stop # NLA erzwingen
        
        # 1.2 PS-Remoting (WinRM) aktivieren
        # Enable-PSRemoting kann interaktiv sein, daher besser über WinRM Service und Firewall
        Set-Service -Name "WinRM" -StartupType Automatic -ErrorAction Stop
        Start-Service -Name "WinRM" -ErrorAction SilentlyContinue # Nur starten, wenn nicht schon läuft
        # winrm quickconfig -q # Alternative, kann aber Bestätigung erfordern
        
        # 1.3 PS Execution Policy setzen
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
        Write-LogEntry -Message "Erfolg (Remote): RDP, WinRM-Dienst und PS Execution Policy gesetzt."
    } catch {
        Write-LogEntry -Message "FEHLER (Remote): Konnte Remote-Einstellungen nicht setzen: $($_.Exception.Message)" -Type "ERROR"
    }
}

# --- 2. Firewall-Regeln anpassen (Ping, RDP, WinRM) ---
if ($PSCmdlet.ShouldProcess("System", "Firewall-Regeln für Ping, RDP, WinRM öffnen")) {
    # Robuster Ansatz: Gruppen aktivieren statt einzelner Regeln
    try {
        # Ping (ICMP Echo Request)
        Set-NetFirewallRule -DisplayGroup "Datei- und Druckerfreigabe" -Name "*echo*" -Enabled True -ErrorAction Stop
        
        # Remote Desktop
        Set-NetFirewallRule -DisplayGroup "Remotedesktop" -Enabled True -ErrorAction Stop
        
        # Windows Remote Management (WinRM) - HTTP (Standard)
        Set-NetFirewallRule -DisplayGroup "Windows-Remoteverwaltung" -Name "WINRM-HTTP-In-TCP-PUBLIC" -Enabled True -ErrorAction Stop # Für Public aktivieren, falls nötig anpassen
        Set-NetFirewallRule -DisplayGroup "Windows-Remoteverwaltung" -Name "WINRM-HTTP-In-TCP" -Enabled True -ErrorAction Stop       # Für Domain/Private
        
        Write-LogEntry -Message "Erfolg (Firewall): Regeln für Ping, RDP und WinRM aktiviert."
    } catch {
        Write-LogEntry -Message "FEHLER (Firewall): Regeln konnten nicht aktiviert werden: $($_.Exception.Message)" -Type "ERROR"
    }
}

# --- 3. Windows Update (Automatisch suchen, zur Installation benachrichtigen) ---
if ($PSCmdlet.ShouldProcess("System", "Windows Update konfigurieren")) {
    try {
        $WUPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        $AUPath = Join-Path $WUPath 'AU'
        if (-not (Test-Path $AUPath)) { New-Item -Path $AUPath -Force -ErrorAction Stop | Out-Null }
        
        # Automatisches Suchen erlauben
        Set-ItemProperty -Path $AUPath -Name 'NoAutoUpdate' -Value 0 -Type DWord -Force -ErrorAction Stop
        
        # 3 = Auto download and notify for install.
        Set-ItemProperty -Path $AUPath -Name 'AUOptions' -Value 3 -Type DWord -Force -ErrorAction Stop
        
        # Feature-Updates zurückstellen (optional, hier 180 Tage)
        # Set-ItemProperty -Path $WUPath -Name 'DeferFeatureUpdates' -Value 1 -Type DWord -Force -ErrorAction Stop
        # Set-ItemProperty -Path $WUPath -Name 'DeferFeatureUpdatesPeriodInDays' -Value 180 -Type DWord -Force -ErrorAction Stop
        
        Write-LogEntry -Message "Erfolg (Update): Windows Update auf 'Automatisch suchen/downloaden, manuell installieren' (AUOptions=3) gesetzt."
    } catch {
        Write-LogEntry -Message "FEHLER (Update): Windows Update-Richtlinien konnten nicht gesetzt werden: $($_.Exception.Message)" -Type "ERROR"
    }
}

# --- 4. Wake-on-LAN (WOL) ---
if ($PSCmdlet.ShouldProcess("System", "Wake-on-LAN (WOL) konfigurieren")) {
    try {
        # 4.1 Energieplan: Wake-Timer erlauben
        $CurrentScheme = powercfg /GETACTIVESCHEME
        $SchemeGuid = ($CurrentScheme -split ' ')[3] # Extrahiert die GUID
        
        # GUID für "Allow wake timers" (Energie sparen -> Zeitgeber zur Aktivierung zulassen)
        $SubGroupGuid = "238c9fa8-0aaa-4286-a941-30fd9d27a4a2" # Subgroup Sleep
        $SettingGuid = "bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d" # Setting Allow wake timers
        
        powercfg /SETACVALUEINDEX $SchemeGuid $SubGroupGuid $SettingGuid 1 | Out-Null # On AC
        powercfg /SETDCVALUEINDEX $SchemeGuid $SubGroupGuid $SettingGuid 1 | Out-Null # On DC
        powercfg /SETACTIVE $SchemeGuid | Out-Null # Erneut aktivieren, um Änderungen anzuwenden
        
        # 4.2 NIC-Einstellungen (WMI für physische Adapter)
        # Sucht physische Adapter mit IP und aktiviert WOL-Optionen
        $PhysicalAdapters = Get-CimInstance -ClassName Win32_NetworkAdapter -Filter "NetConnectionID IS NOT NULL AND PhysicalAdapter = TRUE"
        foreach ($Adapter in $PhysicalAdapters) {
            try {
                $PowerManagement = Get-CimAssociatedInstance -InputObject $Adapter -ResultClassName Win32_NetworkAdapterConfiguration
                if ($PowerManagement.IPEnabled) {
                     # Hole die Power Management Fähigkeiten
                    $PMC = Get-CimAssociatedInstance -InputObject $Adapter -ResultClassName Win32_PNPEntity | Get-CimInstance -ClassName MSiDN_PowerManagementCapabilities # Dies braucht ggf. Admin-Rechte
                    
                    if ($PMC -and $PMC.WakeFromPowerState -contains 3) { # Prüft ob Magic Packet unterstützt wird
                         # Aktiviere die Power Management Features über WMI Methoden (vorsichtig!)
                        # (Get-WmiObject Win32_NetworkAdapter -Filter "Index=$($Adapter.Index)").EnableWakeOnLan(1) # Beispiel, genaue Methode kann variieren
                        
                        # Sichererer Ansatz: Registry für bekannte Treiber (Intel/Realtek)
                        $PnPDeviceID = $Adapter.PNPDeviceID
                        $DriverKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}" # Network Adapters Class GUID
                        $DriverInstances = Get-ChildItem -Path $DriverKeyPath -Recurse -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty -Path $_.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue)."DriverDesc" -eq $Adapter.Name }

                        foreach ($Instance in $DriverInstances) {
                            # Intel: EnablePME=1 / WakeOnMagicPacket=1
                            Set-ItemProperty -Path $Instance.PSPath -Name "EnablePME" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                            Set-ItemProperty -Path $Instance.PSPath -Name "WakeOnMagicPacket" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                            # Realtek: WolSpeed = 1 (oder andere Werte je nach Chip) / WakeOnPattern / WakeOnMagicPacket
                            Set-ItemProperty -Path $Instance.PSPath -Name "WakeOnMagicPacket" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                        }
                         Write-LogEntry -Message "INFO (WOL): WOL-Registry-Keys für NIC '$($Adapter.Name)' gesetzt (falls Intel/Realtek)."
                    } else {
                         Write-LogEntry -Message "INFO (WOL): NIC '$($Adapter.Name)' unterstützt WOL möglicherweise nicht." -Type "INFO"
                    }
                }
            } catch {
                Write-LogEntry -Message "WARNUNG (WOL): Fehler beim Konfigurieren der NIC '$($Adapter.Name)': $($_.Exception.Message)" -Type "WARNING"
            }
        }
        Write-LogEntry -Message "Erfolg (WOL): Wake-Timer und NIC-Einstellungen für WOL (versucht) zu aktivieren."
    } catch {
        Write-LogEntry -Message "FEHLER (WOL): Konnte WOL-Einstellungen nicht anwenden: $($_.Exception.Message)" -Type "ERROR"
    }
}

# === ABSCHNITT B: ENERGIEEINSTELLUNGEN (PowerCFG - Detailliert) ===
Write-LogEntry -Message "Abschnitt B: Konfiguriere Energieoptionen (Monitor, Sleep, Hibernate)."
if ($PSCmdlet.ShouldProcess("System", "Energieoptionen anwenden")) {
    try {
        $CurrentScheme = powercfg /GETACTIVESCHEME
        $SchemeGuid = ($CurrentScheme -split ' ')[3]
        
        # Aktiviert Hibernation (notwendig für Hibernate-Timeout)
        powercfg /hibernate on
        
        # Setzt alle Werte in Minuten (0 = Nie)
        # AC = Netzbetrieb, DC = Akkubetrieb
        
        # Bildschirmschoner (via Registry, da PowerCfg unzuverlässig)
        $SSPath = 'HKCU:\Control Panel\Desktop' # Gilt für den aktuellen Benutzer (SYSTEM)
        Set-ItemProperty -Path $SSPath -Name "ScreenSaveActive" -Value "1" -Type String -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $SSPath -Name "ScreenSaverIsSecure" -Value "0" -Type String -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $SSPath -Name "ScreenSaveTimeOut" -Value (20 * 60).ToString() -Type String -Force -ErrorAction SilentlyContinue | Out-Null # 20 Min in Sekunden
        Set-ItemProperty -Path $SSPath -Name "SCRNSAVE.EXE" -Value "C:\Windows\System32\scrnsave.scr" -Type String -Force -ErrorAction SilentlyContinue | Out-Null # Standard "Leer"
        Write-LogEntry -Message "INFO (Energie): Bildschirmschoner-Registry für aktuellen Benutzer gesetzt (20 Min)."

        # PowerCFG für Monitor, Standby, Hibernate
        powercfg /change -scheme $SchemeGuid -monitor-timeout-ac 60     # Monitor aus nach 60 Min (AC)
        powercfg /change -scheme $SchemeGuid -monitor-timeout-dc 60     # Monitor aus nach 60 Min (DC)
        powercfg /change -scheme $SchemeGuid -standby-timeout-ac 480    # Standby (Sleep) nach 8 Stunden (AC)
        powercfg /change -scheme $SchemeGuid -standby-timeout-dc 480    # Standby (Sleep) nach 8 Stunden (DC)
        powercfg /change -scheme $SchemeGuid -hibernate-timeout-ac 2880 # Ruhezustand (Hibernate) nach 2 Tagen (AC)
        powercfg /change -scheme $SchemeGuid -hibernate-timeout-dc 2880 # Ruhezustand (Hibernate) nach 2 Tagen (DC)
        
        # Änderungen anwenden
        powercfg /SETACTIVE $SchemeGuid | Out-Null
        
        Write-LogEntry -Message "Erfolg (Energie): Energieplan (Monitor 60, Sleep 480, Hibernate 2880 Min) gesetzt."
    } catch {
        Write-LogEntry -Message "FEHLER (Energie): Konnte powercfg-Befehle nicht ausführen: $($_.Exception.Message)" -Type "ERROR"
    }
}

# === ABSCHNITT C: ONLINE TREIBER INSTALLATION ===
Write-LogEntry -Message "Abschnitt C: Installiere Online-Treiber."
if ($PSCmdlet.ShouldProcess("System", "Online-Treiber installieren (Modus: $DriverUpdateMode)")) {

    $driversInstalled = $false

    # --- Lokale Treiber zuerst (falls Modus erlaubt) ---
    if ($DriverUpdateMode -in ('LocalOnly', 'LocalThenOnline')) {
        if (Test-Path $DriversPathSource -PathType Container) {
            Write-LogEntry -Message "Lokaler Treiber-Ordner '$DriversPathSource' gefunden. Starte PnPUtil..."
            try {
                # pnputil gibt manchmal Fehlercodes zurück, auch wenn Treiber installiert wurden.
                $pnpResult = pnputil /add-driver "$DriversPathSource\*.inf" /install /subdirs
                Write-LogEntry -Message "INFO (Treiber): PnPUtil-Ausgabe für lokale Treiber: $pnpResult"
                Write-LogEntry -Message "Erfolg (Treiber): Lokale PnPUtil-Treiberinstallation abgeschlossen (Prüfung auf Fehler empfohlen)."
                $driversInstalled = $true # Markieren, dass zumindest versucht wurde
            } catch {
                Write-LogEntry -Message "FEHLER (Treiber): Lokale PnPUtil-Treiberinstallation fehlgeschlagen: $($_.Exception.Message)" -Type "ERROR"
            }
        } else {
            Write-LogEntry -Message "INFO (Treiber): Kein lokaler 'Drivers'-Ordner in '$DriversPathSource' gefunden." -Type "INFO"
        }
    }

    # --- Online-Suche (falls Modus erlaubt) ---
    # Vorsicht: Benötigt Internetzugang und kann Telemetrie auslösen!
    if ($DriverUpdateMode -in ('OnlineOnly', 'LocalThenOnline')) {
        Write-LogEntry -Message "INFO (Treiber): Starte Online-Treibersuche via Windows Update (Kann dauern)..." -Type "INFO"
        try {
            # Prüfen ob das Modul verfügbar ist (Server vs. Client OS)
            if (Get-Module -ListAvailable -Name WindowsUpdateProvider) {
                 # Dieses Cmdlet sucht und installiert Treiber über WU
                 # Update-WindowsDriver -OnlineScan -AcceptAll # VORSICHT: Kann unerwünschte Treiber installieren!
                 # Sicherer Ansatz: Nur suchen und Log schreiben
                $onlineDrivers = Update-WindowsDriver -OnlineScan -Verbose
                Write-LogEntry -Message "INFO (Treiber): Online-Suche abgeschlossen. Gefundene Treiber: $($onlineDrivers | Out-String)" -Type "INFO"
                # Hier könnte man eine Logik einbauen, um nur bestimmte Treiber zu installieren
                # z.B. Update-WindowsDriver -OnlineScan -AcceptAll -DriverManufacturer "NVIDIA"
                Write-LogEntry -Message "Erfolg (Treiber): Online-Treibersuche abgeschlossen (keine automatische Installation implementiert)."
            } else {
                 Write-LogEntry -Message "WARNUNG (Treiber): Modul 'WindowsUpdateProvider' nicht gefunden. Online-Treibersuche übersprungen." -Type "WARNING"
            }
        } catch {
            Write-LogEntry -Message "FEHLER (Treiber): Online-Treibersuche fehlgeschlagen: $($_.Exception.Message)" -Type "ERROR"
        }
    }

    if (-not $driversInstalled -and $DriverUpdateMode -eq 'LocalOnly') {
         Write-LogEntry -Message "WARNUNG (Treiber): Keine lokalen Treiber gefunden und Online-Suche deaktiviert." -Type "WARNING"
    }
}


# === ABSCHNITT D: SYSTEMWEITE HÄRTUNG (HKLM, Dienste, Ballast) ===
Write-LogEntry -Message "Abschnitt D: Systemweite Härtung (HKLM, Dienste, AppX)."

if ($PSCmdlet.ShouldProcess("System", "Systemweite Härtung anwenden")) {

    # --- 1. Dienste deaktivieren ---
    $ServicesToDisable = @("DiagTrack", "dmwappushservice", "WpnService", "wlidsvc", "Themes", "DusmSvc") # Themes hinzugefügt
    foreach ($ServiceName in $ServicesToDisable) {
        try {
            $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($Service -and $Service.Status -ne 'Stopped') {
                 Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            }
            if ($Service) {
                Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction Stop 
                Write-LogEntry -Message "Erfolg (Dienst): Dienst '$ServiceName' gestoppt und deaktiviert."
            } else {
                 Write-LogEntry -Message "INFO (Dienst): Dienst '$ServiceName' nicht gefunden." -Type "INFO"
            }
        } catch {
            Write-LogEntry -Message "WARNUNG (Dienst): Dienst '$ServiceName' konnte nicht deaktiviert werden: $($_.Exception.Message)" -Type "WARNING"
        }
    }

    # --- 2. HKLM Registry Härtung (Erweitert) ---
    $HklmSettings = @(
        # DataCollection (Telemetrie Kern)
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowTelemetry'; Value = 0; Type = 'DWord'; Description = 'Telemetrie Minimum (Security)' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'LimitEnhancedDiagnosticDataWindowsAnalytics'; Value = 1; Type = 'DWord'; Description = 'Analytics begrenzen' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'ConfigureTelemetryOptInSettingsUx'; Value = 1; Type = 'DWord'; Description = 'Opt-In UX deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'LimitDiagnosticLogCollection'; Value = 1; Type = 'DWord'; Description = 'Diagnoseprotokoll-Sammlung begrenzen' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'DisableOneSettingsDownloads'; Value = 1; Type = 'DWord'; Description = 'OneSettings Downloads deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'DisableDeviceDelete'; Value = 1; Type = 'DWord'; Description = 'Geräte-Löschung via Cloud deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowUpdateComplianceProcessing'; Value = 0; Type = 'DWord'; Description = 'Update Compliance deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowCommercialDataPipeline'; Value = 0; Type = 'DWord'; Description = 'Commercial Data Pipeline deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'AllowDesktopAnalyticsProcessing'; Value = 0; Type = 'DWord'; Description = 'Desktop Analytics deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\DataCollection"; Name = 'DoNotShowFeedbackNotifications'; Value = 1; Type = 'DWord'; Description = 'Feedback-Benachrichtigungen unterdrücken' },

        # Windows Error Reporting (WER)
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\Windows Error Reporting"; Name = 'Disabled'; Value = 1; Type = 'DWord'; Description = 'WER deaktivieren' },
        @{ Path = "$HKLMprefix\Microsoft\Windows\Windows Error Reporting"; Name = 'Disabled'; Value = 1; Type = 'DWord'; Description = 'WER deaktivieren (Legacy)' }, # Auch non-policy Key setzen

        # Customer Experience Improvement Program (CEIP)
        @{ Path = "$HKLMprefix\Policies\Microsoft\SQMClient\Windows"; Name = 'CEIPEnable'; Value = 0; Type = 'DWord'; Description = 'CEIP deaktiviert' },
        @{ Path = "$HKLMprefix\Microsoft\SQMClient\Windows"; Name = 'CEIPEnable'; Value = 0; Type = 'DWord'; Description = 'CEIP deaktiviert (Legacy)' },

        # App Compat / Inventory
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\AppCompat"; Name = 'AITEnable'; Value = 0; Type = 'DWord'; Description = 'Anwendungstelemetrie deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\AppCompat"; Name = 'DisableInventory'; Value = 1; Type = 'DWord'; Description = 'Inventory Collector deaktivieren' },

        # Push Notifications (WNS/WpnService related)
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = 'NoToastApplicationNotification'; Value = 1; Type = 'DWord'; Description = 'Toast-Notifications (Apps) deaktivieren' }, # Policy Key
        @{ Path = "$HKLMprefix\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = 'ToastEnabled'; Value = 0; Type = 'DWord'; Description = 'Toast-Notifications (System) deaktivieren' }, # Non-Policy Key

        # Cloud Content / Consumer Experiences
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\CloudContent"; Name = 'DisableWindowsConsumerFeatures'; Value = 1; Type = 'DWord'; Description = 'Consumer Features deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\CloudContent"; Name = 'DisableWindowsSpotlightFeatures'; Value = 1; Type = 'DWord'; Description = 'Spotlight Features deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\CloudContent"; Name = 'DisableSoftLanding'; Value = 1; Type = 'DWord'; Description = 'Soft Landing (Werbung) deaktivieren' },

        # Location Service
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\LocationAndSensors"; Name = 'DisableLocation'; Value = 1; Type = 'DWord'; Description = 'Location Service deaktivieren' },

        # Maps / Offline Maps AutoDownload
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\Maps"; Name = 'AutoDownloadAndUpdateMapData'; Value = 0; Type = 'DWord'; Description = 'Karten Auto-Download deaktivieren' },

        # OneDrive (Policy - Deaktiviert Integration)
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\OneDrive"; Name = 'DisableFileSyncNGSC'; Value = 1; Type = 'DWord'; Description = 'OneDrive Integration deaktivieren' },

        # Cortana (Policy)
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\Windows Search"; Name = 'AllowCortana'; Value = 0; Type = 'DWord'; Description = 'Cortana deaktivieren' },

        # Activity Feed / Timeline
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\System"; Name = 'EnableActivityFeed'; Value = 0; Type = 'DWord'; Description = 'Activity Feed deaktivieren' },
        @{ Path = "$HKLMprefix\Policies\Microsoft\Windows\System"; Name = 'PublishUserActivities'; Value = 0; Type = 'DWord'; Description = 'User Activities nicht publizieren' },
    )
    foreach ($Setting in $HklmSettings) {
        try {
            if (-not (Test-Path $Setting.Path)) { New-Item -Path $Setting.Path -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force -ErrorAction SilentlyContinue | Out-Null
            Write-LogEntry -Message "Erfolg (HKLM): $($Setting.Description)"
        } catch {
            Write-LogEntry -Message "FEHLER (HKLM): Fehler bei '$($Setting.Name)': $($_.Exception.Message)" -Type "ERROR"
        }
    }

    # --- 3. AppX / Ballast Entfernung (Erweitert) ---
    $PackagesToRemove = @(
        "*MicrosoftTeams*", # Teams entfernen
        "*Outlook*", # Mail & Kalender Apps (Falls nicht benötigt)
        "*People*", # Kontakte App
        "*SkypeApp*",
        "*WindowsAlarms*",
        "*WindowsCalculator*", # Ggf. behalten?
        "*WindowsCamera*",
        "*WindowsCommunicationsApps*", # Mail, Kalender, People
        "*WindowsFeedbackHub*",
        "*GetHelp*",
        "*Getstarted*", # Tipps App
        "*Maps*",
        "*Messaging*",
        "*MicrosoftOfficeHub*",
        "*MicrosoftSolitaireCollection*",
        "*MixedReality*",
        "*News*", # Microsoft News / MSN Nachrichten
        "*OneNote*", # Falls nicht benötigt
        "*Paint3D*",
        "*ScreenSketch*", # Ausschneiden und Skizzieren
        "*SoundRecorder*", # Sprachrekorder
        "*StickyNotes*", # Kurznotizen
        "*Microsoft.Todos*", # Microsoft To Do
        "*Wallet*",
        "*WebExperience*", # Widgets
        "*Weather*", # MSN Wetter
        "*Xbox*", # Alle Xbox Komponenten
        "*YourPhone*", # Smartphone-Link
        "*ZuneMusic*", # Groove Musik
        "*ZuneVideo*"  # Filme & TV
    )
    # Entferne Provisioned Packages (für neue Benutzer)
    $cachedProv = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($PackagePattern in $PackagesToRemove) {
        try {
            $cachedProv | Where-Object { $_.DisplayName -like $PackagePattern } | ForEach-Object {
                Write-LogEntry -Message "INFO (AppX): Entferne Provisioned Package '$($_.DisplayName)'..." -Type "INFO"
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop
                Write-LogEntry -Message "Erfolg (AppX): Provisioned Package '$($_.DisplayName)' entfernt."
            }
        } catch {
            Write-LogEntry -Message "FEHLER (AppX Provisioned): '$PackagePattern': $($_.Exception.Message)" -Type "ERROR"
        }
    }
     # Entferne installierte Pakete für den aktuellen Benutzer (SYSTEM) - oft nicht nötig, aber zur Sicherheit
    $cachedInst = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    foreach ($PackagePattern in $PackagesToRemove) {
        try {
            $cachedInst | Where-Object { $_.Name -like $PackagePattern } | ForEach-Object {
                 Write-LogEntry -Message "INFO (AppX): Entferne installiertes Package '$($_.Name)'..." -Type "INFO"
                Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
                 Write-LogEntry -Message "Erfolg (AppX): Installiertes Package '$($_.Name)' entfernt."
            }
        } catch {
            Write-LogEntry -Message "FEHLER (AppX Installed): '$PackagePattern': $($_.Exception.Message)" -Type "ERROR"
        }
    }

    # --- 4. Optionale Windows Features / Capabilities entfernen ---
    $CapabilitiesToRemove = @(
        "App.Support.QuickAssist",
        "App.StepsRecorder", # Problemaufzeichnung
        "Browser.InternetExplorer", # IE11
        "Hello.Face", # Windows Hello Gesichtserkennung
        "MathRecognizer",
        "Media.WindowsMediaPlayer", # WMP
        "Microsoft.Windows.Wordpad", # Wordpad
        "Print.Fax.Scan", # Windows Fax & Scan
        "Language.Handwriting*", # Handschrift (alle Sprachen)
        "Language.Speech*"     # Spracheingabe (alle Sprachen)
    )
     foreach ($CapPattern in $CapabilitiesToRemove) {
        try {
            Get-WindowsCapability -Online -Name $CapPattern -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Installed' } | ForEach-Object {
                Write-LogEntry -Message "INFO (Capability): Entferne '$($_.Name)'..." -Type "INFO"
                Remove-WindowsCapability -Online -Name $_.Name -ErrorAction Stop
                Write-LogEntry -Message "Erfolg (Capability): '$($_.Name)' entfernt."
            }
        } catch {
            Write-LogEntry -Message "FEHLER (Capability): '$CapPattern': $($_.Exception.Message)" -Type "ERROR"
        }
    }
} # End ShouldProcess System Härtung

# === ABSCHNITT E: BENUTZERSPEZIFISCHE HÄRTUNG (HKCU - Nur für aktuellen Benutzer SYSTEM) ===
Write-LogEntry -Message "Abschnitt E: Benutzerspezifische Härtung (HKCU). Gilt für den ausführenden Benutzer (SYSTEM)."

if ($PSCmdlet.ShouldProcess("Benutzer (SYSTEM)", "Benutzerspezifische Härtung anwenden")) {

    $HkcuSettings = @(
        # Telemetrie & Datenschutz
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Input\TIPC'; Name = 'Enabled'; Value = 0; Type = 'DWord'; Description = 'Eingabe-Telemetrie deaktiviert' },
        @{ Path = 'HKCU:\Control Panel\International\User Profile'; Name = 'HttpAcceptLanguageOptOut'; Value = 1; Type = 'DWord'; Description = 'Websites Sprachliste deaktivieren' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackProgs'; Value = 0; Type = 'DWord'; Description = 'App-Starts nicht nachverfolgen' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Messaging'; Name = 'CloudServiceSyncEnabled'; Value = 0; Type = 'DWord'; Description = 'Nachrichten Cloud-Sync deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Value = 1; Type = 'DWord'; Description = 'Freihand-Wörterbuchabgleich deaktivieren' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Value = 1; Type = 'DWord'; Description = 'Texteingabe-Wörterbuchabgleich deaktivieren' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore'; Name = 'HarvestContacts'; Value = 0; Type = 'DWord'; Description = 'Kontakte nicht für Personalisierung nutzen' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings'; Name = 'AcceptedPrivacyPolicy'; Value = 0; Type = 'DWord'; Description = 'Privacy Policy zurückgesetzt' }, # Erzwingt erneute Abfrage (falls gewünscht)

        # Suche & Cloud
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Value = 0; Type = 'DWord'; Description = 'Bing-Suche deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Value = 1; Type = 'DWord'; Description = 'Suchvorschläge deaktivieren' }, # Policy Key

        # Consumer Features
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Value = 0; Type = 'DWord'; Description = 'Vorgeschlagene Apps deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Type = 'DWord'; Description = 'Systemvorschläge deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Value = 0; Type = 'DWord'; Description = 'OneDrive/Cloud Benachrichtigungen deaktivieren' },
        
        # Edge (Policies-Pfad)
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'MetricsReportingEnabled'; Value = 0; Type = 'DWord'; Description = 'Edge: Metriken deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HideFirstRunExperience'; Value = 1; Type = 'DWord'; Description = 'Edge: Onboarding deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'PersonalizationDataCollectionEnabled'; Value = 0; Type = 'DWord'; Description = 'Edge: Personalisierung deaktiviert' },
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'ShowRecommendationsEnabled'; Value = 0; Type = 'DWord'; Description = 'Edge: Empfehlungen deaktivieren' },
        @{ Path = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'ShoppingAssistantEnabled'; Value = 0; Type = 'DWord'; Description = 'Edge: Shopping Assistent deaktivieren' },

        # Explorer Ansicht
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Value = 1; Type = 'DWord'; Description = 'Explorer: Zeige versteckte Dateien' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Value = 0; Type = 'DWord'; Description = 'Explorer: Zeige Dateiendungen' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCompColor'; Value = 1; Type = 'DWord'; Description = 'Explorer: Komprimierte Dateien farbig' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneExpandToCurrentFolder'; Value = 1; Type = 'DWord'; Description = 'Explorer: Aktuellen Ordner im Nav.-Bereich aufklappen' }, # Besser als ExpandAll
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'NavPaneShowAllFolders'; Value = 1; Type = 'DWord'; Description = 'Explorer: Alle Ordner im Nav.-Bereich anzeigen' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DontUsePowerShellOnWinX'; Value = 0; Type = 'DWord'; Description = 'Explorer: PowerShell im Win+X Menü statt CMD' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CabinetState'; Name = 'FullPath'; Value = 1; Type = 'DWord'; Description = 'Explorer: Vollen Pfad in Titelleiste anzeigen' }, # Braucht CabinetState Key
        
        # Laufwerke immer anzeigen
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideDrivesWithNoMedia'; Value = 0; Type = 'DWord'; Description = 'Explorer: Leere Laufwerke anzeigen' },
    )

    # Sicherstellen, dass der CabinetState-Key existiert
    $CabinetStatePath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CabinetState'
    if (-not (Test-Path $CabinetStatePath)) { New-Item -Path $CabinetStatePath -Force -ErrorAction SilentlyContinue | Out-Null }

    foreach ($Setting in $HkcuSettings) {
        try {
            if (-not (Test-Path $Setting.Path)) { New-Item -Path $Setting.Path -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Type $Setting.Type -Force -ErrorAction SilentlyContinue | Out-Null
            Write-LogEntry -Message "Erfolg (HKCU): $($Setting.Description)"
        } catch {
            Write-LogEntry -Message "FEHLER (HKCU): Fehler bei '$($Setting.Name)': $($_.Exception.Message)" -Type "ERROR"
        }
    }
    
    # Neustart des Explorers, um Änderungen sichtbar zu machen (optional, kann störend sein)
    # Write-LogEntry -Message "INFO: Starte Explorer neu, um Änderungen anzuwenden." -Type "INFO"
    # Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    # Start-Sleep -Seconds 2 # Kurz warten
    # Start-Process explorer.exe

} # End ShouldProcess HKCU Härtung

Write-Host "--- Vollständige Härtung und Konfiguration abgeschlossen. Details im Logfile. ---" -ForegroundColor Green
Write-LogEntry -Message "Skript erfolgreich beendet."

