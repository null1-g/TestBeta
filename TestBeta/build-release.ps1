$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $projectRoot "dist"
$versionPath = Join-Path $projectRoot "version.txt"

if (-not (Test-Path $versionPath)) {
    Set-Content -Path $versionPath -Value "1.0.0"
}

$version = (Get-Content $versionPath -Raw).Trim()
$safeVersion = $version -replace '[^0-9A-Za-z\.\-]', '-'
$appName = "TestBetaApp-$safeVersion.exe"
$setupName = "TestBetaSetup-$safeVersion.exe"
$appPath = Join-Path $distDir $appName
$setupPath = Join-Path $distDir $setupName

if (-not (Test-Path $appPath)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "build-exe.ps1")
}

if (-not (Test-Path $setupPath)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "build-installer.ps1")
}

$releaseRoot = Join-Path $distDir "release"
$releaseFolderName = "TestBeta-Windows-$safeVersion"
$releaseDir = Join-Path $releaseRoot $releaseFolderName
$zipPath = Join-Path $distDir "$releaseFolderName.zip"
$releaseChecksumsPath = Join-Path $releaseDir "SHA256SUMS.txt"
$zipChecksumsPath = Join-Path $distDir "$releaseFolderName-SHA256.txt"
$appChecksumsPath = Join-Path $distDir ("{0}-SHA256.txt" -f [System.IO.Path]::GetFileNameWithoutExtension($appName))
$setupChecksumsPath = Join-Path $distDir ("{0}-SHA256.txt" -f [System.IO.Path]::GetFileNameWithoutExtension($setupName))

if (Test-Path $releaseDir) {
    Remove-Item $releaseDir -Recurse -Force
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

if (Test-Path $zipChecksumsPath) {
    Remove-Item $zipChecksumsPath -Force
}

if (Test-Path $appChecksumsPath) {
    Remove-Item $appChecksumsPath -Force
}

if (Test-Path $setupChecksumsPath) {
    Remove-Item $setupChecksumsPath -Force
}

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
Copy-Item $appPath $releaseDir -Force
Copy-Item $setupPath $releaseDir -Force

Set-Content -Path (Join-Path $releaseDir "README.txt") -Value @"
Test Beta Windows Release
Version: $version

Files:
- ${setupName}: installer build that creates shortcuts and includes an uninstall path.
- ${appName}: portable standalone desktop app build.

Desktop app hotkeys:
- F1 About dialog
- F11 window fullscreen
- Esc exits window fullscreen

In-game controls:
- WASD move
- Mouse look
- Q / E backup turn
- Space or left click fire
- F request fullscreen
- [ and ] tune mouse sensitivity
- R restart
"@

$releaseHashes = Get-ChildItem $releaseDir -File |
    Sort-Object Name |
    ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        "{0} *{1}" -f $hash.Hash.ToLowerInvariant(), $_.Name
    }

Set-Content -Path $releaseChecksumsPath -Value @(
    "SHA-256 checksums for $releaseFolderName"
    ""
    $releaseHashes
)

Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -Force

$appHash = (Get-FileHash $appPath -Algorithm SHA256).Hash.ToLowerInvariant()
$setupHash = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

Set-Content -Path $appChecksumsPath -Value @(
    "SHA-256 checksum for $appName"
    ""
    "{0} *{1}" -f $appHash, $appName
)

Set-Content -Path $setupChecksumsPath -Value @(
    "SHA-256 checksum for $setupName"
    ""
    "{0} *{1}" -f $setupHash, $setupName
)

Set-Content -Path $zipChecksumsPath -Value @(
    "SHA-256 checksums for $releaseFolderName"
    ""
    "{0} *{1}" -f $zipHash, (Split-Path $zipPath -Leaf)
    ""
    "Included release folder files:"
    $releaseHashes
)

Write-Host "Built $releaseDir"
Write-Host "Built $zipPath"
Write-Host "Built $releaseChecksumsPath"
Write-Host "Built $zipChecksumsPath"
Write-Host "Built $appChecksumsPath"
Write-Host "Built $setupChecksumsPath"
