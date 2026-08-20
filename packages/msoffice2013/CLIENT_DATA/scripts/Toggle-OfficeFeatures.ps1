<#
.SYNOPSIS
    Toggle-OfficeFeatures.ps1 - An-/Abschalten von Microsoft Office Telemetrie und Online-Funktionen.

.DESCRIPTION
    Skript zur Steuerung von Telemetrie, Feedback-Funktionen und Connected Experiences in Microsoft Office.
    Ermöglicht das Deaktivieren (Härtung) oder Reaktivieren von Online-Diensten, Cloud-Schriftarten und Telemetrie-Uploads.

.PARAMETER DisableFeatures
    Aktiviert den gehärteten Modus: Schaltet Telemetrie, CEIP, Feedback, Cloud-Schriftarten und Online-Dienste aus.

.PARAMETER EnableFeatures
    Setzt den Standardmodus wieder her: Entfernt Einschränkungen für Online-Dienste und Vorlagen.

.PARAMETER Status
    Gibt den aktuellen Status der Telemetrie- und Richtlinien-Einstellungen aus.

.EXAMPLE
    .\Toggle-OfficeFeatures.ps1 -DisableFeatures

.EXAMPLE
    .\Toggle-OfficeFeatures.ps1 -EnableFeatures

.EXAMPLE
    .\Toggle-OfficeFeatures.ps1 -Status
#>

[CmdletBinding(DefaultParameterSetName = 'Status')]
param (
    [Parameter(ParameterSetName = 'Disable')]
    [switch]$DisableFeatures,

    [Parameter(ParameterSetName = 'Enable')]
    [switch]$EnableFeatures,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# Registrierungspfade für Office 16.0 Policy
$PoliciesPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0"
$UserPoliciesPath = "HKCU:\Software\Policies\Microsoft\Office\16.0"

function Set-RegistryValue {
    param (
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$PropertyType = "DWord"
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType -ErrorAction SilentlyContinue
}

function Remove-RegistryValue {
    param (
        [string]$Path,
        [string]$Name
    )
    if (Test-Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

function Set-OfficeTasksState {
    param ([bool]$Enable)
    $tasks = @(
        "\Microsoft\Office\Office Telemetry Agent Log Upload",
        "\Microsoft\Office\Office Telemetry Agent Fallback",
        "\Microsoft\Office\Office Feature Updates",
        "\Microsoft\Office\Office Feature Updates Logon"
    )
    
    foreach ($task in $tasks) {
        try {
            if ($Enable) {
                Enable-ScheduledTask -TaskPath "\" -TaskName ($task -split '\\')[-1] -ErrorAction SilentlyContinue | Out-Null
            } else {
                Disable-ScheduledTask -TaskPath "\" -TaskName ($task -split '\\')[-1] -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {
            # Aufgabe existiert möglicherweise nicht auf allen Systemen
        }
    }
}

if ($DisableFeatures) {
    Write-Host "[INFO] Aktiviere gehärteten Modus (Telemetrie & Online-Dienste werden abgeschaltet)..." -ForegroundColor Yellow

    # 1. Telemetrie & Logging deaktivieren (NTLite / WindowsTelemetryBlocker)
    Set-RegistryValue -Path "$PoliciesPath\common\telemetry" -Name "enabletelemetry" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\common\telemetry" -Name "enablelogging" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\common\telemetry" -Name "sendtelemetry" -Value 0

    # 2. Kundenfeedback-Programm (CEIP) deaktivieren
    Set-RegistryValue -Path "$PoliciesPath\common" -Name "qmenable" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\common" -Name "updatereliabilitydata" -Value 0

    # 3. Privacy & Connected Experiences abschalten (O&O ShutUp10 Vorgabe)
    Set-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "disconnectedstate" -Value 2
    Set-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "telemetryenabled" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "downloadcontentdisabled" -Value 2
    Set-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "controllerconnectedservicesenabled" -Value 2

    # 4. Feedback & Screenshot-Übermittlung blockieren
    Set-RegistryValue -Path "$PoliciesPath\common\feedback" -Name "enabled" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\common\feedback" -Name "includescreenshotenabled" -Value 0

    # 5. Office Service Manager Telemetrie
    Set-RegistryValue -Path "$PoliciesPath\osm" -Name "enabletelemetry" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\osm" -Name "enablelogging" -Value 0
    Set-RegistryValue -Path "$PoliciesPath\osm" -Name "enablefileobfuscation" -Value 1

    # 6. Aufgabenplanung bereinigen
    Set-OfficeTasksState -Enable $false

    Write-Host "[OK] Gehärteter Modus erfolgreich angewendet." -ForegroundColor Green
    Exit 0
}

if ($EnableFeatures) {
    Write-Host "[INFO] Entferne Härtungs-Richtlinien (Standardfunktionen werden wieder freigeschaltet)..." -ForegroundColor Yellow

    # Entferne gesetzte Policy-Sperren
    Remove-RegistryValue -Path "$PoliciesPath\common\telemetry" -Name "enabletelemetry"
    Remove-RegistryValue -Path "$PoliciesPath\common\telemetry" -Name "enablelogging"
    Remove-RegistryValue -Path "$PoliciesPath\common\telemetry" -Name "sendtelemetry"
    Remove-RegistryValue -Path "$PoliciesPath\common" -Name "qmenable"
    Remove-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "disconnectedstate"
    Remove-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "telemetryenabled"
    Remove-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "downloadcontentdisabled"
    Remove-RegistryValue -Path "$PoliciesPath\common\privacy" -Name "controllerconnectedservicesenabled"
    Remove-RegistryValue -Path "$PoliciesPath\common\feedback" -Name "enabled"

    # Aufgaben wieder aktivieren
    Set-OfficeTasksState -Enable $true

    Write-Host "[OK] Richtlinien zurückgesetzt. Standardfunktionen sind wieder verfügbar." -ForegroundColor Green
    Exit 0
}

# Default: Status anzeigen
Write-Host "=== Status der Microsoft Office Telemetrie & Richtlinien ===" -ForegroundColor Cipher
$telemetryReg = Get-ItemProperty -Path "$PoliciesPath\common\telemetry" -ErrorAction SilentlyContinue
$privacyReg   = Get-ItemProperty -Path "$PoliciesPath\common\privacy" -ErrorAction SilentlyContinue

Write-Host "Telemetrie aktiviert         : $(if ($telemetryReg.enabletelemetry -eq 1) { 'JA' } else { 'NEIN (Gehärtet)' })"
Write-Host "Connected Experiences        : $(if ($privacyReg.disconnectedstate -eq 2) { 'NEIN (Deaktiviert)' } else { 'JA (Aktiv)' })"
Write-Host "Kundenfeedback-Programm (CEIP): $(if ((Get-ItemProperty -Path "$PoliciesPath\common" -ErrorAction SilentlyContinue).qmenable -eq 1) { 'JA' } else { 'NEIN' })"
