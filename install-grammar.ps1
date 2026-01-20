<#
.SYNOPSIS
    Downloads and installs the pre-built tree-sitter-stata grammar for Windows.

.DESCRIPTION
    Zed cannot compile tree-sitter grammars on Windows. This script downloads
    the pre-built grammar WASM and installs it to both the project directory
    and the Zed extensions directory.

.EXAMPLE
    .\install-grammar.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$grammarUrl = "https://github.com/jbearak/tree-sitter-stata/releases/download/v0.1.0/tree-sitter-stata.wasm"

# Download to project grammars directory
$grammarsDir = Join-Path $PSScriptRoot 'grammars'
if (-not (Test-Path $grammarsDir))
{
    New-Item -ItemType Directory -Path $grammarsDir -Force | Out-Null
}

$destWasm = Join-Path $grammarsDir 'stata.wasm'

Write-Host "Downloading pre-built tree-sitter-stata grammar..."
Invoke-WebRequest -Uri $grammarUrl -OutFile $destWasm

if (-not (Test-Path $destWasm))
{
    throw "Failed to download grammar WASM"
}

$size = (Get-Item $destWasm).Length
Write-Host "Downloaded grammar: grammars\stata.wasm ($size bytes)" -ForegroundColor Green

# Remove grammar source directory if it exists.
# If grammars/stata/ exists, Zed will try to compile it and fail on Windows.
$grammarSrcDir = Join-Path $grammarsDir 'stata'
if (Test-Path $grammarSrcDir)
{
    Remove-Item -Path $grammarSrcDir -Recurse -Force
    Write-Host "Removed grammar source directory: grammars\stata\" -ForegroundColor Yellow
}

# Also install to Zed extensions directory if it exists
$zedExtDir = Join-Path $env:LOCALAPPDATA 'Zed\extensions\installed\sight'
if (Test-Path $zedExtDir)
{
    $zedGrammarsDir = Join-Path $zedExtDir 'grammars'
    if (-not (Test-Path $zedGrammarsDir))
    {
        New-Item -ItemType Directory -Path $zedGrammarsDir -Force | Out-Null
    }

    Copy-Item -Path $destWasm -Destination $zedGrammarsDir -Force
    Write-Host "Installed grammar to Zed: $zedGrammarsDir\stata.wasm" -ForegroundColor Green

    # Remove source dir from installed extension too
    $zedGrammarSrcDir = Join-Path $zedGrammarsDir 'stata'
    if (Test-Path $zedGrammarSrcDir)
    {
        Remove-Item -Path $zedGrammarSrcDir -Recurse -Force
        Write-Host "Removed grammar source from Zed extension" -ForegroundColor Yellow
    }

    # Patch extension.toml to remove the [grammars.stata] section.
    # If this section exists, Zed will try to compile the grammar from source,
    # which fails on Windows. Removing it makes Zed use the pre-built WASM.
    $extensionToml = Join-Path $zedExtDir 'extension.toml'
    if (Test-Path $extensionToml)
    {
        $content = Get-Content -Path $extensionToml -Raw
        # Remove the [grammars.stata] section and its contents
        $pattern = '(?ms)\[grammars\.stata\]\r?\nrepository = "[^"]*"\r?\nrev = "[^"]*"\r?\n'
        $newContent = $content -replace $pattern, ''
        if ($newContent -ne $content)
        {
            Set-Content -Path $extensionToml -Value $newContent -NoNewline
            Write-Host "Patched extension.toml: removed [grammars.stata] section" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "Done. Restart Zed to load the grammar." -ForegroundColor Cyan
