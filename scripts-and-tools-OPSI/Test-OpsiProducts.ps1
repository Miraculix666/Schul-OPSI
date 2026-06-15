<#
    FILE: Test-OpsiProducts.ps1
    PURPOSE: Validiert, ob alle Produkte im Ordner 'OPSI-Produkte' den Richtlinien entsprechen.
    LAST MODIFIED: 2026-06-15
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path $ScriptDir -Parent
$ProductsDir = Join-Path $RepoRoot "OPSI-Produkte"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Schul-OPSI Richtlinien-Validator V1.0" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if (-not (Test-Path $ProductsDir)) {
    Write-Host "[OK] Ordner '$ProductsDir' existiert nicht. Keine Produkte zu prüfen." -ForegroundColor Green
    Exit 0
}

$SubDirs = Get-ChildItem -Path $ProductsDir -Directory
$AnyFailed = $false

foreach ($dir in $SubDirs) {
    # Ignoriere versteckte Ordner oder spezielle Systemordner
    if ($dir.Name.StartsWith(".")) { continue }
    
    Write-Host "`nPrüfe Produkt: $($dir.Name)..." -ForegroundColor Yellow
    $Errors = @()

    # 1. Namenskonvention prüfen
    if ($dir.Name -notmatch '^[a-z0-9-]+$') {
        $Errors += "Ordnername '$($dir.Name)' entspricht nicht den Konventionen (nur Kleinbuchstaben, Zahlen und Bindestriche erlaubt)."
    }

    # 2. OPSI/control vorhanden?
    $controlPath = Join-Path $dir.FullName "OPSI\control"
    if (-not (Test-Path $controlPath)) {
        $Errors += "Metadaten-Datei 'OPSI\control' fehlt."
    }

    # 3. CLIENT_DATA vorhanden?
    $clientDataPath = Join-Path $dir.FullName "CLIENT_DATA"
    if (-not (Test-Path $clientDataPath)) {
        $Errors += "Ordner 'CLIENT_DATA' fehlt."
    }

    # 4. readme.md vorhanden?
    $readmePath = Join-Path $dir.FullName "readme.md"
    if (-not (Test-Path $readmePath)) {
        $Errors += "Dokumentationsdatei 'readme.md' fehlt."
    }

    # Auswertung für dieses Produkt
    if ($Errors.Count -eq 0) {
        Write-Host "  [OK] Alle Richtlinien erfüllt." -ForegroundColor Green
    } else {
        $AnyFailed = $true
        foreach ($err in $Errors) {
            Write-Host "  [FEHLER] $err" -ForegroundColor Red
        }
    }
}

Write-Host "`n================================================================" -ForegroundColor Cyan
if ($AnyFailed) {
    Write-Host "  VALIDIERUNG FEHLGESCHLAGEN: Ein oder mehrere Produkte verletzen die Richtlinien!" -ForegroundColor Red
    Exit 1
} else {
    Write-Host "  VALIDIERUNG ERFOLGREICH: Alle Produkte entsprechen den Richtlinien." -ForegroundColor Green
    Exit 0
}
