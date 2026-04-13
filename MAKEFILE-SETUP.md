# Makefile Setup Guide

## ⚠️ Make Not Found on Windows

The new `Makefile` requires the `make` command, which is not available on standard Windows.

## ✅ Solutions

### Option 1: Use WSL (Windows Subsystem for Linux) - RECOMMENDED
```powershell
# In PowerShell or Terminal
wsl
cd /mnt/c/code-server-enterprise
make deploy


**Why**: WSL has full `make` support and is the easiest path.

### Option 2: Install GNU Make on Windows
```powershell
# Using Chocolatey
choco install make

# Or using Scoop
scoop install make

# Or download from: https://www.gnu.org/software/make/


Then:
```powershell
cd c:\code-server-enterprise
make deploy


### Option 3: Use Git Bash
```bash
# Right-click → Git Bash Here
# Then run:
cd /c/code-server-enterprise
make deploy


### Option 4: Use Docker for Make
```powershell
# Run make commands in a Docker container
docker run --rm -v c:/code-server-enterprise:/workspace
  -w /workspace
  alpine:lates
  sh -c "apk add make && make deploy"


## 🚀 Recommended Setup

### For Windows Users
1. **Use WSL** - Most seamless experience
2. Install `make` via `choco install make` as fallback
3. Or use Docker if already familiar

### For macOS/Linux Users
- `make` should be pre-installed
- Just run `make deploy

## 📋 Immediate Workaround: Use Terraform Directly

If `make` is not available immediately:

```powershell
cd c:\code-server-enterprise
terraform ini
terraform plan -out=tfplan
terraform apply tfplan
docker compose restart oauth2-proxy


This achieves the same result as `make deploy` but manually.

## ✅ Verification

Once `make` is installed:
```bash
make help


Should display all available commands.

---

**Next Steps**: Install `make` on your system, then enjoy the full `make deploy` workflow!
