<#OPSI WinPE & Unattended Rebuild History (Version 13.5)

1. Tree of Thoughts (Systematische Analyse)

Problem A: Der 0603ef Fehler (No matching OS images)

Beobachtung: Das Log WINPEsetupact.log zeigt ElementValue = [] für den Image-Namen.

Ursache: Das alte OPSI-Paket enthält Variablen wie #@imagename*#. Da das Feld in der OPSI-GUI leer ist, löscht das OPSI-Python-Skript den Inhalt im Template und hinterlässt ein leeres <Value></Value>. Windows Setup findet kein Image namens "" und bricht ab.

Lösung: Radikale Entfernung aller OPSI-Variablen im Bereich ImageInstall. Wir nutzen nun hartcodiert <Key>/IMAGE/INDEX</Key><Value>1</Value>. Da jede LTSC-ISO Index 1 ist, gibt es immer einen Match.

Problem B: Win10-Altlasten & CPI-Fehler

Beobachtung: Win10-Pfade und cpi:offlineImage erscheinen am Ende der XML.

Ursache: OPSI priorisiert Dateien im Verzeichnis /custom/. Ein kopiertes Win10-Paket hat dort oft veraltete Templates, die manuelle Änderungen in opsi/ oder installfiles/ überschreiben.

Lösung: Platzierung des neuen LTSC-Templates direkt in /custom/ und physisches Löschen des CPI-Blocks.

Problem C: Hardening-Skripte

Beobachtung: Hardening-Scripts im Depot werden nicht gefunden oder PowerShell schlägt fehl.

Lösung: Verwendung des $OEM$-Mechanismus. Dateien liegen in sources\$OEM$\$$\Setup\Files\ und werden beim ersten Login lokal von C:\Windows\Setup\Files\ aufgerufen.

2. Installationsanleitung

Schritt 1: Builder ausführen (Lokal)

Führe WinPE.ps1 aus. Es bereinigt blockierte DISM-Sitzungen automatisch, kopiert die Tools und erstellt das ISO. Prüfe den Ordner _WIM_CONTENT_INSPECT auf Vollständigkeit.

Schritt 2: OPSI-Server vorbereiten

Verbinde dich per SSH mit dem OPSI-Server.

Lösche veraltete Templates in opsi/ und installfiles/.

Erstelle die Datei /var/lib/opsi/depot/win11-x64/custom/unattend.xml.template mit dem Inhalt der V13.5.

Führe opsi-set-rights /var/lib/opsi/depot/win11-x64 aus.

Führe opsi-setup --init-current-config aus.

Schritt 3: OPSI-GUI (configed) Einstellungen

imagename: LEER LASSEN.

productkey: LEER LASSEN.

installto: disk.

askbeforeinst: Haken raus.

3. Rebuild History Summary

V10-V12: Identifikation des Variablen-Mismatchs und der Ordner-Priorität.

V13.1-V13.4: Verfeinerung des PowerShell-Builders (Handling von Fehlern 50 & 0xc1510111).

V13.5 (Aktuell): Finale Konsolidierung. Vollständiger Verzicht auf OPSI-Variablen in der XML zur Fehlervermeidung. Fix der Hardening-Pfade auf lokale Pfade.
#>

<#
Schritt 1: Das OPSI-Template auf dem Server fixieren

Lösche alle .template Dateien in opsi/ und installfiles/ (oder benenne sie um).
Erstelle die Datei: /var/lib/opsi/depot/win11-x64/custom/unattend.xml.template
(Inhalt siehe unten: OPSI Unattended LTSC V13.1)

Schritt 2: Die PowerShell-Umgebung fixieren

Ersetze den Inhalt deiner lokalen C:\GitHub\...\WinPE.ps1 durch den unten stehenden Code. Stelle sicher, dass kein Chat-Text am Anfang der Datei steht.

Schritt 3: OPSI-GUI Einstellungen (configed)

imagename: (leer)

productkey: (leer)

installto: disk

win11_hardware_check: false

askbeforeinst: false

Schritt 4: Finale am Server (Konsole)

opsi-set-rights /var/lib/opsi/depot/win11-x64
opsi-setup --init-current-config
systemctl restart opsiconfd

#>

<#<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <!-- .VERSION 13.5 - MASTER FIX - CLEAN SLATE -->
    <!-- PFAD: /var/lib/opsi/depot/win11-x64/custom/unattend.xml.template -->
    <!-- Logik: Ersetzt alle OPSI-Variablen durch harte Werte um Fehler 0603ef zu vermeiden. -->

    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <DiskConfiguration>
                <WillShowUI>Never</WillShowUI>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add"><Order>1</Order><Type>Primary</Type><Size>500</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>2</Order><Type>EFI</Type><Size>100</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>3</Order><Type>MSR</Type><Size>128</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>4</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>Recovery</Label><Format>NTFS</Format><TypeID>DE94BBA4-06D1-4D40-A16A-BFD50179D6AC</TypeID></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID><Label>System</Label><Format>FAT32</Format></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>4</Order><PartitionID>4</PartitionID><Label>WINDOWS</Label><Format>NTFS</Format><Letter>C</Letter></ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <UserData>
                <ProductKey>
                    <!-- KMS Key LTSC 2024 Hartcodiert -->
                    <Key>NVH6G-RVTFM-XTY3J-69WW6-RRG44</Key>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
                <FullName>IT-Administrator</FullName>
                <Organization>Dienststelle</Organization>
            </UserData>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <!-- INDEX 1 loest den Fehler 0603ef (Empty Name) -->
                            <Key>/IMAGE/INDEX</Key>
                            <Value>1</Value>
                        </MetaData>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>4</PartitionID>
                    </InstallTo>
                    <WillShowUI>Never</WillShowUI>
                </OSImage>
            </ImageInstall>
            <RunSynchronous>
                <!-- HARDWARE-BYPASS GEGEN 1-KERN-VM-FEHLER -->
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>cmd.exe /c "reg add HKLM\System\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>cmd.exe /c "reg add HKLM\System\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>cmd.exe /c "reg add HKLM\System\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f"</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage><UILanguage>de-DE</UILanguage><WillShowUI>Never</WillShowUI></SetupUILanguage>
            <InputLocale>de-DE</InputLocale>
            <SystemLocale>de-DE</SystemLocale>
            <UserLocale>de-DE</UserLocale>
        </component>
    </settings>

    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>cmd.exe /c net user Administrator nt123! /active:yes</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>*</ComputerName>
        </component>
    </settings>

    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <AutoLogon>
                <Enabled>true</Enabled>
                <LogonCount>2</LogonCount>
                <Username>admin</Username>
                <Password><Value>bgB0ADEAMgAzACEA</Value><PlainText>false</PlainText></Password>
            </AutoLogon>
            <UserAccounts>
                <LocalAccount wcm:action="add">
                    <Password><Value>bgB0ADEAMgAzACEA</Value><PlainText>false</PlainText></Password>
                    <Name>admin</Name>
                    <Group>Administrators</Group>
                </LocalAccount>
            </UserAccounts>
            <FirstLogonCommands>
                <!-- HARDENING AUS LOKALEM PFAD (OEM-KOPIE C:\Windows\Setup\Files) -->
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Files\Apply_Harden.ps1</CommandLine>
                    <Description>Hardening Skript 1</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Files\Apply_Harden_Policies.ps1</CommandLine>
                    <Description>Hardening Skript 2</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <CommandLine>cmd.exe /c W:\opsi\postinst.cmd</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <ProtectYourPC>3</ProtectYourPC>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
            </OOBE>
        </component>
    </settings>
</unattend>
#>



<#
    .SYNOPSIS
    Standardkonformer WinPE Builder V13.5 für OPSI 4.3 (LTSC 2024).

    ANFORDERUNGEN:
    - Erstellung der WinPE Ordnerstruktur & ISO-Image.
    - Integration externer Tools (Explorer++, Micro, NPP, Sysinternals).
    - Caching-Logik: Kopiert ISO-Inhalte nur, wenn sie nicht bereits vorhanden sind.
    - Verbose Debugging & Inspect-Kopie (_WIM_CONTENT_INSPECT) für die Validierung.
    - Robustes DISM-Management zur Vermeidung von Sperren (Fehler 50/0xc1510111).
#>

param (
    [Parameter(Mandatory=$true)] [string]$opsiexportpath,
    [Parameter(Mandatory=$true)] [string]$WorkingPath,
    [Parameter(Mandatory=$true)] [string]$DriverSource,
    [Parameter(Mandatory=$true)] [string]$sourceiso,
    [string]$ToolsSource = "Y:\opsi-winpe\tools"
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Pfad-Definitionen
$MountPath = Join-Path $WorkingPath "mount"
$BootWimMod = Join-Path $WorkingPath "boot_modified.wim"
$InspectPath = Join-Path $opsiexportpath "_WIM_CONTENT_INSPECT"
$IsoFile = Join-Path $WorkingPath "OPSI_WinPE_LTSC_2024.iso"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   OPSI WinPE Builder V13.5 (Standard-Kform)   " -ForegroundColor Cyan
Write-Host "   System: Windows 11 LTSC 2024 Build 26100    " -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# --- 1. ADMIN-CHECK & ADK-WERKZEUGE ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Skript erfordert Administratorrechte!"
}

function Get-OscdimgPath {
    $paths = @(
        "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "C:\Program Files (x86)\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    foreach ($p in $paths) { if (Test-Path $p) { return $p } }
    $fromPath = Get-Command "oscdimg.exe" -ErrorAction SilentlyContinue
    return if ($fromPath) { $fromPath.Source } else { $null }
}

# --- 2. REINIGUNGSPHASE (Verhindert DISM-Fehler) ---
Write-Host "[CLEANUP] Bereinige Mount-Punkte..." -ForegroundColor Yellow
$mountedImages = Get-WindowsImage -Mounted
foreach ($img in $mountedImages) {
    if ($img.Path -eq $MountPath) {
        Write-Host "[REPAIR] Löse blockierten Mount in $MountPath..." -ForegroundColor Red
        Dism /Unmount-Wim /MountDir:$MountPath /Discard
    }
}

if (Test-Path $MountPath) { Remove-Item $MountPath -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $MountPath, $InspectPath, $opsiexportpath -Force | Out-Null

# --- 3. ISO-PHASE & CACHING ---
$targetWim = Join-Path $opsiexportpath "sources\boot.wim"
if (!(Test-Path $targetWim)) {
    Write-Host "[ISO] Extrahiere Basis-Dateien von ISO..." -ForegroundColor Cyan
    $mountResult = Mount-DiskImage -ImagePath $sourceiso -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    if (!$driveLetter) { throw "ISO Mount fehlgeschlagen!" }

    $isoPath = "$($driveLetter):\"
    Write-Host "[COPY] Kopiere Daten nach $opsiexportpath..."
    Copy-Item "$isoPath*" $opsiexportpath -Recurse -Force
    Dismount-DiskImage -ImagePath $sourceiso | Out-Null
} else {
    Write-Host "[CACHE] Nutze vorhandene Struktur in $opsiexportpath." -ForegroundColor Green
}

# --- 4. WIM-MANIPULATION (Index 2) ---
Write-Host "[MODIFY] Bereite boot.wim zur Injektion vor..."
Copy-Item $targetWim $BootWimMod -Force
Dism /Mount-Wim /WimFile:$BootWimMod /Index:2 /MountDir:$MountPath

# --- 5. INJEKTION (Treiber & OPSI-Tools) ---
Write-Host "[CUSTOM] Injektiere Treiber..." -ForegroundColor Cyan
Dism /Image:$MountPath /Add-Driver /Driver:$DriverSource /Recurse /ForceUnsigned

Write-Host "[CUSTOM] Integriere Tools in System32\Tools..."
$peToolsPath = Join-Path $MountPath "Windows\System32\Tools"
New-Item -ItemType Directory -Path $peToolsPath -Force | Out-Null

if (Test-Path $ToolsSource) {
    Copy-Item "$ToolsSource\*" $peToolsPath -Recurse -Force
    Write-Host "[OK] Werkzeuge injiziert." -ForegroundColor Green
}

# --- 6. DEBUG-KOPIE (INSPECT) ---
Write-Host "[INSPECT] Erstelle Inhaltskopie für Validierung..." -ForegroundColor Yellow
robocopy $MountPath $InspectPath /E /R:0 /W:0 /XJ /NFL /NDL /NJH /NJS | Out-Null

# --- 7. SPEICHERN & ISO-BUILD ---
Write-Host "[SAVE] Schließe WIM (Commit)..." -ForegroundColor Cyan
Dism /Unmount-Wim /MountDir:$MountPath /Commit
Copy-Item $BootWimMod $targetWim -Force

Write-Host "[ISO] Generiere bootfähiges Medium..."
$oscdimg = Get-OscdimgPath
if ($oscdimg) {
    $etfs = Join-Path $opsiexportpath "boot\etfsboot.com"
    $args = "-n -m -b`"$etfs`" `"$opsiexportpath`" `"$IsoFile`""
    Start-Process -FilePath $oscdimg -ArgumentList $args -Wait -NoNewWindow
    Write-Host "[FERTIG] ISO erstellt: $IsoFile" -ForegroundColor Green
} else {
    Write-Host "[WARNUNG] oscdimg.exe fehlt. ISO-Erstellung übersprungen." -ForegroundColor Red
}

Write-Host "`nDebugging-Ebene: $InspectPath" -ForegroundColor Gray
