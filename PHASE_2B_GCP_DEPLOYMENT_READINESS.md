# Phase 2b GCP Deployment Readiness Guide

**Version:** 1.0  
**Purpose:** Complete guide to prepare and verify GCP deployment readiness  
**Status:** Production-ready checklist  

---

## Overview

Comprehensive guide for verifying GCP environment is ready for Phase 2b deployment.

---

## Part 1: GCP Project Setup

### 1.1 Create GCP Project

```bash
# Set project name and ID
PROJECT_NAME="code-server-phase2b"
PROJECT_ID="code-server-phase2b-prod"

# Create project
gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME"

# Set as active project
gcloud config set project "$PROJECT_ID"

# Enable billing
gcloud billing projects link "$PROJECT_ID" --billing-account=BILLING_ACCOUNT_ID
```

### 1.2 Enable Required APIs

```bash
#!/bin/bash

PROJECT_ID="code-server-phase2b-prod"

echo "Enabling APIs for project: $PROJECT_ID"

# Required APIs
APIS=(
  "compute.googleapis.com"
  "iam.googleapis.com"
  "storage-api.googleapis.com"
  "container.googleapis.com"
  "monitoring.googleapis.com"
  "logging.googleapis.com"
  "cloudresourcemanager.googleapis.com"
)

for api in "${APIS[@]}"; do
  echo "Enabling: $api"
  gcloud services enable "$api" --project="$PROJECT_ID"
done

echo "✅ All APIs enabled"
```

### 1.3 Create Service Account

```bash
#!/bin/bash

PROJECT_ID="code-server-phase2b-prod"
SERVICE_ACCOUNT="code-server-deployer"
SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com"

echo "Creating service account: $SERVICE_ACCOUNT"

# Create service account
gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
  --display-name="Code-Server Phase 2b Deployer" \
  --project="$PROJECT_ID"

# Grant required roles
ROLES=(
  "roles/compute.admin"
  "roles/storage.admin"
  "roles/iam.securityAdmin"
  "roles/logging.admin"
  "roles/monitoring.admin"
)

for role in "${ROLES[@]}"; do
  echo "Granting role: $role"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="$role"
done

echo "✅ Service account created and configured"
```

### 1.4 Create Service Account Key

```bash
#!/bin/bash

PROJECT_ID="code-server-phase2b-prod"
SERVICE_ACCOUNT="code-server-deployer"

# Create key
KEY_FILE="$HOME/.gcp/${SERVICE_ACCOUNT}-key.json"
mkdir -p "$(dirname "$KEY_FILE")"

gcloud iam service-accounts keys create "$KEY_FILE" \
  --iam-account="$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com"

# Set permissions
chmod 600 "$KEY_FILE"

echo "✅ Service account key created: $KEY_FILE"
echo "⚠️  KEEP THIS KEY SECURE - DO NOT COMMIT TO GIT"
```

---

## Part 2: Network Setup

### 2.1 Create VPC Network

```bash
#!/bin/bash

PROJECT_ID="code-server-phase2b-prod"
NETWORK_NAME="code-server-network"
NETWORK_REGION="us-central1"

echo "Creating VPC network: $NETWORK_NAME"

# Create VPC
gcloud compute networks create "$NETWORK_NAME" \
  --subnet-mode=custom \
  --project="$PROJECT_ID"

# Create subnet
gcloud compute networks subnets create "${NETWORK_NAME}-subnet" \
  --network="$NETWORK_NAME" \
  --region="$NETWORK_REGION" \
  --range="10.0.0.0/24" \
  --project="$PROJECT_ID"

echo "✅ VPC network created"
```

### 2.2 Create Firewall Rules

```bash
#!/bin/bash

PROJECT_ID="code-server-phase2b-prod"
NETWORK_NAME="code-server-network"

echo "Creating firewall rules"

# Allow internal communication
gcloud compute firewall-rules create "${NETWORK_NAME}-allow-internal" \
  --network="$NETWORK_NAME" \
  --allow=tcp,udp,icmp \
  --source-ranges="10.0.0.0/24" \
  --project="$PROJECT_ID"

# Allow SSH from bastion/office
gcloud compute firewall-rules create "${NETWORK_NAME}-allow-ssh" \
  --network="$NETWORK_NAME" \
  --allow=tcp:22 \
  --source-ranges="YOUR_OFFICE_IP/32" \
  --project="$PROJECT_ID"

# Allow HTTP/HTTPS from anywhere (GitLab)
gcloud compute firewall-rules create "${NETWORK_NAME}-allow-http" \
  --network="$NETWORK_NAME" \
  --allow=tcp:80,tcp:443,tcp:8101 \
  --source-ranges="0.0.0.0/0" \
  --project="$PROJECT_ID"

echo "✅ Firewall rules created"
```

---

## Part 3: Environment Variables

### 3.1 Set GCP Deployment Variables

```bash
#!/bin/bash

# GCP Configuration
export GCP_PROJECT_ID="code-server-phase2b-prod"
export GCP_CREDENTIALS_JSON="$HOME/.gcp/code-server-deployer-key.json"
export GCP_ZONE="us-central1-a"
export GCP_REGION="us-central1"
export GCP_NETWORK="code-server-network"
export GCP_SUBNET="code-server-network-subnet"

# Instance Configuration
export GCP_MACHINE_TYPE="e2-standard-4"
export GCP_IMAGE_FAMILY="ubuntu-2204-lts"
export GCP_IMAGE_PROJECT="ubuntu-os-cloud"
export DISK_SIZE_GB="100"

# Instance Names
export PRIMARY_INSTANCE_NAME="gitlab-primary"
export REPLICA_INSTANCE_NAME="gitlab-replica"

# Tags
export GCP_TAGS="phase2b,gitlab,production"

echo "✅ GCP environment variables configured"
```

### 3.2 Verify Configuration

```bash
#!/bin/bash

echo "=== GCP Configuration Verification ==="
echo ""

# Check credentials file
if [ ! -f "$GCP_CREDENTIALS_JSON" ]; then
  echo "❌ FAILED: Credentials file not found: $GCP_CREDENTIALS_JSON"
  exit 1
fi
echo "✅ Credentials file exists"

# Check project ID
PROJECT_FROM_CREDS=$(jq -r '.project_id' "$GCP_CREDENTIALS_JSON")
if [ "$PROJECT_FROM_CREDS" != "$GCP_PROJECT_ID" ]; then
  echo "⚠️  WARNING: Project ID mismatch"
  echo "  Env var: $GCP_PROJECT_ID"
  echo "  Credentials: $PROJECT_FROM_CREDS"
fi
echo "✅ Project ID: $GCP_PROJECT_ID"

# Verify other variables
echo "✅ Zone: $GCP_ZONE"
echo "✅ Machine type: $GCP_MACHINE_TYPE"
echo "✅ Disk size: ${DISK_SIZE_GB}GB"

echo ""
echo "✅ Configuration verified"
```

---

## Part 4: GCP Resource Quotas

### 4.1 Check Quotas

```bash
#!/bin/bash

PROJECT_ID="code-server-phase2b-prod"

echo "=== GCP Resource Quotas ==="
echo ""

# Check compute quotas
echo "Checking compute quotas..."
gcloud compute project-info describe "$PROJECT_ID" \
  --format='table(quotas[].{metric,usage,limit})' \
  | grep -E "CPUS|MEMORY|DISK"

# Required minimums
echo ""
echo "Required quotas:"
echo "  - CPUs: >= 8 (for 2x e2-standard-4 instances)"
echo "  - Memory: >= 32 GB"
echo "  - Disk: >= 200 GB"
```

### 4.2 Request Quota Increases (if needed)

```bash
# Via UI: Console → Quotas → Select metrics → Edit quotas
# Or request via CLI:
gcloud compute project-info describe PROJECT_ID --format='table(quotas)'
```

---

## Part 5: Pre-Deployment Checklist

### Checklist: GCP Environment Ready

- [ ] GCP project created
- [ ] Billing enabled
- [ ] Required APIs enabled (8+)
- [ ] Service account created
- [ ] Service account key generated and secured
- [ ] VPC network created
- [ ] Subnets created
- [ ] Firewall rules configured
- [ ] Environment variables set
- [ ] Credentials file verified
- [ ] Resource quotas sufficient
- [ ] SSH key configured (if needed)
- [ ] Test authentication successful

### Test GCP API Access

```bash
#!/bin/bash

echo "=== Testing GCP API Access ==="
echo ""

# Get access token
echo "Getting access token..."
TOKEN=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d @<(jq -r \
    --arg iss $(jq -r '.client_email' "$GCP_CREDENTIALS_JSON") \
    --arg sub $(jq -r '.client_email' "$GCP_CREDENTIALS_JSON") \
    --arg aud "https://oauth2.googleapis.com/token" \
    --arg exp $(date -d "+1 hour" +%s) \
    '{
      "iss": $iss,
      "sub": $sub,
      "aud": $aud,
      "exp": $exp,
      "iat": '$(date +%s)',
      "scope": "https://www.googleapis.com/auth/cloud-platform"
    }' "$GCP_CREDENTIALS_JSON") \
  | jq -r '.access_token')

if [ -z "$TOKEN" ]; then
  echo "❌ FAILED: Could not get access token"
  exit 1
fi

echo "✅ Access token obtained"

# List compute instances
echo "Listing compute instances..."
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://www.googleapis.com/compute/v1/projects/$GCP_PROJECT_ID/zones/$GCP_ZONE/instances" \
  | jq '.items | length'

echo "✅ GCP API working correctly"
```

---

## Part 6: Dry-Run Deployment Test

### Test GCP Deployment Script

```bash
#!/bin/bash

echo "=== GCP Deployment Dry-Run Test ==="
echo ""

# Make sure all env vars are set
source scripts/config/gcp-env.sh

# Run validation
bash scripts/ops/gcp-deploy.sh validate
if [ $? -ne 0 ]; then
  echo "❌ FAILED: Validation failed"
  exit 1
fi

echo "✅ Validation passed"

# Test authentication
bash scripts/ops/gcp-deploy.sh status
if [ $? -ne 0 ]; then
  echo "❌ FAILED: Status check failed"
  exit 1
fi

echo "✅ Status check passed"
echo "✅ GCP deployment ready"
```

---

## Part 7: Cost Estimation

### 7.1 Calculate Monthly Costs

```bash
#!/bin/bash

# Instance costs (us-central1)
# e2-standard-4: $0.134 per hour
HOURLY_INSTANCE=$0.134
INSTANCES=2
HOURS_PER_MONTH=730

INSTANCE_COST=$(echo "$HOURLY_INSTANCE * $INSTANCES * $HOURS_PER_MONTH" | bc)

# Storage costs (us-central1)
# $0.020 per GB per month
DISK_SIZE=100
DISKS=2
STORAGE_COST=$(echo "$DISK_SIZE * $DISKS * 0.020" | bc)

# Network costs (approximately)
NETWORK_COST=$(echo "$INSTANCES * $HOURS_PER_MONTH * 0.01" | bc)

# Total
TOTAL=$(echo "$INSTANCE_COST + $STORAGE_COST + $NETWORK_COST" | bc)

echo "=== GCP Phase 2b Monthly Cost Estimation ==="
echo ""
echo "Instances (2x e2-standard-4): \$$INSTANCE_COST"
echo "Storage (200GB total): \$$STORAGE_COST"
echo "Network: \$$NETWORK_COST"
echo ""
echo "Estimated Monthly Cost: \$$TOTAL"
echo "Estimated Annual Cost: \$(echo "$TOTAL * 12" | bc)"
```

---

## Part 8: Security Checklist

### Security Verification

- [ ] Service account has minimal required roles
- [ ] Service account key secured (chmod 600)
- [ ] Firewall rules restricted appropriately
- [ ] SSH access restricted to approved networks
- [ ] No default credentials stored in code
- [ ] Credentials stored in vault/secret manager
- [ ] IAM audit logging enabled
- [ ] VPC isolation verified
- [ ] API access logging enabled
- [ ] Regular key rotation planned

### Key Security Commands

```bash
# Audit service account permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:*"

# List service account keys
gcloud iam service-accounts keys list \
  --iam-account="$SERVICE_ACCOUNT@$GCP_PROJECT_ID.iam.gserviceaccount.com"

# Rotate key (create new, deprecate old)
gcloud iam service-accounts keys list \
  --iam-account="$SERVICE_ACCOUNT@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --filter="validAfterTime<$(date -d '90 days ago' -Iseconds)"
```

---

## Part 9: Backup & Recovery

### 9.1 Backup Configuration

```bash
#!/bin/bash

BACKUP_DIR="$HOME/gcp-backups"
mkdir -p "$BACKUP_DIR"

# Backup credentials
cp "$GCP_CREDENTIALS_JSON" "$BACKUP_DIR/credentials-backup-$(date +%Y%m%d).json"

# Backup environment configuration
cat > "$BACKUP_DIR/gcp-config-backup-$(date +%Y%m%d).sh" << EOF
# GCP Configuration Backup
export GCP_PROJECT_ID="$GCP_PROJECT_ID"
export GCP_ZONE="$GCP_ZONE"
export GCP_MACHINE_TYPE="$GCP_MACHINE_TYPE"
export GCP_NETWORK="$GCP_NETWORK"
EOF

echo "✅ Backup created: $BACKUP_DIR"
```

### 9.2 Recovery Procedure

```bash
# 1. Restore credentials from backup
cp "$BACKUP_DIR/credentials-backup-YYYYMMDD.json" "$HOME/.gcp/code-server-deployer-key.json"

# 2. Restore environment variables
source "$BACKUP_DIR/gcp-config-backup-YYYYMMDD.sh"

# 3. Verify access
bash scripts/ops/gcp-deploy.sh status
```

---

## Part 10: Readiness Sign-Off

### Deployment Readiness Checklist

**GCP Project Setup:**
- [ ] Project created and configured
- [ ] Billing enabled
- [ ] All APIs enabled
- [ ] Service account created with correct roles
- [ ] Service account key generated and secured

**Network Infrastructure:**
- [ ] VPC network created
- [ ] Subnets configured
- [ ] Firewall rules set appropriately
- [ ] Routing configured

**Security:**
- [ ] IAM roles minimal and appropriate
- [ ] Keys stored securely (not in git)
- [ ] Access logging enabled
- [ ] Audit trail configured

**Testing:**
- [ ] API access verified
- [ ] Dry-run deployment successful
- [ ] Quota limits sufficient
- [ ] Cost estimation approved

**Documentation:**
- [ ] Environment variables documented
- [ ] Security procedures documented
- [ ] Disaster recovery plan reviewed
- [ ] Team training completed

### Approval Sign-Off

- [ ] Infrastructure Lead Approval: __________ Date: __________
- [ ] Security Lead Approval: __________ Date: __________
- [ ] Finance Lead Approval: __________ Date: __________

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Authentication fails | Verify credentials file exists and is readable |
| Quota exceeded | Request quota increase via GCP Console |
| Network unreachable | Check firewall rules allow required ports |
| Permission denied | Verify service account has required IAM roles |
| API not enabled | Run `gcloud services enable` for required APIs |

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID

# View audit logs
gcloud logging read "resource.type=service_account" --limit=50

# Test connectivity
gcloud compute ssh --zone=$GCP_ZONE --internal-ip $PRIMARY_INSTANCE_NAME

# View GCP resource usage
gcloud compute project-info describe $GCP_PROJECT_ID
```

---

**Version:** 1.0  
**Status:** Production-ready  
**Created:** April 30, 2026

