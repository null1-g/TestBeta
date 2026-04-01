$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $projectRoot "dist"
$versionPath = Join-Path $projectRoot "version.txt"

if (-not (Test-Path $versionPath)) {
    Set-Content -Path $versionPath -Value "1.0.0"
}

$version = (Get-Content $versionPath -Raw).Trim()
$safeVersion = $version -replace '[^0-9A-Za-z\.\-]', '-'
$setupPath = Join-Path $distDir "TestBetaSetup-$safeVersion.exe"
$smokeRoot = Join-Path $distDir "smoke-test"
$installPath = Join-Path $smokeRoot ("install-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$registrySubKey = "Software\Microsoft\Windows\CurrentVersion\Uninstall\TestBetaApp"
$registryPath = "HKCU:\$registrySubKey"
$shortcutDesktopRoot = Join-Path $smokeRoot "shortcut-targets\Desktop"
$shortcutProgramsRoot = Join-Path $smokeRoot "shortcut-targets\Programs"
$desktopShortcut = Join-Path $shortcutDesktopRoot "Test Beta App.lnk"
$startMenuDir = Join-Path $shortcutProgramsRoot "Test Beta App"
$startMenuShortcut = Join-Path $startMenuDir "Test Beta App.lnk"
$startMenuUninstallShortcut = Join-Path $startMenuDir "Uninstall Test Beta App.lnk"
$backupDir = Join-Path $smokeRoot ("shortcut-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$registryBackup = $null

function Backup-ExistingShortcut([string]$path, [string]$tag) {
    if (Test-Path $path) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backupName = $tag + "--" + [IO.Path]::GetFileName($path)
        Move-Item -Path $path -Destination (Join-Path $backupDir $backupName) -Force
    }
}

function Restore-BackedUpShortcuts() {
    if (-not (Test-Path $backupDir)) {
        return
    }

    Get-ChildItem $backupDir -File | ForEach-Object {
        $target =
            if ($_.Name -eq "desktop--Test Beta App.lnk") { $desktopShortcut }
            elseif ($_.Name -eq "startmenu-app--Test Beta App.lnk") { $startMenuShortcut }
            elseif ($_.Name -eq "startmenu-uninstall--Uninstall Test Beta App.lnk") { $startMenuUninstallShortcut }
            else { $null }

        if ($target) {
            $targetDir = Split-Path -Parent $target
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Move-Item -Path $_.FullName -Destination $target -Force
        }
    }

    if (Test-Path $backupDir) {
        Remove-Item $backupDir -Recurse -Force
    }
}

function Backup-ExistingRegistryKey() {
    if (-not (Test-Path $registryPath)) {
        return
    }

    $key = Get-Item $registryPath
    $entries = @()
    foreach ($name in $key.GetValueNames()) {
        $entries += [PSCustomObject]@{
            Name = $name
            Value = $key.GetValue($name)
            Kind = $key.GetValueKind($name)
        }
    }

    $script:registryBackup = $entries
    Remove-Item $registryPath -Recurse -Force
}

function Restore-BackedUpRegistryKey() {
    if (Test-Path $registryPath) {
        Remove-Item $registryPath -Recurse -Force
    }

    if (-not $script:registryBackup) {
        return
    }

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($registrySubKey)
    foreach ($entry in $script:registryBackup) {
        $key.SetValue($entry.Name, $entry.Value, $entry.Kind)
    }
    $key.Close()
}

if (-not (Test-Path $setupPath)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "build-installer.ps1")
}

New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
New-Item -ItemType Directory -Path $shortcutDesktopRoot -Force | Out-Null
New-Item -ItemType Directory -Path $shortcutProgramsRoot -Force | Out-Null

Backup-ExistingShortcut $desktopShortcut "desktop"
Backup-ExistingShortcut $startMenuShortcut "startmenu-app"
Backup-ExistingShortcut $startMenuUninstallShortcut "startmenu-uninstall"
Backup-ExistingRegistryKey

try {
    & $setupPath /silent /target="$installPath" /shortcutdesktop="$shortcutDesktopRoot" /shortcutprograms="$shortcutProgramsRoot"

    $appExe = Join-Path $installPath "TestBetaApp-$safeVersion.exe"
    $uninstallerExe = Join-Path $installPath "Uninstall Test Beta App.exe"

    $installOk = $false
    $shortcutInstallOk = $false
    $registryStatus = "not checked"
    $registryValues = $null
    $installDeadline = (Get-Date).AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 500
        $installOk = (Test-Path $appExe) -and (Test-Path $uninstallerExe)
        $shortcutInstallOk = (Test-Path $desktopShortcut) -and (Test-Path $startMenuShortcut) -and (Test-Path $startMenuUninstallShortcut)

        $registryStatus = "not checked"
        $registryValues = $null
        try {
            if (Test-Path $registryPath) {
                $registryValues = Get-ItemProperty $registryPath
                $registryStatus = "present"
            } else {
                $registryStatus = "missing"
            }
        }
        catch {
            $registryStatus = "blocked: " + $_.Exception.Message
        }
    } until (($installOk -and $shortcutInstallOk -and $registryStatus -eq "present") -or (Get-Date) -ge $installDeadline)

    if (-not $installOk) {
        throw "Installer smoke test failed during install. App or uninstaller was not written to $installPath"
    }

    if (-not $shortcutInstallOk) {
        throw "Installer smoke test failed during install. One or more shortcuts were not created."
    }

    if ($registryStatus -eq "present") {
        if ([string]::IsNullOrWhiteSpace($registryValues.BuildDateUtc)) {
            throw "Installer smoke test failed during install. Registry BuildDateUtc was not written."
        }

        if ([string]::IsNullOrWhiteSpace($registryValues.GitCommit)) {
            throw "Installer smoke test failed during install. Registry GitCommit was not written."
        }
    }

    & $uninstallerExe /uninstall /silent /target="$installPath" /shortcutdesktop="$shortcutDesktopRoot" /shortcutprograms="$shortcutProgramsRoot"

    $deadline = (Get-Date).AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 500
        $appStillPresent = Test-Path $appExe
        $uninstallerStillPresent = Test-Path $uninstallerExe
        $folderStillPresent = Test-Path $installPath
        $desktopShortcutStillPresent = Test-Path $desktopShortcut
        $startMenuShortcutStillPresent = Test-Path $startMenuShortcut
        $startMenuUninstallShortcutStillPresent = Test-Path $startMenuUninstallShortcut
    } until ((-not $appStillPresent -and -not $uninstallerStillPresent -and -not $desktopShortcutStillPresent -and -not $startMenuShortcutStillPresent -and -not $startMenuUninstallShortcutStillPresent) -or (Get-Date) -ge $deadline)

    $uninstallOk = (-not (Test-Path $appExe)) -and (-not (Test-Path $uninstallerExe))
    $shortcutUninstallOk = (-not (Test-Path $desktopShortcut)) -and (-not (Test-Path $startMenuShortcut)) -and (-not (Test-Path $startMenuUninstallShortcut))

    $result = [PSCustomObject]@{
        Version = $version
        SetupPath = $setupPath
        InstallPath = $installPath
        InstallPassed = $installOk
        ShortcutsCreated = $shortcutInstallOk
        RegistryStatus = $registryStatus
        DisplayName = $(if ($registryValues) { $registryValues.DisplayName } else { $null })
        DisplayVersion = $(if ($registryValues) { $registryValues.DisplayVersion } else { $null })
        RegistryComments = $(if ($registryValues) { $registryValues.Comments } else { $null })
        BuildDateUtc = $(if ($registryValues) { $registryValues.BuildDateUtc } else { $null })
        GitCommit = $(if ($registryValues) { $registryValues.GitCommit } else { $null })
        UninstallPassed = $uninstallOk
        ShortcutsRemoved = $shortcutUninstallOk
        InstallFolderRemaining = (Test-Path $installPath)
    }

    $result | Format-List

    if (-not $uninstallOk) {
        throw "Installer smoke test failed during uninstall. Files still remain under $installPath"
    }

    if (-not $shortcutUninstallOk) {
        throw "Installer smoke test failed during uninstall. One or more shortcuts were not removed."
    }
}
finally {
    Restore-BackedUpShortcuts
    Restore-BackedUpRegistryKey
}
