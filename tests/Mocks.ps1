function Enable-Mocks {
    $script:MockClipboard = $true
    $script:MockWindow = $true
    $script:MockSendKeys = $true
}

function Disable-Mocks {
    $script:MockClipboard = $false
    $script:MockWindow = $false
    $script:MockSendKeys = $false
}

function Get-MockClipboard { return $script:ClipboardContent }
function Get-MockKeystrokes { return $script:SentKeystrokes }
function Reset-Mocks {
    $script:ClipboardContent = $null
    $script:SentKeystrokes = @()
}