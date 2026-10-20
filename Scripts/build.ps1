#Requires -Version 5.1
<#
.SYNOPSIS
    Builds Prism on Windows with the MSVC toolchain.

.DESCRIPTION
    One command from a normal PowerShell prompt:

        .\Scripts\build.ps1
        .\Scripts\build.ps1 -Test
        .\Scripts\build.ps1 -Configuration release

    The script:
      * imports the Visual Studio x64 developer environment,
      * finds (or bootstraps) vcpkg,
      * installs the dependencies listed in vcpkg.json,
      * creates a real 'pkg-config.exe' from vcpkg's 'pkgconf.exe',
      * writes a 'vulkan.pc' that points at vcpkg's Vulkan headers,
      * sets PKG_CONFIG_PATH and the DLL path for this process,
      * runs 'swift build' (and 'swift test' with -Test).

    Nothing is installed system-wide; vcpkg goes into '.vcpkg/' and its
    packages into 'vcpkg_installed/'.

.PARAMETER Configuration
    'debug' (default) or 'release'.

.PARAMETER Test
    Run 'swift test' after a successful build.

.PARAMETER Clean
    Run 'swift package clean' before building.

.PARAMETER NoBootstrap
    Fail instead of cloning vcpkg when no vcpkg installation can be found.

.PARAMETER VcpkgRoot
    Path to an existing vcpkg checkout. Defaults to $env:VCPKG_ROOT, then
    the usual locations, then a repo-local '.vcpkg'.
#>
[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "debug",

    [switch]$Test,
    [switch]$Clean,
    [switch]$NoBootstrap,

    [string]$VcpkgRoot = $env:VCPKG_ROOT
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepoRoot

$Triplet = "x64-windows"
$InstallBase = Join-Path $RepoRoot "vcpkg_installed"
$InstallRoot = Join-Path $InstallBase $Triplet
$PrismDir = Join-Path $RepoRoot ".prism"
$ShimDir = Join-Path $PrismDir "bin"
$PkgConfigDir = Join-Path $PrismDir "pkgconfig"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    throw $Message
}

function Find-VcpkgRoot([string]$Preferred) {
    $candidates = @()

    if ($Preferred) {
        if (Test-Path -LiteralPath $Preferred -PathType Leaf) {
            $candidates += Split-Path -Parent (Resolve-Path -LiteralPath $Preferred).Path
        } else {
            $candidates += $Preferred
        }
    }

    $candidates += @(
        $env:VCPKG_ROOT,
        $env:VCPKG_INSTALLATION_ROOT,
        "C:\vcpkg",
        "C:\src\vcpkg",
        (Join-Path $env:USERPROFILE "vcpkg"),
        (Join-Path $RepoRoot ".vcpkg")
    )

    # Manifest versioning needs versions/baseline.json from vcpkg's git
    # history, so a vcpkg without .git (the copy bundled with Visual Studio,
    # or an unzipped one) cannot be used. Skip it and bootstrap .vcpkg instead.
    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $candidate "vcpkg.exe"))) { continue }

        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $key = $resolved.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        if (-not (Test-Path -LiteralPath (Join-Path $resolved ".git"))) {
            Write-Host "warning: ignoring vcpkg at '$resolved' (not a git clone; versioning needs its history)" -ForegroundColor Yellow
            continue
        }

        return $resolved
    }

    $command = Get-Command vcpkg.exe -ErrorAction SilentlyContinue
    if ($command) {
        $commandDir = Split-Path -Parent $command.Source
        $key = $commandDir.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            if (Test-Path -LiteralPath (Join-Path $commandDir ".git")) {
                return $commandDir
            }
            Write-Host "warning: ignoring vcpkg at '$commandDir' (not a git clone; versioning needs its history)" -ForegroundColor Yellow
        }
    }

    return $null
}

function Enter-MsvcEnvironment {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
        return
    }

    $vswhere = $null
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ($programFilesX86) {
        $candidate = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path -LiteralPath $candidate) {
            $vswhere = $candidate
        }
    }
    if (-not $vswhere) {
        $command = Get-Command vswhere.exe -ErrorAction SilentlyContinue
        if ($command) {
            $vswhere = $command.Source
        }
    }
    if (-not $vswhere) {
        Fail "Visual Studio not found. Install Visual Studio 2022 with the 'Desktop development with C++' workload, then run this script from a normal PowerShell prompt."
    }

    $installationPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath |
        Select-Object -First 1

    if (-not $installationPath) {
        Fail "Visual Studio is installed, but the x64 C++ build tools are missing. Re-run the Visual Studio Installer and add 'Desktop development with C++'."
    }

    $vcvars = Join-Path $installationPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars)) {
        Fail "Could not find vcvars64.bat under '$installationPath'."
    }

    Write-Step "Importing the MSVC x64 environment from $installationPath"

    # 'set' after vcvars gives us every variable the developer prompt would
    # have set, without depending on the DevShell PowerShell module.
    $environment = & cmd.exe /d /c "call `"$vcvars`" >nul 2>&1 && set"
    if ($LASTEXITCODE -ne 0) {
        Fail "vcvars64.bat failed (exit code $LASTEXITCODE)."
    }

    foreach ($line in $environment) {
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            Set-Item -Path "env:$($matches[1])" -Value $matches[2]
        }
    }
}

function Install-Vcpkg([string]$Target) {
    $vcpkgExe = Join-Path $Target "vcpkg.exe"

    if (Test-Path -LiteralPath $vcpkgExe) {
        return $vcpkgExe
    }

    if ($NoBootstrap) {
        Fail "vcpkg was not found. Set VCPKG_ROOT (or pass -VcpkgRoot), or drop -NoBootstrap to let the script clone vcpkg into '$Target'."
    }

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        Fail "git.exe is required to bootstrap vcpkg. Install Git for Windows, or install vcpkg yourself and set VCPKG_ROOT."
    }

    if (-not (Test-Path -LiteralPath $Target)) {
        Write-Step "Cloning vcpkg into $Target (one time)"
        & git.exe clone --depth 1 https://github.com/microsoft/vcpkg.git $Target
        if ($LASTEXITCODE -ne 0) {
            Fail "git clone failed. Check your network connection, or install vcpkg manually and set VCPKG_ROOT."
        }
    }

    $bootstrap = Join-Path $Target "bootstrap-vcpkg.bat"
    if (-not (Test-Path -LiteralPath $bootstrap)) {
        Fail "'$Target' exists but does not look like a vcpkg checkout."
    }

    Write-Step "Bootstrapping vcpkg"
    & cmd.exe /d /c "`"$bootstrap`" -disableMetrics"
    if ($LASTEXITCODE -ne 0) {
        Fail "vcpkg bootstrap failed."
    }

    if (-not (Test-Path -LiteralPath $vcpkgExe)) {
        Fail "vcpkg bootstrap finished but '$vcpkgExe' is missing."
    }

    return $vcpkgExe
}

function Find-PkgConf([string]$SearchRoot) {
    if (Test-Path -LiteralPath $SearchRoot) {
        $found = Get-ChildItem -LiteralPath $SearchRoot -Filter "pkgconf.exe" -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    foreach ($root in @($VcpkgRoot, (Join-Path $RepoRoot ".vcpkg"))) {
        if (-not $root) { continue }
        $legacy = Join-Path $root "installed\$Triplet\tools\pkgconf\pkgconf.exe"
        if (Test-Path -LiteralPath $legacy) {
            return $legacy
        }
    }

    $command = Get-Command pkgconf.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Find-VulkanInclude([string]$SearchRoot) {
    $candidates = @()

    if ($env:VULKAN_SDK) {
        $candidates += Join-Path $env:VULKAN_SDK "Include"
        $candidates += Join-Path $env:VULKAN_SDK "include"
    }

    $candidates += Join-Path $SearchRoot "include"

    if (Test-Path -LiteralPath "C:\VulkanSDK") {
        $candidates += Get-ChildItem -LiteralPath "C:\VulkanSDK" -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                Join-Path $_.FullName "Include"
                Join-Path $_.FullName "include"
            }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate "vulkan\vulkan_core.h"))) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

try {
    if (-not $env:OS -or $env:OS -ne "Windows_NT") {
        Fail "This script is for Windows. On Linux or macOS use 'make build' or 'swift build'."
    }

    $swift = Get-Command swift.exe -ErrorAction SilentlyContinue
    if (-not $swift) {
        Fail "Swift was not found on PATH. Install Swift 6.2 or newer from https://www.swift.org/install/windows/ and reopen PowerShell."
    }

    Enter-MsvcEnvironment

    $foundRoot = Find-VcpkgRoot $VcpkgRoot
    if (-not $foundRoot) {
        $foundRoot = Join-Path $RepoRoot ".vcpkg"
    }
    $VcpkgRoot = $foundRoot
    $env:VCPKG_ROOT = $VcpkgRoot

    $vcpkgExe = Install-Vcpkg $VcpkgRoot
    $env:VCPKG_DISABLE_METRICS = "1"

    # Manifest versioning reads versions/baseline.json out of vcpkg's git
    # history. The bootstrap clone is shallow, and an existing vcpkg may be
    # too, so make sure the pinned baseline commit is present.
    $manifestPath = Join-Path $RepoRoot "vcpkg.json"
    if (Test-Path -LiteralPath $manifestPath) {
        $baseline = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).'builtin-baseline'
        if ($baseline) {
            if (-not (Test-Path -LiteralPath (Join-Path $VcpkgRoot ".git"))) {
                Fail "vcpkg at '$VcpkgRoot' is not a git clone. Manifest versioning needs the git history; clone microsoft/vcpkg instead of using a zip."
            }
            if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
                Fail "git.exe is required to fetch the vcpkg baseline '$baseline'."
            }

            & git.exe -C $VcpkgRoot cat-file -e "$baseline^{commit}" 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Step "Fetching vcpkg baseline $baseline"
                & git.exe -C $VcpkgRoot fetch --depth 1 origin $baseline
                if ($LASTEXITCODE -ne 0) {
                    Fail "Could not fetch vcpkg baseline '$baseline'."
                }
            }
        }
    }

    Write-Step "Installing dependencies from vcpkg.json (this can take a while the first time)"
    & $vcpkgExe install --triplet $Triplet
    if ($LASTEXITCODE -ne 0) {
        Fail "vcpkg install failed."
    }

    # pkgconf is the executable; SwiftPM only looks for the name 'pkg-config'.
    $pkgConfExe = Find-PkgConf $InstallRoot
    if (-not $pkgConfExe) {
        Fail "vcpkg did not provide pkgconf.exe. Delete 'vcpkg_installed' and run the script again, or install pkgconf manually."
    }

    New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null
    $pkgConfigExe = Join-Path $ShimDir "pkg-config.exe"
    if ((Resolve-Path -LiteralPath $pkgConfExe).Path -ne (Resolve-Path -LiteralPath $pkgConfigExe -ErrorAction SilentlyContinue).Path) {
        Copy-Item -LiteralPath $pkgConfExe -Destination $pkgConfigExe -Force
    }

    # pkgconf may load a DLL from its own directory, so keep that on PATH too.
    $pkgConfDir = Split-Path -Parent $pkgConfExe
    $vcpkgBin = Join-Path $InstallRoot "bin"
    $pathEntries = @($ShimDir, $pkgConfDir, $vcpkgBin) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $env:PATH = (($pathEntries -join ";") + ";" + $env:PATH)

    # Vulkan ships headers but no .pc file in vcpkg, so write the tiny one
    # SwiftPM needs. Only types are used; there is no loader to link.
    New-Item -ItemType Directory -Force -Path $PkgConfigDir | Out-Null
    $vulkanInclude = Find-VulkanInclude $InstallRoot
    if (-not $vulkanInclude) {
        Fail "Could not find 'vulkan\vulkan_core.h'. vcpkg should have installed vulkan-headers; delete 'vcpkg_installed' and run the script again."
    }

    $vulkanPc = @'
includedir=__INCLUDEDIR__

Name: vulkan
Description: Vulkan headers (types only; no loader is linked)
Version: 1.3
Cflags: -I${includedir}
'@
    $vulkanPc = $vulkanPc.Replace("__INCLUDEDIR__", $vulkanInclude.Replace("\", "/"))
    Set-Content -LiteralPath (Join-Path $PkgConfigDir "vulkan.pc") -Value $vulkanPc -Encoding ASCII

    $pkgConfigPaths = @($PkgConfigDir)
    foreach ($extra in @("lib\pkgconfig", "share\pkgconfig")) {
        $candidate = Join-Path $InstallRoot $extra
        if (Test-Path -LiteralPath $candidate) {
            $pkgConfigPaths += $candidate
        }
    }
    $env:PKG_CONFIG_PATH = $pkgConfigPaths -join ";"

    Write-Step "Checking pkg-config metadata"
    foreach ($module in @("sdl3", "sdl3-image", "freetype2", "vulkan")) {
        & $pkgConfigExe --exists $module
        if ($LASTEXITCODE -ne 0) {
            $available = @()
            $pcDir = Join-Path $InstallRoot "lib\pkgconfig"
            if (Test-Path -LiteralPath $pcDir) {
                $available = @(Get-ChildItem -LiteralPath $pcDir -Filter "*.pc" -File | ForEach-Object Name)
            }
            Fail "pkg-config cannot find '$module'.`nPKG_CONFIG_PATH=$($env:PKG_CONFIG_PATH)`nAvailable: $($available -join ', ')"
        }
    }

    if ($Clean) {
        Write-Step "Cleaning SwiftPM build products"
        & $swift.Source package clean
        if ($LASTEXITCODE -ne 0) {
            Fail "swift package clean failed."
        }
    }

    Write-Step "swift build -c $Configuration"
    & $swift.Source build -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        Fail "swift build failed."
    }

    if ($Test) {
        Write-Step "swift test -c $Configuration"
        & $swift.Source test -c $Configuration
        if ($LASTEXITCODE -ne 0) {
            Fail "swift test failed."
        }
    }

    Write-Host ""
    Write-Host "Done ($Configuration)." -ForegroundColor Green
    Write-Host "vcpkg:      $VcpkgRoot"
    Write-Host "packages:   $InstallRoot"
    Write-Host "DLLs:       $(Join-Path $InstallRoot 'bin') (on PATH for this run)"
} catch {
    Write-Host ""
    Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
