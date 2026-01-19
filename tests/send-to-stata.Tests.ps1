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
}