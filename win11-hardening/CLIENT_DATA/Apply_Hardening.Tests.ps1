BeforeAll {
    # Extract just the function to test
    $content = Get-Content -Path "$PSScriptRoot/Apply_Hardening.ps1" -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$null)
    $funcAst = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq "Test-IsRemoteSession"}, $false)[0]

    # Evaluate it into the current scope
    Invoke-Expression $funcAst.Extent.Text

    # Test-IsRemoteSession uses $SilentMode from script scope, so define it
    $script:SilentMode = $false
}

Describe "Test-IsRemoteSession" {
    BeforeEach {
        # Reset variables
        $script:SilentMode = $false

        # Remove variables we might check
        if (Test-Path Env:SESSIONNAME) { Remove-Item Env:SESSIONNAME }
        [Environment]::SetEnvironmentVariable("SSH_CONNECTION", $null)
        $global:PSSenderInfo = $null
    }

    It "Should return `$false in a normal local session" {
        Test-IsRemoteSession | Should -Be $false
    }

    It "Should return `$true when SESSIONNAME is RDP-Tcp" {
        $env:SESSIONNAME = "RDP-Tcp#0"
        Test-IsRemoteSession | Should -Be $true
    }

    It "Should return `$false when SESSIONNAME is Console" {
        $env:SESSIONNAME = "Console"
        Test-IsRemoteSession | Should -Be $false
    }

    It "Should return `$true when SSH_CONNECTION is set" {
        [Environment]::SetEnvironmentVariable("SSH_CONNECTION", "10.0.0.1 55555 10.0.0.2 22")
        Test-IsRemoteSession | Should -Be $true
    }

    It "Should return `$true when SilentMode is active" {
        $script:SilentMode = $true
        Test-IsRemoteSession | Should -Be $true
    }
}
