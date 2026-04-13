# Windows port-forwarding: route external :443 → WSL2 Caddy
# Run as Administrator in PowerShell
# Required once per WSL2 session (WSL2 IP changes on restart)
#
# Why: WSL2 has its own IP (e.g. 172.26.x.x) — Windows doesn't auto-forward
# to it. This script adds a portproxy rule and firewall exception.

param(
    [int]$ListenPort = 443,
    [int]$ConnectPort = 443
)

$ErrorActionPreference = "Stop"

# Get current WSL2 IP
$wslIp = wsl hostname -I | ForEach-Object { $_.Trim().Split(" ")[0] }
if (-not $wslIp) {
    Write-Error "Could not determine WSL2 IP. Is WSL2 running?"
    exit 1
}
Write-Host "WSL2 IP: $wslIp"

# Remove any existing rule for this port
netsh interface portproxy delete v4tov4 `
    listenport=$ListenPort listenaddress=0.0.0.0 2>$null

# Add new portproxy rule: Windows :443 → WSL2:443
netsh interface portproxy add v4tov4 `
    listenport=$ListenPort `
    listenaddress=0.0.0.0 `
    connectport=$ConnectPort `
    connectaddress=$wslIp

Write-Host "Port proxy added: 0.0.0.0:$ListenPort → $wslIp:$ConnectPort"

# Also forward port 80 for Let's Encrypt HTTP-01 challenge
netsh interface portproxy delete v4tov4 `
    listenport=80 listenaddress=0.0.0.0 2>$null
netsh interface portproxy add v4tov4 `
    listenport=80 `
    listenaddress=0.0.0.0 `
    connectport=80 `
    connectaddress=$wslIp
Write-Host "Port proxy added: 0.0.0.0:80 → $wslIp:80"

# Windows Firewall rules
$rules = @(
    @{ Name = "WSL2-HTTPS-Inbound"; Port = 443 },
    @{ Name = "WSL2-HTTP-Inbound";  Port = 80  }
)
foreach ($rule in $rules) {
    Remove-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName $rule.Name `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $rule.Port `
        -Action Allow `
        -Profile Any | Out-Null
    Write-Host "Firewall rule added: $($rule.Name) (TCP $($rule.Port))"
}

# Show current port proxies
Write-Host "`nCurrent port proxies:"
netsh interface portproxy show all

Write-Host "`nDone. kushnir.cloud port 443 → WSL2 Caddy"
Write-Host "Re-run this script after every WSL2 restart (IP may change)"
