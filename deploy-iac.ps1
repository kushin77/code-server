#!/usr/bin/env pwsh

# Code-Server Enterprise IaC Deployment (PowerShell)
# Works on Windows, macOS, Linux with PowerShell 7+

param(
    [string]$Action = "deploy",  # deploy, destroy, plan, state
    [switch]$Verbose = $false,
    [switch]$DryRun = $false
)

# Configuration
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "code-server-enterprise"
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
    Write-Log "INFO" "  1. Open browser: http://localhost"
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
    Write-Log "INFO" "Starting Code-Server Enterprise IaC Deployment"
    Write-Log "INFO" "Log file: $logFile"
    Write-Log "INFO" "Action: $Action"
    Write-Log "INFO" ""
    
    Test-Prerequisites
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
    
    Write-Log "SUCCESS" ""
    Write-Log "SUCCESS" "🎉 IaC deployment complete!"
}

# Run main function
Main
