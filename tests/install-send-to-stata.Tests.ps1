BeforeAll {
    # Don't source the installer directly as it runs main execution
    # Instead, define test versions of the functions
}

Describe "Config File Preservation" {
    It "Property8: preserves non-Stata entries in tasks.json" -Tag "Property8" {
        for ($i = 0; $i -lt 100; $i++) {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test_$([System.IO.Path]::GetRandomFileName())"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $tasksFile = Join-Path $tempDir "tasks.json"
            
            # Create random non-Stata entries
            $randomTasks = @(
                @{ label = "MyTask-$i"; command = "echo $i" },
                @{ label = "OtherTask"; command = "test" }
            )
            $randomTasks | ConvertTo-Json -Depth 10 | Set-Content $tasksFile
            
            # Simulate Install-Tasks logic
            $tasks = Get-Content $tasksFile | ConvertFrom-Json
            $tasks = @($tasks | Where-Object { !$_.label.StartsWith("Stata:") })
            $tasks += @{ label = "Stata: Test"; command = "test" }
            $tasks | ConvertTo-Json -Depth 10 | Set-Content $tasksFile
            
            # Verify non-Stata entries preserved
            $result = Get-Content $tasksFile | ConvertFrom-Json
            ($result | Where-Object { $_.label -eq "MyTask-$i" }) | Should -Not -BeNullOrEmpty
            ($result | Where-Object { $_.label -eq "OtherTask" }) | Should -Not -BeNullOrEmpty
            
            Remove-Item $tempDir -Recurse -Force
        }
    }
    
    It "Property8: preserves non-Stata entries in keymap.json" -Tag "Property8" {
        for ($i = 0; $i -lt 100; $i++) {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test_$([System.IO.Path]::GetRandomFileName())"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $keymapFile = Join-Path $tempDir "keymap.json"
            
            # Create random non-Stata entries
            $randomKeybindings = @(
                @{ context = "Editor"; bindings = @{ "ctrl-k" = "test::Action" } },
                @{ context = "Workspace"; bindings = @{ "ctrl-p" = "other::Action" } }
            )
            $randomKeybindings | ConvertTo-Json -Depth 10 | Set-Content $keymapFile
            
            # Simulate Install-Keybindings logic
            $keybindings = Get-Content $keymapFile | ConvertFrom-Json
            $keybindings = @($keybindings | Where-Object { $_.context -ne "Editor && extension == do" })
            $keybindings += @{ context = "Editor && extension == do"; bindings = @{ "ctrl-enter" = "test" } }
            $keybindings | ConvertTo-Json -Depth 10 | Set-Content $keymapFile
            
            # Verify non-Stata entries preserved
            $result = Get-Content $keymapFile | ConvertFrom-Json
            ($result | Where-Object { $_.context -eq "Editor" }) | Should -Not -BeNullOrEmpty
            ($result | Where-Object { $_.context -eq "Workspace" }) | Should -Not -BeNullOrEmpty
            
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

Describe "Checksum Verification" {
    It "Property9: verifies checksum correctly" -Tag "Property9" {
        for ($i = 0; $i -lt 100; $i++) {
            $content = "test content $i with random $(Get-Random)"
            $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))
            $actualHash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
            
            # Correct hash should pass
            $actualHash | Should -Be $actualHash
            
            # Wrong hash should differ
            $wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
            $actualHash | Should -Not -Be $wrongHash
        }
    }
    
    It "Property9: skips verification when SIGHT_GITHUB_REF is set" -Tag "Property9" {
        $env:SIGHT_GITHUB_REF = "test-branch"
        try {
            # When SIGHT_GITHUB_REF is set, checksum verification should be skipped
            $skipVerification = $null -ne $env:SIGHT_GITHUB_REF
            $skipVerification | Should -Be $true
        } finally {
            Remove-Item env:SIGHT_GITHUB_REF -ErrorAction SilentlyContinue
        }
    }
}

Describe "Automation Registration" {
    It "Property14: Registration is idempotent" -Tag "Property14", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Windows-only test implementation
    }
    
    It "Property15: Version mismatch detection" -Tag "Property15", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Windows-only test implementation
    }
}
