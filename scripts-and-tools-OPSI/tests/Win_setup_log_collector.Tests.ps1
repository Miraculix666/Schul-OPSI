Describe "Test-UNCPathAccess" {
    BeforeAll {
        $ScriptPath = "$PSScriptRoot/../Win_setup_log_collector.ps1"
        $Content = Get-Content -Path $ScriptPath -Raw
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$null, [ref]$null)
        $FunctionAst = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-UNCPathAccess' }, $true)
        if ($FunctionAst) {
            Invoke-Expression $FunctionAst[0].Extent.Text
        } else {
            throw "Function Test-UNCPathAccess not found"
        }

        function global:net.exe { return "" }
    }

    Context "With Credentials" {
        BeforeEach {
            $cred = [pscredential]::new("user", (ConvertTo-SecureString "pass" -AsPlainText -Force))
            # Mock variables used in the original script but not defined in our isolated test
            $global:UserName = "user"
            $global:Password = "pass"
            $script:TempDriveName = "T"
        }

        It "Should return `$true when New-PSDrive succeeds" {
            Mock net.exe {}
            Mock New-PSDrive {}

            $result = Test-UNCPathAccess -Path "\\server\share" -Cred $cred
            $result | Should -Be $true
            Should -Invoke -CommandName net.exe -Times 1
            Should -Invoke -CommandName New-PSDrive -Times 1
        }

        It "Should return `$false when New-PSDrive throws an error" {
            Mock net.exe {}
            Mock New-PSDrive { throw "Drive error" }

            $result = Test-UNCPathAccess -Path "\\server\share" -Cred $cred
            $result | Should -Be $false
            Should -Invoke -CommandName net.exe -Times 1
            Should -Invoke -CommandName New-PSDrive -Times 1
        }

        It "Should return `$false when net.exe throws an error" {
            Mock net.exe { throw "Net exe error" }
            # Since net.exe is inside a general try block, it will catch the error

            $result = Test-UNCPathAccess -Path "\\server\share" -Cred $cred
            $result | Should -Be $false
            Should -Invoke -CommandName net.exe -Times 1
        }
    }

    Context "Without Credentials" {
        It "Should return `$true when Test-Path returns `$true" {
            Mock Test-Path { return $true }

            $result = Test-UNCPathAccess -Path "\\server\share"
            $result | Should -Be $true
            Should -Invoke -CommandName Test-Path -Times 1
        }

        It "Should return `$false when Test-Path returns `$false" {
            Mock Test-Path { return $false }

            $result = Test-UNCPathAccess -Path "\\server\share"
            $result | Should -Be $false
            Should -Invoke -CommandName Test-Path -Times 1
        }

        It "Should return `$false when Test-Path throws an error" {
            Mock Test-Path { throw "Path error" }

            $result = Test-UNCPathAccess -Path "\\server\share"
            $result | Should -Be $false
            Should -Invoke -CommandName Test-Path -Times 1
        }
    }
}
