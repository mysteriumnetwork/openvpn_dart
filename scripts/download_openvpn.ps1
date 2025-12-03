# OpenVPN Bundle Downloader for Windows
# This script downloads and extracts OpenVPN components for bundling with Flutter app

param(
    [string]$OutputDir = "..\windows\openvpn_bundle",
    [string]$OpenVPNVersion = "2.6.17"
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Success { Write-Host "Success $args" -ForegroundColor Green }
function Write-Info { Write-Host "Info $args" -ForegroundColor Cyan }
function Write-Warning { Write-Host "Warning $args" -ForegroundColor Yellow }
function Write-Failure { Write-Host "Failure $args" -ForegroundColor Red }

Write-Host "`n================================" -ForegroundColor Green
Write-Host "OpenVPN Bundle Downloader" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green

# Create output directory
Write-Info "Creating output directory: $OutputDir"
$OutputDir = Join-Path $PSScriptRoot $OutputDir
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = Resolve-Path $OutputDir

# Define download URLs
$OPENVPN_MSI_URL = "https://swupdate.openvpn.org/community/releases/OpenVPN-${OpenVPNVersion}-I001-amd64.msi"
$TAP_DRIVER_URL = "https://build.openvpn.net/downloads/releases/tap-windows-9.24.7-I601-Win10.exe"

$MSI_FILE = Join-Path $env:TEMP "openvpn_installer.msi"
$ExtractDir = Join-Path $env:TEMP "openvpn_extract"

# Download OpenVPN MSI
Write-Info "Downloading OpenVPN $OpenVPNVersion..."
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $OPENVPN_MSI_URL -OutFile $MSI_FILE -UseBasicParsing
    Write-Success "Downloaded OpenVPN installer ($('{0:N2}' -f ((Get-Item $MSI_FILE).Length / 1MB)) MB)"
} catch {
    Write-Failure "Failed to download OpenVPN: $_"
    Write-Warning "Please download manually from: https://openvpn.net/community-downloads/"
    exit 1
}

# Extract MSI
Write-Info "Extracting OpenVPN files..."
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

try {
    $process = Start-Process msiexec.exe -ArgumentList "/a `"$MSI_FILE`" /qn TARGETDIR=`"$ExtractDir`"" -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -eq 0) {
        Write-Success "Extracted OpenVPN files"
    } else {
        throw "MSI extraction failed with exit code: $($process.ExitCode)"
    }
} catch {
    Write-Failure "Failed to extract MSI: $_"
    exit 1
}

# Find bin directory (structure may vary)
$BinDir = $null
$PossiblePaths = @(
    (Join-Path $ExtractDir "PFiles\OpenVPN\bin"),
    (Join-Path $ExtractDir "Program Files\OpenVPN\bin"),
    (Join-Path $ExtractDir "OpenVPN\bin"),
    (Join-Path $ExtractDir "ProgramFiles\OpenVPN\bin")
)

foreach ($path in $PossiblePaths) {
    if (Test-Path $path) {
        $BinDir = $path
        Write-Info "Found bin directory: $path"
        break
    }
}

if (-not $BinDir) {
    Write-Warning "Could not find OpenVPN bin directory in expected locations"
    Write-Info "Searching for openvpn.exe..."
    $FoundExe = Get-ChildItem $ExtractDir -Recurse -Filter "openvpn.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($FoundExe) {
        $BinDir = $FoundExe.DirectoryName
        Write-Success "Found OpenVPN executable at: $BinDir"
    } else {
        Write-Failure "Could not find openvpn.exe anywhere in extraction directory"
        Write-Info "Extraction directory structure:"
        Get-ChildItem $ExtractDir -Recurse -Directory | Select-Object -First 20 | ForEach-Object { Write-Host "  $($_.FullName)" }
        exit 1
    }
}

Write-Info "Found OpenVPN binaries at: $BinDir"

# Define required files
$RequiredFiles = @(
    "openvpn.exe"
)

# Optional files (DLL dependencies - names vary by OpenVPN version)
$OptionalFiles = @(
    # OpenSSL 3.x (newer versions)
    "libcrypto-3-x64.dll",
    "libssl-3-x64.dll",
    # OpenSSL 1.1.x (older versions)
    "libcrypto-1_1-x64.dll",
    "libssl-1_1-x64.dll",
    # Legacy OpenSSL
    "libeay32.dll",
    "ssleay32.dll",
    # LZO compression
    "liblzo2-2.dll",
    # PKCS11
    "libpkcs11-helper-1.dll",
    # Visual C++ Runtime
    "msvcr120.dll",
    "msvcp120.dll",
    "vcruntime140.dll",
    "msvcp140.dll"
)

# Copy required files
Write-Info "Copying required files..."
$CopiedCount = 0
$MissingFiles = @()

foreach ($file in $RequiredFiles) {
    $sourcePath = Join-Path $BinDir $file
    $destPath = Join-Path $OutputDir $file
    
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath $destPath -Force
        Write-Success "Copied $file"
        $CopiedCount++
    } else {
        Write-Warning "Missing required file: $file"
        $MissingFiles += $file
    }
}

# Copy optional files
Write-Info "Copying optional files..."
foreach ($file in $OptionalFiles) {
    $sourcePath = Join-Path $BinDir $file
    $destPath = Join-Path $OutputDir $file
    
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath $destPath -Force
        Write-Success "Copied $file (optional)"
        $CopiedCount++
    }
}

# Check if we have at least OpenSSL libraries (required for OpenVPN to work)
$HasOpenSSL = $false
$OpenSSLVariants = @("libcrypto-3-x64.dll", "libcrypto-1_1-x64.dll", "libeay32.dll")
foreach ($variant in $OpenSSLVariants) {
    if (Test-Path (Join-Path $OutputDir $variant)) {
        $HasOpenSSL = $true
        break
    }
}

if (-not $HasOpenSSL) {
    Write-Warning "No OpenSSL libraries found! OpenVPN may not work."
    Write-Info "Searching for all DLLs in bin directory..."
    Get-ChildItem $BinDir -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $OutputDir $_.Name) -Force
        Write-Success "Copied $($_.Name) (auto-detected)"
        $CopiedCount++
    }
}

# Download TAP-Windows driver
Write-Info "Downloading TAP-Windows driver..."
$TapInstallerPath = Join-Path $OutputDir "tap-windows-installer.exe"

try {
    Invoke-WebRequest -Uri $TAP_DRIVER_URL -OutFile $TapInstallerPath -UseBasicParsing
    Write-Success "Downloaded TAP-Windows driver ($('{0:N2}' -f ((Get-Item $TapInstallerPath).Length / 1MB)) MB)"
} catch {
    Write-Warning "Failed to download TAP driver: $_"
    Write-Info "You can download it manually from: https://build.openvpn.net/downloads/releases/"
}

# Cleanup temporary files
Write-Info "Cleaning up temporary files..."
Remove-Item $MSI_FILE -Force -ErrorAction SilentlyContinue
Remove-Item $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Success "Cleanup completed"

# Summary
Write-Host "`n================================" -ForegroundColor Green
Write-Host "Bundle Creation Summary" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green

Write-Host "Bundle location: $OutputDir" -ForegroundColor Cyan
Write-Host "`nBundled files ($CopiedCount):" -ForegroundColor Cyan
Get-ChildItem $OutputDir | ForEach-Object { 
    $size = '{0:N2}' -f ($_.Length / 1KB)
    Write-Host "  - $($_.Name) ($size KB)" 
}

$TotalSize = (Get-ChildItem $OutputDir | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "`nTotal bundle size: $([math]::Round($TotalSize, 2)) MB" -ForegroundColor Cyan

if ($MissingFiles.Count -eq 0) {
    Write-Success "`nAll required files copied successfully!"
} else {
    Write-Warning "`nMissing $($MissingFiles.Count) required file(s):"
    $MissingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

# Verification
Write-Host "`n================================" -ForegroundColor Green
Write-Host "Verification" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green

$OpenvpnExe = Join-Path $OutputDir "openvpn.exe"
if (Test-Path $OpenvpnExe) {
    try {
        $version = (& $OpenvpnExe --version 2>&1 | Select-Object -First 1)
        Write-Success "OpenVPN executable is valid"
        Write-Info "Version: $version"
    } catch {
        Write-Warning "Could not verify OpenVPN version"
    }
} else {
    Write-Failure "openvpn.exe not found!"
}

# Next steps
Write-Host "`n================================" -ForegroundColor Green
Write-Host "Next Steps" -ForegroundColor Green
Write-Host "================================`n" -ForegroundColor Green

Write-Host "1. Verify all files in: $OutputDir" -ForegroundColor White
Write-Host "2. Update your Flutter app's windows/CMakeLists.txt" -ForegroundColor White
Write-Host "3. Build your Flutter app: flutter build windows" -ForegroundColor White
Write-Host "4. Test the bundled OpenVPN functionality" -ForegroundColor White

Write-Host "Bundle creation completed successfully!" -ForegroundColor Green
Write-Host "`nNote: Ensure all DLL dependencies are present for OpenVPN to work." -ForegroundColor Yellow

# Return status
if ($MissingFiles.Count -eq 0 -and $CopiedCount -gt 1) {
    exit 0
} else {
    Write-Warning "Some files may be missing. Please verify the bundle."
    exit 1
}
