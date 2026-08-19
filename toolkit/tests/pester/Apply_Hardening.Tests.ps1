Describe "Write-LogEntry" {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../win11-hardening/CLIENT_DATA/Apply_Hardening.ps1"

        # Use AST to extract the function reliably
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $funcAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Write-LogEntry"
        }, $true)

        if ($null -ne $funcAst) {
            $functionCode = $funcAst.Extent.Text
            Invoke-Expression $functionCode
        } else {
            throw "Could not extract Write-LogEntry function using AST"
        }
    }

    BeforeEach {
        $Script:Stats = @{ Success = 0; Warnings = 0; Errors = 0; Skipped = 0 }
        $Script:LogFile = [System.IO.Path]::GetTempFileName()
    }

    AfterEach {
        if ($Script:LogFile -and (Test-Path $Script:LogFile)) {
            Remove-Item $Script:LogFile -Force
        }
    }

    It "Logs an INFO message correctly" {
        Mock Write-Verbose {}
        Write-LogEntry -Message "Test Info" -Type "INFO"

        $logContent = Get-Content $Script:LogFile
        $logContent | Should -Match "\[.*\] \[INFO\] Test Info"
        Assert-MockCalled Write-Verbose -Times 1 -ParameterFilter { $Message -match "Test Info" }
    }

    It "Logs a SUCCESS message correctly" {
        Mock Write-Host {}
        Write-LogEntry -Message "Test Success" -Type "SUCCESS"

        $logContent = Get-Content $Script:LogFile
        $logContent | Should -Match "\[.*\] \[SUCCESS\] Test Success"
        $Script:Stats.Success | Should -Be 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match "Test Success" -and $ForegroundColor -eq "Green" }
    }

    It "Logs a WARNING message correctly" {
        Mock Write-Host {}
        Write-LogEntry -Message "Test Warning" -Type "WARNING"

        $logContent = Get-Content $Script:LogFile
        $logContent | Should -Match "\[.*\] \[WARNING\] Test Warning"
        $Script:Stats.Warnings | Should -Be 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match "Test Warning" -and $ForegroundColor -eq "Yellow" }
    }

    It "Logs an ERROR message correctly" {
        Mock Write-Host {}
        Write-LogEntry -Message "Test Error" -Type "ERROR"

        $logContent = Get-Content $Script:LogFile
        $logContent | Should -Match "\[.*\] \[ERROR\] Test Error"
        $Script:Stats.Errors | Should -Be 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match "Test Error" -and $ForegroundColor -eq "Red" }
    }

    It "Logs a HEAD message correctly" {
        Mock Write-Host {}
        Write-LogEntry -Message "Test Head" -Type "HEAD"

        $logContent = Get-Content $Script:LogFile
        $logContent | Should -Match "\[.*\] \[HEAD\] Test Head"
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match "Test Head" -and $ForegroundColor -eq "Cyan" }
    }

    It "Throws an error for invalid Type" {
        { Write-LogEntry -Message "Test Invalid" -Type "INVALID" } | Should -Throw
    }
}
