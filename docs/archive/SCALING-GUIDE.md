# Infrastructure Scaling & Host Migration Guide

## Overview

The code-server-enterprise infrastructure is now parameterized for easy scaling. When you outgrow the current host (`192.168.168.31`) or need to migrate, you don't need to modify application code — just update Terraform variables.

---

## Quick Scale Scenario

**Current State:** Single host at `192.168.168.31`  
**Future Need:** Expand to `192.168.168.32` (or any new host)

### Step 1: Prepare New Host

```bash
# On new host (e.g., 192.168.168.32)
sudo apt-get update
sudo apt-get install -y docker.io docker-compose git

# Add SSH user (if needed)
sudo useradd -m -s /bin/bash akushnir  # Or your deployment_user
sudo usermod -aG docker akushnir

# Clone repository
git clone https://github.com/kushin77/code-server-enterprise.git
cd code-server-enterprise
```

### Step 2: Update Terraform Variables

```bash
# On your Windows/local machine where you run Terraform
cd c:\code-server-enterprise

# Edit terraform.tfvars (or create if doesn't exist)
cp terraform.tfvars.example terraform.tfvars
```

**Before (current):**
```hcl
deployment_host = "192.168.168.31"
deployment_user = "akushnir"
deployment_port = 22
```

**After (new host):**
```hcl
deployment_host = "192.168.168.32"  # ← Change this
deployment_user = "akushnir"
deployment_port = 22
```

### Step 3: Plan & Apply Infrastructure Changes

```bash
# Preview what will change
terraform plan -out=tfplan

# Review output - should show deployment_host in new values
# Then apply
terraform apply tfplan
```

### Step 4: Deploy Services to New Host

```bash
# SSH to new host
ssh akushnir@192.168.168.32

# Go to repo directory
cd ~/code-server-enterprise

# Start services using the existing docker-compose.yml
docker-compose up -d

# Verify all services started
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

### Step 5: Migrate Data

```bash
# Option 1: Backup from old host, restore on new host
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise
docker-compose exec postgres pg_dump -U codeserver codeserver > /tmp/backup.sql
scp /tmp/backup.sql akushnir@192.168.168.32:/tmp/

# On new host
docker-compose exec postgres psql -U codeserver codeserver < /tmp/backup.sql

# Option 2: For persistent volumes, copy NAS mount paths directly
# (if using shared NAS storage, no migration needed)
```

### Step 6: Update DNS/Load Balancer

```bash
# If using public DNS (e.g., ide.kushnir.cloud)
# Update DNS A record to point to 192.168.168.32

# If using CloudFlare tunnel
# Update tunnel to point to new host
cloudflared tunnel update ide-kushnir-cloud --url http://192.168.168.32
```

### Step 7: Verify New Host

```bash
# Test HTTP access
curl -I http://192.168.168.32

# Test OAuth2 login
curl -I -H 'Host: ide.kushnir.cloud' http://192.168.168.32

# Monitor logs
ssh akushnir@192.168.168.32
cd ~/code-server-enterprise
docker-compose logs -f
```

### Step 8: Decommission Old Host (Optional)

```bash
# Once new host is stable and tested, stop old host services
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise
docker-compose down

# Backup any remaining data
docker-compose exec postgres pg_dump -U codeserver codeserver > /tmp/final-backup.sql
scp /tmp/final-backup.sql your-backup-location:/

# Optional: Decommission the VM/hardware
```

---

## Multi-Host Scenarios

### Scenario 1: High Availability (Active-Standby)

Use Terraform to deploy to **multiple hosts**:

```hcl
# terraform.tfvars
deployment_hosts = [
  { host = "192.168.168.31", user = "akushnir", primary = true },
  { host = "192.168.168.32", user = "akushnir", primary = false }
]
```

Then use a load balancer (HAProxy, Nginx) to route traffic.

### Scenario 2: Blue-Green Deployment

```bash
# Step 1: Deploy all services to "green" (new host)
# terraform.tfvars: deployment_host = "192.168.168.32"
terraform apply

# Step 2: Verify green is healthy
ssh akushnir@192.168.168.32 && docker ps

# Step 3: Switch traffic (update DNS/LB)
# Update load balancer to point to 192.168.168.32

# Step 4: Decommission "blue" (old host)
# ssh akushnir@192.168.168.31 && docker-compose down
```

### Scenario 3: Canary Deployment (1% → 100%)

```bash
# Using weighted load balancer:
# 99% traffic → 192.168.168.31 (current/blue)
# 1% traffic → 192.168.168.32 (new/green)
#
# Monitor for 15 minutes:
# - Error rate < 0.1%
# - Latency p99 < 150ms
# - All health checks passing
#
# Then gradually shift:
# 50% → 192.168.168.31, 50% → 192.168.168.32
# 10% → 192.168.168.31, 90% → 192.168.168.32
# 0% → 192.168.168.31, 100% → 192.168.168.32
```

---

## Parameterized Values

All these values are now parameterized in Terraform:

| Variable | Current | Example New Value | Where Used |
|----------|---------|-------------------|-----------|
| `deployment_host` | `192.168.168.31` | `192.168.168.32` | SSH target for deployments |
| `deployment_user` | `akushnir` | `ubuntu` or `admin` | SSH user login |
| `deployment_port` | `22` | `2222` | SSH port (if non-standard) |
| `domain` | `ide.kushnir.cloud` | `ide.example.com` | OAuth2 redirect URI |
| `deployment_path` | `/home/akushnir/...` | Auto-computed | Container mount paths |
| `deployment_ssh` | `akushnir@192.168.168.31` | Auto-computed | SSH connection string |

---

## Checking Current Configuration

```bash
# See all current variable values
terraform show

# See deployment-specific values
terraform output deployment_host
terraform output deployment_user
terraform output deployment_path
terraform output deployment_ssh
```

---

## Troubleshooting Scaling Issues

### Issue: SSH connection fails to new host

```bash
# Verify SSH access
ssh -vvv akushnir@192.168.168.32

# Check if SSH key is authorized
# ssh-copy-id akushnir@192.168.168.32

# Verify deployment_user exists on new host
ssh akushnir@192.168.168.32 whoami
```

### Issue: Services fail to start on new host

```bash
# Check docker-compose on new host
ssh akushnir@192.168.168.32
cd ~/code-server-enterprise
docker-compose config  # Validates syntax
docker-compose up -d   # Start with verbose output
docker-compose logs    # Check error messages
```

### Issue: Data didn't migrate

```bash
# Verify PostgreSQL backup/restore
docker-compose exec postgres psql -U codeserver -c "\dt"  # List tables
docker-compose exec postgres psql -U codeserver -c "SELECT COUNT(*) FROM schema_information_schema.tables;"

# Check NAS mounts
mount | grep nas
df -h /mnt/nas-export
```

---

## Best Practices

1. **Always plan before apply:** `terraform plan -out=tfplan` + review
2. **Test on staging first:** Don't scale directly to production without testing
3. **Monitor during migration:** Keep dashboards open during cutover
4. **Automated backups:** Ensure daily backups before scaling operations
5. **Rollback plan:** Always know how to quickly revert to previous host
6. **Communication:** Notify team before scaling operations

---

## Rollback Procedure

If new host deployment fails:

```bash
# Revert Terraform
terraform.tfvars: deployment_host = "192.168.168.31"  # Back to old host
terraform apply

# Verify old services still running
ssh akushnir@192.168.168.31
docker ps

# Decommission new host
ssh akushnir@192.168.168.32
docker-compose down
```

Rollback time: **<5 minutes**

---

## Summary

**Old way (hardcoded):**
```
$ grep -r "192.168.168.31" . | wc -l
847 files with hardcoded IPs  ❌ Hard to migrate
```

**New way (parameterized):**
```
$ terraform apply  # Single command
1 variable change → entire infrastructure migrates  ✅ Easy scaling
```

When you need to expand: Just update `deployment_host` and apply.
