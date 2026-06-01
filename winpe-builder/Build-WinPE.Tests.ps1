Describe "Invoke-SelfElevation" {
    BeforeAll {
        . "$PSScriptRoot/Build-WinPE.ps1"
    }

    It "Should return without starting a new process if already admin" {
        Mock Test-IsAdministrator { return $true }
        Mock Write-OK {}
        Mock Start-Process { throw "Should not start process" }

        Invoke-SelfElevation

        Assert-MockCalled Test-IsAdministrator -Times 1 -Exactly
        Assert-MockCalled Write-OK -Times 1 -Exactly
        Assert-MockCalled Start-Process -Times 0 -Exactly
    }

    It "Should attempt to start a new elevated process if not admin" {
        Mock Test-IsAdministrator { return $false }
        Mock Write-Warn {}
        Mock Start-Process {}
        Mock Exit-Script { throw "ExitMock" }
        Mock Write-Err {}
        Mock Write-Host {}
        Mock Read-Host {}

        { Invoke-SelfElevation } | Should -Throw "ExitMock"

        Assert-MockCalled Test-IsAdministrator -Times 1 -Exactly
        Assert-MockCalled Write-Warn -Times 1 -Exactly
        Assert-MockCalled Start-Process -Times 1 -Exactly
    }

    It "Should show error and exit 1 if starting process fails" {
        Mock Test-IsAdministrator { return $false }
        Mock Write-Warn {}
        Mock Write-Err {}
        Mock Start-Process { throw "Access Denied" }
        Mock Write-Host {}
        Mock Read-Host {}
        Mock Exit-Script { throw "ExitFailMock" }

        { Invoke-SelfElevation } | Should -Throw "ExitFailMock"

        Assert-MockCalled Test-IsAdministrator -Times 1 -Exactly
        Assert-MockCalled Start-Process -Times 1 -Exactly
        Assert-MockCalled Write-Err -Times 1 -Exactly
    }
}
