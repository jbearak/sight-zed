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