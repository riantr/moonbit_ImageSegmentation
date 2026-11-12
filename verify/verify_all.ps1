<#
.SYNOPSIS
    Runs the whole verification of the MoonBit port.

.DESCRIPTION
    One entry point for everything that has to be green before the port may
    be called a faithful port of the Java original:

      1. `moon check --deny-warn`  - the source has to be free of warnings
      2. `moon test --target all`  - the library tests on all four backends
      3. `verify\run_verify.ps1`   - the byte exact comparison of the seven
         happy path images (the Java harness is rebuilt and the committed
         golden is checked against the fresh Java run)
      4. `ref\harness\tools\LiCrossCheck.java` - the `Li` method of the
         original `AutoThresholder` against the port, on a thousand hostile
         histograms (both sides are pinned to the same checksum)
      5. `ref\harness\tools\PowCrossCheck.java` - the `pow` of the port against
         the `Math.pow` of the reference, on the arguments the algorithms use
      6. `ref\harness\tools\AutoThresholderCrossCheck.java` - **all fifteen**
         threshold methods of the original `AutoThresholder` against the port,
         on hostile histograms (both sides are pinned to the same checksums)
      7. `ref\harness\tools\BlobCrossCheck.java` - the six configurations of the
         original `Blob_Labeler` against the port, on random images (both sides
         are pinned to the same checksums)
      8. `ref\harness\tools\ThresholdCrossCheck.java` - the original
         `OtsuThresholding_` and `Multi_OtsuThreshold` against the port, on
         random images (both sides are pinned to the same checksums)
      9. `ref\harness\tools\MixtureCrossCheck.java` - the original
         `MixtureModeling_` against the port, on random images (both sides are
         pinned to the same checksum)
      10. `ref\harness\tools\SioxCrossCheck.java` - the original
         `SioxSegmentator` against the port, on random images (both sides are
         pinned to the same checksum)
      11. `verify\run_edge_verify.py` - the same comparison for the eighteen
         adversarial images, on all four backends, with every algorithm
         additionally run on its own
      12. `verify\run_targets.ps1` - the matrix of backend x algorithm on the
         seven happy path images
      13. `verify\run_png_verify.py` - the PNG commands against an independent
         decoder (Pillow), on all four backends
      14. `verify\run_bench.py` - the runtime against the Java reference on
         the same machine (a ratio, not an absolute time)

    Every step has to succeed; the script stops at the first failure.

    Steps 13 and 14 need Python with Pillow and a JDK; they are skipped with a
    warning when something is missing, so that the byte exact gates still run
    on a machine without them.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify\verify_all.ps1
#>
param(
    [string[]]$Targets = @('native', 'js', 'wasm', 'wasm-gc'),
    # The PNG and the performance gate need Python with Pillow and a JDK. They
    # are skipped with a warning when something is missing, so that the byte
    # exact gates still run on a machine without them.
    [switch]$SkipOptional
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Step([string]$title, [scriptblock]$body) {
  Write-Host ''
  Write-Host ('=' * 72)
  Write-Host "== $title"
  Write-Host ('=' * 72)
  & $body
  if ($LASTEXITCODE -ne 0) { throw "$title failed (exit code $LASTEXITCODE)" }
}

Step '1. the source has to be free of warnings' {
  Push-Location $root
  & moon check --deny-warn
  Pop-Location
}

Step '2. the library tests on every backend' {
  Push-Location $root
  & moon test --target all
  Pop-Location
}

Step '3. the byte exact comparison (the happy path images)' {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $root 'verify\run_verify.ps1')
}

Step '4. the Li method of the original AutoThresholder against the port' {
  # The Java tool drives the original `AutoThresholder.Li` with a thousand
  # hostile histograms and checks the checksum against the constant that the
  # MoonBit test `the Li threshold matches the original AutoThresholder on
  # hostile histograms` uses as well. Both sides are pinned to the same
  # number, so a divergence shows up on the side that caused it.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\AutoThresholder.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\LiCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'LiCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' LiCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '5. the pow of the port against the Math.pow of the reference' {
  # The Java tool pins the behaviour of the JDK's `Math.pow` on the
  # arguments the algorithms use, and the MoonBit test `the pow of the port
  # matches the Java Math.pow on the arguments of the algorithms` pins the
  # behaviour of `@math.pow` on every backend. The exponent 2.0 (the mixture
  # model and the Otsu plugin) has the **same** checksum on both sides.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\AutoThresholder.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\PowCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'PowCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' PowCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '6. all fifteen threshold methods of the original AutoThresholder against the port' {
  # The QA report listed as a residual risk that the `Li` cross check covers
  # one method of the fifteen. This gate closes that gap: every method of the
  # original is driven with the same hostile histograms, and the checksum of
  # every method is pinned to the same constant in this tool and in the MoonBit
  # test `the fifteen threshold methods match the original AutoThresholder on
  # hostile histograms`. A divergence shows up on the side that caused it.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\AutoThresholder.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\AutoThresholderCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'AutoThresholderCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' AutoThresholderCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '7. the six configurations of the original Blob_Labeler against the port' {
  # The labeling of the blobs is the most intricate algorithm of the port and
  # the image corpus of twenty five images never contains many separate blobs,
  # blobs that touch or blobs with a hole. This gate drives the original and
  # the port with the same random images - among them the one row and the one
  # column high ones, on which the original raises an exception - and pins the
  # same checksums on both sides.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\Blob_Labeler.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\BlobCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'BlobCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' BlobCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '8. the threshold plugins of the original against the port' {
  # The image corpus is a set of pictures, and a picture does not contain a
  # histogram on purpose - a histogram is exactly what the `OtsuThresholding_`
  # and the `Multi_OtsuThreshold` plugins consume. This gate drives the
  # originals and the port with the same random images - among them the
  # degenerate histograms (one bin, two levels, completely black) - and pins
  # the same checksums on both sides.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\OtsuThresholding_.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\ThresholdCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'ThresholdCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' ThresholdCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '9. the mixture model of the original against the port' {
  # The mixture model fits two Gaussian components to the histogram and reports
  # the mean, the variance, the fitting error and two thresholds. Its output is
  # floating point, and the corpus compares it bit for bit - but only on the
  # images of the corpus. This gate drives the original and the port with the
  # same random images, among them the degenerate histograms (one bin, two
  # levels, completely black), and pins the same checksum on both sides.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\MixtureModeling_.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\MixtureCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'MixtureCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' MixtureCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '10. the siox segmentation of the original against the port' {
  # The `SioxSegmentator` clusters the colours of an RGB image into a background
  # and a foreground. The corpus of the byte exact comparison does not contain
  # a colourful picture at all - all seven images are greyscale - so the port
  # had never been compared against the original on the kind of input the plugin
  # is meant for. This gate drives both sides with the same random colour images
  # and pins the same checksum and the same number of failing rounds on both
  # sides: on eight of the sixty four images the original raises an exception,
  # and the port has to fail in the same way.
  $harness = Join-Path $root 'ref\harness'
  Push-Location $harness
  if (-not (Test-Path 'out\siox\SioxSegmentator.class')) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $harness 'build.ps1')
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'the Java harness could not be built' }
  }
  & javac -encoding UTF-8 -cp out -d tools\out tools\SioxCrossCheck.java
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'SioxCrossCheck.java could not be compiled' }
  & java -cp 'out;tools\out' SioxCrossCheck
  $code = $LASTEXITCODE
  Pop-Location
  $global:LASTEXITCODE = $code
}

Step '11. the byte exact comparison (the adversarial images, every backend)' {
  & python (Join-Path $root 'verify\run_edge_verify.py') --backend all --per-algorithm
}

Step '12. the matrix of backend x algorithm' {
  # The backends are passed as a real array. With `powershell -File` the
  # values that follow a named parameter would be bound to the *next*
  # positional parameter (`-Images`), so the array is passed with -Command.
  $targetsLiteral = ($Targets | ForEach-Object { "'" + $_ + "'" }) -join ','
  $script = Join-Path $root 'verify\run_targets.ps1'
  & powershell -ExecutionPolicy Bypass -Command "& '$script' -Targets @($targetsLiteral)"
}

Step '13. the PNG commands against an independent decoder (Pillow)' {
  if ($SkipOptional) {
    Write-Host '  skipped (-SkipOptional)'
    $global:LASTEXITCODE = 0
    return
  }
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Warning 'no python found - the PNG gate is skipped'
    $global:LASTEXITCODE = 0
    return
  }
  & python -c 'import PIL' 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Pillow is not installed - the PNG gate is skipped (pip install Pillow)'
    $global:LASTEXITCODE = 0
    return
  }
  & python (Join-Path $root 'verify\run_png_verify.py') --backend all
}

Step '14. the runtime against the Java reference (a ratio, not an absolute time)' {
  if ($SkipOptional) {
    Write-Host '  skipped (-SkipOptional)'
    $global:LASTEXITCODE = 0
    return
  }
  if (-not (Get-Command python -ErrorAction SilentlyContinue) -or
      -not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Warning 'no python or no JDK found - the performance gate is skipped'
    $global:LASTEXITCODE = 0
    return
  }
  & python (Join-Path $root 'verify\run_bench.py')
}

Write-Host ''
Write-Host ('=' * 72)
Write-Host 'ALL-PASS: every gate of the verification is green'
Write-Host ('=' * 72)
exit 0
