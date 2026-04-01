$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $projectRoot "dist"
$iconPath = Join-Path $projectRoot "app.ico"
$versionPath = Join-Path $projectRoot "version.txt"

if (-not (Test-Path $iconPath)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $projectRoot "generate-icon.ps1")
}

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

if (-not (Test-Path $versionPath)) {
    Set-Content -Path $versionPath -Value "1.0.0"
}

$version = (Get-Content $versionPath -Raw).Trim()
$safeVersion = $version -replace '[^0-9A-Za-z\.\-]', '-'
$assemblyVersion = if ($version -match '^\d+\.\d+\.\d+$') { "$version.0" } elseif ($version -match '^\d+\.\d+\.\d+\.\d+$') { $version } else { "1.0.0.0" }
$versionedAppName = "TestBetaApp-$safeVersion.exe"
$versionedOutputPath = Join-Path $distDir $versionedAppName
$stableOutputPath = Join-Path $distDir "TestBetaApp.exe"
$companyName = "OpenAI Codex"
$productName = "Test Beta App"
$fileDescription = "Standalone desktop wrapper for the Test Beta FPS prototype"
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

$indexHtml = Get-Content (Join-Path $projectRoot "index.html") -Raw
$stylesCss = Get-Content (Join-Path $projectRoot "styles.css") -Raw
$gameJs = (Get-Content (Join-Path $projectRoot "game.js") -Raw) -replace "</script>", "<\/script>"
$bundledHtml = $indexHtml `
    -replace '<link rel="stylesheet" href="styles.css">', "<style>`r`n$stylesCss`r`n</style>" `
    -replace '<script src="game.js"></script>', "<script>`r`n$gameJs`r`n</script>"
$bundledHtmlBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bundledHtml))

$compiler = New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters = New-Object System.CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable = $true
$parameters.OutputAssembly = $versionedOutputPath
$parameters.CompilerOptions = "/target:winexe /optimize"
if (Test-Path $iconPath) {
    $parameters.CompilerOptions += ' /win32icon:"' + $iconPath + '"'
}
$parameters.ReferencedAssemblies.Add("System.dll") | Out-Null
$parameters.ReferencedAssemblies.Add("System.Windows.Forms.dll") | Out-Null
$parameters.ReferencedAssemblies.Add("System.Drawing.dll") | Out-Null

$launcherSource = @"
using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
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

internal static class Program
{
    private static readonly string BundledHtmlBase64 = "$bundledHtmlBase64";
    private static readonly string AppVersion = "$version";
    private static readonly string BuildDateUtc = "$buildDateUtc";
    private static readonly string GitCommit = "$gitCommit";

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        EnsureBrowserEmulation();
        Application.Run(new LauncherForm(
            Encoding.UTF8.GetString(Convert.FromBase64String(BundledHtmlBase64)),
            AppVersion,
            BuildDateUtc,
            GitCommit));
    }

    private static void EnsureBrowserEmulation()
    {
        try
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(
                @"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION"))
            {
                if (key != null)
                {
                    string executableName = Path.GetFileName(Application.ExecutablePath);
                    key.SetValue(executableName, 11001, RegistryValueKind.DWord);
                    key.SetValue("TestBetaApp.exe", 11001, RegistryValueKind.DWord);
                }
            }
        }
        catch
        {
        }
    }
}

internal sealed class LauncherForm : Form
{
    private readonly WebBrowser browser = new WebBrowser();
    private readonly Panel splashPanel = new Panel();
    private readonly Label splashStatus = new Label();
    private readonly Timer splashTimer = new Timer();
    private readonly string appVersion;
    private readonly string buildDateUtc;
    private readonly string gitCommit;
    private bool fullscreenActive;
    private bool splashQueuedForDismiss;
    private FormBorderStyle previousBorderStyle;
    private Rectangle previousBounds;
    private FormWindowState previousWindowState;

    public LauncherForm(string htmlDocument, string version, string buildDate, string commit)
    {
        appVersion = version;
        buildDateUtc = buildDate;
        gitCommit = commit;

        Text = "Test Beta App";
        ClientSize = new Size(1280, 720);
        MinimumSize = new Size(1024, 640);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(18, 15, 12);
        KeyPreview = true;
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

        browser.Dock = DockStyle.Fill;
        browser.ScriptErrorsSuppressed = true;
        browser.WebBrowserShortcutsEnabled = false;
        browser.AllowWebBrowserDrop = false;
        browser.IsWebBrowserContextMenuEnabled = false;
        browser.DocumentCompleted += OnDocumentCompleted;
        Controls.Add(browser);

        BuildSplash();
        Controls.Add(splashPanel);
        splashPanel.BringToFront();

        splashTimer.Interval = 900;
        splashTimer.Tick += OnSplashTimerTick;

        browser.DocumentText = htmlDocument;
    }

    private void BuildSplash()
    {
        splashPanel.Dock = DockStyle.Fill;
        splashPanel.BackColor = Color.FromArgb(20, 15, 12);
        splashPanel.Padding = new Padding(36);
        splashPanel.Cursor = Cursors.Hand;
        splashPanel.Click += delegate { HideSplash(); };

        Panel card = new Panel();
        card.Size = new Size(620, 340);
        card.BackColor = Color.FromArgb(35, 26, 20);
        card.BorderStyle = BorderStyle.FixedSingle;
        card.Location = new Point(
            Math.Max(24, (ClientSize.Width - 620) / 2),
            Math.Max(24, (ClientSize.Height - 340) / 2));
        card.Anchor = AnchorStyles.None;
        card.Click += delegate { HideSplash(); };

        Label eyebrow = new Label();
        eyebrow.Text = "Standalone Desktop Build";
        eyebrow.ForeColor = Color.FromArgb(209, 177, 141);
        eyebrow.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
        eyebrow.AutoSize = true;
        eyebrow.Location = new Point(28, 24);

        Label title = new Label();
        title.Text = "Test Beta App";
        title.ForeColor = Color.FromArgb(246, 231, 208);
        title.Font = new Font("Segoe UI", 26f, FontStyle.Bold);
        title.AutoSize = true;
        title.Location = new Point(24, 48);

        Label versionLabel = new Label();
        versionLabel.Text = "Version " + appVersion;
        versionLabel.ForeColor = Color.FromArgb(120, 213, 222);
        versionLabel.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
        versionLabel.AutoSize = true;
        versionLabel.Location = new Point(30, 102);

        Label buildLabel = new Label();
        buildLabel.Text = "Build " + buildDateUtc + "  |  Commit " + gitCommit;
        buildLabel.ForeColor = Color.FromArgb(209, 177, 141);
        buildLabel.Font = new Font("Segoe UI", 8.5f, FontStyle.Regular);
        buildLabel.AutoSize = true;
        buildLabel.Location = new Point(30, 122);

        Label summary = new Label();
        summary.Text = "Low-spec FPS extraction prototype for Windows with embedded assets, fullscreen support, and desktop-native controls.";
        summary.ForeColor = Color.FromArgb(238, 216, 187);
        summary.Font = new Font("Segoe UI", 10.5f, FontStyle.Regular);
        summary.Size = new Size(560, 54);
        summary.Location = new Point(30, 146);

        Label hints = new Label();
        hints.Text = "Click in-game to lock pointer" + Environment.NewLine +
            "F1 opens About" + Environment.NewLine +
            "F11 toggles app fullscreen";
        hints.ForeColor = Color.FromArgb(246, 231, 208);
        hints.Font = new Font("Segoe UI", 10f, FontStyle.Regular);
        hints.Size = new Size(250, 72);
        hints.Location = new Point(32, 214);

        Button aboutButton = new Button();
        aboutButton.Text = "About";
        aboutButton.Size = new Size(100, 34);
        aboutButton.Location = new Point(378, 270);
        aboutButton.BackColor = Color.FromArgb(47, 33, 23);
        aboutButton.ForeColor = Color.FromArgb(246, 231, 208);
        aboutButton.FlatStyle = FlatStyle.Flat;
        aboutButton.FlatAppearance.BorderColor = Color.FromArgb(135, 96, 60);
        aboutButton.Click += delegate
        {
            ShowAboutDialog();
            HideSplash();
        };

        Button launchButton = new Button();
        launchButton.Text = "Launch";
        launchButton.Size = new Size(120, 34);
        launchButton.Location = new Point(484, 270);
        launchButton.BackColor = Color.FromArgb(224, 98, 47);
        launchButton.ForeColor = Color.FromArgb(37, 22, 12);
        launchButton.FlatStyle = FlatStyle.Flat;
        launchButton.FlatAppearance.BorderColor = Color.FromArgb(255, 184, 116);
        launchButton.Click += delegate { HideSplash(); };

        splashStatus.Text = "Preparing embedded runtime...";
        splashStatus.ForeColor = Color.FromArgb(209, 177, 141);
        splashStatus.Font = new Font("Segoe UI", 9f, FontStyle.Italic);
        splashStatus.AutoSize = true;
        splashStatus.Location = new Point(320, 220);

        card.Controls.Add(eyebrow);
        card.Controls.Add(title);
        card.Controls.Add(versionLabel);
        card.Controls.Add(buildLabel);
        card.Controls.Add(summary);
        card.Controls.Add(hints);
        card.Controls.Add(splashStatus);
        card.Controls.Add(aboutButton);
        card.Controls.Add(launchButton);

        splashPanel.Controls.Add(card);
    }

    private void OnDocumentCompleted(object sender, WebBrowserDocumentCompletedEventArgs eventArgs)
    {
        if (splashQueuedForDismiss)
        {
            return;
        }

        splashQueuedForDismiss = true;
        splashStatus.Text = "Ready. Click Launch or press F1 for app details.";
        splashTimer.Start();
    }

    private void OnSplashTimerTick(object sender, EventArgs eventArgs)
    {
        splashTimer.Stop();
        HideSplash();
    }

    private void HideSplash()
    {
        if (!splashPanel.Visible)
        {
            return;
        }

        splashTimer.Stop();
        splashPanel.Visible = false;
        browser.Focus();
    }

    private void ShowAboutDialog()
    {
        using (Form dialog = new Form())
        {
            dialog.Text = "About Test Beta App";
            dialog.ClientSize = new Size(470, 355);
            dialog.StartPosition = FormStartPosition.CenterParent;
            dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
            dialog.MaximizeBox = false;
            dialog.MinimizeBox = false;
            dialog.BackColor = Color.FromArgb(22, 18, 15);
            dialog.ForeColor = Color.FromArgb(246, 231, 208);
            dialog.Icon = Icon;

            Label title = new Label();
            title.Text = "Test Beta App";
            title.Font = new Font("Segoe UI", 18f, FontStyle.Bold);
            title.AutoSize = true;
            title.Location = new Point(22, 20);

            Label versionLabel = new Label();
            versionLabel.Text = "Version " + appVersion;
            versionLabel.ForeColor = Color.FromArgb(120, 213, 222);
            versionLabel.AutoSize = true;
            versionLabel.Location = new Point(24, 58);

            Label buildLabel = new Label();
            buildLabel.Text = "Build date (UTC): " + buildDateUtc + Environment.NewLine +
                "Git commit: " + gitCommit;
            buildLabel.AutoSize = true;
            buildLabel.Location = new Point(24, 82);

            Label body = new Label();
            body.Text = "Desktop wrapper for the Test Beta FPS prototype." + Environment.NewLine + Environment.NewLine +
                "Controls:" + Environment.NewLine +
                "- WASD move" + Environment.NewLine +
                "- Mouse look" + Environment.NewLine +
                "- Q / E backup turn" + Environment.NewLine +
                "- Space or left click fire" + Environment.NewLine +
                "- F in-game fullscreen, F11 app fullscreen" + Environment.NewLine +
                "- [ and ] tune sensitivity" + Environment.NewLine + Environment.NewLine +
                "Credits:" + Environment.NewLine +
                "- Design and packaging: OpenAI Codex" + Environment.NewLine +
                "- Runtime: embedded HTML/CSS/JavaScript desktop wrapper";
            body.Size = new Size(410, 205);
            body.Location = new Point(24, 124);

            Button closeButton = new Button();
            closeButton.Text = "Close";
            closeButton.Size = new Size(96, 32);
            closeButton.Location = new Point(338, 312);
            closeButton.Click += delegate { dialog.Close(); };

            dialog.Controls.Add(title);
            dialog.Controls.Add(versionLabel);
            dialog.Controls.Add(buildLabel);
            dialog.Controls.Add(body);
            dialog.Controls.Add(closeButton);
            dialog.AcceptButton = closeButton;
            dialog.ShowDialog(this);
        }
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == Keys.F1)
        {
            ShowAboutDialog();
            return true;
        }

        if (keyData == Keys.F11 || keyData == (Keys.Alt | Keys.Enter))
        {
            ToggleWindowFullscreen();
            return true;
        }

        if (keyData == Keys.Escape && fullscreenActive)
        {
            ToggleWindowFullscreen();
            return true;
        }

        return base.ProcessCmdKey(ref msg, keyData);
    }

    private void ToggleWindowFullscreen()
    {
        if (!fullscreenActive)
        {
            previousBorderStyle = FormBorderStyle;
            previousBounds = Bounds;
            previousWindowState = WindowState;

            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Normal;
            Bounds = Screen.FromControl(this).Bounds;
            TopMost = true;
            fullscreenActive = true;
            return;
        }

        TopMost = false;
        FormBorderStyle = previousBorderStyle;
        Bounds = previousBounds;
        WindowState = previousWindowState;
        fullscreenActive = false;
    }
}
"@

$result = $compiler.CompileAssemblyFromSource($parameters, $launcherSource)

if ($result.Errors.HasErrors) {
    $errors = $result.Errors | ForEach-Object { $_.ToString() }
    throw ("Failed to build app:`n" + ($errors -join "`n"))
}

Invoke-OptionalCodeSigning $versionedOutputPath
Copy-Item $versionedOutputPath $stableOutputPath -Force
Invoke-OptionalCodeSigning $stableOutputPath
Copy-Item (Join-Path $projectRoot "index.html") $distDir -Force
Copy-Item (Join-Path $projectRoot "styles.css") $distDir -Force
Copy-Item (Join-Path $projectRoot "game.js") $distDir -Force

Set-Content -Path (Join-Path $distDir "README-app.txt") -Value @"
Test Beta App
Version: $version

Run $versionedAppName to launch the standalone desktop app build.

Notes:
- The app embeds the HTML, CSS, and JavaScript directly into the executable.
- F1 opens the About dialog.
- F11 toggles window fullscreen at the desktop-app level.
- The loose html/css/js files are included here for reference and browser testing, but the app does not depend on them sitting beside the exe.
"@

Write-Host "Built $versionedOutputPath"
