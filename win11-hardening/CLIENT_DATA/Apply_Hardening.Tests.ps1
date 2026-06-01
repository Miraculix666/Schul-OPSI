BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "Apply_Hardening.ps1"
    $scriptContent = Get-Content $scriptPath -Raw
    $functionAst = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$null).FindAll({
        param($ast) $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $ast.Name -eq 'Test-IsRemoteSession'
    }, $true)
    Invoke-Expression $functionAst[0].Extent.Text

    $originalSessionName = $env:SESSIONNAME
    $originalSshConnection = [System.Environment]::GetEnvironmentVariable("SSH_CONNECTION")
}

Describe "Test-IsRemoteSession" {
    BeforeEach {
        # Reset variables to ensure clean state
        $env:SESSIONNAME = $null
        [System.Environment]::SetEnvironmentVariable("SSH_CONNECTION", $null)
        $global:PSSenderInfo = $null
        $global:SilentMode = $false
    }

    AfterAll {
        $env:SESSIONNAME = $originalSessionName
        [System.Environment]::SetEnvironmentVariable("SSH_CONNECTION", $originalSshConnection)
    }

    It "returns false when running locally and interactive" {
        $env:SESSIONNAME = "Console"
        Test-IsRemoteSession | Should -Be $false
    }

    It "returns true when SESSIONNAME is set and not Console" {
        $env:SESSIONNAME = "RDP-Tcp#0"
        Test-IsRemoteSession | Should -Be $true
    }

    It "returns true when SSH_CONNECTION environment variable is set" {
        [System.Environment]::SetEnvironmentVariable("SSH_CONNECTION", "192.168.1.2 55555 192.168.1.3 22")
        Test-IsRemoteSession | Should -Be $true
    }

    It "returns true when PSSenderInfo is present" {
        $global:PSSenderInfo = [PSCustomObject]@{ UserInfo = "Admin" }
        Test-IsRemoteSession | Should -Be $true
    }

    It "returns true when SilentMode is active" {
        $global:SilentMode = $true
        Test-IsRemoteSession | Should -Be $true
    }

    It "returns false when nothing is set" {
        Test-IsRemoteSession | Should -Be $false
    }
}
