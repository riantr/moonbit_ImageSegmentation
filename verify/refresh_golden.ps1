<#
.SYNOPSIS
    Regenerates the committed Java reference outputs in ref\harness\golden.

.DESCRIPTION
    The golden files are the *oracle* of the whole verification: the 4 backend
    matrix (verify\run_targets.ps1) compares the MoonBit port against them.
    They are produced by the Java reference harness only - the MoonBit port
    never writes into this directory.

    Run this script whenever the harness, the ImageJ stubs or the test images
    change, and commit the result. verify\run_verify.ps1 checks that the
    golden is in sync with a fresh Java run, so a stale oracle cannot make
    the verification pass (or fail) silently.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify\refresh_golden.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$images = @{
  'ramp_blobs' = @(32, 24)
  'two_blobs'  = @(24, 20)
  'gradient'   = @(28, 22)
  'checker'    = @(16, 16)
  'uniform'    = @(12, 10)
  'sparse'     = @(24, 12)
  'ring'       = @(22, 18)
}

Write-Host '== build the Java reference harness =='
& powershell -ExecutionPolicy Bypass -File (Join-Path $root 'ref\harness\build.ps1')
if ($LASTEXITCODE -ne 0) { throw 'java harness build failed' }

Write-Host '== regenerate the test images =='
& python (Join-Path $root 'verify\make_test_images.py') (Join-Path $root 'verify\images')
if ($LASTEXITCODE -ne 0) { throw 'test image generation failed' }

$goldenRoot = Join-Path $root 'ref\harness\golden'
foreach ($name in ($images.Keys | Sort-Object)) {
  $w = $images[$name][0]
  $h = $images[$name][1]
  $gray = Join-Path $root "verify\images\$name.gray"
  $out = Join-Path $goldenRoot $name
  if (Test-Path -LiteralPath $out) {
    Remove-Item -Recurse -Force -LiteralPath $out
  }
  New-Item -ItemType Directory -Force -Path $out | Out-Null

  Push-Location (Join-Path $root 'ref\harness')
  & java -cp out Harness $gray $w $h $out | Out-Null
  Pop-Location
  if ($LASTEXITCODE -ne 0) { throw "java harness failed on $name" }

  $count = (Get-ChildItem -LiteralPath $out -File).Count
  Write-Host ("  {0,-12} {1} file(s)" -f $name, $count)
}

Write-Host ''
Write-Host ("refresh_golden.ps1: the golden in {0} is up to date" -f $goldenRoot)
exit 0
