# Quick Start - Code-Server Enterprise IaC

## 🚀 Deploy in 30 Seconds

### All Platforms (Recommended - Uses Make)
```bash
cd c:\code-server-enterprise
make deploy


### Windows (PowerShell Alternative)
```powershell
cd c:\code-server-enterprise
terraform ini
terraform apply -auto-approve


### Linux/macOS/WSL (Alternative)
```bash
cd ~/code-server-enterprise
terraform ini
terraform apply -auto-approve


### View What Will Deploy (Safe - Read-Only)
```bash
make plan


---

## ✅ What Gets Deployed

✓ **Docker Network** - Isolated, secure container network
✓ **Code-Server Container** - Full VS Code IDE in browser
✓ **Caddy Reverse Proxy** - HTTPS, security headers, WebSocket suppor
✓ **Persistent Volumes** - Your code and settings survive restarts
✓ **No Manual Config** - Fully automated, zero interventions

---

## 🌐 Access Your IDE

**URL:** `http://localhos
**Password:** Retrieved after deploymen

No GitHub authentication. No dialogs. Just works.

---

## 📋 Verify Deploymen

```bash
# Check containers
docker ps --filter "label=service=code-server-enterprise"

# View logs
docker logs code-server-enterprise-app

# Check Terraform state
terraform state lis


---

## 🔧 Common Commands

### Plan Changes (Safe - Preview Only)
```bash
make plan


### Deploy Infrastructure (Idempotent - Safe to Run Repeatedly)
```bash
make deploy


### Check Status
```bash
make status


### View Logs
```bash
make logs


### Shell Into Container
```bash
make shell


### View Full Dashboard
```bash
make dashboard


### Update Password
Edit `terraform.tfvars`:
```hcl
code_server_password = "new-password"

Then:
```bash
make deploy


### Run IaC Audits
```bash
make audi


### Destroy Everything
```bash
make destroy


## 📚 All Available Commands
```bash
make help



### View Outputs
```bash
terraform outpu


---

## 🐛 Troubleshooting

**Can't connect?**
```bash
docker ps  # Check if containers are running
docker logs code-server-enterprise-app  # Check errors


**Terraform not found?**
```bash
# Install manually: https://www.terraform.io/downloads
terraform version


**Port already in use?**
```bash
# Change port in docker-compose or firewall rules
netstat -an | grep 8080  # Check what's using por


---

## 📚 Learn More

- **Full IaC Guide:** `IaC-README.md
- **Terraform Docs:** `main.tf` (well documented)
- **Architecture:** `IaC-README.md` (ASCII diagram)

---

## 💡 Tips

- **Save state file**: Git ignore it with `.gitignore` (included)
- **Multiple environments**: Create `prod.tfvars`, `dev.tfvars
- **Use Makefile**: `make help` for shortcuts
- **Backup state**: `terraform state pull > backup.tfstate

---

**That's it! Your enterprise IDE is ready. 🎉**
