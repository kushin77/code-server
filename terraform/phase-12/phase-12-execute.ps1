# Phase 12 Execution Script - Multi-Region Federation Setup (PowerShell)
# Usage: .\phase-12-execute.ps1 -Command validate|plan|apply|destroy
# Date: April 13, 2026

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('validate', 'plan', 'apply', 'destroy')]
    [string]$Command = 'validate',
    
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentFile = 'terraform.tfvars',
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove = $false
)

# Configuration
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = "logs/phase-12-execution-${timestamp}.log"
$projectName = 'code-server-enterprise'
$phase = '12'

# Ensure logs directory exists
$logsDir = Split-Path -Path $logFile
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir | Out-Null
}

# Logging functions
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    switch ($Level) {
        'Info' {
            $output = "[INFO] $timestamp - $Message"
            Write-Host $output -ForegroundColor Blue
        }
        'Warning' {
            $output = "[WARNING] $timestamp - $Message"
            Write-Host $output -ForegroundColor Yellow
        }
        'Error' {
            $output = "[ERROR] $timestamp - $Message"
            Write-Host $output -ForegroundColor Red
        }
        'Success' {
            $output = "[SUCCESS] $timestamp - $Message"
            Write-Host $output -ForegroundColor Green
        }
    }
    
    Add-Content -Path $logFile -Value $output
}

# Preflight checks
function Invoke-PreflightCheck {
    Write-Log "Running pre-flight checks..."
    
    # Check for required tools
    $requiredTools = @('aws', 'terraform', 'jq')
    foreach ($tool in $requiredTools) {
        try {
            $cmd = Get-Command $tool -ErrorAction Stop
            Write-Log "✓ $tool is available: $($cmd.Source)" -Level Success
        }
        catch {
            Write-Log "$tool is not installed. Please install it before proceeding." -Level Error
            exit 1
        }
    }
    
    # Check AWS credentials
    try {
        $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
        Write-Log "✓ AWS credentials verified" -Level Success
        Write-Log "  Account: $($identity.Account)"
        Write-Log "  User: $($identity.Arn)"
    }
    catch {
        Write-Log "AWS credentials not configured. Please run 'aws configure'" -Level Error
        exit 1
    }
    
    # Check Terraform version
    try {
        $tfVersion = terraform version -json | ConvertFrom-Json
        Write-Log "✓ Terraform version: $($tfVersion.terraform_version)" -Level Success
    }
    catch {
        Write-Log "Failed to get Terraform version" -Level Error
        exit 1
    }
    
    # Check terraform.tfvars
    if (-not (Test-Path $EnvironmentFile)) {
        Write-Log "terraform.tfvars not found. Please copy terraform.tfvars.example and update values" -Level Error
        exit 1
    }
    
    $content = Get-Content $EnvironmentFile -Raw
    if ($content -match 'PLACEHOLDER') {
        Write-Log "terraform.tfvars contains PLACEHOLDER values. Please update with actual AWS IDs" -Level Error
        exit 1
    }
    
    Write-Log "✓ terraform.tfvars is configured" -Level Success
}

# Validate configuration
function Invoke-Validate {
    Write-Log "Validating Terraform configuration..."
    
    # Initialize Terraform
    Write-Log "Initializing Terraform..."
    terraform init
    
    # Validate syntax
    Write-Log "Validating Terraform syntax..."
    terraform validate
    
    # Format check
    Write-Log "Checking Terraform formatting..."
    $formatResult = terraform fmt -check -recursive . 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Some files need formatting" -Level Warning
    } else {
        Write-Log "✓ All files properly formatted" -Level Success
    }
    
    Write-Log "✓ Terraform configuration is valid" -Level Success
}

# Plan deployment
function Invoke-Plan {
    Write-Log "Planning Terraform deployment..."
    
    # Generate plan
    $planFile = "phase-12-${timestamp}.tfplan"
    Write-Log "Generating plan: $planFile"
    
    terraform plan -out=$planFile
    
    # Get plan summary
    $planJson = terraform show -json $planFile | ConvertFrom-Json
    $resourceCount = $planJson.resource_changes.Length
    
    Write-Log "Plan Summary:" -Level Info
    Write-Log "  File: $planFile" -Level Info
    Write-Log "  Resources to create/modify: $resourceCount" -Level Info
    
    # Show plan details
    Write-Log "`nResource changes:" -Level Info
    $planJson.resource_changes | ForEach-Object {
        $action = $_.change.actions[0]
        $address = $_.address
        Write-Log "  $action $address" -Level Info
    }
    
    if (-not $AutoApprove) {
        $response = Read-Host "`nContinue with apply? (yes/no)"
        if ($response -eq 'yes') {
            Invoke-Apply -PlanFile $planFile
        } else {
            Write-Log "Plan cancelled by user" -Level Warning
            Remove-Item $planFile -Force
        }
    } else {
        Invoke-Apply -PlanFile $planFile
    }
}

# Apply deployment
function Invoke-Apply {
    param(
        [Parameter(Mandatory=$true)]
        [string]$PlanFile
    )
    
    Write-Log "Applying Terraform plan: $PlanFile"
    
    terraform apply -input=false $PlanFile
    
    # Save outputs
    Write-Log "Saving Terraform outputs..."
    $outputFile = "phase-12-outputs-${timestamp}.json"
    terraform output -json | Out-File $outputFile
    
    Write-Log "✓ Phase 12.1 Infrastructure deployment completed!" -Level Success
    Write-Log "Outputs saved to: $outputFile" -Level Info
    
    # Print important outputs
    Write-Log "`nImportant endpoints:" -Level Info
    $outputs = terraform output -json | ConvertFrom-Json
    $outputs.PSObject.Properties | ForEach-Object {
        Write-Log "  $($_.Name): $($_.Value.value)" -Level Info
    }
}

# Validate deployment
function Invoke-ValidateDeployment {
    Write-Log "Validating Phase 12.1 deployment..."
    
    $regions = @{
        'primary'   = 'us-east-1'
        'secondary' = 'us-west-2'
        'tertiary'  = 'eu-west-1'
    }
    
    foreach ($regionName in $regions.Keys) {
        $region = $regions[$regionName]
        Write-Log "Checking region: $regionName ($region)"
        
        # Get VPC info
        try {
            $vpc = aws ec2 describe-vpcs `
                --region $region `
                --filters "Name=tag:Phase,Values=12" `
                --query "Vpcs[0].VpcId" `
                --output text
            
            if ($vpc -and $vpc -ne 'None') {
                Write-Log "  ✓ VPC: $vpc" -Level Success
            } else {
                Write-Log "  VPC not found in $region" -Level Warning
            }
        }
        catch {
            Write-Log "  Error checking VPC in $region: $_" -Level Warning
        }
    }
    
    Write-Log "✓ Deployment validation completed" -Level Success
}

# Destroy infrastructure (DANGEROUS)
function Invoke-Destroy {
    Write-Log "⚠️  WARNING: This will DESTROY all Phase 12 infrastructure" -Level Warning
    Write-Log "This action cannot be undone!" -Level Warning
    
    $confirmation = Read-Host "Type 'DESTROY_PHASE_12' to confirm"
    if ($confirmation -eq 'DESTROY_PHASE_12') {
        Write-Log "Destroying Phase 12 infrastructure..."
        terraform destroy -auto-approve
        Write-Log "✓ Infrastructure destroyed" -Level Success
    } else {
        Write-Log "Destroy cancelled" -Level Warning
    }
}

# Main execution
function Main {
    Write-Log "=========================================="
    Write-Log "Phase 12 Execution Script"
    Write-Log "Project: $projectName"
    Write-Log "Phase: $phase"
    Write-Log "Command: $Command"
    Write-Log "=========================================="
    
    # Always run preflight checks first
    Invoke-PreflightCheck
    
    switch ($Command) {
        'validate' {
            Invoke-Validate
        }
        'plan' {
            Invoke-Validate
            Invoke-Plan
        }
        'apply' {
            Invoke-Validate
            Invoke-Plan
        }
        'destroy' {
            Invoke-Destroy
        }
        default {
            Write-Log "Unknown command: $Command" -Level Error
            exit 1
        }
    }
    
    Write-Log "=========================================="
    Write-Log "Phase 12 execution script completed"
    Write-Log "Log file: $logFile"
    Write-Log "=========================================="
}

# Run main function
Main
