# Quick Start - Code-Server Enterprise IaC

## 🚀 Deploy in 30 Seconds

### Windows (PowerShell)
```powershell
cd c:\code-server-enterprise
.\deploy-iac.ps1
```

### Linux/macOS/WSL (Bash)
```bash
cd ~/code-server-enterprise
chmod +x deploy-iac.sh
./deploy-iac.sh
```

### Using Terraform Directly
```bash
cd ~/code-server-enterprise
terraform init
terraform apply
```

---

## ✅ What Gets Deployed

✓ **Docker Network** - Isolated, secure container network  
✓ **Code-Server Container** - Full VS Code IDE in browser  
✓ **Caddy Reverse Proxy** - HTTPS, security headers, WebSocket support  
✓ **Persistent Volumes** - Your code and settings survive restarts  
✓ **No Manual Config** - Fully automated, zero interventions  

---

## 🌐 Access Your IDE

**URL:** `http://localhost`  
**Password:** Retrieved after deployment  

No GitHub authentication. No dialogs. Just works.

---

## 📋 Verify Deployment

```bash
# Check containers
docker ps --filter "label=service=code-server-enterprise"

# View logs
docker logs code-server-enterprise-app

# Check Terraform state
terraform state list
```

---

## 🔧 Common Commands

### Plan Changes
```bash
terraform plan
```

### Update Password
Edit `terraform.tfvars`:
```hcl
code_server_password = "new-password"
```
Then:
```bash
terraform apply
```

### Destroy Everything
```bash
terraform destroy
```

### View Outputs
```bash
terraform output
```

---

## 🐛 Troubleshooting

**Can't connect?**
```bash
docker ps  # Check if containers are running
docker logs code-server-enterprise-app  # Check errors
```

**Terraform not found?**
```bash
# Install manually: https://www.terraform.io/downloads
terraform version
```

**Port already in use?**
```bash
# Change port in docker-compose or firewall rules
netstat -an | grep 8080  # Check what's using port
```

---

## 📚 Learn More

- **Full IaC Guide:** `IaC-README.md`
- **Terraform Docs:** `main.tf` (well documented)
- **Architecture:** `IaC-README.md` (ASCII diagram)

---

## 💡 Tips

- **Save state file**: Git ignore it with `.gitignore` (included)
- **Multiple environments**: Create `prod.tfvars`, `dev.tfvars`
- **Use Makefile**: `make help` for shortcuts
- **Backup state**: `terraform state pull > backup.tfstate`

---

**That's it! Your enterprise IDE is ready. 🎉**
