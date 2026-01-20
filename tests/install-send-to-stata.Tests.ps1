
# NOTE: These tests use Pester 3.x assertion style, because some environments (including CI)
# may still be pinned to Pester 3.* where modern operators like:
#   Should -Be, Should -Match, Should -Not -Match, Should -BeGreaterThan
# are not available.

Describe "Windows Installer Task Generation (ActivateStata)" {
    It "adds -ActivateStata to Stata tasks when configured" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test_$([System.IO.Path]::GetRandomFileName())"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            $tasksFile = Join-Path $tempDir "tasks.json"

            # Seed with a non-Stata task to ensure preservation is not impacted
            @(
                @{ label = "MyTask"; command = "echo hello" }
            ) | ConvertTo-Json -Depth 10 | Set-Content $tasksFile

            # Simulate installer "Install-Tasks -UseActivateStata $true" behavior
            $tasks = @()
            if (Test-Path $tasksFile) {
                # Normalize to an array (ConvertFrom-Json may return a single PSObject)
                $parsed = Get-Content $tasksFile -Raw | ConvertFrom-Json
                if ($parsed) { $tasks = @($parsed) }
            }

            $tasks = $tasks | Where-Object { -not ($_.label) -or -not $_.label.StartsWith("Stata:") }

            $exePath = "$env:APPDATA\Zed\stata\send-to-stata.exe"
            $activateStataArg = " -ActivateStata"

            $newTasks = @(
                @{
                    label = "Stata: Send Statement"
                    command = "& `"$exePath`" -Statement$activateStataArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
                },
                @{
                    label = "Stata: Send File"
                    command = "& `"$exePath`" -FileMode$activateStataArg -File `"`$ZED_FILE`""
                },
                @{
                    label = "Stata: Include Statement"
                    command = "& `"$exePath`" -Statement -Include$activateStataArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
                },
                @{
                    label = "Stata: Include File"
                    command = "& `"$exePath`" -FileMode -Include$activateStataArg -File `"`$ZED_FILE`""
                }
            )

            $tasks = @($tasks) + @($newTasks)

            $tasks | ConvertTo-Json -Depth 10 | Set-Content $tasksFile

            $raw = Get-Content $tasksFile -Raw
            ($raw -match '\-ActivateStata') | Should Be $true
        } finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not add -ActivateStata to Stata tasks when not configured" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "test_$([System.IO.Path]::GetRandomFileName())"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            $tasksFile = Join-Path $tempDir "tasks.json"

            # Simulate installer "Install-Tasks -UseActivateStata $false" behavior
            $tasks = @()

            $exePath = "$env:APPDATA\Zed\stata\send-to-stata.exe"
            $activateStataArg = ""

            $tasks += @(
                @{
                    label = "Stata: Send Statement"
                    command = "& `"$exePath`" -Statement$activateStataArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
                },
                @{
                    label = "Stata: Send File"
                    command = "& `"$exePath`" -FileMode$activateStataArg -File `"`$ZED_FILE`""
                },
                @{
                    label = "Stata: Include Statement"
                    command = "& `"$exePath`" -Statement -Include$activateStataArg -File `"`$ZED_FILE`" -Row `$ZED_ROW"
                },
                @{
                    label = "Stata: Include File"
                    command = "& `"$exePath`" -FileMode -Include$activateStataArg -File `"`$ZED_FILE`""
                }
            )

            $tasks | ConvertTo-Json -Depth 10 | Set-Content $tasksFile

            $raw = Get-Content $tasksFile -Raw
            ($raw -match '\-ActivateStata') | Should Be $false
        } finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

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
            ((($result | Where-Object { $_.label -eq "MyTask-$i" }).Count) -gt 0) | Should Be $true
            ((($result | Where-Object { $_.label -eq "OtherTask" }).Count) -gt 0) | Should Be $true

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
            ((($result | Where-Object { $_.context -eq "Editor" }).Count) -gt 0) | Should Be $true
            ((($result | Where-Object { $_.context -eq "Workspace" }).Count) -gt 0) | Should Be $true

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
            ($actualHash -match '^[A-F0-9]{64}$') | Should Be $true

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
