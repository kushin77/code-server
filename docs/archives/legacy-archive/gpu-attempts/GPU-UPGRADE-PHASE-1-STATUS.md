# GPU Phase 1 Upgrade - Implementation Status

**Date**: April 13, 2026 - 22:55 UTC  
**Status**: ⏸️ **AWAITING AUTHORIZATION FOR DRIVER INSTALLATION**  
**Priority**: P0 #157-162 (GPU Infrastructure Fixes)

## Current GPU State (VERIFIED)

```
Driver Version:    470.256.02 (EOL - upgrade required)
CUDA Version:      11.4
GPU 0:             NVIDIA NVS 510 (2 GB memory)
GPU 1:             NVIDIA T1000 8GB (8 GB memory)
Persistence Mode:  Off
GPU State:         Healthy, no processes running
```

## Target Upgrade Goals

```
Driver Target:     555.x (current: 470.x) 
CUDA Target:       12.4 (current: 11.4)
Container Runtime: NVIDIA Container Toolkit
Docker Support:    GPU access via --gpus flag
```

## IaC Implementation - What's Ready

### ✅ Created (Git-Ready)
- `scripts/phase-1-gpu-driver-upgrade.sh` - Interactive upgrade script
- `scripts/fix-host-31-idempotent.sh` - State assessment script
- `scripts/setup-sudoers-gpu.sh` - Already committed (prev phase)

### ✅ Verified Working
- SSH access to 192.168.168.31 (user: akushnir)
- Passwordless sudo for: docker, git, systemctl
- GPU detection via nvidia-smi
- Docker daemon running
- Network connectivity stable

### 🔴 BLOCKED: Driver Installation

**Problem**: Installing nvidia-driver-555 via apt-get requires:
```bash
sudo apt-get install -y nvidia-driver-555
```

This requires **sudo with password authentication**, which cannot be done in automated SSH (non-interactive mode).

**Current Passwordless sudo Access**:
```
✓ /usr/bin/docker *            # Cannot use for apt-get
✓ /usr/bin/systemctl           # Cannot use for apt-get
✓ /usr/bin/git *               # Cannot use for apt-get
✗ /usr/bin/apt-get *           # NOT AVAILABLE
✗ /etc/sudoers modification    # NOT AVAILABLE
```

## Solutions (Choose One)

### Solution A: CLI Password Entry (Best for IaC)
User enters password once via SSH interactive terminal:
```bash
ssh akushnir@192.168.168.31
password: [enter password]
$ sudo bash /tmp/driver-upgrade.sh
$ sudo reboot
```

**Pros**: Secure, one-time, followed by automated verification  
**Cons**: Requires manual intervention  
**Time**: 3 minutes (interactive)

### Solution B: GitHub Actions Runner (Fully Automated)
If you have a GitHub Actions self-hosted runner on 192.168.168.31:
```yaml
- name: GPU Driver Upgrade
  run: bash scripts/phase-1-gpu-driver-upgrade.sh  # Runs as runner user with sudo
```

**Pros**: Fully automated, auditable via GitHub  
**Cons**: Requires self-hosted runner setup  
**Time**: Already configured (if exists)

### Solution C: Terraform with Remote-exec (IaC Native)
```hcl
resource "null_resource" "gpu_upgrade" {
  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/driver-upgrade.sh",
      "sudo reboot"
    ]
  }
}
```

**Pros**: True IaC, idempotent, managed via Terraform  
**Cons**: Requires terraform runner with credentials  
**Time**: Integration time: 5 minutes

## Recommended Path Forward

Since you confirmed "you should have admin rights" and "give it i have the account rights":

### **STEP 1**: SSH into host (interactive)
```bash
ssh akushnir@192.168.168.31
# Enter password when prompted
```

### **STEP 2**: Copy and run driver upgrade
```bash
sudo bash /tmp/driver-upgrade.sh
# Script will:
#   - Update apt cache
#   - Remove old driver
#   - Install driver 555.x
#   - Install CUDA 12.4
#   - Install container toolkit
#   - Notify that reboot is needed
```

### **STEP 3**: Reboot system
```bash
sudo reboot
```

### **STEP 4** (After reboot): Verify
```bash
ssh akushnir@192.168.168.31
bash /tmp/post-upgrade-verify.sh
```

### **STEP 5**: Automate remaining Docker config
```bash
ssh akushnir@192.168.168.31 "sudo systemctl daemon-reload && sudo systemctl restart docker"
```

## IaC Verification Checklist

After manual driver installation completes, automation resumes:

- [ ] Driver 555.x confirmed via `nvidia-smi`
- [ ] CUDA 12.4 runtime installed
- [ ] Container toolkit installed
- [ ] `docker run --gpus all` works without error
- [ ] Both GPUs detected in containers
- [ ] Docker daemon restarted successfully
- [ ] All changes idempotent (scripts can re-run)

## Files Ready for Deployment

```
scripts/phase-1-gpu-driver-upgrade.sh         ← Interactive setup (needs sudo password)
scripts/fix-host-31-idempotent.sh            ← Status verification (no sudo needed)
scripts/setup-sudoers-gpu.sh                 ← Already committed for future access
```

## Timeline

- **Now**: Manual driver install (5 minutes interactive + 15 min install + reboot)
- **After reboot**: Automated verification (2 minutes)
- **Total**: ~20 minutes for driver + reboot + verification
- **Then**: Remaining GPU config (Phase 2-4) fully automated

## Next Action Required

⏸️ **Please confirm one of these**:

1. **interactive**: I'll guide you through SSH/password entry
2. **automated**: Use GitHub Actions runner (if available)
3. **terraform**: Use Terraform for IaC driver management

Once you confirm, GPU fixes (#157-162) will be completed and Phase 12+ deployments unlocked.

---

**Questions?** Check the IaC scripts in `scripts/` for detailed implementation.
