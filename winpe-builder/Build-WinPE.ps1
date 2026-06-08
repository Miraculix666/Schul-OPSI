<#
    FILE: Build-WinPE.ps1
    PURPOSE: Unified OPSI WinPE Builder - Erstellt vollstaendiges win11-x64 Netboot-Paket
    DEPENDS ON: Windows ADK (auto-install), Windows 11 ISO
    DEPENDED ON BY: OPSI Depot (win11-x64 Netboot Product)
    LAST MODIFIED: 2026-04-23
    MODIFIED BY: antigravity-agent
    CHANGE SUMMARY: v3.0 - Zentrales config/environment.json, -Env Quick-Start, Repo-Restrukturierung
    BRANCH: main

    .SYNOPSIS
    Erstellt ein vollstaendiges OPSI win11-x64 Netboot-Paket inkl. WinPE.

    .DESCRIPTION
    Automatisierter Builder der:
    - Automatische Admin-Elevation (Self-Elevate)
    - ADK erkennt / installiert
    - copype.cmd fuer echte WinPE-Dateien nutzt
    - boot.wim modifiziert (startnet.cmd, Treiber, WinPE-Komponenten)
    - BCD korrekt via bcdedit erstellt (BIOS + UEFI) mit Locale de-DE
    - Windows ISO-Inhalt nach installfiles/ kopiert
    - winpe_uefi -> winpe Symlink (opsi-depot-intern)
    - Alle Parameter in settings.json persistiert (letzter Run = Voreinstellung)
    - Interaktive Parameterabfrage (immer, auch mit CLI-Params)
    - Post-Build-Validierung

    .EXAMPLE
    # Interaktiv (Menü):
    .\Build-WinPE.ps1 -IsoPath "D:\temp\Win11.iso" -OutputPath "C:\temp\opsiPE" -DriverSource "Y:\drivers"

    .EXAMPLE
    # Quick-Start (alle Werte aus config/environment.json):
    .\Build-WinPE.ps1 -Env
#>

param(
    [switch]$Env,
    [string]$IsoPath,
    [string]$OutputPath,
    [string]$DriverSource,
    [string]$WorkingPath,
    [string]$ToolsSource,
    [string]$ProductId = "win11-x64",
    [ValidateSet("amd64","x86","arm64")]
    [string]$Architecture = "amd64",
    [string]$ADK_Path,
    [switch]$UseCache,
    [switch]$SkipIsoExtract,
    [switch]$SkipDrivers,
    [switch]$SkipToolkitDownload
)

# ============================================================================
# KONFIGURATION
# ============================================================================
$ErrorActionPreference = "Stop"
$script:ScriptVersion = "3.0.0"
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
# Zentrale Konfiguration aus config/environment.json (eine Ebene hoeher)
$script:RepoRoot = Split-Path $script:ScriptDir -Parent
$script:EnvFile = Join-Path $script:RepoRoot "config\environment.json"
$script:LogFile = $null
$script:MountedWim = $false
$script:MountPath = $null
$script:IsoMounted = $false
$script:IsoMountPath = $null

# WinPE-Komponenten die fuer Win11 PFLICHT sind
$script:RequiredComponents = @(
    "WinPE-WMI",
    "WinPE-SecureStartup",
    "WinPE-Scripting",
    "WinPE-NetFX",
    "WinPE-PowerShell",
    "WinPE-StorageWMI",
    "WinPE-DismCmdlets"
)

# ============================================================================
# HILFSFUNKTIONEN
# ============================================================================

function Write-Step {
    param([string]$Step, [string]$Message, [string]$Color = "Yellow")
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] [$Step] $Message" -ForegroundColor $Color
    if ($script:LogFile) {
        "[$ts] [$Step] $Message" | Add-Content $script:LogFile -ErrorAction SilentlyContinue
    }
}

function Write-OK   { param([string]$Msg) Write-Step "  OK" $Msg "Green" }
function Write-Warn { param([string]$Msg) Write-Step "WARN" $Msg "DarkYellow" }
function Write-Err  { param([string]$Msg) Write-Step " ERR" $Msg "Red" }

function Show-Banner {
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ("     OPSI WinPE Builder v" + $script:ScriptVersion) -ForegroundColor Cyan
    Write-Host "     Vollstaendiges win11-x64 Netboot-Paket" -ForegroundColor Cyan
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# 0. AUTO-ELEVATION
# ============================================================================

function Invoke-SelfElevation {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        Write-OK "Administrator-Rechte bestaetigt"
        return
    }

    Write-Warn "Keine Admin-Rechte - starte erneut als Administrator..."

    # Argumente rekonstruieren
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$($MyInvocation.PSCommandPath)`"")
    foreach ($param in $MyInvocation.BoundParameters.GetEnumerator()) {
        if ($param.Value -is [switch]) {
            if ($param.Value.IsPresent) { $argList += ("-" + $param.Key) }
        }
        else {
            $argList += ("-" + $param.Key)
            $argList += ("`"" + $param.Value + "`"")
        }
    }

    try {
        Start-Process powershell -ArgumentList ($argList -join " ") -Verb RunAs -Wait
        exit 0
    }
    catch {
        Write-Err "Elevation fehlgeschlagen: $_"
        Write-Host ""
        Write-Host "  Bitte manuell als Administrator starten:" -ForegroundColor Yellow
        Write-Host "  Win+X -> Terminal (Admin)" -ForegroundColor Gray
        Read-Host "  [Enter] zum Beenden..."
        exit 1
    }
}

# ============================================================================
# 1. ENVIRONMENT / SETTINGS MANAGEMENT (environment.json)
# ============================================================================

function Read-Environment {
    # Defaults (alle relevanten Variablen)
    $env_data = @{
        Build = @{
            IsoPath       = ""
            OutputPath    = "C:\temp\opsi_winpe\win11-x64"
            WorkingPath   = "C:\PSC_WinPE_Temp"
            DriverSource  = ""
            ToolsSource   = "C:\TEMP_WINPE"
            Architecture  = "amd64"
            ADK_Path      = ""
            UseCache      = $false
            CachePath     = "C:\PSC_WinPE_Cache"
        }
        Product = @{
            ProductId      = "win11-x64"
            ProductName    = "Windows 11 LTSC Enterprise"
            ProductVersion = "24H2"
            ImageIndex     = 1
        }
        Windows = @{
            ProductKey     = "M7XTQ-FN8P6-TTKYV-9D4CC-J462D"
            AdminPassword  = "nt123!"
            AdminUser      = "admin"
            ComputerName   = "*"
            Locale         = "de-DE"
            TimeZone       = "W. Europe Standard Time"
        }
        OPSI = @{
            ServerAddress  = "opsi-server"
            ServerUser     = "root"
            DepotBasePath  = "/var/lib/opsi/depot"
            DepotSharePath = "Y:\"
            ImageName      = ""
        }
        Deployment = @{
            InstallTo        = "disk"
            AskBeforeInstall = $false
            HardwareCheck    = $false
            BypassTPMCheck   = $true
            BypassCPUCheck   = $true
            BypassRAMCheck   = $true
        }
        Meta = @{
            LastRun        = ""
            LastRunBy      = $env:USERNAME
            ScriptVersion  = $script:ScriptVersion
        }
    }

    # environment.json einlesen (wenn vorhanden)
    if (Test-Path $script:EnvFile) {
        try {
            $saved = Get-Content $script:EnvFile -Raw | ConvertFrom-Json
            foreach ($section in @("Build","Product","Windows","OPSI","Deployment","Meta")) {
                if ($saved.PSObject.Properties.Name -contains $section) {
                    foreach ($prop in $saved.$section.PSObject.Properties) {
                        if ($prop.Name -notmatch "^//" -and $null -ne $prop.Value) {
                            $val = $prop.Value
                            # Bereinigung: Anfuehrungszeichen entfernen (falls vorhanden)
                            if ($val -is [string]) { $val = $val.Trim().Trim('"').Trim("'") }
                            $env_data[$section][$prop.Name] = $val
                        }
                    }
                }
            }
            Write-Step "ENV" "environment.json geladen (sanitized)" "Gray"
        }
        catch {
            Write-Warn "environment.json fehlerhaft, nutze Defaults"
        }
    }
    else {
        Write-Step "ENV" "Keine environment.json - nutze Defaults" "Gray"
    }

    # CLI-Parameter ueberschreiben
    if ($IsoPath)      { $env_data.Build.IsoPath      = $IsoPath }
    if ($OutputPath)   { $env_data.Build.OutputPath    = $OutputPath }
    if ($DriverSource) { $env_data.Build.DriverSource  = $DriverSource }
    if ($WorkingPath)  { $env_data.Build.WorkingPath   = $WorkingPath }
    if ($ToolsSource)  { $env_data.Build.ToolsSource   = $ToolsSource }
    if ($ADK_Path)     { $env_data.Build.ADK_Path      = $ADK_Path }
    if ($UseCache)     { $env_data.Build.UseCache      = $UseCache }
    if ($ProductId -and $ProductId -ne "win11-x64") { $env_data.Product.ProductId = $ProductId }
    if ($Architecture -and $Architecture -ne "amd64") { $env_data.Build.Architecture = $Architecture }

    return $env_data
}

function Save-Environment {
    param([hashtable]$Env)
    $Env.Meta.LastRun = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $Env.Meta.LastRunBy = $env:USERNAME
    $Env.Meta.ScriptVersion = $script:ScriptVersion

    # Konvertierung: verschachtelte Hashtables -> PSCustomObject fuer JSON
    $jsonObj = [ordered]@{}
    foreach ($section in @("Build","Product","Windows","OPSI","Deployment","Meta")) {
        $jsonObj[$section] = [ordered]@{}
        foreach ($key in ($Env[$section].Keys | Sort-Object)) {
            $jsonObj[$section][$key] = $Env[$section][$key]
        }
    }
    $jsonObj | ConvertTo-Json -Depth 4 | Set-Content $script:EnvFile -Encoding UTF8
    Write-Step "ENV" "environment.json gespeichert" "Gray"
}

# ============================================================================
# 2. ADK ERKENNUNG / INSTALLATION
# ============================================================================

function Find-ADK {
    param([string]$ManualPath)

    # Manueller Pfad zuerst
    if ($ManualPath -and (Test-Path $ManualPath)) {
        # Pruefe ob es der OC-Pfad ist oder der Root
        if ($ManualPath -match "WinPE_OCs$") {
            $root = ($ManualPath -replace "\\Windows Preinstallation Environment.*$","")
            return @{
                Root   = $root
                CopypePath = Join-Path $root "Windows Preinstallation Environment\copype.cmd"
                OcPath = $ManualPath
            }
        }
    }

    $searchPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit",
        "${env:ProgramFiles(x86)}\Windows Kits\11\Assessment and Deployment Kit",
        "$env:ProgramFiles\Windows Kits\11\Assessment and Deployment Kit"
    )

    foreach ($adkBase in $searchPaths) {
        $copype = Join-Path $adkBase "Windows Preinstallation Environment\copype.cmd"
        if (Test-Path $copype) {
            $arch = $Architecture
            return @{
                Root       = $adkBase
                CopypePath = $copype
                OcPath     = Join-Path $adkBase "Windows Preinstallation Environment\$arch\WinPE_OCs"
            }
        }
    }
    return $null
}

function Install-ADKIfMissing {
    param([string]$ManualPath)

    $adk = Find-ADK -ManualPath $ManualPath
    if ($adk) {
        Write-OK ("ADK gefunden: " + $adk.Root)
        if (-not (Test-Path $adk.OcPath)) {
            Write-Warn "ADK installiert, aber WinPE Add-on fehlt!"
            Write-Step "ADK" "Versuche WinPE Add-on zu installieren..." "Yellow"
            try {
                & winget install --id Microsoft.ADKPEAddon --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                Write-OK "WinPE Add-on installiert"
                $adk = Find-ADK -ManualPath $ManualPath
            }
            catch {
                Write-Err "WinPE Add-on konnte nicht installiert werden"
                exit 1
            }
        }
        return $adk
    }

    Write-Warn "Windows ADK nicht gefunden!"
    Write-Step "ADK" "Versuche ADK ueber winget zu installieren..." "Yellow"

    try {
        Write-Step "ADK" "Installiere Windows ADK (dauert einige Minuten)..." "Cyan"
        & winget install --id Microsoft.ADK --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "ADK install fehlgeschlagen (Exit: $LASTEXITCODE)" }

        Write-Step "ADK" "Installiere WinPE Add-on..." "Cyan"
        & winget install --id Microsoft.ADKPEAddon --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "WinPE Addon fehlgeschlagen (Exit: $LASTEXITCODE)" }

        $adk = Find-ADK -ManualPath $ManualPath
        if (-not $adk) { throw "ADK nach Installation nicht gefunden" }
        return $adk
    }
    catch {
        Write-Err ("ADK-Installation fehlgeschlagen: " + $_)
        Write-Host "  Bitte manuell installieren:" -ForegroundColor Yellow
        Write-Host "  1. ADK:         https://go.microsoft.com/fwlink/?linkid=2269546" -ForegroundColor Gray
        Write-Host "  2. WinPE-Addon: https://go.microsoft.com/fwlink/?linkid=2269547" -ForegroundColor Gray
        exit 1
    }
}

# ============================================================================
# 3. ISO-QUELLEN SUCHEN
# ============================================================================

function Find-WindowsISO {
    Write-Step "ISO" "Suche Windows 11 ISO-Quellen..." "Yellow"
    $found = @()

    # DVD-Laufwerke pruefen
    Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" -and $_.DriveLetter } | ForEach-Object {
        $setupPath = "$($_.DriveLetter):\sources\boot.wim"
        if (Test-Path $setupPath) {
            $found += @{ Type = "DVD/USB"; Path = "$($_.DriveLetter):\"; Label = $_.FileSystemLabel }
        }
    }

    # Bekannte ISO-Verzeichnisse durchsuchen
    $isoSearchDirs = @("$env:USERPROFILE\Downloads", "D:\ISOs", "D:\Downloads", "D:\temp", "E:\", "C:\ISOs")
    foreach ($dir in $isoSearchDirs) {
        if (Test-Path $dir) {
            Get-ChildItem $dir -Filter "*.iso" -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match "Win.*11|LTSC|W11"
            } | ForEach-Object {
                $found += @{ Type = "ISO-Datei"; Path = $_.FullName; Label = $_.Name }
            }
        }
    }
    return $found
}

# ============================================================================
# 4. INTERAKTIVE KONFIGURATION (IMMER - auch mit CLI-Params)
# ============================================================================

function Show-EnvValue {
    param([string]$Val, [string]$Empty = "(nicht gesetzt)")
    if ($Val) { return $Val } else { return $Empty }
}

function Show-ConfigMenu {
    param([hashtable]$Env)

    $running = $true
    while ($running) {
        Clear-Host
        Write-Host ""
        Write-Host "  ==========================================================================" -ForegroundColor Cyan
        Write-Host ("     OPSI WinPE Builder v" + $script:ScriptVersion + " - Konfiguration") -ForegroundColor Cyan
        Write-Host "  ==========================================================================" -ForegroundColor Cyan
        Write-Host ""

        # --- QUELLEN ---
        Write-Host "  [ QUELLEN ]" -ForegroundColor Yellow
        $isoColor = if ($Env.Build.IsoPath) { "White" } else { "Red" }
        Write-Host ("   [1] Windows ISO       : " + (Show-EnvValue $Env.Build.IsoPath "(!!! FEHLT !!!)")) -ForegroundColor $isoColor
        Write-Host ("   [2] Treiber-Ordner    : " + (Show-EnvValue $Env.Build.DriverSource "(keine)")) -ForegroundColor White
        Write-Host ("   [3] Tools-Quelle      : " + (Show-EnvValue $Env.Build.ToolsSource "(keine)")) -ForegroundColor White
        Write-Host ("   [4] ADK-Pfad (auto)   : " + (Show-EnvValue $Env.Build.ADK_Path)) -ForegroundColor White
        $cColor = if ($Env.Build.UseCache) { "Green" } else { "Gray" }
        Write-Host ("   [C] Cache nutzen      : " + $Env.Build.UseCache + " (" + $Env.Build.CachePath + ")") -ForegroundColor $cColor
        Write-Host ""

        # --- ZIELE / PFADE ---
        Write-Host "  [ ZIELE & PFADE ]" -ForegroundColor Yellow
        Write-Host ("   [5] Ausgabe lokal     : " + $Env.Build.OutputPath) -ForegroundColor White
        Write-Host ("   [6] Arbeitsbereich    : " + $Env.Build.WorkingPath) -ForegroundColor White
        Write-Host ("   [S] OPSI-Server Addr. : " + $Env.OPSI.ServerAddress) -ForegroundColor White
        Write-Host ("   [U] OPSI-Server User  : " + $Env.OPSI.ServerUser) -ForegroundColor White
        Write-Host ("   [D] OPSI-Depot Pfad   : " + $Env.OPSI.DepotBasePath) -ForegroundColor White
        Write-Host ""

        # --- OPSI PRODUKT ---
        Write-Host "  [ OPSI PRODUKT ]" -ForegroundColor Yellow
        Write-Host ("   [I] Produkt-ID (Ordner): " + $Env.Product.ProductId) -ForegroundColor White
        Write-Host ("   [N] Anzeigename        : " + $Env.Product.ProductName) -ForegroundColor White
        Write-Host ("   [V] Version            : " + $Env.Product.ProductVersion) -ForegroundColor White
        Write-Host ("   [A] Architektur        : " + $Env.Build.Architecture) -ForegroundColor White
        Write-Host ""

        # --- WINDOWS ---
        Write-Host "  [ WINDOWS SETUP ]" -ForegroundColor Yellow
        Write-Host ("   [K] Product Key        : " + (Show-EnvValue $Env.Windows.ProductKey)) -ForegroundColor White
        Write-Host ("   [P] Admin-Passwort     : " + $Env.Windows.AdminPassword) -ForegroundColor White
        Write-Host ("   [L] Locale             : " + $Env.Windows.Locale) -ForegroundColor White
        Write-Host ""

        Write-Host "  --------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "   [B] BUILD STARTEN      [E] Alle Editieren      [X] ABBRECHEN" -ForegroundColor Green
        Write-Host "  ==========================================================================" -ForegroundColor Cyan

        if ($Env.Meta.LastRun) {
            Write-Host ("   Letzter Run: " + $Env.Meta.LastRun + " (" + $Env.Meta.LastRunBy + ")") -ForegroundColor DarkGray
        }
        Write-Host ""

        $choice = Read-Host " Auswahl"

        switch ($choice.ToUpper()) {
            "1" {
                $isos = Find-WindowsISO
                if ($isos.Count -gt 0) {
                    Write-Host "`n Gefundene ISOs:" -ForegroundColor Yellow
                    for ($i = 0; $i -lt $isos.Count; $i++) {
                        Write-Host ("  [" + ($i+1) + "] " + $isos[$i].Label) -ForegroundColor Gray
                    }
                    Write-Host "  [M] Manuell eingeben"
                    $isoChoice = Read-Host " Auswahl"
                    if ($isoChoice -match "^\d+$" -and [int]$isoChoice -le $isos.Count) { $Env.Build.IsoPath = $isos[[int]$isoChoice - 1].Path }
                    elseif ($isoChoice.ToUpper() -eq "M") { $v = Read-Host " ISO-Pfad"; if ($v) { $Env.Build.IsoPath = $v } }
                } else { $v = Read-Host " ISO-Pfad"; if ($v) { $Env.Build.IsoPath = $v } }
            }
            "2" { $v = Read-Host (" Treiber-Ordner [" + $Env.Build.DriverSource + "]"); if ($v) { $Env.Build.DriverSource = $v } }
            "3" { $v = Read-Host (" Tools-Quelle [" + $Env.Build.ToolsSource + "]"); if ($v) { $Env.Build.ToolsSource = $v } }
            "4" { $v = Read-Host (" ADK-Pfad [" + $Env.Build.ADK_Path + "]"); if ($v) { $Env.Build.ADK_Path = $v } }
            "5" { $v = Read-Host (" Ausgabe-Pfad [" + $Env.Build.OutputPath + "]"); if ($v) { $Env.Build.OutputPath = $v } }
            "6" { $v = Read-Host (" Arbeitsbereich [" + $Env.Build.WorkingPath + "]"); if ($v) { $Env.Build.WorkingPath = $v } }
            
            "C" { 
                $Env.Build.UseCache = -not $Env.Build.UseCache
                if ($Env.Build.UseCache) {
                    $v = Read-Host (" Cache-Pfad [" + $Env.Build.CachePath + "]")
                    if ($v) { $Env.Build.CachePath = $v }
                }
            }

            "I" { $v = Read-Host (" Produkt-ID [" + $Env.Product.ProductId + "]"); if ($v) { $Env.Product.ProductId = $v } }
            "N" { $v = Read-Host (" Anzeigename [" + $Env.Product.ProductName + "]"); if ($v) { $Env.Product.ProductName = $v } }
            "V" { $v = Read-Host (" Version [" + $Env.Product.ProductVersion + "]"); if ($v) { $Env.Product.ProductVersion = $v } }
            "A" { 
                $v = Read-Host (" Architektur (amd64/x86/arm64) [" + $Env.Build.Architecture + "]")
                if ($v -in @("amd64","x86","arm64")) { $Env.Build.Architecture = $v }
            }

            "S" { $v = Read-Host (" OPSI-Server Addr [" + $Env.OPSI.ServerAddress + "]"); if ($v) { $Env.OPSI.ServerAddress = $v } }
            "U" { $v = Read-Host (" OPSI-Server User [" + $Env.OPSI.ServerUser + "]"); if ($v) { $Env.OPSI.ServerUser = $v } }
            "D" { $v = Read-Host (" Depot-Basispfad [" + $Env.OPSI.DepotBasePath + "]"); if ($v) { $Env.OPSI.DepotBasePath = $v } }

            "K" { $v = Read-Host (" Product Key [" + $Env.Windows.ProductKey + "]"); if ($v) { $Env.Windows.ProductKey = $v } }
            "P" { $v = Read-Host (" Admin-Passwort [" + $Env.Windows.AdminPassword + "]"); if ($v) { $Env.Windows.AdminPassword = $v } }
            "L" { $v = Read-Host (" Locale [" + $Env.Windows.Locale + "]"); if ($v) { $Env.Windows.Locale = $v } }

            "E" {
                Write-Host "`n === Alle Pfade schnell aendern (Enter=beibehalten) ===" -ForegroundColor Yellow
                $v = Read-Host (" ISO-Datei [" + $Env.Build.IsoPath + "]"); if ($v) { $Env.Build.IsoPath = $v }
                $v = Read-Host (" Ausgabe-Pfad [" + $Env.Build.OutputPath + "]"); if ($v) { $Env.Build.OutputPath = $v }
                $v = Read-Host (" Arbeitsbereich [" + $Env.Build.WorkingPath + "]"); if ($v) { $Env.Build.WorkingPath = $v }
                $v = Read-Host (" Treiber [" + $Env.Build.DriverSource + "]"); if ($v) { $Env.Build.DriverSource = $v }
                $v = Read-Host (" Tools [" + $Env.Build.ToolsSource + "]"); if ($v) { $Env.Build.ToolsSource = $v }
            }
            "B" { if ($Env.Build.IsoPath) { $running = $false } else { Write-Host " !!! ISO-Pfad fehlt !!!" -ForegroundColor Red; Start-Sleep -Seconds 2 } }
            "X" { Write-Host " Abgebrochen."; exit 0 }
        }
    }
    return $Env
}

# ============================================================================
# 5. WORKSPACE ERSTELLEN (copype)
# ============================================================================

function Initialize-Workspace {
    param(
        [hashtable]$ADK,
        [string]$WorkDir,
        [string]$Arch
    )

    Write-Step "WORKSPACE" "Erstelle WinPE-Arbeitsverzeichnis via copype..." "Yellow"

    # Alte Mounts bereinigen
    Write-Step "CLEANUP" "Bereinige alte DISM-Mounts..." "Gray"
    & dism.exe /Cleanup-Wim 2>&1 | Out-Null

    # Altes Arbeitsverzeichnis loeschen (aggressiv)
    if (Test-Path $WorkDir) {
        Write-Step "CLEANUP" ("Loesche altes WorkDir: " + $WorkDir) "Gray"
        for ($i = 1; $i -le 3; $i++) {
            try {
                Remove-Item $WorkDir -Recurse -Force -ErrorAction Stop
                break
            }
            catch {
                Write-Warn ("Cleanup-Versuch " + $i + " fehlgeschlagen. Warte...")
                Start-Sleep -Seconds 2
            }
        }
    }
    if (Test-Path $WorkDir) { throw "Konnte Arbeitsverzeichnis nicht loeschen: $WorkDir" }

    Write-Step "COPYPE" ("copype.cmd " + $Arch + " '" + $WorkDir + "'") "Cyan"
    $copypeLogOut = Join-Path $script:ScriptDir "copype_stdout.log"
    $copypeLogErr = Join-Path $script:ScriptDir "copype_stderr.log"
    
    # cmd.exe Argument Parser Fix:
    # We must wrap the ENTIRE argument block in quotes to prevent cmd.exe from stripping inner quotes.
    $argList = "/c `"`"`"$($ADK.CopypePath)`" $Arch `"$WorkDir`"`"`""
    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $argList -Wait -NoNewWindow -PassThru -RedirectStandardOutput $copypeLogOut -RedirectStandardError $copypeLogErr
    
    if ($proc.ExitCode -ne 0) {
        $errOut = Get-Content $copypeLogOut -ErrorAction SilentlyContinue | Out-String
        $errErr = Get-Content $copypeLogErr -ErrorAction SilentlyContinue | Out-String
        $err = ($errOut + "`n" + $errErr).Trim()
        Write-Err ("copype.cmd fehlgeschlagen (Exit: " + $proc.ExitCode + ")")
        if ($err) { Write-Host "--- COPYPE OUTPUT ---`n$err`n---------------------" -ForegroundColor Red }
        throw "copype.cmd fehlgeschlagen"
    }

    $bootWim = Join-Path $WorkDir "media\sources\boot.wim"
    if (-not (Test-Path $bootWim)) {
        throw "copype hat keine boot.wim erzeugt: $bootWim"
    }

    $wimSizeMB = [math]::Round((Get-Item $bootWim).Length / 1MB, 1)
    Write-OK ("copype erfolgreich - boot.wim: " + $wimSizeMB + " MB")
    return $WorkDir
}

# ============================================================================
# 6. ISO EXTRAHIEREN
# ============================================================================

function Import-BootWimFromISO {
    param(
        [string]$IsoFilePath,
        [string]$WorkDir,
        [string]$TargetOutputPath,
        [bool]$UseCache,
        [string]$CachePath
    )

    if (-not $IsoFilePath -or $SkipIsoExtract) {
        Write-Warn "Kein ISO angegeben - verwende ADK-Standard winpe.wim"
        return
    }

    if (-not (Test-Path $IsoFilePath)) {
        Write-Err ("ISO nicht gefunden: " + $IsoFilePath)
        throw "ISO-Datei nicht gefunden"
    }

    $isoRoot = $IsoFilePath
    $installFiles = Join-Path $TargetOutputPath "installfiles"
    $targetBootWim = Join-Path $WorkDir "media\sources\boot.wim"

    # CACHE CHECK
    if ($UseCache -and $CachePath) {
        Write-Step "CACHE" "Pruefe Cache..." "Yellow"
        if (-not (Test-Path $CachePath)) { New-Item $CachePath -ItemType Directory -Force | Out-Null }
        
        $cachedBootWim = Join-Path $CachePath "boot.wim"
        $cachedInstall = Join-Path $CachePath "installfiles"

        if ((Test-Path $cachedBootWim) -and (Test-Path $cachedInstall) -and ((Get-ChildItem $cachedInstall).Count -gt 50)) {
            Write-Step "CACHE" "Cache gefunden! Ueberspringe ISO-Mount." "Green"
            Copy-Item $cachedBootWim $targetBootWim -Force
            Set-ItemProperty $targetBootWim -Name IsReadOnly -Value $false
            
            if (Test-Path $installFiles) { Remove-Item $installFiles -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item $installFiles -ItemType Directory -Force | Out-Null
            & robocopy "$cachedInstall" "$installFiles" /E /R:1 /W:1 /NJH /NJS /NDL /NC /NS /MT:8 2>&1 | Out-Null
            Write-OK "Dateien aus Cache kopiert"
            return
        }
        else {
            Write-Warn "Cache leer oder unvollstaendig, ISO wird geladen..."
        }
    }

    Write-Step "ISO" ("Mounte ISO: " + $IsoFilePath) "Cyan"
    $mountResult = Mount-DiskImage -ImagePath $IsoFilePath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    if (-not $driveLetter) { throw "ISO Mount fehlgeschlagen: $IsoFilePath" }
    $isoRoot = "${driveLetter}:\"
    $script:IsoMounted = $true
    $script:IsoMountPath = $IsoFilePath
    Write-OK ("ISO gemountet: " + $driveLetter + ":")

    # boot.wim aus ISO uebernehmen
    $isoBootWim = Join-Path $isoRoot "sources\boot.wim"

    if (Test-Path $isoBootWim) {
        Write-Step "ISO" "Ersetze ADK-WinPE durch ISO boot.wim..." "Cyan"
        Copy-Item $isoBootWim $targetBootWim -Force
        Set-ItemProperty $targetBootWim -Name IsReadOnly -Value $false
        $wimSizeMB = [math]::Round((Get-Item $targetBootWim).Length / 1MB, 1)
        Write-OK ("boot.wim aus ISO: " + $wimSizeMB + " MB")
    }

    # installfiles/ erstellen
    $installFiles = Join-Path $TargetOutputPath "installfiles"
    Write-Step "ISO" "Kopiere Windows-Installationsdateien nach installfiles/..." "Cyan"
    Write-Step "ISO" "Das kann einige Minuten dauern..." "Gray"

    if (Test-Path $installFiles) {
        Remove-Item $installFiles -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item $installFiles -ItemType Directory -Force | Out-Null

    # Robocopy: alles kopieren, OHNE install.wim/install.esd
    & robocopy "$isoRoot" "$installFiles" /E /R:1 /W:1 /NJH /NJS /NDL /NC /NS /MT:8 2>&1 | Out-Null
    if ($LASTEXITCODE -gt 7) {
        Write-Warn "Robocopy hatte Fehler (Exit: $LASTEXITCODE)"
    }

    $fileCount = (Get-ChildItem $installFiles -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-OK ("installfiles/ befuellt: " + $fileCount + " Dateien")

    # CACHE UPDATE
    if ($UseCache -and $CachePath) {
        Write-Step "CACHE" "Speichere ISO-Dateien in Cache..." "Gray"
        $cachedBootWim = Join-Path $CachePath "boot.wim"
        $cachedInstall = Join-Path $CachePath "installfiles"
        if (Test-Path $isoBootWim) { Copy-Item $isoBootWim $cachedBootWim -Force }
        if (-not (Test-Path $cachedInstall)) { New-Item $cachedInstall -ItemType Directory -Force | Out-Null }
        & robocopy "$installFiles" "$cachedInstall" /E /R:1 /W:1 /NJH /NJS /NDL /NC /NS /MT:8 2>&1 | Out-Null
    }
}

# ============================================================================
# 7. WIM MOUNTEN
# ============================================================================

function Mount-BootWim {
    param([string]$WorkDir)

    $wimPath = Join-Path $WorkDir "media\sources\boot.wim"
    $mountDir = Join-Path $WorkDir "mount"

    if (-not (Test-Path $mountDir)) {
        New-Item $mountDir -ItemType Directory -Force | Out-Null
    }

    Write-Step "MOUNT" "Validiere boot.wim..." "Yellow"
    try {
        $wimInfo = Get-WindowsImage -ImagePath $wimPath -ErrorAction Stop
        Write-OK ("boot.wim valide - " + $wimInfo.Count + " Image(s)")
    }
    catch { throw "boot.wim ungueltig: $_" }

    $maxAttempts = 2
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Write-Step "MOUNT" ("Mounte boot.wim (Index 1), Versuch " + $attempt + "/" + $maxAttempts) "Cyan"
            Mount-WindowsImage -ImagePath $wimPath -Index 1 -Path $mountDir -ErrorAction Stop | Out-Null
            $script:MountedWim = $true
            $script:MountPath = $mountDir
            Write-OK ("boot.wim gemountet: " + $mountDir)
            return $mountDir
        }
        catch {
            Write-Warn ("Mount fehlgeschlagen: " + $_)
            if ($attempt -lt $maxAttempts) {
                Write-Step "CLEANUP" "Bereinige und versuche erneut..." "Gray"
                & dism.exe /Cleanup-Wim 2>&1 | Out-Null
                Start-Sleep -Seconds 2
            }
        }
    }
    throw "Mount nach $maxAttempts Versuchen fehlgeschlagen"
}

# ============================================================================
# 8. STARTNET.CMD (OPSI-konform!)
# ============================================================================

function Set-StartnetCmd {
    param([string]$MountDir)

    Write-Step "STARTNET" "Erstelle OPSI-konforme startnet.cmd..." "Yellow"
    $startnetPath = Join-Path $MountDir "Windows\System32\startnet.cmd"

    # OPSI-Doku: wpeinit + c:\opsi\startnet.cmd
    $startnetLines = @(
        "@echo off"
        "wpeinit"
        "echo."
        "echo ============================================"
        "echo    OPSI WinPE - Warte auf OPSI Boot-Image"
        "echo ============================================"
        "echo."
        "c:\opsi\startnet.cmd"
    )

    $startnetLines -join "`r`n" | Out-File $startnetPath -Encoding ASCII -Force
    Write-OK "startnet.cmd erstellt (OPSI-konform)"
}

# ============================================================================
# 9. WINPE-KOMPONENTEN
# ============================================================================

function Add-WinPEComponents {
    param([string]$MountDir, [string]$OcPath)

    Write-Step "COMPONENTS" "Integriere WinPE Optional Components..." "Yellow"

    if (-not (Test-Path $OcPath)) {
        Write-Warn ("WinPE OCs Pfad nicht gefunden: " + $OcPath)
        return
    }

    foreach ($comp in $script:RequiredComponents) {
        $cabFile = Get-ChildItem $OcPath -Filter "$comp.cab" -ErrorAction SilentlyContinue | Select-Object -First 1

        if (-not $cabFile) {
            $cabFile = Get-ChildItem $OcPath -Filter "*${comp}*.cab" -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -notmatch "de-de|en-us|fr-fr" } | Select-Object -First 1
        }

        if ($cabFile) {
            try {
                Add-WindowsPackage -Path $MountDir -PackagePath $cabFile.FullName -IgnoreCheck -ErrorAction Stop | Out-Null
                Write-Step "  CAB" ("  " + $comp + " OK") "Green"
            }
            catch { Write-Warn ("  " + $comp + " fehlgeschlagen: " + $_) }
        }
        else { Write-Warn ("  " + $comp + ".cab nicht gefunden") }

        # Deutsches Sprachpaket
        $langCab = $null
        $langDir = Join-Path $OcPath "de-de"
        if (Test-Path $langDir) {
            $langCab = Get-ChildItem $langDir -Filter "*${comp}*de-de.cab" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $langCab) {
            $langCab = Get-ChildItem $OcPath -Filter "${comp}_de-de.cab" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($langCab) {
            Add-WindowsPackage -Path $MountDir -PackagePath $langCab.FullName -IgnoreCheck -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Write-OK "WinPE-Komponenten integriert"
}

# ============================================================================
# 10. TREIBER
# ============================================================================

function Add-Drivers {
    param([string]$MountDir, [string]$DriverPath)

    if (-not $DriverPath -or -not (Test-Path $DriverPath) -or $SkipDrivers) {
        Write-Step "DRIVERS" "Keine Treiber angegeben - ueberspringe" "Gray"
        return
    }

    Write-Step "DRIVERS" ("Injiziere Treiber aus " + $DriverPath) "Yellow"
    try {
        & dism.exe /Image:"$MountDir" /Add-Driver /Driver:"$DriverPath" /Recurse /ForceUnsigned 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "Treiber erfolgreich injiziert" }
        else { Write-Warn ("Treiber mit Warnungen (Code: " + $LASTEXITCODE + ")") }
    }
    catch { Write-Warn ("Treiber-Injection fehlgeschlagen: " + $_) }
}

# ============================================================================
# 11. TOOLS INJIZIEREN (aus ToolsSource)
# ============================================================================

function Add-ExternalTools {
    param([string]$MountDir, [string]$ToolsSrc)

    if (-not $ToolsSrc -or -not (Test-Path $ToolsSrc)) {
        Write-Step "TOOLS" "Kein Tools-Verzeichnis angegeben - ueberspringe" "Gray"
        return
    }

    Write-Step "TOOLS" ("Injiziere Tools aus " + $ToolsSrc) "Yellow"
    $peToolsPath = Join-Path $MountDir "Windows\System32\Tools"
    New-Item $peToolsPath -ItemType Directory -Force | Out-Null

    & robocopy "$ToolsSrc" "$peToolsPath" /E /R:1 /W:1 /MT:4 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
    $toolCount = (Get-ChildItem $peToolsPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-OK ("Tools injiziert: " + $toolCount + " Dateien")
}

# ============================================================================
# 12. WIM UNMOUNT + COMMIT
# ============================================================================

function Save-AndUnmountWim {
    param([string]$MountDir)

    Write-Step "SAVE" "Speichere und unmounte boot.wim (Commit)..." "Yellow"
    try {
        Dismount-WindowsImage -Path $MountDir -Save -ErrorAction Stop | Out-Null
        $script:MountedWim = $false
        Write-OK "boot.wim erfolgreich gespeichert"
    }
    catch {
        Write-Err ("Commit fehlgeschlagen: " + $_)
        try { Dismount-WindowsImage -Path $MountDir -Discard -ErrorAction Stop | Out-Null; $script:MountedWim = $false }
        catch { & dism.exe /Cleanup-Wim 2>&1 | Out-Null; $script:MountedWim = $false }
        throw ("WIM Commit fehlgeschlagen: " + $_)
    }
}

# ============================================================================
# 13. OPSI-ZIELSTRUKTUR ERSTELLEN
# ============================================================================

function New-OpsiStructure {
    param([string]$WorkDir, [string]$TargetOutputPath)

    Write-Step "OPSI" ("Erstelle OPSI-Depot-Struktur: " + $TargetOutputPath) "Yellow"

    $winpeDir = Join-Path $TargetOutputPath "winpe"

    # Altes winpe/winpe_uefi loeschen
    foreach ($d in @($winpeDir, (Join-Path $TargetOutputPath "winpe_uefi"))) {
        if (Test-Path $d) {
            $item = Get-Item $d -Force -ErrorAction SilentlyContinue
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                cmd.exe /c ("rmdir `"" + $d + "`"") 2>&1 | Out-Null
            }
            else { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # copype media -> winpe/ (ECHTE Boot-Dateien)
    $mediaDir = Join-Path $WorkDir "media"
    Write-Step "OPSI" "Kopiere Media -> winpe/ (echte ADK-Dateien)..." "Cyan"
    New-Item $winpeDir -ItemType Directory -Force | Out-Null
    Get-ChildItem $mediaDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName -Destination $winpeDir -Recurse -Force
    }

    # Weitere OPSI-Verzeichnisse
    foreach ($subDir in @("drivers", "custom", "opsi")) {
        $target = Join-Path $TargetOutputPath $subDir
        if (-not (Test-Path $target)) {
            New-Item $target -ItemType Directory -Force | Out-Null
            Write-Step "OPSI" ("Ordner erstellt: " + $subDir + "/") "Gray"
        }
    }

    Write-OK "OPSI-Verzeichnisstruktur erstellt"
    return $winpeDir
}

# ============================================================================
# 14. BCD ERSTELLEN (BIOS + UEFI, Locale de-DE)
# ============================================================================

function New-BCDStore {
    param([string]$WinpeDir)

    Write-Step "BCD" "Erstelle Boot Configuration Data (BIOS + UEFI)..." "Yellow"

    $ramdiskGuid = "{7619dcc8-fafe-11d9-b411-000476eba25f}"

    $bcdConfigs = @(
        @{ Type = "BIOS"; BcdPath = (Join-Path $WinpeDir "Boot\BCD"); Loader  = "\windows\system32\boot\winload.exe" },
        @{ Type = "UEFI"; BcdPath = (Join-Path $WinpeDir "EFI\Microsoft\Boot\BCD"); Loader  = "\windows\system32\boot\winload.efi" }
    )

    foreach ($cfg in $bcdConfigs) {
        $bcdPath = $cfg.BcdPath
        $bcdDir = Split-Path $bcdPath

        Write-Step "BCD" ("Konfiguriere " + $cfg.Type + " BCD...") "Cyan"

        if (-not (Test-Path $bcdDir)) { New-Item $bcdDir -ItemType Directory -Force | Out-Null }

        $bcdTemplatePath = Join-Path $bcdDir "BCDTemplate"

        if (-not (Test-Path $bcdPath) -or (Get-Item $bcdPath).Length -lt 100) {
            if (Test-Path $bcdTemplatePath) {
                Copy-Item $bcdTemplatePath $bcdPath -Force
            }
            else {
                & bcdedit.exe /createstore "$bcdPath" 2>&1 | Out-Null
                & bcdedit.exe /store "$bcdPath" /create "{bootmgr}" /d "Windows Boot Manager" 2>&1 | Out-Null
                & bcdedit.exe /store "$bcdPath" /create "{default}" /d "OPSI WinPE" /application osloader 2>&1 | Out-Null
            }
        }

        if (Test-Path $bcdPath) {
            Set-ItemProperty $bcdPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }

        # Boot Manager
        & bcdedit.exe /store "$bcdPath" /set "{bootmgr}" device boot 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{bootmgr}" displayorder "{default}" 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{bootmgr}" timeout 3 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{bootmgr}" locale de-DE 2>&1 | Out-Null

        # OS Loader
        & bcdedit.exe /store "$bcdPath" /set "{default}" device "ramdisk=[boot]\sources\boot.wim,$ramdiskGuid" 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" osdevice "ramdisk=[boot]\sources\boot.wim,$ramdiskGuid" 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" path $cfg.Loader 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" systemroot "\windows" 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" winpe Yes 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" detecthal Yes 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" nointegritychecks Yes 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set "{default}" locale de-DE 2>&1 | Out-Null

        # Ramdisk
        $ramdiskExists = & bcdedit.exe /store "$bcdPath" /enum all 2>&1 | Select-String $ramdiskGuid
        if (-not $ramdiskExists) {
            & bcdedit.exe /store "$bcdPath" /create $ramdiskGuid /d "Ramdisk Options" /device 2>&1 | Out-Null
        }
        & bcdedit.exe /store "$bcdPath" /set $ramdiskGuid ramdisksdidevice boot 2>&1 | Out-Null
        & bcdedit.exe /store "$bcdPath" /set $ramdiskGuid ramdisksdipath "\Boot\boot.sdi" 2>&1 | Out-Null

        if ((Test-Path $bcdPath) -and (Get-Item $bcdPath).Length -gt 100) {
            Write-OK ($cfg.Type + " BCD erstellt (" + (Get-Item $bcdPath).Length + " Bytes)")
        }
        else { Write-Err ($cfg.Type + " BCD Fehler!") }
    }
}

# ============================================================================
# 15. SYMLINK winpe_uefi -> winpe
# ============================================================================

function New-WinpeUefiSymlink {
    param([string]$TargetOutputPath)

    Write-Step "SYMLINK" "Erstelle winpe_uefi -> winpe Symlink..." "Yellow"

    $winpeUefiDir = Join-Path $TargetOutputPath "winpe_uefi"
    $winpeDir = Join-Path $TargetOutputPath "winpe"

    if (Test-Path $winpeUefiDir) {
        $item = Get-Item $winpeUefiDir -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd.exe /c ("rmdir `"" + $winpeUefiDir + "`"") 2>&1 | Out-Null
        }
        else { Remove-Item $winpeUefiDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    $null = cmd.exe /c ("mklink /D `"" + $winpeUefiDir + "`" `"" + $winpeDir + "`"") 2>&1
    if ($LASTEXITCODE -eq 0) { Write-OK "Symlink erstellt: winpe_uefi -> winpe" }
    else {
        $null = cmd.exe /c ("mklink /J `"" + $winpeUefiDir + "`" `"" + $winpeDir + "`"") 2>&1
        if (Test-Path $winpeUefiDir) { Write-OK "Junction erstellt: winpe_uefi -> winpe" }
        else { Write-Err "Symlink/Junction fehlgeschlagen!" }
    }
}

# ============================================================================
# 16. POST-BUILD VALIDIERUNG
# ============================================================================

function Test-BuildResult {
    param([string]$TargetOutputPath)

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host "     POST-BUILD VALIDIERUNG" -ForegroundColor Cyan
    Write-Host "  ================================================================" -ForegroundColor Cyan
    Write-Host ""

    $winpeDir = Join-Path $TargetOutputPath "winpe"
    $errCount = 0
    $warnCount = 0

    $requiredFiles = @(
        @{ Path = "sources\boot.wim";       MinSize = 209715200; Desc = "WinPE Boot-Image" },
        @{ Path = "Boot\BCD";               MinSize = 8192;      Desc = "BIOS Boot Config" },
        @{ Path = "Boot\boot.sdi";          MinSize = 1048576;   Desc = "Boot SDI" },
        @{ Path = "bootmgr";               MinSize = 102400;    Desc = "Boot Manager" },
        @{ Path = "EFI\Microsoft\Boot\BCD"; MinSize = 8192;      Desc = "UEFI Boot Config" }
    )

    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $winpeDir $file.Path
        if (Test-Path $fullPath) {
            $fileSize = (Get-Item $fullPath).Length
            if ($fileSize -ge $file.MinSize) {
                if ($fileSize -gt 1048576) { $sizeStr = ([math]::Round($fileSize / 1048576, 1)).ToString() + " MB" }
                else { $sizeStr = ([math]::Round($fileSize / 1024, 1)).ToString() + " KB" }
                Write-Host ("   [OK] " + $file.Desc + ": " + $sizeStr) -ForegroundColor Green
            }
            else {
                $sizeStr = ([math]::Round($fileSize / 1024, 1)).ToString() + " KB"
                Write-Host ("   [!!] " + $file.Desc + ": " + $sizeStr + " (zu klein!)") -ForegroundColor Yellow
                $warnCount++
            }
        }
        else { Write-Host ("   [XX] " + $file.Desc + ": FEHLT!") -ForegroundColor Red; $errCount++ }
    }

    # Symlink
    $uefiLink = Join-Path $TargetOutputPath "winpe_uefi"
    if (Test-Path $uefiLink) {
        $item = Get-Item $uefiLink -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Write-Host "   [OK] winpe_uefi -> winpe (Symlink)" -ForegroundColor Green }
        else { Write-Host "   [!!] winpe_uefi ist Ordner, kein Symlink" -ForegroundColor Yellow; $warnCount++ }
    }
    else { Write-Host "   [XX] winpe_uefi FEHLT!" -ForegroundColor Red; $errCount++ }

    # installfiles
    $installDir = Join-Path $TargetOutputPath "installfiles"
    if (Test-Path $installDir) {
        $fc = (Get-ChildItem $installDir -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($fc -gt 100) { Write-Host ("   [OK] installfiles/: " + $fc + " Dateien") -ForegroundColor Green }
        else { Write-Host ("   [!!] installfiles/: Nur " + $fc + " Dateien") -ForegroundColor Yellow; $warnCount++ }
    }
    else { Write-Host "   [!!] installfiles/ nicht vorhanden" -ForegroundColor Yellow; $warnCount++ }

    # BCD
    $biosBcd = Join-Path $winpeDir "Boot\BCD"
    if (Test-Path $biosBcd) {
        $bcdDump = & bcdedit.exe /store "$biosBcd" /enum all 2>&1 | Out-String
        if ($bcdDump -match "ramdisk=") { Write-Host "   [OK] BCD: ramdisk-Eintrag korrekt" -ForegroundColor Green }
        else { Write-Host "   [XX] BCD: ramdisk FEHLT" -ForegroundColor Red; $errCount++ }
    }

    Write-Host ""
    Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
    if ($errCount -eq 0 -and $warnCount -eq 0) { Write-Host "   ALLE PRUEFUNGEN BESTANDEN" -ForegroundColor Green }
    elseif ($errCount -eq 0) { Write-Host ("   " + $warnCount + " Warnung(en), 0 Fehler") -ForegroundColor Yellow }
    else { Write-Host ("   " + $errCount + " FEHLER, " + $warnCount + " Warnung(en)") -ForegroundColor Red }
    Write-Host "  ================================================================" -ForegroundColor Cyan

    return @{ Errors = $errCount; Warnings = $warnCount }
}

# ============================================================================
# 17. TRANSFER-HINWEISE
# ============================================================================

function Show-TransferInstructions {
    param([string]$TargetOutputPath, [string]$ProdId)

    # OPSI-Server-Daten aus Environment (falls verfuegbar)
    $srvUser = if ($Env.OPSI.ServerUser) { $Env.OPSI.ServerUser } else { "root" }
    $srvAddr = if ($Env.OPSI.ServerAddress) { $Env.OPSI.ServerAddress } else { "opsi-server" }
    $srvDepot = if ($Env.OPSI.DepotBasePath) { $Env.OPSI.DepotBasePath } else { "/var/lib/opsi/depot" }

    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Green
    Write-Host "     NAECHSTE SCHRITTE - Transfer zum OPSI-Server" -ForegroundColor Green
    Write-Host "  ================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  1. scp -r `"" + $TargetOutputPath + "\*`" " + $srvUser + "@" + $srvAddr + ":" + $srvDepot + "/" + $ProdId + "/") -ForegroundColor Gray
    Write-Host ("  2. ln -sfn winpe winpe_uefi  (auf dem Server)") -ForegroundColor Gray
    Write-Host ("  3. opsi-set-rights " + $srvDepot + "/" + $ProdId + "/") -ForegroundColor Gray
    Write-Host ("  4. opsi-configed: " + $ProdId + " -> setup -> Reboot") -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# CLEANUP
# ============================================================================

function Invoke-Cleanup {
    if ($script:MountedWim -and $script:MountPath) {
        Write-Step "CLEANUP" "Unmounte WIM (Discard)..." "Red"
        try { Dismount-WindowsImage -Path $script:MountPath -Discard -ErrorAction SilentlyContinue | Out-Null }
        catch { & dism.exe /Cleanup-Wim 2>&1 | Out-Null }
        $script:MountedWim = $false
    }
    if ($script:IsoMounted -and $script:IsoMountPath) {
        Write-Step "CLEANUP" "Unmounte ISO..." "Gray"
        Dismount-DiskImage -ImagePath $script:IsoMountPath -ErrorAction SilentlyContinue | Out-Null
        $script:IsoMounted = $false
    }
}

# ============================================================================
# HAUPTPROGRAMM
# ============================================================================

Show-Banner

# 0. Auto-Elevation
Invoke-SelfElevation

# Merke -Env Switch (wird von Read-Environment ueberschrieben)
$Env_Switch = $Env.IsPresent

try {
    # 1. Environment laden
    $Env = Read-Environment

    # 2. ADK suchen
    Write-Step "ADK" "Suche Windows Assessment and Deployment Kit..." "Yellow"
    $ADK = Install-ADKIfMissing -ManualPath $Env.Build.ADK_Path
    $Env.Build.ADK_Path = $ADK.Root

    # 3. Log-Datei
    $logDir = Join-Path $Env.Build.OutputPath "logs"
    New-Item $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $script:LogFile = Join-Path $logDir ("WinPE_Build_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    Write-Step "LOG" ("Log: " + $script:LogFile) "Gray"

    # 4. Konfiguration: -Env = Quick-Start (kein Menü), sonst interaktiv
    if ($Env_Switch) {
        Write-Step "ENV" "Quick-Start Modus (-Env): Verwende config/environment.json" "Green"
        if (-not $Env.Build.IsoPath) {
            Write-Err "ISO-Pfad fehlt in environment.json (Build.IsoPath)!"
            throw "ISO-Pfad fehlt in environment.json"
        }
    }
    else {
        $Env = Show-ConfigMenu $Env
    }

    # 5. Environment speichern
    Save-Environment $Env

    # 6. Arbeitsverzeichnis
    $WorkDir = $Env.Build.WorkingPath
    if (-not $WorkDir) { $WorkDir = Join-Path $env:TEMP ("WinPE_Build_" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
    Initialize-Workspace -ADK $ADK -WorkDir $WorkDir -Arch $Env.Build.Architecture

    # 7. Ausgabepfad
    if (-not (Test-Path $Env.Build.OutputPath)) {
        New-Item $Env.Build.OutputPath -ItemType Directory -Force | Out-Null
    }

    # 8. ISO extrahieren + boot.wim + installfiles/ (inkl Cache)
    Import-BootWimFromISO -IsoFilePath $Env.Build.IsoPath -WorkDir $WorkDir -TargetOutputPath $Env.Build.OutputPath -UseCache $Env.Build.UseCache -CachePath $Env.Build.CachePath

    # 9. WIM mounten
    $MountDir = Mount-BootWim -WorkDir $WorkDir

    # 10. startnet.cmd
    Set-StartnetCmd -MountDir $MountDir

    # 11. WinPE-Komponenten
    Add-WinPEComponents -MountDir $MountDir -OcPath $ADK.OcPath

    # 12. Treiber
    Add-Drivers -MountDir $MountDir -DriverPath $Env.Build.DriverSource

    # 13. Tools injizieren
    Add-ExternalTools -MountDir $MountDir -ToolsSrc $Env.Build.ToolsSource

    # 14. WIM speichern
    Save-AndUnmountWim -MountDir $MountDir

    # 15. OPSI-Struktur
    $WinpeDir = New-OpsiStructure -WorkDir $WorkDir -TargetOutputPath $Env.Build.OutputPath

    # 16. BCD
    New-BCDStore -WinpeDir $WinpeDir

    # 17. Symlink
    New-WinpeUefiSymlink -TargetOutputPath $Env.Build.OutputPath

    # 18. ISO unmounten
    if ($script:IsoMounted) {
        Dismount-DiskImage -ImagePath $script:IsoMountPath -ErrorAction SilentlyContinue | Out-Null
        $script:IsoMounted = $false
    }

    # 19. Cleanup Temp
    Write-Step "CLEANUP" "Loesche temporaeres Arbeitsverzeichnis..." "Gray"
    # Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

    # 20. Validierung
    $buildResult = Test-BuildResult -TargetOutputPath $Env.Build.OutputPath

    # 21. Transfer-Hinweise (mit OPSI-Server aus Environment)
    Show-TransferInstructions -TargetOutputPath $Env.Build.OutputPath -ProdId $Env.Product.ProductId

    # Abschluss
    Write-Host ""
    if ($buildResult.Errors -eq 0) {
        Write-Host "  BUILD ERFOLGREICH ABGESCHLOSSEN!" -ForegroundColor Green
    }
    else {
        Write-Host ("  BUILD ABGESCHLOSSEN MIT " + $buildResult.Errors + " FEHLER(N)") -ForegroundColor Yellow
    }
    Write-Host ("  Ausgabe: " + $Env.Build.OutputPath) -ForegroundColor Gray
    Write-Host ("  Log:     " + $script:LogFile) -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Host "     KRITISCHER FEHLER" -ForegroundColor Red
    Write-Host "  ================================================================" -ForegroundColor Red
    Write-Host ("  " + $_.Exception.Message) -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host ("  " + $_.ScriptStackTrace) -ForegroundColor DarkGray
    }
    Invoke-Cleanup
    Write-Host ""
    if ($script:LogFile) { Write-Host ("  Log: " + $script:LogFile) -ForegroundColor Gray }
}
finally {
    Invoke-Cleanup
    Write-Host ""
    Read-Host "  [Enter] druecken zum Beenden..."
    exit 0
}
