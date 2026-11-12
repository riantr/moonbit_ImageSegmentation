<#
.SYNOPSIS
    Runs every ported algorithm on its own on all four MoonBit backends and
    compares the result byte for byte with the Java reference output.

.DESCRIPTION
    The port has to work on every backend, and every algorithm has to work
    on its own. This script therefore

      1. runs the library test suite on all backends (`moon test --target all`),
      2. builds the command line tool for a backend,
      3. runs every algorithm **alone** on every test image and compares the
         files and the scalars it wrote with the Java reference
         (`verify/compare.py --algo <algorithm>`),
      4. runs the integrated `seg run` on every test image and compares the
         complete output set.

    The result is a matrix of backend x algorithm.

    The wasm backends need a file system policy for the host (`moonrun` only
    wires the file system imports when a policy is given).

.PARAMETER Targets
    The backends to test: native, js, wasm, wasm-gc.

.PARAMETER Algorithms
    The algorithms to run on their own. The default is all of them.

.PARAMETER Images
    The test images to use. The default is all seven.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify\run_targets.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify\run_targets.ps1 -Targets wasm
#>
param(
    [string[]]$Targets = @('native', 'js', 'wasm', 'wasm-gc'),
    [string[]]$Algorithms = @(
        'otsu', 'multiotsu', 'autothreshold', 'mixture', 'blob', 'watershed',
        'densitometry', 'retfm', 'rats', 'siox', 'multithresholder'
    ),
    [string[]]$Images = @(
        'ramp_blobs', 'two_blobs', 'gradient', 'checker', 'uniform', 'sparse', 'ring'
    )
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# the dimensions of the test images
$dimensions = @{
    'ramp_blobs' = @(32, 24)
    'two_blobs'  = @(24, 20)
    'gradient'   = @(28, 22)
    'checker'    = @(16, 16)
    'uniform'    = @(12, 10)
    'sparse'     = @(24, 12)
    'ring'       = @(22, 18)
}

$moonrun = Join-Path $env:USERPROFILE '.moon\bin\moonrun.exe'
# The wasm runner is only needed for the wasm backends: the native and the js
# backend do not use it, so a missing runner must not hide their results.
if (($Targets -contains 'wasm') -or ($Targets -contains 'wasm-gc')) {
    if (-not (Test-Path -LiteralPath $moonrun)) {
        throw "the wasm runner was not found at $moonrun (it ships with the MoonBit toolchain)"
    }
}
$policy = Join-Path $root 'verify\wasm_policy.json'

# ---------------------------------------------------------------------------
# 1. the library test suite on every backend
# ---------------------------------------------------------------------------
Write-Host '== 1. the library tests on every backend =='
Push-Location $root
& moon test --target all
Pop-Location
if ($LASTEXITCODE -ne 0) { throw 'the library tests failed' }

# ---------------------------------------------------------------------------
# 2. every algorithm on its own, on every backend
# ---------------------------------------------------------------------------
$results = @{}

# The output tree is emptied first: a file that is left over from an earlier
# run would hide the fact that the current run does not write it.
$targetsOut = Join-Path $root 'verify\out\targets'
if (Test-Path -LiteralPath $targetsOut) {
  Remove-Item -Recurse -Force -LiteralPath $targetsOut
}

foreach ($target in $Targets) {
    Write-Host ''
    Write-Host "== backend: $target =="
    Push-Location $root
    & moon build --target $target
    Pop-Location
    if ($LASTEXITCODE -ne 0) { throw "moon build failed for $target" }

    switch ($target) {
        'native' {
            $runner = Join-Path $root '_build\native\debug\build\cmd\seg\seg.exe'
            $prefix = @()
        }
        'js' {
            $runner = 'node'
            $prefix = @((Join-Path $root '_build\js\debug\build\cmd\seg\seg.js'))
        }
        'wasm' {
            $runner = $moonrun
            $prefix = @('--policy', $policy, (Join-Path $root '_build\wasm\debug\build\cmd\seg\seg.wasm'))
        }
        'wasm-gc' {
            $runner = $moonrun
            $prefix = @('--policy', $policy, (Join-Path $root '_build\wasm-gc\debug\build\cmd\seg\seg.wasm'))
        }
        default { throw "unknown target: $target" }
    }

    # --- every algorithm on its own ---
    foreach ($algorithm in $Algorithms) {
        $failures = @()
        foreach ($name in $Images) {
            $w = $dimensions[$name][0]
            $h = $dimensions[$name][1]
            $gray = Join-Path $root "verify\images\$name.gray"
            $golden = Join-Path $root "ref\harness\golden\$name"
            $outDir = Join-Path $root "verify\out\targets\$target\$algorithm\$name"
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null

            & $runner @prefix $algorithm --input $gray --width $w --height $h --outdir $outDir | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $failures += "$name (the command failed)"
                continue
            }
            & python (Join-Path $root 'verify\compare.py') --algo $algorithm $golden $outDir | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $failures += "$name (the output differs)"
            }
        }
        if ($failures.Count -eq 0) {
            Write-Host ("  PASS {0,-18} {1} image(s)" -f $algorithm, $Images.Count)
            $results["$target/$algorithm"] = 'PASS'
        } else {
            Write-Host ("  FAIL {0,-18} {1}" -f $algorithm, ($failures -join ', '))
            $results["$target/$algorithm"] = 'FAIL'
        }
    }

    # --- the integrated run: all the algorithms at once ---
    $runFailures = @()
    foreach ($name in $Images) {
        $w = $dimensions[$name][0]
        $h = $dimensions[$name][1]
        $gray = Join-Path $root "verify\images\$name.gray"
        $golden = Join-Path $root "ref\harness\golden\$name"
        $outDir = Join-Path $root "verify\out\targets\$target\run\$name"
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null

        & $runner @prefix run --input $gray --width $w --height $h --outdir $outDir | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $runFailures += "$name (the command failed)"
            continue
        }
        & python (Join-Path $root 'verify\compare.py') $golden $outDir | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $runFailures += "$name (the output differs)"
        }
    }
    if ($runFailures.Count -eq 0) {
        Write-Host ("  PASS {0,-18} {1} image(s)" -f 'run (all)', $Images.Count)
        $results["$target/run"] = 'PASS'
    } else {
        Write-Host ("  FAIL {0,-18} {1}" -f 'run (all)', ($runFailures -join ', '))
        $results["$target/run"] = 'FAIL'
    }
}

# ---------------------------------------------------------------------------
# 3. the matrix
# ---------------------------------------------------------------------------
$columns = $Algorithms + @('run (all)')
Write-Host ''
Write-Host '== the matrix: backend x algorithm =='
$header = 'backend'.PadRight(10)
foreach ($column in $columns) { $header = $header + ' ' + $column.PadRight(16) }
Write-Host $header
$failed = 0
foreach ($target in $Targets) {
    $line = $target.PadRight(10)
    foreach ($column in $columns) {
        $key = if ($column -eq 'run (all)') { "$target/run" } else { "$target/$column" }
        $state = $results[$key]
        if ($state -eq 'PASS') { $state = 'ok' } else { $state = 'FAIL'; $failed = $failed + 1 }
        $line = $line + ' ' + $state.PadRight(16)
    }
    Write-Host $line
}

if ($failed -gt 0) {
    Write-Host ''
    Write-Host ("FAIL: {0} backend/algorithm combination(s) differ" -f $failed)
    exit 1
}
Write-Host ''
Write-Host ('ALL-PASS: every algorithm works on its own on {0} backend(s)' -f $Targets.Count)
exit 0
