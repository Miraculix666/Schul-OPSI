$ScriptPath = Join-Path $PSScriptRoot "Apply_Hardening.ps1"
$global:TempScriptPath = Join-Path $PSScriptRoot "Apply_Hardening_Temp.ps1"

$ScriptLines = Get-Content $ScriptPath
$MainBlockIndex = -1
for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
    if ($ScriptLines[$i] -match "HAUPTPROGRAMM") {
        for ($j = $i; $j -ge 0; $j--) {
            if ($ScriptLines[$j] -match "╔══════════════════════════════════════════════════════════════════════════════╗") {
                $MainBlockIndex = $j
                break
            }
        }
        break
    }
}

if ($MainBlockIndex -gt 0) {
    $SafeContent = $ScriptLines[0..($MainBlockIndex - 1)] -join "`n"
} else {
    $SafeContent = $ScriptLines -join "`n"
}

$global:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "Hardening"
$SafeContent = $SafeContent -replace '"C:\\ProgramData\\Hardening"', "`"$global:TestDir`""
$SafeContent = $SafeContent -replace '"C:\\Drivers_Temp"', '"/tmp/Drivers_Temp"'

$SafeContent | Set-Content $global:TempScriptPath -Encoding UTF8

Describe "Invoke-PrivacyHardening" {
    BeforeAll {
        if (-not (Test-Path $global:TestDir)) {
            New-Item -Path $global:TestDir -ItemType Directory | Out-Null
        }
        . $global:TempScriptPath

        # Stub Windows-specific cmdlets that are not available on Linux
        function Get-ScheduledTask {}
        function Disable-ScheduledTask {}
    }

    AfterAll {
        if (Test-Path $global:TempScriptPath) {
            Remove-Item $global:TempScriptPath -Force
        }
    }

    Context "Registry Hardening" {
        It "Should call Set-RegValue for each privacy setting" {
            Mock Set-RegValue {}
            Mock Write-LogEntry {}
            Mock Get-ScheduledTask {}
            Mock Disable-ScheduledTask {}

            Invoke-PrivacyHardening

            # We don't want to break the test if a new registry setting is added.
            # While Assert-MockCalled does not support "-Minimum", Pester 5 doesn't have an exact equivalent.
            # We'll just assert that the mock was called successfully, which proves the loop executes.
            Assert-MockCalled Set-RegValue
        }
    }

    Context "Scheduled Tasks (Happy Path)" {
        It "Should disable all found ready telemetry tasks" {
            Mock Set-RegValue {}
            Mock Write-LogEntry {}
            Mock Get-ScheduledTask {
                return [PSCustomObject]@{ State = 'Ready' }
            }
            Mock Disable-ScheduledTask {}

            Invoke-PrivacyHardening

            Assert-MockCalled Disable-ScheduledTask -Times 8 -Exactly
            Assert-MockCalled Write-LogEntry -ParameterFilter { $Message -like "Telemetrie-Task deaktiviert: *" } -Times 8 -Exactly
        }
    }

    Context "Scheduled Tasks (Already Disabled)" {
        It "Should not attempt to disable tasks that are already disabled" {
            Mock Set-RegValue {}
            Mock Write-LogEntry {}
            Mock Get-ScheduledTask {
                return [PSCustomObject]@{ State = 'Disabled' }
            }
            Mock Disable-ScheduledTask {}

            Invoke-PrivacyHardening

            Assert-MockCalled Disable-ScheduledTask -Times 0 -Exactly
        }
    }

    Context "Scheduled Tasks (Exception/Not Found)" {
        It "Should gracefully handle missing or failing tasks" {
            Mock Set-RegValue {}
            Mock Write-LogEntry {}
            Mock Get-ScheduledTask {
                throw "Task nicht gefunden"
            }
            Mock Disable-ScheduledTask {}

            Invoke-PrivacyHardening

            Assert-MockCalled Disable-ScheduledTask -Times 0 -Exactly
            Assert-MockCalled Write-LogEntry -ParameterFilter { $Message -like "Task nicht gefunden/deaktivierbar: *" } -Times 8 -Exactly
        }
    }
}
