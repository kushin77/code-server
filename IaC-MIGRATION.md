# IaC Migration Guide: From Scripts to Makefile

## 🎯 Objective
Replace imperative PowerShell (`deploy-iac.ps1`) and Bash (`deploy-iac.sh`) scripts with a **declarative, idempotent Makefile** that uses Terraform as the single source of truth.

## ✅ Migration Complete

The following old scripts are **DEPRECATED and should be deleted**:

| Old Script | Replacement | Status |
|-----------|-------------|--------|
| `deploy-iac.ps1` | `make deploy` | ✅ Replaced |
| `deploy-iac.sh` | `make deploy` | ✅ Replaced |
| PowerShell-specific logic | Terraform (platform-agnostic) | ✅ Replaced |

## 📋 Mapping: Old Commands → New Commands

### Deployment Flow

| Task | Old Command | New Command |
|------|------------|------------|
| Initialize | `terraform init` | `make init` |
| Plan | `terraform plan` | `make plan` |
| Deploy | `.\deploy-iac.ps1` or `./deploy-iac.sh` | `make deploy` |
| Apply | `terraform apply` | *(auto in `make deploy`)* |
| Destroy | `terraform destroy` | `make destroy` |

### Maintenance

| Task | Old Command | New Command |
|------|------------|------------|
| Validate | `terraform validate` | `make validate` |
| Format | `terraform fmt -recursive` | `make fmt` |
| Status | `docker ps` | `make status` |
| Logs | `docker logs -f <container>` | `make logs` |
| Shell | `docker exec -it <container> bash` | `make shell` |
| Dashboard | Manual checks | `make dashboard` |

## 🔄 Manual Script Removal

### Step 1: Verify New Makefile Works
```bash
make help        # Shows all available commands
make plan        # Preview deployment (safe)
make deploy      # Deploy (idempotent)
```

### Step 2: Delete Old Scripts
```bash
rm -f deploy-iac.ps1 deploy-iac.sh
```

### Step 3: Update Documentation
- ✅ QUICK_START.md updated to reference `make deploy`
- ✅ DEPLOYMENT.md ready for detailed workflow docs
- Update any CI/CD pipelines to use `make deploy`

### Step 4: Test on All Platforms

#### On Windows (PowerShell)
```powershell
cd c:\code-server-enterprise
make deploy
```

#### On Linux/macOS/WSL
```bash
cd ~/code-server-enterprise
make deploy
```

## ✨ Key Benefits of Makefile Approach

### 1. **Platform-Agnostic**
- Single `make deploy` works on Windows, macOS, Linux, WSL
- No PowerShell-specific logic needed
- Terraform handles cross-platform compatibility

### 2. **True Idempotency**
- `make deploy` called 100x produces identical results
- No imperative logic that can fail in complex ways
- Terraform ensures desired state matches actual state

### 3. **Better Maintainability**
- All logic in one place (Makefile + Terraform)
- Clear, comment-documented targets
- Easy to add new operational targets

### 4. **Improved Safety**
- `make plan` previews changes without applying
- Separates read/write operations
- Explicit confirmation of changes

### 5. **Built-in Auditing**
- `make audit` checks for drift, mutability, idempotency
- `make status` shows deployment health
- `make dashboard` provides full visibility

## 🔍 Makefile Features

### Core Deployment
```bash
make init       # Initialize Terraform
make plan       # Preview changes (safe, read-only)
make deploy     # Apply changes (idempotent)
make destroy    # Remove everything
```

### Operations & Monitoring
```bash
make status     # Show container/resource status
make logs       # Stream application logs
make shell      # SSH into running container
make dashboard  # Full deployment dashboard
```

### Maintenance
```bash
make validate   # Check Terraform syntax
make fmt        # Auto-format Terraform files
make refresh    # Sync state with reality
make audit      # Run IaC compliance checks
make clean      # Remove temporary files
```

### State Management
```bash
make output           # Show Terraform outputs
make state-list       # List all resources
make state-show       # Show resource details
make console          # Terraform console (debugging)
```

## 🚨 Gotchas & Notes

### 1. Makefile Requires `make` Command
- **Windows**: Install via `choco install make` or use WSL
- **macOS**: Included in Xcode Command Line Tools
- **Linux**: Usually pre-installed; else `apt install make`

### 2. Old `terraform.tfstate` Still Used
- Migration is **non-destructive**
- Existing state continues to work
- No data loss or re-provisioning needed

### 3. Environment-Specific Configs
- Use `terraform.tfvars` for variable overrides
- `make plan` and `make deploy` automatically pick it up

### 4. CI/CD Pipeline Updates Required
If using GitHub Actions, GitLab CI, or Cloud Build:
```bash
# OLD (Bad - manual script)
./deploy-iac.sh

# NEW (Good - IaC-first)
make deploy
```

## 📚 Related Documentation

- [QUICK_START.md](QUICK_START.md) - 30-second deployment
- [DEPLOYMENT.md](DEPLOYMENT.md) - Full deployment workflow
- [IaC-README.md](IaC-README.md) - Terraform architecture details
- [Makefile](Makefile) - All operational targets

## ✅ Checklist for Full Migration

- [x] Create new Makefile with all targets
- [x] Update QUICK_START.md to use `make deploy`
- [x] Document new command mappings
- [ ] Test on Windows (PowerShell)
- [ ] Test on Linux/WSL
- [ ] Test on macOS
- [ ] Update CI/CD pipelines
- [ ] Delete old scripts (`deploy-iac.ps1`, `deploy-iac.sh`)
- [ ] Update team documentation
- [ ] Train team on new workflow

## 🎓 Learning Resources

### Makefile Basics
- [GNU Make Manual](https://www.gnu.org/software/make/manual/)
- [Practical Makefile Guide](https://tech.davis-hansson.com/p/make/)

### Terraform Best Practices
- [Terraform Documentation](https://www.terraform.io/docs)
- [Terraform Best Practices](https://docs.terraform.io/language)

### IaC Philosophy
- [Infrastructure as Code (Wikipedia)](https://en.wikipedia.org/wiki/Infrastructure_as_code)
- [IaC Best Practices](https://cloud.google.com/architecture/devops/devops-tech-infrastructure-code)

---

**Migration Date**: 2026-01-27  
**Status**: ✅ Complete and Ready for Testing

