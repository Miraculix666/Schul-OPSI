[CmdletBinding()]
param (
    [string]$ExecutionPolicyVal = "Bypass",
    [string]$SilentVal = "true",
    [string]$ScriptFilterVal = "*.ps1",
    [string]$ScriptParametersVal = ""
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptsDir = Join-Path $scriptPath "scripts"

Write-Output "=== PowerShell Script Runner Wrapper ==="
Write-Output "Execution Policy: $ExecutionPolicyVal"
Write-Output "Silent Mode     : $SilentVal"
Write-Output "Script Filter   : $ScriptFilterVal"
Write-Output "Script Params   : $ScriptParametersVal"
Write-Output "Scripts Directory: $scriptsDir"

# Setze bei Bedarf die System-ExecutionPolicy
if ($ExecutionPolicyVal -ne "Bypass") {
    Write-Output "Versuche ExecutionPolicy permanent auf '$ExecutionPolicyVal' fuer die Maschine zu setzen..."
    try {
        Set-ExecutionPolicy -ExecutionPolicy $ExecutionPolicyVal -Scope LocalMachine -Force -ErrorAction Stop
        Write-Output "ExecutionPolicy erfolgreich auf '$ExecutionPolicyVal' gesetzt."
    } catch {
        Write-Warning "Konnte ExecutionPolicy nicht auf LocalMachine-Ebene setzen: $_"
    }
}

if (-not (Test-Path $scriptsDir)) {
    Write-Output "Verzeichnis '$scriptsDir' existiert nicht. Bitte lege deine .ps1 Skripte dort ab."
    Exit 0
}

# Skripte suchen
$files = Get-ChildItem -Path $scriptsDir -Filter $ScriptFilterVal -File
if ($files.Count -eq 0) {
    Write-Output "Keine Skripte gefunden, die dem Filter '$ScriptFilterVal' entsprechen."
    Exit 0
}

Write-Output "Gefundene Skripte zur Ausfuehrung:"
foreach ($file in $files) {
    Write-Output " - $($file.Name)"
}

$anyFailed = $false
$exitCode = 0

foreach ($file in $files) {
    Write-Output "--------------------------------------------------"
    Write-Output "Starte Ausfuehrung von: $($file.Name)"
    
    $procArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $file.FullName)
    if ($SilentVal -eq "true") {
        $procArgs += @("-NonInteractive", "-WindowStyle", "Hidden")
    }
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    
    $argsString = $procArgs -join " "
    if ($ScriptParametersVal) {
        $argsString += " " + $ScriptParametersVal
    }
    $psi.Arguments = $argsString
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = ($SilentVal -eq "true")
    
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    
    try {
        [void]$proc.Start()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        
        if ($stdout) {
            Write-Output "OUTPUT:"
            Write-Output $stdout
        }
        if ($stderr) {
            Write-Warning "ERROR OUTPUT:"
            Write-Warning $stderr
        }
        
        Write-Output "Skript $($file.Name) beendet mit ExitCode: $($proc.ExitCode)"
        if ($proc.ExitCode -ne 0) {
            $anyFailed = $true
            $exitCode = $proc.ExitCode
        }
    } catch {
        Write-Error "Fehler bei der Ausfuehrung von $($file.Name): $_"
        $anyFailed = $true
        $exitCode = 1
    }
}

Write-Output "=================================================="
if ($anyFailed) {
    Write-Output "Ein oder mehrere Skripte wurden mit Fehlern beendet."
    exit $exitCode
} else {
    Write-Output "Alle Skripte wurden erfolgreich ausgefuehrt."
    exit 0
}
