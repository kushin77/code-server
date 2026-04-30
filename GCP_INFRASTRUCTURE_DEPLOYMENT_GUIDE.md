# GCP Infrastructure Deployment Guide

**Version:** 1.0  
**Date:** April 30, 2026  
**Status:** ✅ Production Ready  

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [GCP Setup](#gcp-setup)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [Integration with code-server](#integration-with-code-server)
7. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
8. [Architecture](#architecture)

---

## Overview

The GCP Infrastructure Deployment script (`scripts/ops/gcp-deploy.sh`) enables deploying code-server cluster infrastructure to Google Cloud Platform using the REST API directly via curl. This provides:

- **No CLI Dependency:** Uses curl and REST APIs instead of `gcloud` CLI
- **Kubernetes-Free:** Direct VM deployment to GCP Compute Engine
- **Phase 2b Integration:** Full parity validation for cross-region deployments
- **Complete IaC:** Infrastructure as Code via REST API
- **Multi-Zone Support:** Deploy to any GCP zone
- **Failover Ready:** Creates PRIMARY and REPLICA instances

### Key Features

✅ Service account authentication (JWT-based)  
✅ Dynamic image lookup (Ubuntu LTS)  
✅ Network and firewall configuration  
✅ Storage bucket creation  
✅ Instance lifecycle management (create/delete/status)  
✅ Operation polling and error handling  
✅ Structured logging  

---

## Prerequisites

### Local Requirements

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y curl jq openssl

# Verify installations
curl --version
jq --version
openssl version
```

### GCP Account Requirements

1. **Active GCP Project**
   - Project ID available
   - Billing enabled

2. **Service Account with Permissions**
   - Compute Instance Admin (roles/compute.instanceAdmin.v1)
   - Compute Security Admin (roles/compute.securityAdmin)
   - Storage Admin (roles/storage.admin)
   - Service Account Key (JSON format)

3. **API Enablement**
   ```bash
   # Enable required APIs in GCP
   gcloud services enable compute.googleapis.com
   gcloud services enable storage-api.googleapis.com
   ```

---

## GCP Setup

### Step 1: Create GCP Service Account

**Via Google Cloud Console:**

1. Go to: `https://console.cloud.google.com/iam-admin/serviceaccounts`
2. Click "Create Service Account"
3. Name: `code-server-deploy`
4. Grant roles:
   - Compute Instance Admin v1
   - Compute Security Admin
   - Storage Admin
5. Create key (JSON format)
6. Download JSON key file

**Via gcloud CLI:**

```bash
# Set your project
export GCP_PROJECT_ID="my-project-id"
gcloud config set project $GCP_PROJECT_ID

# Create service account
gcloud iam service-accounts create code-server-deploy \
  --display-name "Code Server Deployment Service Account"

# Grant roles
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create and download JSON key
gcloud iam service-accounts keys create code-server-key.json \
  --iam-account="code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Store securely
mkdir -p ~/.gcp
mv code-server-key.json ~/.gcp/
chmod 600 ~/.gcp/code-server-key.json
```

### Step 2: Enable Required APIs

```bash
gcloud services enable compute.googleapis.com
gcloud services enable storage-api.googleapis.com
```

### Step 3: Set Environment Variables

```bash
# Store in ~/.env.gcp or directly in shell
export GCP_PROJECT_ID="my-project-id"
export GCP_CREDENTIALS_JSON="$HOME/.gcp/code-server-key.json"
export GCP_ZONE="us-central1-a"          # Choose your zone
export GCP_MACHINE_TYPE="e2-standard-4"  # 4vCPU, 16GB RAM
export GCP_IMAGE_FAMILY="ubuntu-2204-lts" # Ubuntu 22.04 LTS
export DISK_SIZE_GB="100"
```

---

## Configuration

### Supported Zones

```bash
# Common US zones
us-central1-a, us-central1-b, us-central1-c
us-east1-b, us-east1-c, us-east1-d
us-west1-a, us-west1-b, us-west1-c

# Common Europe zones
europe-west1-b, europe-west1-c, europe-west1-d

# List all available zones
gcloud compute zones list
```

### Machine Types

```
e2-standard-2  : 2 vCPU, 8GB RAM   — Development
e2-standard-4  : 4 vCPU, 16GB RAM  — Recommended for code-server
e2-standard-8  : 8 vCPU, 32GB RAM  — High-performance clusters
e2-highmem-4   : 4 vCPU, 32GB RAM  — Memory-intensive workloads
```

### Image Families

```
ubuntu-2204-lts      : Ubuntu 22.04 LTS (Recommended)
ubuntu-2004-lts      : Ubuntu 20.04 LTS
debian-12            : Debian 12
centos-7             : CentOS 7
rhel-8               : RHEL 8
```

---

## Usage

### Basic Commands

```bash
# Source environment variables
source ~/.env.gcp

# Validate configuration
bash scripts/ops/gcp-deploy.sh validate

# List existing instances
bash scripts/ops/gcp-deploy.sh list

# Get instance status
bash scripts/ops/gcp-deploy.sh status

# Create new infrastructure
bash scripts/ops/gcp-deploy.sh create

# Delete infrastructure (WARNING: destructive)
bash scripts/ops/gcp-deploy.sh delete
```

### Example: Full Deployment

```bash
#!/bin/bash
set -e

# Setup
export GCP_PROJECT_ID="my-project-id"
export GCP_CREDENTIALS_JSON="$HOME/.gcp/code-server-key.json"
export GCP_ZONE="us-central1-a"
export GCP_MACHINE_TYPE="e2-standard-4"
export DISK_SIZE_GB="100"

cd /path/to/code-server

# 1. Validate configuration
echo "=== Validating GCP Configuration ==="
bash scripts/ops/gcp-deploy.sh validate

# 2. Create infrastructure
echo "=== Creating GCP Infrastructure ==="
bash scripts/ops/gcp-deploy.sh create

# 3. Wait for instances to boot
sleep 60

# 4. Get instance IPs
echo "=== Instance Status ==="
bash scripts/ops/gcp-deploy.sh status

# 5. Extract IP addresses
PRIMARY_IP=$(bash scripts/ops/gcp-deploy.sh status | \
  grep "code-server-primary" -A 1 | \
  grep "externalIP" | jq -r '.externalIP')

REPLICA_IP=$(bash scripts/ops/gcp-deploy.sh status | \
  grep "code-server-replica" -A 1 | \
  grep "externalIP" | jq -r '.externalIP')

echo "Primary: $PRIMARY_IP"
echo "Replica: $REPLICA_IP"

# 6. Deploy code-server to instances (manual or via Terraform)
# ...
```

### Output Examples

**validate command:**
```
[2026-04-30T12:00:00Z] [INFO] Validating prerequisites...
[2026-04-30T12:00:01Z] [SUCCESS] All prerequisites validated

Configuration:
  Project ID: my-project-id
  Zone: us-central1-a
  Machine Type: e2-standard-4
  Image Family: ubuntu-2204-lts
  Network: code-server-network
  Firewall Rule: code-server-firewall
```

**list command:**
```
code-server-primary    RUNNING    e2-standard-4    35.192.1.10
code-server-replica    RUNNING    e2-standard-4    35.192.1.11
```

**status command:**
```json
=== PRIMARY Instance ===
{
  "name": "code-server-primary",
  "status": "RUNNING",
  "machineType": "e2-standard-4",
  "zone": "us-central1-a",
  "externalIP": "35.192.1.10"
}

=== REPLICA Instance ===
{
  "name": "code-server-replica",
  "status": "RUNNING",
  "machineType": "e2-standard-4",
  "zone": "us-central1-a",
  "externalIP": "35.192.1.11"
}
```

---

## Integration with code-server

### Step 1: Deploy Instances

```bash
# Set environment variables
source ~/.env.gcp

# Create GCP infrastructure
bash scripts/ops/gcp-deploy.sh create

# Get IP addresses
bash scripts/ops/gcp-deploy.sh status
```

### Step 2: Update Terraform Variables

```bash
# Update terraform/environments/gcp/terraform.tfvars
cat > terraform/environments/gcp/terraform.tfvars <<EOF
gcp_project_id      = "my-project-id"
gcp_region          = "us-central1"
gcp_zone            = "us-central1-a"
primary_instance_ip = "35.192.1.10"
replica_instance_ip = "35.192.1.11"
EOF
```

### Step 3: Configure SSH Access

```bash
# Add SSH keys to instances (gcloud method)
gcloud compute instances add-metadata code-server-primary \
  --metadata-from-file=ssh-keys=~/.ssh/id_rsa.pub

gcloud compute instances add-metadata code-server-replica \
  --metadata-from-file=ssh-keys=~/.ssh/id_rsa.pub

# Test SSH connectivity
ssh -i ~/.ssh/id_rsa ubuntu@35.192.1.10
ssh -i ~/.ssh/id_rsa ubuntu@35.192.1.11
```

### Step 4: Clone code-server Repository

```bash
# On PRIMARY instance
ssh ubuntu@35.192.1.10 << 'EOF'
cd ~
git clone https://github.com/kushin77/code-server.git
cd code-server
mkdir -p code-server-enterprise
# Copy docker-compose and configuration files
EOF

# On REPLICA instance
ssh ubuntu@35.192.1.11 << 'EOF'
cd ~
git clone https://github.com/kushin77/code-server.git
cd code-server
mkdir -p code-server-enterprise
# Copy docker-compose and configuration files
EOF
```

### Step 5: Deploy via Terraform

```bash
# From local workstation
cd terraform/environments/gcp

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan.bin

# Apply deployment
terraform apply tfplan.bin
```

### Step 6: Validate Phase 2b Parity

```bash
# Set environment variables pointing to GCP instances
export PRIMARY_HOST="35.192.1.10"
export REPLICA_HOST="35.192.1.11"

# Run full deployment test
bash scripts/ops/full-deployment-test.sh --dry-run

# Expected: PASS/PASS/PASS/PASS/PASS/PASS
```

---

## Monitoring & Troubleshooting

### Common Issues

#### Issue 1: Authentication Failed

**Symptom:**
```
[ERROR] Failed to obtain access token
```

**Solution:**
```bash
# Verify service account credentials
jq '.client_email' ~/.gcp/code-server-key.json

# Verify environment variable
echo $GCP_CREDENTIALS_JSON

# Test authentication directly
bash scripts/ops/gcp-deploy.sh validate
```

#### Issue 2: Insufficient Permissions

**Symptom:**
```
[ERROR] Instance creation failed: ... insufficient permission ...
```

**Solution:**
```bash
# Re-grant roles to service account
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"
```

#### Issue 3: Network Connectivity

**Symptom:**
```
ssh: connect to host 35.192.1.10 port 22: Connection refused
```

**Solution:**
```bash
# Verify firewall rule
gcloud compute firewall-rules list

# Check instance status
bash scripts/ops/gcp-deploy.sh status

# Wait for instance to boot (can take 1-2 minutes)
sleep 120

# Retry SSH
ssh -i ~/.ssh/id_rsa ubuntu@35.192.1.10
```

#### Issue 4: Image Not Found

**Symptom:**
```
[ERROR] Image not found: ubuntu-2204-lts
```

**Solution:**
```bash
# List available images
gcloud compute images list --filter="family:ubuntu-2204"

# Update GCP_IMAGE_FAMILY variable
export GCP_IMAGE_FAMILY="ubuntu-2004-lts"
```

### Monitoring

```bash
# Monitor instance creation progress
watch -n 5 'bash scripts/ops/gcp-deploy.sh list'

# Check GCP logs
gcloud compute operations list

# Monitor compute resources
gcloud compute instances list

# Check firewall rules
gcloud compute firewall-rules list --filter="name:code-server-firewall"
```

---

## Architecture

### Network Topology

```
┌─────────────────────────────────────────┐
│     GCP Project (my-project-id)         │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   code-server-network (VPC)      │  │
│  │                                  │  │
│  │  ┌──────────────┐  ┌──────────┐ │  │
│  │  │  PRIMARY     │  │ REPLICA  │ │  │
│  │  │              │  │          │ │  │
│  │  │ e2-std-4     │  │ e2-std-4 │ │  │
│  │  │ 35.192.1.10  │  │35.192.1.11  │  │
│  │  │              │  │          │ │  │
│  │  └──────────────┘  └──────────┘ │  │
│  │                                  │  │
│  │  Firewall Rule: code-server-fw  │  │
│  │  - SSH (22)                     │  │
│  │  - HTTP (80)                    │  │
│  │  - HTTPS (443)                  │  │
│  │  - Services (8004, 8040, 8060)  │  │
│  │                                  │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Storage Bucket                  │  │
│  │  (my-project-id-artifacts)       │  │
│  │                                  │  │
│  │  - Compose files                 │  │
│  │  - Terraform state               │  │
│  │  - Deployment logs               │  │
│  └──────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

### Deployment Sequence

```
1. Validate Prerequisites
   ├─ Check curl, jq, openssl
   ├─ Verify GCP credentials
   └─ Confirm environment variables

2. Authenticate with GCP
   ├─ Create JWT from service account
   ├─ Exchange JWT for access token
   └─ Cache token (valid for 1 hour)

3. Create Infrastructure
   ├─ Create VPC network (code-server-network)
   ├─ Create firewall rule (code-server-firewall)
   ├─ Create storage bucket (artifacts)
   ├─ Lookup image (ubuntu-2204-lts)
   ├─ Create PRIMARY instance
   ├─ Create REPLICA instance
   ├─ Poll operations until DONE
   └─ Return instance IPs

4. Configure & Deploy
   ├─ SSH into PRIMARY instance
   ├─ Clone code-server repository
   ├─ Configure Docker Compose
   ├─ Deploy containers
   ├─ Repeat for REPLICA
   └─ Validate Phase 2b parity

5. Integration & Operations
   ├─ Register instances with Terraform
   ├─ Configure monitoring
   ├─ Setup alerting
   └─ Enable Phase 2b validation
```

---

## Security Considerations

### Service Account Security

```bash
# Rotate service account key regularly
gcloud iam service-accounts keys create new-key.json \
  --iam-account="code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Delete old key
gcloud iam service-accounts keys delete OLD_KEY_ID \
  --iam-account="code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Restrict key file permissions
chmod 600 ~/.gcp/code-server-key.json
```

### Network Security

```bash
# Restrict source IPs in firewall rule (optional)
gcloud compute firewall-rules update code-server-firewall \
  --source-ranges="YOUR.IP.ADDRESS/32"

# Use OS Login for SSH access
gcloud compute project-info describe --format='value(commonInstanceMetadata.items[oslogin])'
```

### Monitoring & Auditing

```bash
# Enable Cloud Audit Logs
gcloud compute project-info add-metadata \
  --metadata=enable-oslogin=TRUE

# View audit logs
gcloud logging read "resource.type=gce_instance" --limit 20
```

---

## Cost Optimization

### Recommended Configuration

```bash
# Development environment
export GCP_MACHINE_TYPE="e2-standard-2"  # $30/month per instance
export DISK_SIZE_GB="50"

# Production environment
export GCP_MACHINE_TYPE="e2-standard-4"  # $60/month per instance
export DISK_SIZE_GB="100"
```

### Cost Estimation

| Component | Quantity | Unit Cost | Monthly |
|-----------|----------|-----------|---------|
| e2-standard-4 VM | 2 | $0.08/hr | $120 |
| 100GB Disk | 2 | $0.04/GB | $8 |
| Storage Bucket | 1 | $0.020/GB | $1-10 |
| Network Egress | 1TB | $0.12/GB | $120 |
| **Total** | - | - | **~$250-270** |

### Cost Reduction Tips

1. Use preemptible instances for development: $0.024/hr (70% discount)
2. Use committed discounts for 1-3 year terms: 25-52% savings
3. Set up auto-shutdown for unused instances
4. Use persistent disks only for data, not OS

---

## Next Steps

1. ✅ Create GCP service account with credentials
2. ✅ Set environment variables
3. ✅ Run `bash scripts/ops/gcp-deploy.sh validate`
4. ✅ Deploy infrastructure: `bash scripts/ops/gcp-deploy.sh create`
5. ✅ Configure SSH access to instances
6. ✅ Deploy code-server via Terraform
7. ✅ Validate Phase 2b parity
8. ✅ Setup monitoring and alerting

---

## References

- [GCP Compute API Documentation](https://cloud.google.com/compute/docs)
- [GCP OAuth 2.0 with Service Accounts](https://cloud.google.com/docs/authentication/production)
- [code-server Phase 2b Parity](PHASE_2B_MASTER_DEPLOYMENT_GUIDE.md)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

---

**Status:** ✅ Production Ready  
**Last Updated:** April 30, 2026  
**Maintainer:** Infrastructure Team

