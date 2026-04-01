$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $projectRoot "dist"
$iconPath = Join-Path $projectRoot "app.ico"
$versionPath = Join-Path $projectRoot "version.txt"
$readmePath = Join-Path $distDir "README-app.txt"

if (-not (Test-Path $iconPath)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "generate-icon.ps1")
}

if (-not (Test-Path $versionPath)) {
    Set-Content -Path $versionPath -Value "1.0.0"
}

$version = (Get-Content $versionPath -Raw).Trim()
$safeVersion = $version -replace '[^0-9A-Za-z\.\-]', '-'
$assemblyVersion = if ($version -match '^\d+\.\d+\.\d+$') { "$version.0" } elseif ($version -match '^\d+\.\d+\.\d+\.\d+$') { $version } else { "1.0.0.0" }
$versionedAppName = "TestBetaApp-$safeVersion.exe"
$versionedSetupName = "TestBetaSetup-$safeVersion.exe"
$appPath = Join-Path $distDir $versionedAppName
$outputPath = Join-Path $distDir $versionedSetupName
$stableSetupPath = Join-Path $distDir "TestBetaSetup.exe"
$companyName = "OpenAI Codex"
$productName = "Test Beta App Setup"
$fileDescription = "Installer and uninstaller bootstrapper for the Test Beta desktop app"
$copyrightText = "Copyright (c) 2026 OpenAI Codex"
$buildDateUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

function Resolve-GitSearchRoot([string]$defaultPath) {
    $configuredRoot = $env:TESTBETA_GIT_ROOT
    if ([string]::IsNullOrWhiteSpace($configuredRoot)) {
        return (Resolve-Path $defaultPath).Path
    }

    try {
        $expandedRoot = [Environment]::ExpandEnvironmentVariables($configuredRoot).Trim().Trim('"')
        if (-not $expandedRoot -or -not (Test-Path $expandedRoot)) {
            return $null
        }

        return (Resolve-Path $expandedRoot).Path
    }
    catch {
        return $null
    }
}

function Find-GitMetadataPath([string]$startPath) {
    if ([string]::IsNullOrWhiteSpace($startPath) -or -not (Test-Path $startPath)) {
        return $null
    }

    $cursor = (Resolve-Path $startPath).Path
    while ($cursor) {
        $candidate = Join-Path $cursor ".git"
        if (Test-Path $candidate) {
            return $candidate
        }

        $parent = Split-Path $cursor -Parent
        if (-not $parent -or $parent -eq $cursor) {
            break
        }

        $cursor = $parent
    }

    return $null
}

function Resolve-GitCommit([string]$startPath) {
    $gitMetadataPath = Find-GitMetadataPath $startPath
    if (-not $gitMetadataPath) {
        return "not-a-git-repo"
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        try {
            $candidate = (& git -C $startPath rev-parse --short=12 HEAD 2>$null).Trim()
            if ($candidate) {
                return $candidate
            }
        }
        catch {
        }
    }

    try {
        $gitDir = $gitMetadataPath
        $gitItem = Get-Item -Force $gitMetadataPath
        if (-not $gitItem.PSIsContainer) {
            $gitPointer = (Get-Content $gitMetadataPath -Raw).Trim()
            if ($gitPointer -match '^gitdir:\s*(.+)$') {
                $gitDir = Join-Path (Split-Path $gitMetadataPath -Parent) $Matches[1].Trim()
            }
        }

        $headPath = Join-Path $gitDir "HEAD"
        if (-not (Test-Path $headPath)) {
            return "git-metadata-unresolved"
        }

        $headContent = (Get-Content $headPath -Raw).Trim()
        if ($headContent -match '^ref:\s*(.+)$') {
            $refName = $Matches[1].Trim()
            $refPath = Join-Path $gitDir $refName
            if (Test-Path $refPath) {
                $hash = (Get-Content $refPath -Raw).Trim()
                if ($hash) {
                    return $hash.Substring(0, [Math]::Min(12, $hash.Length))
                }
            }

            $packedRefsPath = Join-Path $gitDir "packed-refs"
            if (Test-Path $packedRefsPath) {
                $packedMatch = Select-String -Path $packedRefsPath -Pattern ("^[0-9a-fA-F]+\s+{0}$" -f [Regex]::Escape($refName)) | Select-Object -First 1
                if ($packedMatch) {
                    $hash = ($packedMatch.Line -split '\s+')[0].Trim()
                    if ($hash) {
                        return $hash.Substring(0, [Math]::Min(12, $hash.Length))
                    }
                }
            }

            return "git-ref-missing"
        }

        if ($headContent) {
            return $headContent.Substring(0, [Math]::Min(12, $headContent.Length))
        }
    }
    catch {
        return "git-metadata-unresolved"
    }

    return "git-metadata-unresolved"
}

$gitSearchRoot = Resolve-GitSearchRoot $projectRoot
$gitCommit = if ($gitSearchRoot) { Resolve-GitCommit $gitSearchRoot } elseif ([string]::IsNullOrWhiteSpace($env:TESTBETA_GIT_ROOT)) { "not-a-git-repo" } else { "configured-git-root-missing" }

function Invoke-OptionalCodeSigning([string]$filePath) {
    $signTool = $env:TESTBETA_SIGNTOOL
    $thumbprint = $env:TESTBETA_SIGN_CERT_SHA1
    $pfxPath = $env:TESTBETA_SIGN_PFX_PATH
    $pfxPassword = $env:TESTBETA_SIGN_PFX_PASSWORD
    $timestampUrl = $env:TESTBETA_SIGN_TIMESTAMP_URL

    if ([string]::IsNullOrWhiteSpace($signTool)) {
        return
    }

    if (-not (Test-Path $signTool)) {
        Write-Warning "Skipping signing because TESTBETA_SIGNTOOL does not exist: $signTool"
        return
    }

    $arguments = @("sign", "/fd", "SHA256")
    if (-not [string]::IsNullOrWhiteSpace($pfxPath)) {
        if (-not (Test-Path $pfxPath)) {
            Write-Warning "Skipping signing because TESTBETA_SIGN_PFX_PATH does not exist: $pfxPath"
            return
        }
        $arguments += @("/f", $pfxPath)
        if (-not [string]::IsNullOrWhiteSpace($pfxPassword)) {
            $arguments += @("/p", $pfxPassword)
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
        $arguments += @("/sha1", $thumbprint)
    } else {
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($timestampUrl)) {
        $arguments += @("/tr", $timestampUrl, "/td", "SHA256")
    }
    $arguments += $filePath

    & $signTool @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Code signing failed for $filePath"
    }
}

if (-not (Test-Path $appPath)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "build-exe.ps1")
}

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

$appBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($appPath))
$readmeBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($readmePath))

$compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters = New-Object System.CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable = $true
$parameters.OutputAssembly = $outputPath
$parameters.CompilerOptions = "/target:winexe /optimize"
if (Test-Path $iconPath) {
    $parameters.CompilerOptions += ' /win32icon:"' + $iconPath + '"'
}
$parameters.ReferencedAssemblies.Add("System.dll") | Out-Null
$parameters.ReferencedAssemblies.Add("System.Windows.Forms.dll") | Out-Null
$parameters.ReferencedAssemblies.Add("System.Drawing.dll") | Out-Null

$installerSource = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyVersion("$assemblyVersion")]
[assembly: AssemblyFileVersion("$assemblyVersion")]
[assembly: AssemblyInformationalVersion("$version")]
[assembly: AssemblyCompany("$companyName")]
[assembly: AssemblyProduct("$productName")]
[assembly: AssemblyTitle("$productName")]
[assembly: AssemblyDescription("$fileDescription")]
[assembly: AssemblyCopyright("$copyrightText")]
[assembly: AssemblyMetadata("BuildDateUtc", "$buildDateUtc")]
[assembly: AssemblyMetadata("GitCommit", "$gitCommit")]

internal static class InstallerMetadata
{
    public const string AppName = "Test Beta App";
    public const string AppVersion = "$version";
    public const string BuildDateUtc = "$buildDateUtc";
    public const string GitCommit = "$gitCommit";
    public const string Publisher = "OpenAI Codex";
    public const string AppExeName = "$versionedAppName";
    public const string UninstallerExeName = "Uninstall Test Beta App.exe";
    public const string ReadmeName = "README-app.txt";
    public const string UninstallRegistryKeyName = "TestBetaApp";
}

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        InstallerOptions options = InstallerOptions.Parse(args);

        if (options.Uninstall)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (!options.Silent)
            {
                DialogResult result = MessageBox.Show(
                    "Remove Test Beta App from this PC?",
                    "Test Beta App Uninstall",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question);

                if (result != DialogResult.Yes)
                {
                    return;
                }
            }

            InstallerRuntime.Uninstall(options);

            if (!options.Silent)
            {
                MessageBox.Show(
                    "Test Beta App is being removed. Some files may disappear a second after this window closes.",
                    "Uninstall Started",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            }
            return;
        }

        if (options.Silent)
        {
            string installedExe = InstallerRuntime.Install(options);
            if (options.LaunchAfterInstall)
            {
                Process.Start(installedExe);
            }
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SetupForm(options));
    }
}

internal sealed class InstallerOptions
{
    public bool Silent;
    public bool Uninstall;
    public bool LaunchAfterInstall;
    public bool CreateShortcuts = true;
    public bool HasExplicitTarget;
    public string TargetPath = InstallerRuntime.GetDefaultInstallPath();
    public string DesktopShortcutRoot = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    public string ProgramsShortcutRoot = Environment.GetFolderPath(Environment.SpecialFolder.Programs);

    public static InstallerOptions Parse(string[] args)
    {
        InstallerOptions options = new InstallerOptions();

        foreach (string arg in args)
        {
            if (arg.Equals("/silent", StringComparison.OrdinalIgnoreCase))
            {
                options.Silent = true;
            }
            else if (arg.Equals("/launch", StringComparison.OrdinalIgnoreCase))
            {
                options.LaunchAfterInstall = true;
            }
            else if (arg.Equals("/uninstall", StringComparison.OrdinalIgnoreCase))
            {
                options.Uninstall = true;
            }
            else if (arg.Equals("/noshortcuts", StringComparison.OrdinalIgnoreCase))
            {
                options.CreateShortcuts = false;
            }
            else if (arg.StartsWith("/target=", StringComparison.OrdinalIgnoreCase))
            {
                options.TargetPath = arg.Substring(8).Trim('"');
                options.HasExplicitTarget = true;
            }
            else if (arg.StartsWith("/shortcutdesktop=", StringComparison.OrdinalIgnoreCase))
            {
                options.DesktopShortcutRoot = arg.Substring(17).Trim('"');
            }
            else if (arg.StartsWith("/shortcutprograms=", StringComparison.OrdinalIgnoreCase))
            {
                options.ProgramsShortcutRoot = arg.Substring(18).Trim('"');
            }
        }

        if (options.Uninstall && !options.HasExplicitTarget)
        {
            options.TargetPath = Path.GetDirectoryName(Application.ExecutablePath);
        }

        return options;
    }
}

internal static class InstallerRuntime
{
    private static readonly byte[] AppBytes = Convert.FromBase64String("$appBase64");
    private static readonly byte[] ReadmeBytes = Convert.FromBase64String("$readmeBase64");

    public static string GetDefaultInstallPath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            InstallerMetadata.AppName);
    }

    public static string Install(InstallerOptions options)
    {
        Directory.CreateDirectory(options.TargetPath);

        string appExePath = Path.Combine(options.TargetPath, InstallerMetadata.AppExeName);
        string readmePath = Path.Combine(options.TargetPath, InstallerMetadata.ReadmeName);
        string uninstallerPath = Path.Combine(options.TargetPath, InstallerMetadata.UninstallerExeName);

        File.WriteAllBytes(appExePath, AppBytes);
        File.WriteAllBytes(readmePath, ReadmeBytes);
        CopySelfToUninstaller(uninstallerPath);

        if (options.CreateShortcuts)
        {
            CreateShortcuts(
                options.TargetPath,
                appExePath,
                uninstallerPath,
                options.DesktopShortcutRoot,
                options.ProgramsShortcutRoot);
        }
        else
        {
            RemoveShortcuts(options.DesktopShortcutRoot, options.ProgramsShortcutRoot);
        }

        try
        {
            WriteUninstallEntry(options.TargetPath, appExePath, uninstallerPath);
        }
        catch
        {
        }
        return appExePath;
    }

    public static void Uninstall(InstallerOptions options)
    {
        string appExePath = Path.Combine(options.TargetPath, InstallerMetadata.AppExeName);
        string readmePath = Path.Combine(options.TargetPath, InstallerMetadata.ReadmeName);
        string currentExePath = Application.ExecutablePath;

        TryCloseRunningApp(appExePath);
        RemoveShortcuts(options.DesktopShortcutRoot, options.ProgramsShortcutRoot);
        RemoveUninstallEntry();

        TryDeleteFile(appExePath);
        TryDeleteFile(readmePath);
        ScheduleDeferredCleanup(options.TargetPath, currentExePath);
    }

    private static void CopySelfToUninstaller(string uninstallerPath)
    {
        string currentExePath = Application.ExecutablePath;
        if (!string.Equals(
            Path.GetFullPath(currentExePath),
            Path.GetFullPath(uninstallerPath),
            StringComparison.OrdinalIgnoreCase))
        {
            File.Copy(currentExePath, uninstallerPath, true);
        }
    }

    private static void WriteUninstallEntry(string installPath, string appExePath, string uninstallerPath)
    {
        string uninstallCommand = Quote(uninstallerPath) + " /uninstall /target=" + Quote(installPath);
        string quietUninstallCommand = Quote(uninstallerPath) + " /uninstall /silent /target=" + Quote(installPath);
        int estimatedSizeKb = Math.Max(1, (AppBytes.Length + ReadmeBytes.Length + (int)new FileInfo(uninstallerPath).Length) / 1024);

        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + InstallerMetadata.UninstallRegistryKeyName))
        {
            if (key == null)
            {
                return;
            }

            key.SetValue("DisplayName", InstallerMetadata.AppName);
            key.SetValue("DisplayVersion", InstallerMetadata.AppVersion);
            key.SetValue("Publisher", InstallerMetadata.Publisher);
            key.SetValue("InstallLocation", installPath);
            key.SetValue("DisplayIcon", appExePath);
            key.SetValue("UninstallString", uninstallCommand);
            key.SetValue("QuietUninstallString", quietUninstallCommand);
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            key.SetValue("EstimatedSize", estimatedSizeKb, RegistryValueKind.DWord);
            key.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
            key.SetValue("Comments", "Build date UTC: " + InstallerMetadata.BuildDateUtc + " | Git commit: " + InstallerMetadata.GitCommit);
            key.SetValue("BuildDateUtc", InstallerMetadata.BuildDateUtc);
            key.SetValue("GitCommit", InstallerMetadata.GitCommit);
        }
    }

    private static void RemoveUninstallEntry()
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(
                @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + InstallerMetadata.UninstallRegistryKeyName,
                false);
        }
        catch
        {
        }
    }

    private static void CreateShortcuts(string installPath, string appExePath, string uninstallerPath, string desktopRoot, string programsRoot)
    {
        string desktopShortcut = Path.Combine(
            desktopRoot,
            InstallerMetadata.AppName + ".lnk");

        string startMenuDir = Path.Combine(
            programsRoot,
            InstallerMetadata.AppName);

        Directory.CreateDirectory(startMenuDir);

        string startMenuAppShortcut = Path.Combine(startMenuDir, InstallerMetadata.AppName + ".lnk");
        string startMenuUninstallShortcut = Path.Combine(startMenuDir, "Uninstall " + InstallerMetadata.AppName + ".lnk");

        CreateShortcut(desktopShortcut, appExePath, installPath, "Launch " + InstallerMetadata.AppName);
        CreateShortcut(startMenuAppShortcut, appExePath, installPath, "Launch " + InstallerMetadata.AppName);
        CreateShortcut(startMenuUninstallShortcut, uninstallerPath, installPath, "Remove " + InstallerMetadata.AppName);
    }

    private static void RemoveShortcuts(string desktopRoot, string programsRoot)
    {
        TryDeleteFile(Path.Combine(
            desktopRoot,
            InstallerMetadata.AppName + ".lnk"));

        string startMenuDir = Path.Combine(
            programsRoot,
            InstallerMetadata.AppName);

        TryDeleteFile(Path.Combine(startMenuDir, InstallerMetadata.AppName + ".lnk"));
        TryDeleteFile(Path.Combine(startMenuDir, "Uninstall " + InstallerMetadata.AppName + ".lnk"));

        try
        {
            if (Directory.Exists(startMenuDir))
            {
                Directory.Delete(startMenuDir, false);
            }
        }
        catch
        {
        }
    }

    private static void CreateShortcut(string shortcutPath, string targetPath, string workingDirectory, string description)
    {
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null)
        {
            return;
        }

        object shell = Activator.CreateInstance(shellType);
        object shortcut = shellType.InvokeMember(
            "CreateShortcut",
            BindingFlags.InvokeMethod,
            null,
            shell,
            new object[] { shortcutPath });

        Type shortcutType = shortcut.GetType();
        shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { targetPath });
        shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { workingDirectory });
        shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { description });
        shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
    }

    private static void TryCloseRunningApp(string appExePath)
    {
        foreach (Process process in Process.GetProcesses())
        {
            try
            {
                if (string.Equals(process.MainModule.FileName, appExePath, StringComparison.OrdinalIgnoreCase))
                {
                    process.Kill();
                    process.WaitForExit(2000);
                }
            }
            catch
            {
            }
        }
    }

    private static void ScheduleDeferredCleanup(string installPath, string currentExePath)
    {
        string cleanupScriptPath = Path.Combine(
            Path.GetTempPath(),
            "TestBetaApp-Cleanup-" + Guid.NewGuid().ToString("N") + ".cmd");

        string deleteSelf = currentExePath.StartsWith(installPath, StringComparison.OrdinalIgnoreCase)
            ? "del /f /q " + Quote(currentExePath) + Environment.NewLine
            : string.Empty;

        string script = "@echo off" + Environment.NewLine +
            "ping 127.0.0.1 -n 3 > nul" + Environment.NewLine +
            deleteSelf +
            "rmdir /s /q " + Quote(installPath) + Environment.NewLine +
            "del /f /q \"%~f0\"" + Environment.NewLine;

        File.WriteAllText(cleanupScriptPath, script);

        Process.Start(new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = "/c " + Quote(cleanupScriptPath),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        });
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value + "\"";
    }
}

internal sealed class SetupForm : Form
{
    private readonly TextBox pathBox = new TextBox();
    private readonly CheckBox desktopShortcut = new CheckBox();
    private readonly Button installButton = new Button();
    private readonly Button browseButton = new Button();
    private readonly Button cancelButton = new Button();
    private readonly Label statusLabel = new Label();
    private readonly CheckBox launchAfterInstall = new CheckBox();
    private readonly InstallerOptions options;

    public SetupForm(InstallerOptions options)
    {
        this.options = options;

        Text = InstallerMetadata.AppName + " Setup " + InstallerMetadata.AppVersion;
        ClientSize = new Size(560, 330);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(22, 18, 15);
        ForeColor = Color.FromArgb(246, 231, 208);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

        Label title = new Label();
        title.Text = "Install " + InstallerMetadata.AppName;
        title.Font = new Font("Segoe UI", 16f, FontStyle.Bold);
        title.AutoSize = true;
        title.Location = new Point(20, 18);

        Label versionLabel = new Label();
        versionLabel.Text = "Version " + InstallerMetadata.AppVersion;
        versionLabel.ForeColor = Color.FromArgb(120, 213, 222);
        versionLabel.AutoSize = true;
        versionLabel.Location = new Point(22, 48);

        Label buildLabel = new Label();
        buildLabel.Text = "Build " + InstallerMetadata.BuildDateUtc + "  |  Commit " + InstallerMetadata.GitCommit;
        buildLabel.ForeColor = Color.FromArgb(209, 177, 141);
        buildLabel.AutoSize = true;
        buildLabel.Location = new Point(22, 68);

        Label summary = new Label();
        summary.Text = "Installs the standalone desktop app, creates shortcuts if you want them, and registers an uninstall entry in Installed apps.";
        summary.Size = new Size(510, 42);
        summary.Location = new Point(22, 92);

        Label pathLabel = new Label();
        pathLabel.Text = "Install location";
        pathLabel.AutoSize = true;
        pathLabel.Location = new Point(22, 132);

        pathBox.Text = options.TargetPath;
        pathBox.Size = new Size(390, 26);
        pathBox.Location = new Point(22, 154);

        browseButton.Text = "Browse...";
        browseButton.Size = new Size(110, 28);
        browseButton.Location = new Point(420, 152);
        browseButton.Click += OnBrowse;

        desktopShortcut.Text = "Create desktop and Start menu shortcuts";
        desktopShortcut.Checked = true;
        desktopShortcut.AutoSize = true;
        desktopShortcut.Location = new Point(22, 194);

        launchAfterInstall.Text = "Launch app after install";
        launchAfterInstall.Checked = true;
        launchAfterInstall.AutoSize = true;
        launchAfterInstall.Location = new Point(22, 222);

        statusLabel.Text = "The app installs without admin rights.";
        statusLabel.AutoSize = false;
        statusLabel.Size = new Size(510, 32);
        statusLabel.Location = new Point(22, 248);

        installButton.Text = "Install";
        installButton.Size = new Size(110, 32);
        installButton.Location = new Point(306, 286);
        installButton.Click += OnInstall;

        cancelButton.Text = "Cancel";
        cancelButton.Size = new Size(110, 32);
        cancelButton.Location = new Point(420, 286);
        cancelButton.Click += delegate { Close(); };

        Controls.Add(title);
        Controls.Add(versionLabel);
        Controls.Add(buildLabel);
        Controls.Add(summary);
        Controls.Add(pathLabel);
        Controls.Add(pathBox);
        Controls.Add(browseButton);
        Controls.Add(desktopShortcut);
        Controls.Add(launchAfterInstall);
        Controls.Add(statusLabel);
        Controls.Add(installButton);
        Controls.Add(cancelButton);
    }

    private void OnBrowse(object sender, EventArgs eventArgs)
    {
        using (FolderBrowserDialog dialog = new FolderBrowserDialog())
        {
            dialog.Description = "Choose where Test Beta App should be installed.";
            dialog.SelectedPath = pathBox.Text;
            if (dialog.ShowDialog(this) == DialogResult.OK)
            {
                pathBox.Text = dialog.SelectedPath;
            }
        }
    }

    private void OnInstall(object sender, EventArgs eventArgs)
    {
        try
        {
            options.TargetPath = pathBox.Text.Trim();
            options.CreateShortcuts = desktopShortcut.Checked;
            options.LaunchAfterInstall = launchAfterInstall.Checked;

            if (string.IsNullOrWhiteSpace(options.TargetPath))
            {
                statusLabel.Text = "Choose an install folder first.";
                return;
            }

            string installedExe = InstallerRuntime.Install(options);
            statusLabel.Text = "Installed to " + options.TargetPath;

            if (options.LaunchAfterInstall)
            {
                Process.Start(installedExe);
            }

            MessageBox.Show(
                this,
                InstallerMetadata.AppName + " installed successfully.",
                "Setup Complete",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);

            Close();
        }
        catch (Exception ex)
        {
            statusLabel.Text = "Install failed: " + ex.Message;
        }
    }
}
"@

$result = $compiler.CompileAssemblyFromSource($parameters, $installerSource)

if ($result.Errors.HasErrors) {
    $errors = $result.Errors | ForEach-Object { $_.ToString() }
    throw ("Failed to build installer:`n" + ($errors -join "`n"))
}

Invoke-OptionalCodeSigning $outputPath
Copy-Item $outputPath $stableSetupPath -Force
Invoke-OptionalCodeSigning $stableSetupPath
Write-Host "Built $outputPath"
