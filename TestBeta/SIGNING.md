# Signing

`Test Beta` supports two Windows code-signing modes in both:

- `build-exe.ps1`
- `build-installer.ps1`

Shared variables:

- `TESTBETA_SIGNTOOL`
- `TESTBETA_SIGN_TIMESTAMP_URL`

Certificate choice:

- Thumbprint mode: `TESTBETA_SIGN_CERT_SHA1`
- PFX mode: `TESTBETA_SIGN_PFX_PATH`
- Optional PFX password: `TESTBETA_SIGN_PFX_PASSWORD`

Precedence:

1. If `TESTBETA_SIGN_PFX_PATH` is set, the build uses the `.pfx`
2. Otherwise, if `TESTBETA_SIGN_CERT_SHA1` is set, the build uses the certificate thumbprint
3. If neither is set, the build skips signing

## Thumbprint Signing

PowerShell example:

```powershell
$env:TESTBETA_SIGNTOOL = "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe"
$env:TESTBETA_SIGN_CERT_SHA1 = "0123456789ABCDEF0123456789ABCDEF01234567"
$env:TESTBETA_SIGN_TIMESTAMP_URL = "http://timestamp.digicert.com"

Remove-Item Env:TESTBETA_SIGN_PFX_PATH -ErrorAction SilentlyContinue
Remove-Item Env:TESTBETA_SIGN_PFX_PASSWORD -ErrorAction SilentlyContinue

powershell -ExecutionPolicy Bypass -File .\build-exe.ps1
powershell -ExecutionPolicy Bypass -File .\build-installer.ps1
powershell -ExecutionPolicy Bypass -File .\build-release.ps1
```

Use this when the signing certificate is already installed in the Windows certificate store.

## PFX Signing

PowerShell example:

```powershell
$env:TESTBETA_SIGNTOOL = "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe"
$env:TESTBETA_SIGN_PFX_PATH = "C:\Signing\TestBetaCodeSigningCert.pfx"
$env:TESTBETA_SIGN_PFX_PASSWORD = "replace-with-your-pfx-password"
$env:TESTBETA_SIGN_TIMESTAMP_URL = "http://timestamp.digicert.com"

Remove-Item Env:TESTBETA_SIGN_CERT_SHA1 -ErrorAction SilentlyContinue

powershell -ExecutionPolicy Bypass -File .\build-exe.ps1
powershell -ExecutionPolicy Bypass -File .\build-installer.ps1
powershell -ExecutionPolicy Bypass -File .\build-release.ps1
```

Use this when the certificate is provided as a `.pfx` file instead of being installed in the machine store.

## Quick Checks

Show current signing environment:

```powershell
Get-ChildItem Env:TESTBETA_SIGN*
```

Clear all signing variables:

```powershell
Remove-Item Env:TESTBETA_SIGNTOOL -ErrorAction SilentlyContinue
Remove-Item Env:TESTBETA_SIGN_CERT_SHA1 -ErrorAction SilentlyContinue
Remove-Item Env:TESTBETA_SIGN_PFX_PATH -ErrorAction SilentlyContinue
Remove-Item Env:TESTBETA_SIGN_PFX_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:TESTBETA_SIGN_TIMESTAMP_URL -ErrorAction SilentlyContinue
```

Inspect file signature after a build:

```powershell
Get-AuthenticodeSignature .\dist\TestBetaApp-1.0.0.exe | Format-List
Get-AuthenticodeSignature .\dist\TestBetaSetup-1.0.0.exe | Format-List
```

## Git Metadata

If `TestBeta` is not itself inside a git repo, you can point the build at a different repo root so the About screen and installer metadata pick up that commit.

Shared variable:

- `TESTBETA_GIT_ROOT`

PowerShell example:

```powershell
$env:TESTBETA_GIT_ROOT = "C:\src\your-real-repo"

powershell -ExecutionPolicy Bypass -File .\build-exe.ps1
powershell -ExecutionPolicy Bypass -File .\build-installer.ps1
powershell -ExecutionPolicy Bypass -File .\build-release.ps1
```

Behavior:

- If `TESTBETA_GIT_ROOT` points at a repo root, the build reads that repo's current commit
- If `TESTBETA_GIT_ROOT` is missing or invalid, the build falls back to a clear status string
- If `TESTBETA_GIT_ROOT` is not set, the build searches upward from the `TestBeta` project folder

## Notes

- Replace the certificate values with your real thumbprint or `.pfx` path
- Replace `TESTBETA_GIT_ROOT` with the repo root you actually want the build to read
- Replace the timestamp URL if your certificate provider requires a different service
- The build scripts throw if signing is attempted and `signtool` returns a failure
- Avoid committing real passwords or certificate paths to source control
