#!/usr/bin/env pwsh

# Code-Server Enterprise IaC Deployment (PowerShell)
# Works on Windows, macOS, Linux with PowerShell 7+

param(
    [string]$Action = "deploy",  # deploy, destroy, plan, state
    [string]$Host = "192.168.168.32",  # Default remote target
    [string]$User = "akushnir",  # SSH user
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",  # SSH key
    [int]$Port = 22,  # SSH port
    [switch]$Local = $false,  # Deploy locally instead of remote
    [switch]$Verbose = $false,
    [switch]$DryRun = $false
)

# Determine deployment mode
$isRemote = -not $Local -and $Host -ne "localhost" -and $Host -ne "127.0.0.1"

# Configuration
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = $scriptDir
$logFile = Join-Path $scriptDir "deployment.log"

# Color codes
$colors = @{
    Reset  = "`e[0m"
    Red    = "`e[31m"
    Green  = "`e[32m"
    Yellow = "`e[33m"
    Blue   = "`e[34m"
}

# Logging function
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = $colors[$Level] ? $colors[$Level] : $colors.Reset
    
    switch ($Level) {
        "INFO"    { Write-Host "${color}[${timestamp}]${colors.Reset} $Message" -ForegroundColor Cyan }
        "SUCCESS" { Write-Host "${color}[${timestamp}]${colors.Reset} $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "${color}[${timestamp}]${colors.Reset} $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "${color}[${timestamp}]${colors.Reset} $Message" -ForegroundColor Red }
    }
    
    "[${timestamp}] [${Level}] ${Message}" | Add-Content -Path $logFile
}

# Deploy to remote host via SSH
function Invoke-RemoteDeployment {
    param(
        [string]$RemoteHost,
        [string]$RemoteUser,
        [string]$KeyPath,
        [int]$SshPort
    )
    
    Write-Log "INFO" "Preparing remote deployment to ${RemoteUser}@${RemoteHost}:${SshPort}"
    
    # Test SSH connectivity
    try {
        $null = ssh -i $KeyPath -p $SshPort -o StrictHostKeyChecking=no "${RemoteUser}@${RemoteHost}" "echo OK" 2>$null
        Write-Log "SUCCESS" "✓ SSH connectivity verified"
    } catch {
        Write-Log "ERROR" "Cannot connect to ${RemoteUser}@${RemoteHost}:${SshPort}: $_"
        return $false
    }
    
    # Create deployment package
    Write-Log "INFO" "Creating deployment package..."
    $deployPath = "$env:TEMP\code-server-deploy"
    if (Test-Path $deployPath) { Remove-Item -Recurse -Force $deployPath }
    Copy-Item -Path $projectDir -Destination $deployPath -Recurse -ErrorAction SilentlyContinue
    
    # Copy to remote
    Write-Log "INFO" "Uploading to remote host..."
    try {
        Push-Location $deployPath
        scp -i $KeyPath -P $SshPort -r . "${RemoteUser}@${RemoteHost}:/home/${RemoteUser}/code-server-deploy/"
        Pop-Location
        Write-Log "SUCCESS" "✓ Deployment package uploaded"
    } catch {
        Write-Log "ERROR" "Failed to upload: $_"
        return $false
    }
    
    # Execute remote deployment
    Write-Log "INFO" "Executing remote deployment..."
    try {
        ssh -i $KeyPath -p $SshPort "${RemoteUser}@${RemoteHost}" @"
cd /home/${RemoteUser}/code-server-deploy
docker-compose down 2>/dev/null || true
docker-compose up -d
docker-compose ps
"@
        Write-Log "SUCCESS" "✓ Remote deployment successful"
        return $true
    } catch {
        Write-Log "ERROR" "Remote deployment failed: $_"
        return $false
    }
}

# Check prerequisites
function Test-Prerequisites {
    Write-Log "INFO" "Checking prerequisites..."
    
    # Check Docker
    try {
        $dockerVersion = docker --version
        Write-Log "SUCCESS" "✓ Docker found: $dockerVersion"
    } catch {
        Write-Log "ERROR" "Docker is not installed or not in PATH"
        exit 1
    }
}

# Install Terraform
function Install-Terraform {
    Write-Log "INFO" "Checking Terraform installation..."
    
    try {
        $tfVersion = terraform version | Select-Object -First 1
        Write-Log "SUCCESS" "✓ Terraform found: $tfVersion"
        return
    } catch {
        Write-Log "INFO" "Terraform not found. Installing..."
    }
    
    # Detect OS
    $os = if ($IsWindows) { "windows" } elseif ($IsMacOS) { "darwin" } else { "linux" }
    $arch = if ([Environment]::Is64BitProcess) { "amd64" } else { "386" }
    $tfVersion = "1.6.0"
    
    $downloadUrl = "https://releases.hashicorp.com/terraform/${tfVersion}/terraform_${tfVersion}_${os}_${arch}.zip"
    $tempFile = Join-Path $env:TEMP "terraform.zip"
    
    Write-Log "INFO" "Downloading Terraform ${tfVersion}..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile
    
    $installDir = if ($IsWindows) { "C:\Terraform" } else { "/usr/local/bin" }
    Expand-Archive -Path $tempFile -DestinationPath $installDir -Force
    Remove-Item $tempFile
    
    Write-Log "SUCCESS" "✓ Terraform installed"
}

# Initialize Terraform
function Initialize-Terraform {
    Write-Log "INFO" "Initializing Terraform..."
    
    Push-Location $projectDir
    terraform init -upgrade
    Pop-Location
    
    Write-Log "SUCCESS" "✓ Terraform initialized"
}

# Validate configuration
function Test-Configuration {
    Write-Log "INFO" "Validating Terraform configuration..."
    
    Push-Location $projectDir
    terraform validate
    Pop-Location
    
    Write-Log "SUCCESS" "✓ Configuration is valid"
}

# Plan deployment
function New-DeploymentPlan {
    Write-Log "INFO" "Creating deployment plan..."
    
    Push-Location $projectDir
    terraform plan -out=tfplan
    Pop-Location
    
    Write-Log "SUCCESS" "✓ Deployment plan created"
}

# Apply deployment
function Deploy {
    Write-Log "INFO" "Applying Terraform configuration..."
    
    if ($DryRun) {
        Write-Log "WARN" "DRY RUN MODE - No changes will be applied"
        New-DeploymentPlan
        return
    }
    
    Push-Location $projectDir
    terraform apply -auto-approve tfplan
    Pop-Location

    Write-Log "INFO" "Running mandatory runtime redeploy..."
    pwsh -NoProfile -File (Join-Path $projectDir "scripts/mandatory-redeploy.ps1")
    
    Write-Log "SUCCESS" "✓ Deployment applied"
}

# Show outputs
function Show-OutputDetails {
    Write-Log "INFO" "Retrieving access details..."
    
    Push-Location $projectDir
    
    Write-Log "SUCCESS" "=========================================="
    Write-Log "SUCCESS" "Code-Server Enterprise Deployment Complete"
    Write-Log "SUCCESS" "=========================================="
    
    try {
        $url = terraform output -raw code_server_url
        $password = terraform output -raw code_server_password
        
        Write-Log "SUCCESS" "URL: $url"
        Write-Log "SUCCESS" "Password: $password"
    } catch {
        Write-Log "WARN" "Could not retrieve outputs - check Terraform state"
    }
    
    Write-Log "INFO" ""
    Write-Log "INFO" "Next steps:"
    Write-Log "INFO" "  1. Open browser: https://ide.kushnir.cloud"
    Write-Log "INFO" "  2. No GitHub authentication needed"
    Write-Log "INFO" "  3. All infrastructure managed by Terraform"
    Write-Log "INFO" ""
    
    Pop-Location
}

# Destroy resources
function Destroy-Deployment {
    Write-Log "WARN" "Destroying Terraform-managed resources..."
    
    Push-Location $projectDir
    terraform destroy -auto-approve
    Pop-Location
    
    Write-Log "SUCCESS" "✓ Resources destroyed"
}

# Show state
function Show-State {
    Push-Location $projectDir
    
    Write-Log "INFO" "Terraform State:"
    terraform state list
    
    Pop-Location
}

# Main execution
function Main {
    Write-Log "INFO" "Starting Code-Server Enterprise Deployment"
    Write-Log "INFO" "Log file: $logFile"
    Write-Log "INFO" "Action: $Action"
    Write-Log "INFO" "Target host: $Host"
    Write-Log "INFO" "Remote deployment: $isRemote"
    Write-Log "INFO" ""
    
    Test-Prerequisites
    
    if ($isRemote) {
        Write-Log "INFO" "Deploying to remote host: $Host"
        $success = Invoke-RemoteDeployment -RemoteHost $Host -RemoteUser $User -KeyPath $KeyPath -SshPort $Port
        if (-not $success) {
            Write-Log "ERROR" "Remote deployment failed"
            exit 1
        }
    } else {
        Write-Log "INFO" "Deploying locally"
        Install-Terraform
        Initialize-Terraform
        Test-Configuration
        
        switch ($Action) {
            "deploy" {
                New-DeploymentPlan
                Deploy
                Show-OutputDetails
            }
            "plan" {
                New-DeploymentPlan
            }
            "destroy" {
                Destroy-Deployment
            }
            "state" {
                Show-State
            }
            default {
                Write-Log "ERROR" "Unknown action: $Action"
                Write-Log "INFO" "Valid actions: deploy, plan, destroy, state"
                exit 1
            }
        }
    }
    
    Write-Log "SUCCESS" ""
    Write-Log "SUCCESS" "🎉 Deployment complete!"
    Write-Log "INFO" "Target: https://$Host"
}

# Run main function
Main
