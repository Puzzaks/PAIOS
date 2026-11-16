# build_releases.ps1
param(
    [switch]$ApkOnly,
    [switch]$AabOnly,
    [string]$OutputDir = "build"
)

if ($ApkOnly -and $AabOnly) {
    Write-Error "Error: -ApkOnly and -AabOnly cannot be used together."
    exit 1
}

Write-Host "--- Starting PAIOS Build Process ---"

$PubspecPath = "pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
    Write-Error "Error: Could not find $PubspecPath in current directory ($(Get-Location))."
    exit 1
}

# 1. Parse version from pubspec.yaml
$VersionName = ""
$VersionCode = ""

$Content = Get-Content $PubspecPath -Encoding UTF8
foreach ($Line in $Content) {
    if ($Line -match "version:\s*([0-9\.]+)\+([0-9]+)") {
        $VersionName = $Matches[1]
        $VersionCode = $Matches[2]
        break
    }
}

if ($VersionName -eq "" -or $VersionCode -eq "") {
    Write-Error "Error: Could not find 'version: X.Y.Z+BUILD' in $PubspecPath"
    exit 1
}

Write-Host "Version: $VersionName"
Write-Host "Build: $VersionCode"

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = "build"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$TotalSteps = if ($ApkOnly -or $AabOnly) { 1 } else { 2 }
$StepIndex = 0

# 2. Build APK for GitHub
if (-not $AabOnly) {
    $StepIndex++
    Write-Host "Step $StepIndex/$TotalSteps`: Building APK (GitHub)..."
    $ApkSuffix = "GitHub"
    $FullApkName = "PAIOS_v" + $VersionName + "_" + $ApkSuffix + ".apk"
    $BuildNameGit = $VersionName + "-" + $ApkSuffix

    # Using spaces instead of = to ensure Flutter CLI parses correctly
    flutter build apk --release --build-name $BuildNameGit --build-number $VersionCode
    if ($LASTEXITCODE -ne 0) {
        Write-Error "APK Build Failed (exit code $LASTEXITCODE)"
        exit 1
    }

    $SourceApk = "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $SourceApk)) {
        Write-Error "APK Build succeeded but output not found at $SourceApk"
        exit 1
    }
    $TargetApk = Join-Path $OutputDir $FullApkName
    Copy-Item $SourceApk $TargetApk -Force
    Write-Host "Saved APK to: $TargetApk"
}

# 3. Build AAB for Play Store
if (-not $ApkOnly) {
    $StepIndex++
    Write-Host "Step $StepIndex/$TotalSteps`: Building AAB (Play Store)..."
    $AabSuffix = "PlayStore"
    $FullAabName = "PAIOS_v" + $VersionName + "_" + $AabSuffix + ".aab"
    $BuildNamePlay = $VersionName + "-" + $AabSuffix

    flutter build appbundle --release --build-name $BuildNamePlay --build-number $VersionCode
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AAB Build Failed (exit code $LASTEXITCODE)"
        exit 1
    }

    $SourceAab = "build\app\outputs\bundle\release\app-release.aab"
    if (-not (Test-Path $SourceAab)) {
        Write-Error "AAB Build succeeded but output not found at $SourceAab"
        exit 1
    }
    $TargetAab = Join-Path $OutputDir $FullAabName
    Copy-Item $SourceAab $TargetAab -Force
    Write-Host "Saved AAB to: $TargetAab"
}

Write-Host "Done."
exit 0
