<#
.SYNOPSIS
    Builds the Java reference harness: the ORIGINAL (unmodified) segmentation
    algorithms + the minimal ImageJ stubs + the harness driver.

.DESCRIPTION
    Everything is compiled with javac into ref\harness\out. The original
    algorithm sources are only READ, never modified: no .class file is ever
    written next to them because -d points at the output directory.

    The original sources live in two places:
      * ref\java\<plugin>\*.java        (Otsu, Mixture, MultiThresholder,
                                         Watershed, RATS, SIOX)
      * <SegmentationDir>\*.java         (Blob_Labeler, Multi_OtsuThreshold,
                                         Densitometry_*, RetFM_J)

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build.ps1
    powershell -ExecutionPolicy Bypass -File .\build.ps1 -SegmentationDir 'D:\src\java\algo\Segmentation'
#>
param(
    [string]$SegmentationDir = 'D:\src\java\algo\Segmentation',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path          # ...\ref\harness
$refJava = Join-Path (Split-Path -Parent $root) 'java'            # ...\ref\java
if ([string]::IsNullOrEmpty($OutputDir)) {
    $OutputDir = Join-Path $root 'out'
}

if (-not (Get-Command javac -ErrorAction SilentlyContinue)) {
    throw 'javac was not found on PATH (a JDK 11 installation is required).'
}

# --- the original algorithm sources (read only) ----------------------------
$algorithmFiles = @(
    (Join-Path $refJava 'Otsu_Thresholding\OtsuThresholding_.java'),
    (Join-Path $refJava 'Otsu_Thresholding\GrayLevelClass.java'),
    (Join-Path $refJava 'Mixture_Modeling\MixtureModeling_.java'),
    (Join-Path $refJava 'Mixture_Modeling\GrayLevelClassMixtureModeling.java'),
    (Join-Path $refJava 'Multi_Thresholder\AutoThresholder.java'),
    (Join-Path $refJava 'Watershed_Algorithm\Watershed_Algorithm.java'),
    (Join-Path $refJava 'Watershed_Algorithm\WatershedStructure.java'),
    (Join-Path $refJava 'Watershed_Algorithm\WatershedPixel.java'),
    (Join-Path $refJava 'Watershed_Algorithm\WatershedFIFO.java'),
    (Join-Path $refJava 'RATS_\RATS_.java'),
    (Join-Path $refJava 'RATS_\RATSQuadtree.java'),
    (Join-Path $refJava 'siox_\siox\SioxSegmentator.java'),
    (Join-Path $refJava 'siox_\siox\Utils.java'),
    (Join-Path $refJava 'siox_\siox\ColorSignature.java'),
    (Join-Path $refJava 'siox_\siox\IntArrayList.java'),
    (Join-Path $refJava 'siox_\siox\IntHashMap.java'),
    (Join-Path $refJava 'siox_\siox\ControlJPanel.java'),
    (Join-Path $SegmentationDir 'Blob_Labeler.java'),
    (Join-Path $SegmentationDir 'Multi_OtsuThreshold.java'),
    (Join-Path $SegmentationDir 'Densitometry_1_Channel_.java'),
    (Join-Path $SegmentationDir 'Densitometry_3_Channel_.java'),
    (Join-Path $SegmentationDir 'RetFM_J.java')
)

foreach ($file in $algorithmFiles) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "missing original source: $file"
    }
}

# --- the harness -----------------------------------------------------------
$stubFiles = @(Get-ChildItem -Path (Join-Path $root 'stub') -Recurse -Filter '*.java' |
    ForEach-Object { $_.FullName })
$harnessFile = Join-Path $root 'Harness.java'

$sources = @($stubFiles) + @($algorithmFiles) + @($harnessFile)

# --- compile ---------------------------------------------------------------
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -Recurse -Force -LiteralPath $OutputDir
}
New-Item -ItemType Directory -Path $OutputDir | Out-Null

$sourcePath = (Join-Path $root 'stub') + ';' + $root

& javac -encoding UTF-8 -nowarn -implicit:none -d $OutputDir -sourcepath $sourcePath @sources
if ($LASTEXITCODE -ne 0) {
    throw "javac failed with exit code $LASTEXITCODE"
}

Write-Host "build.ps1: compiled $($sources.Count) source files into $OutputDir"

# --- the original Multi_Thresholder class ----------------------------------
#
# The Multi_Thresholder plugin is a GUI frame: its source cannot be
# compiled against the minimal stubs without a full AWT/ImageJ GUI. The
# harness only needs its four level mapping helper methods, and it drives
# them on an instance that is allocated without running the constructor.
#
# Therefore the *original compiled class* of the plugin is taken from the
# jar (it is the artifact that was shipped, so it is the strongest
# possible oracle) instead of recompiling the source.
$multiThresholderJar = Join-Path $SegmentationDir 'Multi_Thresholder.jar'
if (Test-Path -LiteralPath $multiThresholderJar) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($multiThresholderJar)
    try {
        foreach ($entryName in @('Multi_Thresholder.class', 'MultiThresholderPlot.class')) {
            $entry = $archive.GetEntry($entryName)
            if ($null -eq $entry) {
                throw "missing $entryName in $multiThresholderJar"
            }
            $target = Join-Path $OutputDir $entryName
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally {
        $archive.Dispose()
    }
    Write-Host "build.ps1: took the original Multi_Thresholder classes from the jar"
} else {
    throw "missing original plugin jar: $multiThresholderJar"
}

Write-Host "build.ps1: run with  java -cp out Harness <input.gray> <width> <height> <outdir>"
