# setup-on-vps.ps1 - Configure IIS / HttpListener static server for NexConnect updates.
# Run on VPS 104.234.180.103 in PowerShell as Administrator.
#
# Usage (on VPS):
#     powershell -ExecutionPolicy Bypass -File setup-on-vps.ps1
#
# Requires: PowerShell 5.1+, runs as Administrator.

$ErrorActionPreference = "Stop"

$Port       = 3000
$WebRoot    = "C:\dist-update"
$SiteName   = "NexConnectUpdates"

Write-Host "=== Setup IIS site for NexConnect updates ===" -ForegroundColor Cyan

# --- 1) Check admin rights -----------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: must run as Administrator." -ForegroundColor Red
    exit 1
}

# --- 2) Ensure web root -------------------------------------------
if (-not (Test-Path $WebRoot)) {
    Write-Host "Creating $WebRoot ..."
    New-Item -ItemType Directory -Path $WebRoot -Force | Out-Null
}

# --- 3) Install IIS if missing ------------------------------------
$feature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if ($feature -and -not $feature.Installed) {
    Write-Host "Installing IIS ..."
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
} else {
    Write-Host "IIS already installed."
}

Import-Module WebAdministration -ErrorAction SilentlyContinue

# --- 4) Create / configure site -----------------------------------
$sitePath = "IIS:\Sites\$SiteName"
if (Test-Path $sitePath) {
    Write-Host "Removing existing site $SiteName ..."
    Remove-WebSite -Name $SiteName
}

New-Website -Name $SiteName -Port $Port -PhysicalPath $WebRoot -Force | Out-Null

# Set caching headers + disable cache via web.config (created below).
# (Skipped Add-WebConfigurationProperty call: was throwing on empty values on some hosts.)

# Set caching headers via web.config
$webConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <staticContent>
      <clientCache cacheControlMode="DisableCache" />
    </staticContent>
    <httpProtocol>
      <customHeaders>
        <add name="Cache-Control" value="no-cache, no-store, must-revalidate" />
        <add name="Pragma" value="no-cache" />
        <add name="Expires" value="0" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@

$webConfigPath = Join-Path $WebRoot "web.config"
[System.IO.File]::WriteAllText($webConfigPath, $webConfig, [System.Text.UTF8Encoding]::new($false))

# --- 5) Open firewall ---------------------------------------------
Write-Host "Opening firewall for port $Port ..."
try {
    New-NetFirewallRule -DisplayName "NexConnectUpdates" `
        -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow `
        -ErrorAction Stop | Out-Null
} catch {
    Write-Host "(firewall rule may already exist: $_)" -ForegroundColor Yellow
}

# --- 6) Start site -------------------------------------------------
Start-WebSite -Name $SiteName
$iis = Get-Service W3SVC -ErrorAction SilentlyContinue
if ($iis -and $iis.Status -ne 'Running') { Start-Service W3SVC }

# --- 7) Smoke test -------------------------------------------------
Start-Sleep -Seconds 1
try {
    $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/manifest.json" -UseBasicParsing -TimeoutSec 5
    Write-Host "HTTP $($r.StatusCode)  size=$($r.Content.Length) bytes" -ForegroundColor Green
} catch {
    Write-Host "(manifest not found yet, that's OK if you haven't uploaded files): $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Web root : $WebRoot"
Write-Host "URL      : http://104.234.180.103:$Port/manifest.json"
Write-Host ""
Write-Host "Upload files into $WebRoot\ then they will be served at:"
Write-Host "  http://104.234.180.103:$Port/NexConnect.exe"
Write-Host "  http://104.234.180.103:$Port/manifest.json"
Write-Host "  http://104.234.180.103:$Port/nexus_runtime.dll"
