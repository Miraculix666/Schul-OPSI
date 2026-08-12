Import-Module Pester -RequiredVersion 4.10.1

# We can safely dot-source the entire script if we mock Invoke-SelfElevation and then
# exit or wrap the HAUPTPROGRAMM execution in an if block.
# Alternatively, since PowerShell handles mocking beautifully, let's extract the function
# dynamically without rigid Regex matching the end of the function body.
# We will use the PowerShell AST (Abstract Syntax Tree) to reliably extract the function.

$scriptPath = Join-Path $PSScriptRoot "Build-WinPE.ps1"
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

$functionAst = $ast.Find({
    param($astNode)
    $astNode -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $astNode.Name -eq "Test-BuildResult"
}, $true)

if (-not $functionAst) {
    throw "Function Test-BuildResult not found in $scriptPath"
}

# Get the extent text of the function and evaluate it
$functionBody = $functionAst.Extent.Text

$tempScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "Build-WinPE-Temp.ps1"
$functionBody | Set-Content -Path $tempScriptPath
. $tempScriptPath

Describe "Test-BuildResult" {
    BeforeAll {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:tempDir | Out-Null

        $script:winpeDir = Join-Path $script:tempDir "winpe"
        $script:sourcesDir = Join-Path $script:winpeDir "sources"
        $script:bootDir = Join-Path $script:winpeDir "Boot"
        $script:efiDir = Join-Path $script:winpeDir "EFI\Microsoft\Boot"
        $script:installDir = Join-Path $script:tempDir "installfiles"
        $script:uefiLink = Join-Path $script:tempDir "winpe_uefi"

        New-Item -ItemType Directory -Path $script:sourcesDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:bootDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:efiDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:installDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:uefiLink -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:tempDir) {
            Remove-Item $script:tempDir -Recurse -Force
        }
        if (Test-Path $tempScriptPath) {
            Remove-Item $tempScriptPath -Force
        }
    }

    Context "When all required files are present and of correct size" {
        BeforeAll {
            # Create valid files
            $f = [System.IO.File]::Create((Join-Path $script:sourcesDir "boot.wim")); $f.SetLength(209715200); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:bootDir "BCD")); $f.SetLength(8192); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:bootDir "boot.sdi")); $f.SetLength(1048576); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:winpeDir "bootmgr")); $f.SetLength(102400); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:efiDir "BCD")); $f.SetLength(8192); $f.Close()

            for ($i = 1; $i -le 101; $i++) {
                New-Item -ItemType File -Path (Join-Path $script:installDir "file$i.txt") | Out-Null
            }
        }

        AfterAll {
            Get-ChildItem $script:tempDir -Recurse -File | Remove-Item -Force
        }

        It "Should return 0 errors and 0 warnings" {
            $OriginalGetItem = Get-Command Get-Item

            function global:Get-Item {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
                    [string[]]$Path,
                    [switch]$Force
                )
                if ($Path -match "winpe_uefi") {
                    return [PSCustomObject]@{ Attributes = [IO.FileAttributes]::ReparsePoint }
                }

                if ($Force) {
                    & $OriginalGetItem -Path $Path -Force
                } else {
                    & $OriginalGetItem -Path $Path
                }
            }

            Set-Alias bcdedit.exe bcdedit-mock -Scope Global
            function global:bcdedit-mock { return "ramdisk=" }

            try {
                $result = Test-BuildResult -TargetOutputPath $script:tempDir
                $result.Errors | Should -Be 0
                $result.Warnings | Should -Be 0
            } finally {
                Remove-Item Function:\Get-Item
                Remove-Item Function:\bcdedit-mock
                Remove-Alias bcdedit.exe
            }
        }
    }

    Context "When files are missing" {
        It "Should return errors for missing files" {
            $OriginalGetItem = Get-Command Get-Item

            function global:Get-Item {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
                    [string[]]$Path,
                    [switch]$Force
                )
                if ($Path -match "winpe_uefi") {
                    return [PSCustomObject]@{ Attributes = [IO.FileAttributes]::ReparsePoint }
                }

                if ($Force) {
                    & $OriginalGetItem -Path $Path -Force
                } else {
                    & $OriginalGetItem -Path $Path
                }
            }

            Set-Alias bcdedit.exe bcdedit-mock -Scope Global
            function global:bcdedit-mock { return "ramdisk=" }

            try {
                $result = Test-BuildResult -TargetOutputPath $script:tempDir
                $result.Errors | Should -BeGreaterThan 0
            } finally {
                Remove-Item Function:\Get-Item
                Remove-Item Function:\bcdedit-mock
                Remove-Alias bcdedit.exe
            }
        }
    }

    Context "When files are too small" {
        BeforeAll {
            # Create files but too small
            $f = [System.IO.File]::Create((Join-Path $script:sourcesDir "boot.wim")); $f.SetLength(100); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:bootDir "BCD")); $f.SetLength(100); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:bootDir "boot.sdi")); $f.SetLength(100); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:winpeDir "bootmgr")); $f.SetLength(100); $f.Close()
            $f = [System.IO.File]::Create((Join-Path $script:efiDir "BCD")); $f.SetLength(100); $f.Close()
        }

        AfterAll {
            Get-ChildItem $script:tempDir -Recurse -File | Remove-Item -Force
        }

        It "Should return warnings for small files" {
            $OriginalGetItem = Get-Command Get-Item

            function global:Get-Item {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
                    [string[]]$Path,
                    [switch]$Force
                )
                if ($Path -match "winpe_uefi") {
                    return [PSCustomObject]@{ Attributes = [IO.FileAttributes]::ReparsePoint }
                }

                if ($Force) {
                    & $OriginalGetItem -Path $Path -Force
                } else {
                    & $OriginalGetItem -Path $Path
                }
            }

            Set-Alias bcdedit.exe bcdedit-mock -Scope Global
            function global:bcdedit-mock { return "ramdisk=" }

            try {
                $result = Test-BuildResult -TargetOutputPath $script:tempDir
                $result.Warnings | Should -BeGreaterThan 0
            } finally {
                Remove-Item Function:\Get-Item
                Remove-Item Function:\bcdedit-mock
                Remove-Alias bcdedit.exe
            }
        }
    }
}
