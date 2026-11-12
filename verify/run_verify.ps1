# Build the Java reference harness, run both sides and compare every image.
#
#   powershell -ExecutionPolicy Bypass -File verify\run_verify.ps1
#
# Steps:
#   1. compile the original (unmodified) Java algorithms against the ImageJ
#      stubs in ref\harness
#   2. regenerate the deterministic test images
#   3. run the Java harness on every image   -> verify\out\java\<name>
#   4. check that the committed golden (ref\harness\golden\<name>) is in sync
#      with the fresh Java run - a stale oracle must not be able to make the
#      verification pass or fail
#   5. run the MoonBit CLI on every image     -> verify\out\moonbit\<name>
#   6. diff both output sets byte by byte
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

Write-Host '== 1. build the Java reference harness =='
& powershell -ExecutionPolicy Bypass -File (Join-Path $root 'ref\harness\build.ps1')
if ($LASTEXITCODE -ne 0) { throw 'java harness build failed' }

Write-Host '== 2. regenerate the test images =='
& python (Join-Path $root 'verify\make_test_images.py') (Join-Path $root 'verify\images')
if ($LASTEXITCODE -ne 0) { throw 'test image generation failed' }

Write-Host '== 3. build the MoonBit CLI =='
Push-Location $root
& moon build --target native
Pop-Location
if ($LASTEXITCODE -ne 0) { throw 'moon build failed' }
$exe = Join-Path $root '_build\native\debug\build\cmd\seg\seg.exe'

$javaDir = Join-Path $root 'verify\out\java'
$mbtDir = Join-Path $root 'verify\out\moonbit'
# The output directories are emptied first: a file that is left over from an
# earlier run would hide the fact that the current run does not write it.
if (Test-Path -LiteralPath $javaDir) {
  Remove-Item -Recurse -Force -LiteralPath $javaDir
}
if (Test-Path -LiteralPath $mbtDir) {
  Remove-Item -Recurse -Force -LiteralPath $mbtDir
}
New-Item -ItemType Directory -Force -Path $javaDir, $mbtDir | Out-Null

$failed = @()
$staleGolden = @()
foreach ($name in ($images.Keys | Sort-Object)) {
  $w = $images[$name][0]
  $h = $images[$name][1]
  $gray = Join-Path $root "verify\images\$name.gray"
  $jOut = Join-Path $javaDir $name
  $mOut = Join-Path $mbtDir $name
  New-Item -ItemType Directory -Force -Path $jOut, $mOut | Out-Null

  Push-Location (Join-Path $root 'ref\harness')
  & java -cp out Harness $gray $w $h $jOut | Out-Null
  Pop-Location
  if ($LASTEXITCODE -ne 0) { throw "java harness failed on $name" }

  # The committed golden is the oracle of the 4 backend matrix. It has to be
  # the output of the Java harness, not a stale (or hand edited) copy.
  $golden = Join-Path $root "ref\harness\golden\$name"
  if (-not (Test-Path -LiteralPath $golden)) {
    $staleGolden += "$name (there is no golden directory)"
  } else {
    & python (Join-Path $root 'verify\compare.py') $golden $jOut | Out-Null
    if ($LASTEXITCODE -ne 0) {
      $staleGolden += "$name (the golden differs from the fresh Java run)"
    }
  }

  & $exe run --input $gray --width $w --height $h --outdir $mOut | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "moonbit CLI failed on $name" }

  & python (Join-Path $root 'verify\compare.py') $jOut $mOut
  if ($LASTEXITCODE -ne 0) {
    $failed += $name
    Write-Host "  FAIL $name"
  } else {
    Write-Host "  PASS $name"
  }
}

if ($staleGolden.Count -gt 0) {
  Write-Host ''
  Write-Host ('STALE GOLDEN: {0} image(s) differ from the fresh Java run:' -f $staleGolden.Count)
  $staleGolden | ForEach-Object { Write-Host "  - $_" }
  Write-Host 'run verify\refresh_golden.ps1 to update ref\harness\golden'
  exit 1
}

if ($failed.Count -gt 0) {
  Write-Host ("FAIL: {0} image(s) differ: {1}" -f $failed.Count, ($failed -join ', '))
  exit 1
}
Write-Host ''
Write-Host 'ALL-PASS: the MoonBit port matches the Java reference byte for byte'
Write-Host '  (the reference is the Java harness with the ImageJ stubs of ref\harness;'
Write-Host '   for RATS and for the 16 bit Multi_Thresholder cases it is the harness'
Write-Host '   convention, not the behaviour of a stock ImageJ - see ref\harness\README.md)'
exit 0
