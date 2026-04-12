# Infrastructure as Code Deployment - Code-Server Enterprise

## Overview
This is a **fully declarative, Infrastructure-as-Code** approach using Terraform. Zero manual configuration needed.

### Key Features
✅ **Seamless Deployment** - Single command to deploy entire stack  
✅ **No GitHub Auth** - No sign-in dialogs or authentication prompts  
✅ **Reproducible** - Same infrastructure every time  
✅ **Version Controlled** - All config in `.tf` files  
✅ **Scalable** - Easy to modify, extend, or replicate  
✅ **State Management** - Terraform tracks all resources  

---

## Quick Start (IaC Way)

### Option 1: Bash (Linux/WSL)
```bash
cd ~/code-server-enterprise
chmod +x deploy-iac.sh
./deploy-iac.sh
```

### Option 2: PowerShell (Windows)
```powershell
cd c:\code-server-enterprise
.\deploy-iac.ps1
```

### Option 3: Manual Terraform (Full Control)
```bash
cd ~/code-server-enterprise
terraform init
terraform plan
terraform apply
```

---

## What Happens Automatically

1. ✅ Checks Docker installation
2. ✅ Installs/updates Terraform
3. ✅ Validates configuration
4. ✅ Provisions Docker network
5. ✅ Creates persistent volumes
6. ✅ Launches code-server container
7. ✅ Launches Caddy reverse proxy
8. ✅ Outputs access credentials
9. ✅ No manual intervention required

---

## Architecture

```
┌─────────────────────────────────────────────┐
│         Docker Network (Bridge)             │
│  ┌──────────────────────────────────────┐  │
│  │  Caddy (Reverse Proxy)              │  │
│  │  Port: 80, 443                      │  │
│  │  - HTTPS/TLS                        │  │
│  │  - Security headers                 │  │
│  │  - WebSocket support                │  │
│  └──────────────┬───────────────────────┘  │
│                 │                          │
│  ┌──────────────▼───────────────────────┐  │
│  │  Code-Server Container               │  │
│  │  Port: 8080 (internal)               │  │
│  │  - VS Code IDE                       │  │
│  │  - Open VSX extensions               │  │
│  │  - No GitHub auth required           │  │
│  │  - Persistent storage                │  │
│  └─────────────────────────────────────┘  │
│                                            │
│  Volumes:                                  │
│  - code-server-enterprise-data (app)      │
│  - code-server-enterprise-caddy-* (proxy) │
└─────────────────────────────────────────────┘
```

---

## File Structure

```
code-server-enterprise/
├── main.tf                  # Core Terraform config
├── variables.tf             # Variable definitions
├── terraform.tfvars         # Default values
├── Caddyfile.tpl           # Reverse proxy template
├── deploy-iac.sh           # Deployment script (Bash)
├── deploy-iac.ps1          # Deployment script (PowerShell)
├── terraform.tfstate       # State file (auto-generated)
├── terraform.tfstate.backup # Backup state
└── README.md               # This file
```

---

## Advanced Usage

### Change Password
Edit `terraform.tfvars`:
```hcl
code_server_password = "your-new-password"
```

Then apply:
```bash
terraform apply -auto-approve
```

### Enable Debug Logging
```hcl
log_level = "debug"
```

### View Current State
```bash
terraform state list
terraform state show docker_container.code_server
```

### Destroy Everything
```bash
terraform destroy -auto-approve
```

### View Outputs
```bash
terraform output code_server_url
terraform output -json   # All outputs as JSON
```

---

## Troubleshooting IaC Deployment

### Docker not found
**Solution:** Ensure Docker is running
```bash
docker ps
```

### Terraform state lock
**Solution:** Remove lock file
```bash
rm .terraform.lock.hcl
```

### Rebuild containers
```bash
terraform taint docker_container.code_server
terraform taint docker_container.caddy
terraform apply -auto-approve
```

### View Terraform logs
```bash
TF_LOG=DEBUG terraform apply
```

---

## Production Enhancements (Next Steps)

### 1. Remote State Management
Add to `main.tf`:
```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state"
    key    = "code-server/prod/terraform.tfstate"
  }
}
```

### 2. Environment Variables
Create `.tfvars` files per environment:
```bash
terraform apply -var-file="prod.tfvars"
terraform apply -var-file="staging.tfvars"
```

### 3. Workspace Isolation
```bash
terraform workspace new prod
terraform workspace new staging
```

### 4. Add Monitoring
Update `main.tf` to include Prometheus/Grafana containers

### 5. RBAC & Multi-User
Consider Coder platform Terraform provider:
```hcl
provider "coder" {
  url = aws_eip.coder.public_ip
}
```

---

## IaC Best Practices

✅ **Version Control**: Commit `.tf` files (NOT `.tfstate`)  
✅ **State Security**: Protect `terraform.tfstate` - it contains secrets  
✅ **Plan Before Apply**: Always run `terraform plan` first  
✅ **Use Variables**: Never hardcode values  
✅ **Document Changes**: Add comments to `.tf` files  
✅ **Test Locally**: Validate in dev before prod  
✅ **Backup State**: `terraform state pull > backup.tfstate`  

---

## Support & Debugging

View deployment logs:
```bash
tail -f deployment.log
```

SSH into container:
```bash
docker exec -it code-server-enterprise-app bash
```

Check container status:
```bash
docker ps --filter "label=service=code-server-enterprise"
```

View Caddy logs:
```bash
docker logs code-server-enterprise-proxy
```

---

**This is enterprise-grade IaC. Everything is declarative, reproducible, and zero-touch deployment. 🚀**
