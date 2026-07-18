# End-to-end tests for the LLVM native backend on Windows (kaappi#1610).
# PowerShell port of run-e2e.sh's native-parity phase: `kaappi compile` every
# program in programs/, run the native binary, and require its output to match
# the interpreter's.
#
# Unlike run-e2e.sh this script does not build anything: native `zig build` is
# broken in the 0.16.0 aarch64-windows toolchain (#1613), so kaappi.exe and
# kaappi_rt.lib are cross-compiled and copied over — see "Testing on a Windows
# machine" in docs/dev/windows.md. `kaappi compile` discovers kaappi_rt.lib by
# itself (exe-relative ..\lib, or KAAPPI_LIB_DIR) and links with the first C
# compiler found on PATH, so put a working zig on PATH first: on ARM64 that
# means Zig master / >= 0.17.0 (the 0.16.0 toolchain access-violates, #1613);
# on x86_64 the stock 0.16.0 toolchain works (#1613 is aarch64-only) and the
# windows-x64-test CI job runs this script with it on every PR.
#
# Usage: powershell -ExecutionPolicy Bypass -File tests\e2e\run-e2e.ps1 `
#            [-Kaappi <path\to\kaappi.exe>]
#        (default: $env:KAAPPI, then <repo>\zig-out\bin\kaappi.exe)

param([string]$Kaappi = "")

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
if ($Kaappi -eq "") {
    if ($env:KAAPPI) { $Kaappi = $env:KAAPPI }
    else { $Kaappi = Join-Path $repoDir "zig-out\bin\kaappi.exe" }
}
if (-not (Test-Path $Kaappi)) {
    Write-Output "kaappi.exe not found at $Kaappi (pass -Kaappi or set KAAPPI)"
    exit 2
}

$outdir = Join-Path $env:TEMP ("kaappi-e2e-" + $PID)
New-Item -ItemType Directory -Force -Path $outdir | Out-Null

# Dirty builds at the same commit share bytecode-cache ids with different
# code (docs/dev/windows.md) — never trust a warm cache on a test box.
& $Kaappi cache clear 2>&1 | Out-Null

$pass = 0
$fail = 0
$failed = @()

# Default output naming must derive .exe on Windows (#1610).
Copy-Item (Join-Path $scriptDir "programs\hello.scm") (Join-Path $outdir "naming.scm") -Force
$null = (& $Kaappi compile (Join-Path $outdir "naming.scm") 2>&1)
if (($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $outdir "naming.exe"))) {
    Write-Output "PASS: default output naming (naming.scm -> naming.exe)"
    $pass++
} else {
    Write-Output "FAIL: default output naming"
    $fail++; $failed += "default-naming"
}

foreach ($p in (Get-ChildItem (Join-Path $scriptDir "programs\*.scm") | Sort-Object Name)) {
    $name = $p.BaseName
    $expected = (& $Kaappi $p.FullName 2>&1) -join "`n"
    $exe = Join-Path $outdir "$name.exe"
    $cc_out = (& $Kaappi compile $p.FullName -o $exe 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        Write-Output "FAIL: $name - compile failed"
        Write-Output $cc_out
        $fail++; $failed += $name
        continue
    }
    $actual = (& $exe 2>&1) -join "`n"
    if ($actual -ceq $expected) {
        Write-Output "PASS: $name"
        $pass++
    } else {
        Write-Output "FAIL: $name"
        Write-Output "  expected: $expected"
        Write-Output "  actual:   $actual"
        $fail++; $failed += $name
    }
}

Remove-Item -Recurse -Force $outdir -ErrorAction SilentlyContinue

Write-Output ""
$total = $pass + $fail
Write-Output "=== E2E Summary: $pass/$total passed ==="
if ($fail -gt 0) {
    Write-Output ("FAILED: " + ($failed -join ", "))
    exit 1
}
exit 0
