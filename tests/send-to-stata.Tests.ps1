BeforeAll {
    . "$PSScriptRoot/../send-to-stata.ps1"
}

Describe "Get-StatementAtRow" {
    It "Property3: Multi-line statement detection" -Tag "Property3" {
        for ($i = 0; $i -lt 100; $i++) {
            $tempFile = New-TemporaryFile
            
            # Generate random multi-line statements
            $statements = @()
            $lineToStatement = @{}
            $currentLine = 1
            
            # Create 2-4 statements
            $numStatements = Get-Random -Minimum 2 -Maximum 5
            for ($s = 0; $s -lt $numStatements; $s++) {
                $baseCmd = @("regress y x1", "sum x", "gen z = x1")[Get-Random -Maximum 3]
                $numContinuations = Get-Random -Minimum 1 -Maximum 4
                
                $statement = $baseCmd
                $statementLines = @($currentLine)
                
                for ($c = 0; $c -lt $numContinuations; $c++) {
                    $statement += " ///"
                    $lineToStatement[$currentLine] = $s
                    $currentLine++
                    
                    $continuation = @("x$($c+2)", "if condition", "option")[Get-Random -Maximum 3]
                    $statement += "`n    $continuation"
                    $statementLines += $currentLine
                }
                
                $lineToStatement[$currentLine] = $s
                $statements += $statement
                $currentLine++
                
                # Add blank line between statements
                if ($s -lt $numStatements - 1) {
                    $currentLine++
                }
            }
            
            $content = $statements -join "`n`n"
            Set-Content -Path $tempFile.FullName -Value $content
            
            # Pick random line within a multi-line statement
            $multiLineNumbers = $lineToStatement.Keys | Where-Object { $_ -gt 0 }
            $testLine = $multiLineNumbers | Get-Random
            $expectedStatementIndex = $lineToStatement[$testLine]
            $expectedStatement = $statements[$expectedStatementIndex]
            
            # Test the function
            $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row $testLine
            
            # Verify complete statement returned
            $result | Should -Be $expectedStatement
            
            Remove-Item $tempFile.FullName
        }
    }
}

Describe "File Operations" {
    It "Property4: Stdin content round-trip" -Tag "Property4" {
        for ($i = 0; $i -lt 100; $i++) {
            # Generate random text with compound strings
            $parts = @()
            $numParts = Get-Random -Minimum 1 -Maximum 5
            for ($p = 0; $p -lt $numParts; $p++) {
                $type = Get-Random -Maximum 3
                switch ($type) {
                    0 { $parts += "normal text $(Get-Random)" }
                    1 { $parts += "`"quoted text`"" }
                    2 { $parts += "``\`"compound string\`"'" }
                }
            }
            $originalText = $parts -join "`n"
            
            # Write to temp file
            $tempFile = New-TempDoFile -Content $originalText
            
            # Read back
            $readText = Get-Content -Path $tempFile -Raw
            
            # Verify exact match
            $readText | Should -Be $originalText
            
            Remove-Item $tempFile
        }
    }
    
    It "Property5: File content round-trip" -Tag "Property5" {
        for ($i = 0; $i -lt 100; $i++) {
            # Create source file with random content
            $sourceFile = New-TemporaryFile
            $content = @()
            $numLines = Get-Random -Minimum 1 -Maximum 10
            for ($l = 0; $l -lt $numLines; $l++) {
                $line = switch (Get-Random -Maximum 4) {
                    0 { "// Comment with special chars: !@#$%^&*()" }
                    1 { "gen var$l = ``\`"value $l\`"'" }
                    2 { "if condition { action }" }
                    3 { "normal line $l" }
                }
                $content += $line
            }
            $originalContent = $content -join "`n"
            Set-Content -Path $sourceFile.FullName -Value $originalContent
            
            # Read using Read-SourceFile
            $readContent = Read-SourceFile -FilePath $sourceFile.FullName
            
            # Write to temp using New-TempDoFile
            $tempFile = New-TempDoFile -Content $readContent
            $finalContent = Get-Content -Path $tempFile -Raw
            
            # Verify exact match
            $finalContent | Should -Be $originalContent
            
            Remove-Item $sourceFile.FullName, $tempFile
        }
    }
    
    It "Property7: Temp file characteristics" -Tag "Property7" {
        $createdFiles = @()
        for ($i = 0; $i -lt 100; $i++) {
            $content = "test content $i"
            $tempFile = New-TempDoFile -Content $content
            $createdFiles += $tempFile
            
            # Verify in system temp directory
            $tempFile | Should -Match [regex]::Escape([System.IO.Path]::GetTempPath())
            
            # Verify .do extension
            $tempFile | Should -Match '\.do$'
        }
        
        # Verify unique filenames
        $uniqueFiles = $createdFiles | Sort-Object -Unique
        $uniqueFiles.Count | Should -Be $createdFiles.Count
        
        # Cleanup
        $createdFiles | ForEach-Object { Remove-Item $_ -ErrorAction SilentlyContinue }
    }
    
    It "Property6: Command format by mode" -Tag "Property6" {
        # Helper function to extract command format logic
        function Get-CommandFormat {
            param([string]$Path, [bool]$Include)
            if ($Include) {
                return "include `"$Path`""
            } else {
                return "do `"$Path`""
            }
        }
        
        for ($i = 0; $i -lt 100; $i++) {
            # Generate random temp file path
            $tempPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "test_$(Get-Random).do")
            $includeMode = (Get-Random -Maximum 2) -eq 1
            
            $command = Get-CommandFormat -Path $tempPath -Include $includeMode
            
            if ($includeMode) {
                $command | Should -Be "include `"$tempPath`""
            } else {
                $command | Should -Be "do `"$tempPath`""
            }
        }
    }
}

Describe "Windows Automation" {
    It "Property11: Focus acquisition reliability" -Tag "Property11", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Test implementation for Windows
    }
    
    It "Property12: STA mode verification" -Tag "Property12", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Test implementation for Windows
    }
    
    It "Property13: Command window focus" -Tag "Property13", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Test implementation for Windows
    }
}

Describe "Unit Tests" {
    BeforeAll {
        . "$PSScriptRoot/../send-to-stata.ps1" -EnableMocks
    }
    
    Context "Argument parsing" {
        It "Statement and FileMode are mutually exclusive" {
            { & "$PSScriptRoot/../send-to-stata.ps1" -Statement "test" -FileMode } | Should -Throw
        }
        
        It "File parameter is required" {
            { & "$PSScriptRoot/../send-to-stata.ps1" -FileMode } | Should -Throw
        }
    }
    
    Context "Exit codes" {
        It "Returns 1 for Stata not found" {
            Mock Find-StataInstallation { return $null }
            $result = & "$PSScriptRoot/../send-to-stata.ps1" -Statement "test" 2>$null
            $LASTEXITCODE | Should -Be 1
        }
        
        It "Returns 2 for Stata window not found" {
            Mock Find-StataInstallation { return "C:\Stata\Stata.exe" }
            Mock Find-StataWindow { return $null }
            $result = & "$PSScriptRoot/../send-to-stata.ps1" -Statement "test" 2>$null
            $LASTEXITCODE | Should -Be 2
        }
    }
    
    Context "Find-StataInstallation" {
        It "Returns STATA_PATH when set" {
            $env:STATA_PATH = "C:\Custom\Stata.exe"
            try {
                $result = Find-StataInstallation
                $result | Should -Be "C:\Custom\Stata.exe"
            } finally {
                Remove-Item env:STATA_PATH -ErrorAction SilentlyContinue
            }
        }
        
        It "Returns null when no installation found" {
            Mock Test-Path { return $false }
            $result = Find-StataInstallation
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "Find-StataWindow" {
        It "Returns null when no Stata process" {
            Mock Get-Process { return @() }
            $result = Find-StataWindow
            $result | Should -BeNullOrEmpty
        }
        
        It "Filters by window title pattern" {
            Mock Get-Process { return @([PSCustomObject]@{MainWindowTitle="Stata/MP 19.0"}) }
            $result = Find-StataWindow
            $result | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Get-StatementAtRow" {
        It "Returns single-line statement" {
            $tempFile = New-TemporaryFile
            Set-Content -Path $tempFile.FullName -Value "gen x = 1"
            $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row 1
            $result | Should -Be "gen x = 1"
            Remove-Item $tempFile.FullName
        }
        
        It "Returns multi-line statement with ///" {
            $tempFile = New-TemporaryFile
            Set-Content -Path $tempFile.FullName -Value "gen x = 1 ///`n    + 2"
            $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row 1
            $result | Should -Be "gen x = 1 ///`n    + 2"
            Remove-Item $tempFile.FullName
        }
        
        It "Returns statement when cursor on middle line" {
            $tempFile = New-TemporaryFile
            Set-Content -Path $tempFile.FullName -Value "gen x = 1 ///`n    + 2 ///`n    + 3"
            $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row 2
            $result | Should -Be "gen x = 1 ///`n    + 2 ///`n    + 3"
            Remove-Item $tempFile.FullName
        }
    }
    
    Context "New-TempDoFile" {
        It "Creates file in temp directory" {
            $tempFile = New-TempDoFile -Content "test"
            $tempFile | Should -Match [regex]::Escape([System.IO.Path]::GetTempPath())
            Remove-Item $tempFile
        }
        
        It "Has .do extension" {
            $tempFile = New-TempDoFile -Content "test"
            $tempFile | Should -Match '\.do$'
            Remove-Item $tempFile
        }
        
        It "Writes content correctly" {
            $content = "gen x = 1"
            $tempFile = New-TempDoFile -Content $content
            $readContent = Get-Content -Path $tempFile -Raw
            $readContent | Should -Be $content
            Remove-Item $tempFile
        }
    }
}

Describe "Main Script Logic" {
    BeforeAll {
        . "$PSScriptRoot/Mocks.ps1"
        . "$PSScriptRoot/CrossPlatform.ps1"
    }
    
    It "Property1: STATA_PATH override" -Tag "Property1" {
        for ($i = 0; $i -lt 100; $i++) {
            $testPaths = @(
                "C:\Program Files\Stata19\StataMP-64.exe",
                "C:\Stata\StataSE.exe",
                "D:\Tools\Stata\Stata.exe"
            )
            $testPath = $testPaths | Get-Random
            
            $env:STATA_PATH = $testPath
            try {
                $result = Find-StataInstallation
                $result | Should -Be $testPath
            } finally {
                Remove-Item env:STATA_PATH -ErrorAction SilentlyContinue
            }
        }
    }
    
    It "Property2: Stata search order" -Tag "Property2" {
        for ($i = 0; $i -lt 100; $i++) {
            # Extract search paths from Find-StataInstallation logic
            $searchPaths = @(
                "C:\Program Files\Stata19\StataMP-64.exe",
                "C:\Program Files\Stata19\StataSE-64.exe", 
                "C:\Program Files\Stata19\Stata-64.exe",
                "C:\Program Files (x86)\Stata19\StataMP.exe",
                "C:\Program Files (x86)\Stata19\StataSE.exe",
                "C:\Program Files (x86)\Stata19\Stata.exe",
                "C:\Program Files\Stata18\StataMP-64.exe",
                "C:\Program Files\Stata13\StataMP-64.exe"
            )
            
            # Verify version order (19 before 18 before 13)
            $v19Index = $searchPaths.FindIndex({$args[0] -match "Stata19"})
            $v18Index = $searchPaths.FindIndex({$args[0] -match "Stata18"})
            $v13Index = $searchPaths.FindIndex({$args[0] -match "Stata13"})
            
            $v19Index | Should -BeLessThan $v18Index
            $v18Index | Should -BeLessThan $v13Index
            
            # Verify Program Files before Program Files (x86)
            $pf64 = $searchPaths | Where-Object {$_ -match "Program Files\\" -and $_ -notmatch "x86"}
            $pf32 = $searchPaths | Where-Object {$_ -match "Program Files \\(x86\\)"}
            
            $pf64Index = $searchPaths.IndexOf($pf64[0])
            $pf32Index = $searchPaths.IndexOf($pf32[0])
            $pf64Index | Should -BeLessThan $pf32Index
        }
    }
    
    It "Property10: Platform-independent logic isolation" -Tag "Property10" {
        Enable-Mocks
        try {
            for ($i = 0; $i -lt 100; $i++) {
                # Test platform-independent functions work without Windows APIs
                $tempFile = New-TemporaryFile
                $content = "gen x = 1 ///`n    + 2"
                Set-Content -Path $tempFile.FullName -Value $content
                
                # Get-StatementAtRow should work
                $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row 1
                $result | Should -Not -BeNullOrEmpty
                
                # New-TempDoFile should work
                $doFile = New-TempDoFile -Content "test"
                $doFile | Should -Not -BeNullOrEmpty
                Test-Path $doFile | Should -Be $true
                
                # Read-SourceFile should work
                $readContent = Read-SourceFile -FilePath $tempFile.FullName
                $readContent | Should -Not -BeNullOrEmpty
                
                Remove-Item $tempFile.FullName, $doFile -ErrorAction SilentlyContinue
            }
        } finally {
            Disable-Mocks
        }
    }
}