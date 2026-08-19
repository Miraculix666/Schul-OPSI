<#
    FILE: Deploy-ToServer.ps1
    PURPOSE: Automatisierter Deploy-Workflow: Build WinPE + Hardening-Paket auf OPSI-Server
    LAST MODIFIED: 2026-04-23
    MODIFIED BY: Systems Administration

    .SYNOPSIS
    Fuehrt den kompletten Build- und Deploy-Workflow aus:
    1. WinPE bauen (via Build-WinPE.ps1 -Env)
    2. Win11-Hardening OPSI-Paket nach Y:\ kopieren
    3. Server-Befehle anzeigen (opsi-set-rights, opsi-makepackage)

    .EXAMPLE
    .\Deploy-ToServer.ps1
    .\Deploy-ToServer.ps1 -SkipWinPE    # Nur Hardening-Paket deployen
    .\Deploy-ToServer.ps1 -DryRun       # Nur anzeigen, was passieren wuerde
#>

param(
    [switch]$SkipWinPE,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = Split-Path $ScriptDir -Parent
$EnvFile = Join-Path $RepoRoot "config\environment.json"

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "   Schul-OPSI Deploy Pipeline V1.0" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Environment laden
if (-not (Test-Path $EnvFile)) { throw "environment.json nicht gefunden: $EnvFile" }
$Config = Get-Content $EnvFile -Raw | ConvertFrom-Json
$DepotShare = $Config.OPSI.DepotSharePath
$ProductId = $Config.Product.ProductId
$ServerAddr = $Config.OPSI.ServerAddress
$ServerUser = $Config.OPSI.ServerUser
$DepotBase = $Config.OPSI.DepotBasePath

Write-Host "`n[CONFIG] Server: $ServerAddr | Depot: $DepotShare | Produkt: $ProductId" -ForegroundColor Gray

# 2. WinPE Build
if (-not $SkipWinPE) {
    Write-Host "`n[1/3] Starte WinPE-Build..." -ForegroundColor Yellow
    $builderPath = Join-Path $RepoRoot "winpe-builder\Build-WinPE.ps1"
    if (-not (Test-Path $builderPath)) { throw "Build-WinPE.ps1 nicht gefunden: $builderPath" }

    if ($DryRun) {
        Write-Host "  [DRY-RUN] Wuerde ausfuehren: $builderPath -Env" -ForegroundColor Gray
    } else {
        & $builderPath -Env
        if ($LASTEXITCODE -ne 0) { Write-Warning "WinPE-Build mit Warnungen beendet (Code: $LASTEXITCODE)" }
    }
} else {
    Write-Host "`n[1/3] WinPE-Build uebersprungen (-SkipWinPE)" -ForegroundColor Gray
}

# 3. Hardening-Paket deployen
Write-Host "`n[2/3] Deploye win11-hardening Paket..." -ForegroundColor Yellow
$hardeningSource = Join-Path $RepoRoot "win11-hardening"
$hardeningTarget = Join-Path $DepotShare "win11-hardening"

if ($DryRun) {
    Write-Host "  [DRY-RUN] Wuerde kopieren: $hardeningSource -> $hardeningTarget" -ForegroundColor Gray
} else {
    if (-not (Test-Path $DepotShare)) {
        Write-Warning "Depot-Share nicht erreichbar: $DepotShare"
        Write-Host "  Stelle sicher, dass Y:\ gemappt ist oder der Server erreichbar ist." -ForegroundColor Yellow
    } else {
        # Zielverzeichnis erstellen falls noetig
        if (-not (Test-Path $hardeningTarget)) { New-Item $hardeningTarget -ItemType Directory -Force | Out-Null }

        # Sync via Robocopy
        & robocopy "$hardeningSource" "$hardeningTarget" /E /MIR /R:2 /W:1 /NJH /NJS /NDL /NC /NS
        if ($LASTEXITCODE -le 7) {
            Write-Host "  [OK] Hardening-Paket nach $hardeningTarget synchronisiert" -ForegroundColor Green
        } else {
            Write-Warning "Robocopy-Fehler (Code: $LASTEXITCODE)"
        }
    }
}

# 4. WinPE Output deployen
if (-not $SkipWinPE) {
    Write-Host "`n[3/3] Deploye WinPE-Output..." -ForegroundColor Yellow
    $winpeOutput = $Config.Build.OutputPath
    $winpeTarget = Join-Path $DepotShare $ProductId

    if ($DryRun) {
        Write-Host "  [DRY-RUN] Wuerde kopieren: $winpeOutput -> $winpeTarget" -ForegroundColor Gray
    } else {
        if (Test-Path $DepotShare) {
            if (-not (Test-Path $winpeTarget)) { New-Item $winpeTarget -ItemType Directory -Force | Out-Null }
            & robocopy "$winpeOutput" "$winpeTarget" /E /MIR /R:2 /W:1 /NJH /NJS /NDL /NC /NS
            if ($LASTEXITCODE -le 7) {
                Write-Host "  [OK] WinPE nach $winpeTarget synchronisiert" -ForegroundColor Green
            }
        }
    }
} else {
    Write-Host "`n[3/3] WinPE-Deploy uebersprungen" -ForegroundColor Gray
}

# 5. Server-Befehle
Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "   Naechste Schritte auf dem OPSI-Server ($ServerAddr)" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  # Rechte setzen:" -ForegroundColor White
Write-Host "  opsi-set-rights $DepotBase/$ProductId/" -ForegroundColor Gray
Write-Host "  opsi-set-rights $DepotBase/win11-hardening/" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Hardening-Paket bauen:" -ForegroundColor White
Write-Host "  cd $DepotBase/win11-hardening && opsi-makepackage" -ForegroundColor Gray
Write-Host ""
Write-Host "  # OPSI neu laden:" -ForegroundColor White
Write-Host "  opsi-setup --init-current-config" -ForegroundColor Gray
Write-Host "  systemctl restart opsiconfd" -ForegroundColor Gray
Write-Host ""

Write-Host "Deploy-Pipeline abgeschlossen." -ForegroundColor Green

