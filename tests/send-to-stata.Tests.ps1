Describe "send-to-stata.ps1" {
    BeforeAll {
        $script:envBackup = $env:SEND_TO_STATA_SKIP_MAIN
        $env:SEND_TO_STATA_SKIP_MAIN = 1
        . "$PSScriptRoot/../send-to-stata.ps1"
    }
    AfterAll {
        if ($null -ne $script:envBackup) { $env:SEND_TO_STATA_SKIP_MAIN = $script:envBackup } else { Remove-Item env:SEND_TO_STATA_SKIP_MAIN -ErrorAction SilentlyContinue }
    }
    Context "Get-StatementAtRow" {
        It "returns single-line statement" {
            $tempFile = New-TemporaryFile
            Set-Content -Path $tempFile.FullName -Value "gen x = 1"
            $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row 1
            $result.Replace("`r`n","`n") | Should Be "gen x = 1"
            Remove-Item $tempFile.FullName
        }
        It "Property3: Multi-line detection with ///" {
            $tempFile = New-TemporaryFile
            Set-Content -Path $tempFile.FullName -Value "a ///`n b ///`n c"
            foreach ($row in 1..3) {
                $result = Get-StatementAtRow -FilePath $tempFile.FullName -Row $row
                $result.Replace("`r`n","`n") | Should Be "a ///`n b ///`n c"
            }
            Remove-Item $tempFile.FullName
        }
    }
    Context "Temp file and content preservation" {
    It "Property4: stdin round-trip" {
        $text = @'
`"quoted`"
``"compound`"'
'@
        $temp = New-TempDoFile -Content $text
        (Get-Content -Path $temp -Raw) | Should Be $text
        Remove-Item $temp
    }
    It "Property7: temp file has .do extension" {
        $temp = New-TempDoFile -Content "x"
        [IO.Path]::GetExtension($temp) | Should Be ".do"
        Remove-Item $temp
    }
}
    Context "Find-StataInstallation" {
    It "Property1: uses STATA_PATH when valid" {
        $tempExe = New-TemporaryFile
        try {
            $env:STATA_PATH = $tempExe.FullName
            Find-StataInstallation | Should -Be $tempExe.FullName
        } finally {
            Remove-Item env:STATA_PATH -ErrorAction SilentlyContinue
            Remove-Item $tempExe.FullName -ErrorAction SilentlyContinue
        }
    }
}
    Context "Send-ToStata with mocks" {
    BeforeEach {
        $script:MockClipboard = $true
        $script:MockSendKeys = $true
        $script:MockWindow = $true
        $script:MockFocus = $true
        $script:ClipboardContent = $null
        $script:SentKeystrokes = @()
    }
    It "sends include command and keystroke sequence" {
        $tf = New-TempDoFile -Content "gen x=1"
        Send-ToStata -TempFilePath $tf -UseInclude:$true
        $script:ClipboardContent | Should Be "include `"$tf`""
        $script:SentKeystrokes -contains "^1" | Should Be $true
        $script:SentKeystrokes -contains "^v" | Should Be $true
        $script:SentKeystrokes -contains "{ENTER}" | Should Be $true
        Remove-Item $tf
    }
}
}
