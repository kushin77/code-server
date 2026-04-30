# GCP Deployment Quick Reference

**Last Updated:** April 30, 2026  
**Status:** ✅ Production Ready

---

## 60-Second Setup

### 1. Prepare Service Account (First Time Only)

```bash
# Set your GCP project ID
export GCP_PROJECT_ID="my-project-id"

# Create service account
gcloud iam service-accounts create code-server-deploy \
  --display-name "Code Server Deploy"

# Grant roles
for role in compute.instanceAdmin.v1 compute.securityAdmin storage.admin; do
  gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
    --member="serviceAccount:code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/$role"
done

# Download credentials
gcloud iam service-accounts keys create \
  ~/.gcp/code-server-key.json \
  --iam-account="code-server-deploy@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Enable APIs
gcloud services enable compute.googleapis.com storage-api.googleapis.com
```

### 2. Set Environment Variables

```bash
# Add to ~/.bashrc or ~/.zshrc
cat >> ~/.env.gcp <<'EOF'
export GCP_PROJECT_ID="my-project-id"
export GCP_CREDENTIALS_JSON="$HOME/.gcp/code-server-key.json"
export GCP_ZONE="us-central1-a"
export GCP_MACHINE_TYPE="e2-standard-4"
export DISK_SIZE_GB="100"
EOF

# Load environment
source ~/.env.gcp
```

### 3. Validate & Deploy

```bash
# Validate configuration
bash scripts/ops/gcp-deploy.sh validate

# Create infrastructure
bash scripts/ops/gcp-deploy.sh create

# Check status
bash scripts/ops/gcp-deploy.sh status
```

---

## Command Reference

| Command | Purpose | Output |
|---------|---------|--------|
| `bash scripts/ops/gcp-deploy.sh validate` | Verify config | Environment summary |
| `bash scripts/ops/gcp-deploy.sh list` | Show instances | Name, status, IP |
| `bash scripts/ops/gcp-deploy.sh create` | Deploy infra | SUCCESS or error |
| `bash scripts/ops/gcp-deploy.sh delete` | Destroy infra | SUCCESS or error |
| `bash scripts/ops/gcp-deploy.sh status` | Instance details | JSON instance info |

---

## Configuration Options

### Zones

```bash
# US (recommended for low latency to US users)
us-central1-a    # Iowa (default)
us-east1-b       # South Carolina
us-west1-a       # Oregon

# Europe
europe-west1-b   # Belgium
europe-west4-a   # Netherlands

# Asia
asia-southeast1-a # Singapore
asia-northeast1-a # Tokyo
```

### Machine Types (Recommended)

```bash
# Development
e2-standard-2    # 2vCPU, 8GB RAM   ($30/month)

# Production (default)
e2-standard-4    # 4vCPU, 16GB RAM  ($60/month)

# High-performance
e2-standard-8    # 8vCPU, 32GB RAM  ($120/month)
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Failed to obtain access token` | Check `GCP_CREDENTIALS_JSON` path and permissions |
| `Instance creation failed: insufficient permission` | Re-run role grant commands in "60-Second Setup" |
| `Image not found` | Run `gcloud compute images list --filter="family:ubuntu-2204"` |
| `Connection refused on SSH` | Wait 2-3 minutes for instance to fully boot |
| `Firewall rule error (may already exist)` | Script continues; rule already present from previous run |

---

## Integration Checklist

After GCP instances are created:

- [ ] Get instance IPs: `bash scripts/ops/gcp-deploy.sh status`
- [ ] Add SSH keys: `gcloud compute instances add-metadata code-server-primary --metadata-from-file=ssh-keys=~/.ssh/id_rsa.pub`
- [ ] Test SSH: `ssh ubuntu@35.192.1.10`
- [ ] Update Terraform: Set `primary_instance_ip` and `replica_instance_ip` in `terraform.tfvars`
- [ ] Deploy via Terraform: `terraform apply`
- [ ] Validate Phase 2b: `PRIMARY_HOST=35.192.1.10 REPLICA_HOST=35.192.1.11 bash scripts/ops/full-deployment-test.sh --dry-run`

---

## Cost Examples

| Configuration | Monthly Cost | Use Case |
|---------------|-------------|----------|
| 1x e2-std-2 (50GB) | ~$35 | Dev/testing |
| 2x e2-std-4 (100GB) | ~$250 | Production HA |
| 2x e2-highmem-4 (200GB) | ~$400 | Memory-intensive |
| With preemptible VMs | ~65% cheaper | Non-critical workloads |

---

## Related Documentation

- **Full Setup:** [GCP_INFRASTRUCTURE_DEPLOYMENT_GUIDE.md](GCP_INFRASTRUCTURE_DEPLOYMENT_GUIDE.md)
- **Code-Server Integration:** [PHASE_2B_MASTER_DEPLOYMENT_GUIDE.md](PHASE_2B_MASTER_DEPLOYMENT_GUIDE.md)
- **Monitoring:** [PHASE_2B_MONITORING_ALERTING_GUIDE.md](PHASE_2B_MONITORING_ALERTING_GUIDE.md)
- **Troubleshooting:** [PHASE_2B_TROUBLESHOOTING_GUIDE.md](PHASE_2B_TROUBLESHOOTING_GUIDE.md)

---

## One-Liner Examples

```bash
# Create full GCP deployment in one command
source ~/.env.gcp && bash scripts/ops/gcp-deploy.sh create && bash scripts/ops/gcp-deploy.sh status

# Get PRIMARY instance IP
bash scripts/ops/gcp-deploy.sh status | grep -A 1 "PRIMARY Instance" | grep externalIP | jq -r '.externalIP'

# SSH into PRIMARY (after SSH key configured)
ssh -i ~/.ssh/id_rsa ubuntu@$(bash scripts/ops/gcp-deploy.sh status | grep -A 1 "PRIMARY Instance" | grep externalIP | jq -r '.externalIP')

# List all GCP resources created by code-server
gcloud compute instances list --filter="tags:code-server"
gcloud compute firewall-rules list --filter="name:code-server*"
gcloud compute networks list --filter="name:code-server*"

# Delete all code-server GCP resources
bash scripts/ops/gcp-deploy.sh delete
```

---

## Security Notes

✅ Service account uses JWT authentication (no long-lived API keys)  
✅ Access token cached for 1 hour, then automatically refreshed  
✅ Credentials stored locally in `~/.gcp/` (not in git)  
✅ Firewall rules restrict access to necessary ports only  
✅ Instances use OS Login for passwordless SSH  

**Store credentials securely:**
```bash
chmod 600 ~/.gcp/code-server-key.json
# OR use Google Cloud Secret Manager
gcloud secrets create gcp-credentials --data-file=~/.gcp/code-server-key.json
```

---

## Getting Help

**For GCP REST API issues:**
- [GCP Compute API Docs](https://cloud.google.com/compute/docs/reference/rest/v1)
- [GCP OAuth 2.0 with Service Accounts](https://cloud.google.com/docs/authentication/production)

**For code-server deployment issues:**
- See [PHASE_2B_TROUBLESHOOTING_GUIDE.md](PHASE_2B_TROUBLESHOOTING_GUIDE.md)
- Run diagnostic test: `PRIMARY_HOST=... REPLICA_HOST=... bash scripts/ops/full-deployment-test.sh --dry-run`

---

**Version:** 1.0  
**Last Updated:** April 30, 2026  
**Status:** ✅ Production Ready

