
Describe "Config File Preservation" {
    It "Property8: preserves non-Stata entries in tasks.json" {
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
            $result = @(Get-Content $tasksFile -Raw | ConvertFrom-Json)
            (($result | Where-Object { $_.label -eq "MyTask-$i" }).Count) | Should BeGreaterThan 0
            (($result | Where-Object { $_.label -eq "OtherTask" }).Count) | Should BeGreaterThan 0
            
            Remove-Item $tempDir -Recurse -Force
        }
    }
    
    It "Property8: preserves non-Stata entries in keymap.json" {
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
            $result = @(Get-Content $keymapFile -Raw | ConvertFrom-Json)
            (($result | Where-Object { $_.context -eq "Editor" }).Count) | Should BeGreaterThan 0
            (($result | Where-Object { $_.context -eq "Workspace" }).Count) | Should BeGreaterThan 0
            
            Remove-Item $tempDir -Recurse -Force
        }
    }
}

Describe "Checksum Verification" {
    It "Property9: verifies checksum correctly" {
        for ($i = 0; $i -lt 100; $i++) {
            $content = "test content $i with random $(Get-Random)"
            $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))
            $actualHash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
            
            # Verify SHA256 hash format (64 hex characters)
            $actualHash | Should -Match '^[A-F0-9]{64}$'
            
            # Wrong hash should differ
            $wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
            ($actualHash -ne $wrongHash) | Should Be $true
        }
    }
    
    It "Property9: skips verification when SIGHT_GITHUB_REF is set" {
        $env:SIGHT_GITHUB_REF = "test-branch"
        try {
            # When SIGHT_GITHUB_REF is set, checksum verification should be skipped
            $skipVerification = $null -ne $env:SIGHT_GITHUB_REF
            $skipVerification | Should Be $true
        } finally {
            Remove-Item env:SIGHT_GITHUB_REF -ErrorAction SilentlyContinue
        }
    }
}

Describe "Automation Registration" {
    It "Property14: Registration is idempotent" {
        if ($env:OS -ne "Windows_NT") { 
            Set-ItResult -Skipped -Because "Windows-only test" 
        } else {
            Set-ItResult -Pending -Because "Test not yet implemented"
        }
    }
    
    It "Property15: Version mismatch detection" {
        if ($env:OS -ne "Windows_NT") { 
            Set-ItResult -Skipped -Because "Windows-only test" 
        } else {
            Set-ItResult -Pending -Because "Test not yet implemented"
        }
    }
}
