# publish-update.ps1 — bump version locally, build, hash files, write manifest,
# upload artifacts to a hosting target (VPS or GitHub Releases).
#
# Prereqs:
#   - VS / cmake / cl.exe (build).
#   - For VPS target: WinSCP / scp available, and the remote C:\dist-update\ set up
#     via setup-on-vps.ps1 (IIS site, firewall open).
#   - For GitHub target: GitHub CLI (`gh`) installed and `gh auth login` done.
#
# Usage — VPS:
#   .\publish-update.ps1 -NewVersion "1.0.4" `
#                         -VpsHost "104.234.180.103" `
#                         -VpsPort 22 `
#                         -VpsUser "Administrator" `
#                         -RemoteDir "C:\dist-update"
#
# Usage — GitHub Releases:
#   .\publish-update.ps1 -NewVersion "1.0.4" `
#                         -GitHubRepo "owner/nexconnect"
#
# Without -VpsHost and without -GitHubRepo, just stage files under
# .\dist-update\stage\ for manual copy / upload.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars', '', Justification='Stopped-only failure mode is intentional')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $NewVersion,
    [string] $VpsHost    = "",
    [int]    $VpsPort    = 22,
    [string] $VpsUser    = "",
    [string] $RemoteDir  = "C:\dist-update",
    [string] $GitHubRepo = ""
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is the directory containing THIS .ps1 file (reliable when
# invoked via `powershell -File`), unlike $MyInvocation.MyCommand.Path which
# resolves to the caller's CWD in some invocation paths.
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "=== NexConnect update publisher ===" -ForegroundColor Cyan
Write-Host "Local version  : current"
Write-Host "Remote version : $NewVersion" -ForegroundColor Green

# 1) Bump CMake project version ------------------------------------------
$cmakePath = Join-Path $ProjectRoot "CMakeLists.txt"
$cmakeBefore = Get-Content $cmakePath -Raw
$oldVersion = ([regex]::Match($cmakeBefore,
    'project\(NexConnect VERSION ([0-9.]+)').Groups[1].Value)
$cmakeBefore -replace 'project\(NexConnect VERSION [0-9.]+',
    "project(NexConnect VERSION $NewVersion" | Set-Content $cmakePath
Write-Host "Bumped CMakeLists.txt $oldVersion -> $NewVersion" -ForegroundColor Yellow

# 2) Build ---------------------------------------------------------------
Write-Host "Building Release..." -ForegroundColor Yellow
cmake --build build --config Release --target NexConnect 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Build failed." }

$exeLocal = "build\Release\NexConnect.exe"
$dllLocal = "build\Release\nexus_runtime.dll"
if (-not (Test-Path $exeLocal)) { throw "Missing build output: $exeLocal" }

# 3) Stage artifacts -----------------------------------------------------
$stage = Join-Path $ProjectRoot "dist-update\stage"
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item -Path $exeLocal -Destination (Join-Path $stage "NexConnect.exe") -Force

$dllStage = Join-Path $stage "nexus_runtime.dll"
$hasDll = $false
if (Test-Path $dllLocal) {
    Copy-Item -Path $dllLocal -Destination $dllStage -Force
    $hasDll = $true
}

# 4) SHA256 --------------------------------------------------------------
function Get-Hash($path) {
    (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
}

$exeHash = Get-Hash (Join-Path $stage "NexConnect.exe")
$dllHash = ""
if ($hasDll) { $dllHash = Get-Hash $dllStage }

# 5) Write manifest ------------------------------------------------------
if ($GitHubRepo) {
    $baseUrl = "https://github.com/$GitHubRepo/releases/latest/download"
} elseif ($VpsHost) {
    $baseUrl = "http://$VpsHost`:3000"
} else {
    $baseUrl = "http://127.0.0.1:8080"
}
# oldVersion was captured before the bump above.
$message = if ($oldVersion -and $oldVersion -ne $NewVersion) {
    "Tu v$oldVersion len v$NewVersion"
} else {
    "Phien ban v$NewVersion"
}

$manifestJson = @{
    version  = $NewVersion
    url      = "$baseUrl/NexConnect.exe"
    sha256   = $exeHash
    required = $false
    message  = $message
    files    = @()
}
if ($hasDll) {
    $manifestJson.files = @(@{
        path   = "build/Release/nexus_runtime.dll"
        url    = "$baseUrl/nexus_runtime.dll"
        action = "replace"
        sha256 = $dllHash
    })
}
$manifest = $manifestJson | ConvertTo-Json -Depth 5
$manifestPath = Join-Path $stage "manifest.json"
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=== Staged ===" -ForegroundColor Green
Get-ChildItem $stage | Format-Table Name, Length -AutoSize
Write-Host "Manifest:" -ForegroundColor Cyan
Write-Host $manifest

# 6) Upload --------------------------------------------------------------
if ($GitHubRepo) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        # Try the well-known install path (winget puts gh here on Windows).
        $ghCandidates = @(
            "C:\Program Files\GitHub CLI\gh.exe",
            "C:\Program Files (x86)\GitHub CLI\gh.exe",
            (Join-Path $env:LOCALAPPDATA "Programs\GitHub CLI\gh.exe")
        )
        foreach ($p in $ghCandidates) {
            if (Test-Path $p) {
                Write-Host "Found gh at $p (adding to PATH for this session)." -ForegroundColor Yellow
                $env:Path = (Split-Path $p) + [IO.Path]::PathSeparator + $env:Path
                break
            }
        }
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI ('gh') not found. Install it from https://cli.github.com/ and run 'gh auth login'."
    }
    $tag = "v$NewVersion"
    Write-Host ""
    Write-Host "Creating GitHub release $tag on $GitHubRepo ..." -ForegroundColor Yellow
    $notes = "NexConnect v$NewVersion`n`n$message"
    # -F reads notes from file; we already wrote manifest content to console,
    # but to keep it simple we pass notes inline.
    gh release create $tag `
        --repo $GitHubRepo `
        --title "NexConnect $tag" `
        --notes "$notes" `
        --generate-notes `
        (Join-Path $stage "manifest.json") `
        (Join-Path $stage "NexConnect.exe") `
        (Join-Path $stage "nexus_runtime.dll")
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed." }
    Write-Host "GitHub release $tag published." -ForegroundColor Green
    Write-Host "Public URL: $baseUrl/manifest.json" -ForegroundColor Green
    exit 0
}

if (-not $VpsHost) {
    Write-Host ""
    Write-Host "(No -VpsHost and no -GitHubRepo given, skipping upload. Copy the staged files above to $RemoteDir yourself.)" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Uploading to $VpsUser@${VpsHost}:$RemoteDir ..." -ForegroundColor Yellow
$target = "${VpsUser}@${VpsHost}:${RemoteDir}"
foreach ($f in Get-ChildItem $stage) {
    Write-Host "  -> $f.Name"
    scp -P $VpsPort $f.FullName "${target}/"
}
Write-Host "Upload complete." -ForegroundColor Green
