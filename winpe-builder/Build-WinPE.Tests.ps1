$ScriptPath = Join-Path $PSScriptRoot "Build-WinPE.ps1"

Describe "Invoke-SelfElevation" {
    BeforeAll {
        $ScriptPath = "$PSScriptRoot/Build-WinPE.ps1"
        $scriptContent = Get-Content $ScriptPath -Raw
        # Remove top-level configuration that uses Split-Path etc which might fail if $MyInvocation is null
        $scriptContent = $scriptContent -replace '(?m)^\$script:ScriptDir = .*', '$script:ScriptDir = "/tmp"'
        $scriptContent = $scriptContent -replace '(?m)^\$script:RepoRoot = .*', '$script:RepoRoot = "/tmp"'
        $functionsOnly = $scriptContent -replace '(?ms)^Show-Banner.*', ''
        Invoke-Expression $functionsOnly
    }

    Context "When the user is already an Administrator" {
        It "Should log confirmation and return" {
            Mock Test-IsAdministrator { return $true }
            Mock Write-OK {}

            Invoke-SelfElevation

            Assert-MockCalled Test-IsAdministrator -Times 1 -Exactly
            Assert-MockCalled Write-OK -Times 1 -ParameterFilter { $Msg -eq "Administrator-Rechte bestaetigt" }
        }
    }

    Context "When the user is NOT an Administrator" {
        It "Should log a warning and start a new process" {
            Mock Test-IsAdministrator { return $false }
            Mock Write-Warn {}
            Mock Start-Process {}
            Mock Exit-Script {}

            Invoke-SelfElevation

            Assert-MockCalled Test-IsAdministrator -Times 1 -Exactly
            Assert-MockCalled Write-Warn -Times 1 -ParameterFilter { $Msg -match "starte erneut als Administrator" }
            Assert-MockCalled Start-Process -Times 1
            Assert-MockCalled Exit-Script -Times 1 -ParameterFilter { $ExitCode -eq 0 }
        }

        It "Should exit with 1 if starting the process fails" {
            Mock Test-IsAdministrator { return $false }
            Mock Write-Warn {}
            Mock Write-Err {}
            Mock Write-Host {}
            Mock Read-Host {}
            Mock Exit-Script {}

            Mock Start-Process { throw "Access Denied" }

            Invoke-SelfElevation

            Assert-MockCalled Test-IsAdministrator -Times 1 -Exactly
            Assert-MockCalled Write-Warn -Times 1
            Assert-MockCalled Start-Process -Times 1
            Assert-MockCalled Write-Err -Times 1 -ParameterFilter { $Msg -match "Elevation fehlgeschlagen" }
            Assert-MockCalled Read-Host -Times 1
            Assert-MockCalled Exit-Script -Times 1 -ParameterFilter { $ExitCode -eq 1 }
        }
    }
}
