Import-Module Pester -ErrorAction SilentlyContinue

Describe "Test-BuildResult" {
    BeforeAll {
        $tempBasePath = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
        $script:tempDir = Join-Path $tempBasePath "test-buildresult-dir"

        # Mock functions that could cause side-effects or fail without privileges
        function global:bcdedit.exe { return "" }
    }

    BeforeEach {
        if (Test-Path $script:tempDir) { Remove-Item $script:tempDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $script:tempDir
    }

    AfterAll {
        if (Test-Path $script:tempDir) { Remove-Item $script:tempDir -Recurse -Force }
        Remove-Item Function:\bcdedit.exe -ErrorAction SilentlyContinue
    }

    Context "When testing the extracted function directly" {
        BeforeAll {
            # Safely extract the function using AST instead of brittle regex
            $scriptPath = "$PSScriptRoot/Build-WinPE.ps1"
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $functionAst = $ast.Find({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-BuildResult'
            }, $true)

            if ($functionAst) {
                # Execute the extracted function definition in memory
                $scriptBlock = [scriptblock]::Create($functionAst.Extent.Text)
                # Dot-source the script block into the global scope
                . $scriptBlock
            } else {
                throw "Could not find function Test-BuildResult in $scriptPath"
            }
        }

        It "returns errors and warnings when required files and directories are completely missing" {
            $result = Test-BuildResult -TargetOutputPath $script:tempDir
            $result.Errors | Should -Be 6  # 5 required files + 1 symlink = 6 missing
            $result.Warnings | Should -Be 1 # 1 installfiles missing = 1 warning
        }

        It "returns warnings when required files exist but are too small" {
            $winpeDir = Join-Path $script:tempDir "winpe"
            $installDir = Join-Path $script:tempDir "installfiles"

            $null = New-Item -ItemType Directory -Path (Join-Path $winpeDir "sources") -Force
            $null = New-Item -ItemType Directory -Path (Join-Path $winpeDir "Boot") -Force
            $null = New-Item -ItemType Directory -Path (Join-Path $winpeDir "EFI\Microsoft\Boot") -Force
            $null = New-Item -ItemType Directory -Path $installDir -Force

            # Create required files with INSUFFICIENT size (1 byte)
            $null = New-Item -ItemType File -Path (Join-Path $winpeDir "sources\boot.wim") -Value "x"
            $null = New-Item -ItemType File -Path (Join-Path $winpeDir "Boot\BCD") -Value "x"
            $null = New-Item -ItemType File -Path (Join-Path $winpeDir "Boot\boot.sdi") -Value "x"
            $null = New-Item -ItemType File -Path (Join-Path $winpeDir "bootmgr") -Value "x"
            $null = New-Item -ItemType File -Path (Join-Path $winpeDir "EFI\Microsoft\Boot\BCD") -Value "x"

            Mock bcdedit.exe { return "" }

            $result = Test-BuildResult -TargetOutputPath $script:tempDir

            $result.Warnings | Should -Be 6 # 5 too small + 1 installfiles too few
            $result.Errors | Should -Be 2 # 1 symlink missing + 1 BCD check missing
        }

        It "returns success (0 errors, 0 warnings) when everything is correct" {
            Mock Test-Path { return $true }
            Mock Get-Item {
                return [pscustomobject]@{ Length = 300MB; Attributes = [IO.FileAttributes]::ReparsePoint }
            }
            Mock Get-ChildItem {
                return 1..105 | ForEach-Object { [pscustomobject]@{ Name = "file$_.txt" } }
            }
            Mock bcdedit.exe { return "ramdisk=" }

            $result = Test-BuildResult -TargetOutputPath $script:tempDir

            $result.Errors | Should -Be 0
            $result.Warnings | Should -Be 0
        }
    }
}
