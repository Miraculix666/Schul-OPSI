$ErrorActionPreference = "Stop"

BeforeAll {
    . "$PSScriptRoot/Build-WinPE.ps1"
}

Describe "Test-BuildResult" {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path "$([System.IO.Path]::GetTempPath())/WinPETest_$(Get-Random)" -Force
        $script:winpeDir = New-Item -ItemType Directory -Path (Join-Path $script:tempDir "winpe") -Force
        $script:winpeUefiDir = Join-Path $script:tempDir "winpe_uefi"
        $script:installDir = New-Item -ItemType Directory -Path (Join-Path $script:tempDir "installfiles") -Force

        # Create valid required files
        $reqFiles = @(
            @{ Path = "sources\boot.wim"; Size = 210000000 },
            @{ Path = "Boot\BCD"; Size = 9000 },
            @{ Path = "Boot\boot.sdi"; Size = 1100000 },
            @{ Path = "bootmgr"; Size = 110000 },
            @{ Path = "EFI\Microsoft\Boot\BCD"; Size = 9000 }
        )

        foreach ($file in $reqFiles) {
            $fullPath = Join-Path $script:winpeDir $file.Path
            New-Item -ItemType Directory -Path (Split-Path $fullPath) -Force | Out-Null
            $fs = [System.IO.File]::Create($fullPath)
            $fs.SetLength($file.Size)
            $fs.Close()
        }

        # Create valid symlink
        if ($IsLinux) {
            & bash -c "ln -s ""$script:winpeDir"" ""$script:winpeUefiDir"""
        } else {
            New-Item -ItemType SymbolicLink -Path $script:winpeUefiDir -Target $script:winpeDir | Out-Null
        }

        # Create > 100 install files
        for ($i = 1; $i -le 101; $i++) {
            $path = Join-Path $script:installDir "file_$i.txt"
            Set-Content -Path $path -Value "test"
        }
    }

    AfterEach {
        if (Test-Path $script:tempDir) {
            Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should return 0 errors and 0 warnings for a valid output path" {
        function global:bcdedit.exe { return "ramdisk=" }
        Mock -CommandName bcdedit.exe -MockWith { return "ramdisk=" }

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Errors | Should -Be 0
        $result.Warnings | Should -Be 0
    }

    It "Should return errors if required files are missing" {
        function global:bcdedit.exe { return "ramdisk=" }
        Mock -CommandName bcdedit.exe -MockWith { return "ramdisk=" }

        Remove-Item (Join-Path $script:winpeDir "sources\boot.wim") -Force

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Errors | Should -BeGreaterThan 0
    }

    It "Should return warnings if required files are too small" {
        function global:bcdedit.exe { return "ramdisk=" }
        Mock -CommandName bcdedit.exe -MockWith { return "ramdisk=" }

        $bootWimPath = Join-Path $script:winpeDir "sources\boot.wim"
        $fs = [System.IO.File]::OpenWrite($bootWimPath)
        $fs.SetLength(100) # smaller than required
        $fs.Close()

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Warnings | Should -BeGreaterThan 0
    }

    It "Should return errors if bcdedit does not return ramdisk=" {
        function global:bcdedit.exe { return "invalid" }
        Mock -CommandName bcdedit.exe -MockWith { return "invalid" }

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Errors | Should -BeGreaterThan 0
    }

    It "Should return errors if winpe_uefi symlink is missing" {
        function global:bcdedit.exe { return "ramdisk=" }
        Mock -CommandName bcdedit.exe -MockWith { return "ramdisk=" }

        Remove-Item $script:winpeUefiDir -Force

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Errors | Should -BeGreaterThan 0
    }

    It "Should return warnings if winpe_uefi is a directory not a symlink" {
        function global:bcdedit.exe { return "ramdisk=" }
        Mock -CommandName bcdedit.exe -MockWith { return "ramdisk=" }

        Remove-Item $script:winpeUefiDir -Force
        New-Item -ItemType Directory -Path $script:winpeUefiDir -Force | Out-Null

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Warnings | Should -BeGreaterThan 0
    }

    It "Should return warnings if installfiles has 100 or fewer files" {
        function global:bcdedit.exe { return "ramdisk=" }
        Mock -CommandName bcdedit.exe -MockWith { return "ramdisk=" }

        Remove-Item (Join-Path $script:installDir "file_101.txt") -Force

        $result = Test-BuildResult -TargetOutputPath $script:tempDir

        $result.Warnings | Should -BeGreaterThan 0
    }
}
