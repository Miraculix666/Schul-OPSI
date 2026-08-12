Describe "Test-UNCPathAccess" {
    BeforeAll {
        $scriptPath = Resolve-Path "$PSScriptRoot/../Get-WindowsSetupLogs.ps1"
        $scriptContent = Get-Content $scriptPath -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$null)
        $functionAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-UNCPathAccess' }, $true)
        if (-not $functionAst) {
            throw "Function Test-UNCPathAccess not found in $scriptPath"
        }
        $functionText = $functionAst[0].Extent.Text
        Invoke-Expression $functionText
    }

    Context "When using Credentials" {
        BeforeEach {
            $global:cred = [PSCredential]::new("TestUser", (ConvertTo-SecureString "TestPass" -AsPlainText -Force))
        }

        It "Should return true if New-PSDrive succeeds" {
            Mock New-PSDrive {
                # Mock successful creation
                return $null
            }
            Mock Remove-PSDrive { return $null }

            $result = Test-UNCPathAccess -Path "\\server\share" -Cred $global:cred

            $result | Should -Be $true
            Assert-MockCalled New-PSDrive -Times 1 -Exactly -ParameterFilter { $Root -eq "\\server\share" -and $PSProvider -eq "FileSystem" }
            Assert-MockCalled Remove-PSDrive -Times 1 -Exactly
        }

        It "Should return false if New-PSDrive throws an exception" {
            Mock New-PSDrive {
                throw "Unexpected network error"
            }

            $result = Test-UNCPathAccess -Path "\\server\share" -Cred $global:cred

            $result | Should -Be $false
            Assert-MockCalled New-PSDrive -Times 1 -Exactly
        }
    }

    Context "When not using Credentials (Current User)" {
        It "Should return true if Test-Path succeeds" {
            Mock Test-Path { return $true }

            $result = Test-UNCPathAccess -Path "\\server\share"

            $result | Should -Be $true
            Assert-MockCalled Test-Path -Times 1 -Exactly -ParameterFilter { $Path -eq "\\server\share" }
        }

        It "Should return false if Test-Path fails" {
            Mock Test-Path { return $false }

            $result = Test-UNCPathAccess -Path "\\server\share"

            $result | Should -Be $false
            Assert-MockCalled Test-Path -Times 1 -Exactly
        }

        It "Should return false if Test-Path throws an exception" {
            Mock Test-Path { throw "Access Denied" }

            $result = Test-UNCPathAccess -Path "\\server\share"

            $result | Should -Be $false
            Assert-MockCalled Test-Path -Times 1 -Exactly
        }
    }
}
