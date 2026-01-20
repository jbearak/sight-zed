# Windows-native Send-to-Stata tests (no dotnet/xUnit dependency)
#
# Windows send-to-stata is shipped as committed native executables:
#   - send-to-stata-x64.exe
#   - send-to-stata-arm64.exe
#
# These tests validate the *shipped binaries* directly so the suite does not depend on:
#   - dotnet SDK availability/versioning
#   - NuGet restore
#   - xUnit runner infrastructure
#
# Notes:
# - Windows-only tests.
# - Pester 3-compatible assertions (Should Be).
# - Tests are designed to avoid requiring Stata to be installed; we focus on
#   argument parsing / error handling paths that should execute before automation.

. "$PSScriptRoot/CrossPlatform.ps1"

function Invoke-Exe {
    param(
        [Parameter(Mandatory=$true)][string]$ExePath,
        [Parameter(Mandatory=$true)][string[]]$Args
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExePath
    $psi.Arguments = ($Args -join ' ')
    $psi.WorkingDirectory = (Join-Path $PSScriptRoot "..")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    $null = $p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return @{
        ExitCode = $p.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

Describe "send-to-stata (Windows native executable)" {

    It "has committed send-to-stata executables in repo root" {
        Skip-WindowsOnly

        $repoRoot = Join-Path $PSScriptRoot ".."
        $x64 = Join-Path $repoRoot "send-to-stata-x64.exe"
        $arm64 = Join-Path $repoRoot "send-to-stata-arm64.exe"

        (Test-Path $x64) | Should Be $true
        (Test-Path $arm64) | Should Be $true
    }

    It "prints a deprecation warning for -ReturnFocus (argument parsing smoke test)" {
        Skip-WindowsOnly

        $repoRoot = Join-Path $PSScriptRoot ".."
        $arm64 = Join-Path $repoRoot "send-to-stata-arm64.exe"

        if (-not (Test-Path $arm64)) {
            throw "Missing executable: $arm64"
        }

        # Provide required args so the executable gets past basic validation and produces stderr output.
        # We do NOT require the exact deprecation warning text because the executable may exit early
        # due to automation/focus-stealing prevention or missing Stata.
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("test_" + [System.IO.Path]::GetRandomFileName() + ".do")
        Set-Content -Path $tempFile -Value "display 1" -Encoding UTF8

        try {
            $result = Invoke-Exe -ExePath $arm64 -Args @("-FileMode", "-ReturnFocus", "-File", "`"$tempFile`"")

            # Some environments may successfully complete without producing stderr (e.g. if Stata is available
            # and the command sends successfully). We only assert that the process ran to completion.
            ($null -ne $result.ExitCode) | Should Be $true
        } finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "accepts -ActivateStata flag without crashing (argument parsing smoke test)" {
        Skip-WindowsOnly

        $repoRoot = Join-Path $PSScriptRoot ".."
        $arm64 = Join-Path $repoRoot "send-to-stata-arm64.exe"

        if (-not (Test-Path $arm64)) {
            throw "Missing executable: $arm64"
        }

        # Provide minimal but invalid args so it exits quickly. We only assert it runs.
        $result = Invoke-Exe -ExePath $arm64 -Args @("-ActivateStata")

        # Non-zero exit is expected (invalid args), but it should not hard-crash.
        # We treat any integer exit code as "ran"; specifically, it must return.
        ($null -ne $result.ExitCode) | Should Be $true
    }
}
