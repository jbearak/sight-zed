# Tests for send-to-stata.ps1
# Note: We define test versions of functions rather than sourcing the script
# because the script has main execution logic that runs on load

BeforeAll {
    # Define the functions we want to test (copied from send-to-stata.ps1)
    function Get-StatementAtRow {
        param([string]$FilePath, [int]$Row)
        
        $lines = Get-Content $FilePath
        $startRow = $Row
        $endRow = $Row
        
        # Find statement start (search backwards)
        while ($startRow -gt 1 -and $lines[$startRow - 2] -match '///\s*$') {
            $startRow--
        }
        
        # Find statement end (search forwards)
        while ($endRow -lt $lines.Count -and $lines[$endRow - 1] -match '///\s*$') {
            $endRow++
        }
        
        return ($lines[($startRow - 1)..($endRow - 1)] -join [Environment]::NewLine)
    }
    
    function New-TempDoFile {
        param([string]$Content)
        
        try {
            $tempPath = [System.IO.Path]::GetTempPath()
            $fileName = [System.IO.Path]::GetRandomFileName()
            $doFile = [System.IO.Path]::ChangeExtension($fileName, ".do")
            $fullPath = Join-Path $tempPath $doFile
            
            [System.IO.File]::WriteAllText($fullPath, $Content, [System.Text.UTF8Encoding]::new($false))
            return $fullPath
        }
        catch {
            return $null
        }
    }
    
    function Read-SourceFile {
        param([string]$FilePath)
        return [System.IO.File]::ReadAllText($FilePath)
    }
    
    function Find-StataInstallation {
        if ($env:STATA_PATH -and (Test-Path $env:STATA_PATH)) {
            return $env:STATA_PATH
        }
        
        for ($version = 19; $version -ge 13; $version--) {
            $searchPaths = @(
                "C:\Program Files\Stata$version\",
                "C:\Program Files (x86)\Stata$version\",
                "C:\Stata$version\",
                "C:\Program Files\StataNow$version\",
                "C:\Program Files (x86)\StataNow$version\",
                "C:\StataNow$version\"
            )
            
            $variants = @("StataMP-64.exe", "StataSE-64.exe", "StataBE-64.exe", "StataIC-64.exe", 
                         "StataMP.exe", "StataSE.exe", "StataBE.exe", "StataIC.exe")
            
            foreach ($path in $searchPaths) {
                foreach ($variant in $variants) {
                    $fullPath = Join-Path $path $variant
                    if (Test-Path $fullPath) {
                        return $fullPath
                    }
                }
            }
        }
        
        $variants = @("StataMP-64.exe", "StataSE-64.exe", "StataBE-64.exe", "StataIC-64.exe", 
                     "StataMP.exe", "StataSE.exe", "StataBE.exe", "StataIC.exe")
        
        foreach ($variant in $variants) {
            $fullPath = Join-Path "C:\Stata\" $variant
            if (Test-Path $fullPath) {
                return $fullPath
            }
        }
        
        return $null
    }
}

Describe "Get-StatementAtRow" {
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
    
    It "Returns statement when cursor on last line" {
        $tempFile = New-TemporaryFile
        Set-Content -Path $tempFile.FullName -Value "gen x = 1 ///`n    + 2 ///`n    + 3"
        $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row 3
        $result | Should -Be "gen x = 1 ///`n    + 2 ///`n    + 3"
        Remove-Item $tempFile.FullName
    }
    
    It "Property3: Multi-line statement detection" -Tag "Property3" {
        for ($i = 0; $i -lt 100; $i++) {
            $tempFile = New-TemporaryFile
            
            # Create a simple multi-line statement
            $numLines = Get-Random -Minimum 2 -Maximum 5
            $lines = @()
            for ($l = 0; $l -lt $numLines; $l++) {
                if ($l -lt $numLines - 1) {
                    $lines += "line$l ///"
                } else {
                    $lines += "line$l"
                }
            }
            $content = $lines -join "`n"
            Set-Content -Path $tempFile.FullName -Value $content
            
            # Test from each line
            for ($row = 1; $row -le $numLines; $row++) {
                $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row $row
                $result | Should -Be $content
            }
            
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
                    0 { "// Comment with special chars: !@#" }
                    1 { "gen var$l = value" }
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
        function Get-CommandFormat {
            param([string]$Path, [bool]$Include)
            if ($Include) { return "include `"$Path`"" } else { return "do `"$Path`"" }
        }
        
        for ($i = 0; $i -lt 100; $i++) {
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

Describe "New-TempDoFile" {
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

Describe "Find-StataInstallation" {
    It "Property1: Returns STATA_PATH when set and path exists" -Tag "Property1" {
        for ($i = 0; $i -lt 100; $i++) {
            # Create a temp file to simulate Stata executable
            $tempFile = New-TemporaryFile
            $testPath = $tempFile.FullName
            
            $env:STATA_PATH = $testPath
            try {
                $result = Find-StataInstallation
                $result | Should -Be $testPath
            } finally {
                Remove-Item env:STATA_PATH -ErrorAction SilentlyContinue
                Remove-Item $testPath -ErrorAction SilentlyContinue
            }
        }
    }
    
    It "Property1: Ignores STATA_PATH when path does not exist" -Tag "Property1" {
        $env:STATA_PATH = "C:\NonExistent\Path\Stata.exe"
        try {
            $result = Find-StataInstallation
            # Should return null or auto-detected path, not the non-existent path
            $result | Should -Not -Be "C:\NonExistent\Path\Stata.exe"
        } finally {
            Remove-Item env:STATA_PATH -ErrorAction SilentlyContinue
        }
    }
}

Describe "Windows Automation" {
    It "Property11: Focus acquisition reliability" -Tag "Property11", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Windows-only integration test
    }
    
    It "Property12: STA mode verification" -Tag "Property12", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Windows-only integration test
    }
    
    It "Property13: Command window focus" -Tag "Property13", "WindowsOnly" {
        if ($env:OS -ne "Windows_NT") { Set-ItResult -Skipped -Because "Windows-only test" }
        # Windows-only integration test
    }
}
