BeforeAll {
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot/../archive/Hardening_V8.ps1", [ref]$null, [ref]$null)
    $functionAst = $scriptAst.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq "Get-ActivePowerScheme" }, $true)
    if ($functionAst) {
        $functionText = $functionAst.Extent.Text
        Invoke-Expression $functionText
    } else {
        throw "Function Get-ActivePowerScheme not found"
    }

    # Define a dummy powercfg to allow Mocking to work correctly in Linux environment where powercfg.exe does not exist.
    function global:powercfg { return "" }
}

Describe "Get-ActivePowerScheme" {
    Context "When powercfg returns a valid active scheme" {
        It "Should extract and return the GUID" {
            Mock powercfg { return "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *" }
            $result = Get-ActivePowerScheme
            $result | Should -Be "381b4222-f694-41f0-9685-ff5bb260df2e"
        }
    }

    Context "When powercfg returns no valid GUID" {
        It "Should return null" {
            Mock powercfg { return "No active power scheme found." }
            $result = Get-ActivePowerScheme
            $result | Should -BeNullOrEmpty
        }
    }

    Context "When powercfg returns unexpected output but still has GUID" {
        It "Should extract and return the GUID" {
            Mock powercfg { return "Some random text GUID: 11111111-2222-3333-4444-555555555555 some text after" }
            $result = Get-ActivePowerScheme
            $result | Should -Be "11111111-2222-3333-4444-555555555555"
        }
    }

    Context "When powercfg returns multiline output" {
        It "Should extract and return the GUID" {
            Mock powercfg {
                return @"
Powercfg line 1
Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance) *
Powercfg line 3
"@
            }
            $result = Get-ActivePowerScheme
            $result | Should -Be "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
        }
    }

    Context "When powercfg returns empty string" {
        It "Should return null" {
            Mock powercfg { return "" }
            $result = Get-ActivePowerScheme
            $result | Should -BeNullOrEmpty
        }
    }
}
