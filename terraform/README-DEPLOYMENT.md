# Terraform Configuration for 192.168.168.31 Deployment

**Purpose**: Infrastructure-as-Code for fresh code-server-enterprise deployment to 192.168.168.31  
**Deployment Model**: Immutable infrastructure with SSH-based provisioning  
**Idempotency**: All operations are safe to run multiple times

---

## Project Structure

```
terraform/
├── 192.168.168.31/
│   ├── main.tf                    # Compute and Docker host setup
│   ├── gpu.tf                     # GPU driver, CUDA, cuDNN configuration
│   ├── storage.tf                 # Docker volumes, NAS mounts, storage declarations
│   ├── monitoring.tf              # Prometheus, Grafana, alerting (future)
│   ├── variables.tf               # Input variables (deployment parameters)
│   ├── outputs.tf                 # Output values (assessment results)
│   ├── providers.tf               # Provider configuration (SSH, null, local)
│   ├── terraform.tfvars.example   # Example variable values
│   └── .terraform.lock.hcl        # Provider version lock
│
└── modules/
    ├── gpu-setup/
    │   ├── main.tf                # NVIDIA driver/CUDA/cuDNN installation
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── scripts/
    │       └── gpu-init.sh        # GPU setup shell script
    │
    ├── nas-mount/
    │   ├── main.tf                # iSCSI/NFS mount point configuration
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── templates/
    │       └── mount-unit.tpl     # systemd mount unit template
    │
    └── docker-resources/
        ├── main.tf                # Docker resource provisioning
        ├── variables.tf
        └── outputs.tf
```

---

## Key Design Principles

### 1. **Immutable Infrastructure**
- No in-container modifications after startup
- All configuration via environment variables and volume mounts
- Fresh volumes on every deployment (no state reuse)

### 2. **Idempotency**
- Running `terraform apply` 10 times produces same result
- Validation checks prevent conflicts
- Health checks integrated into Terraform

### 3. **Security**
- SSH key-based authentication (no passwords)
- Secrets managed via environment variables (not in state)
- Minimal port exposure (SSH 22, HTTPS 443)

### 4. **Modularity**
- GPU setup separated and reusable
- NAS mounting independent of compute
- Storage configuration decoupled from deployment

---

## Deployment Variables (terraform.tfvars format)

```hcl
# SSH Access
deploy_host          = "192.168.168.31"
deploy_user          = "akushnir"
deploy_ssh_key_path  = "~/.ssh/akushnir-31"

# NAS Configuration
nas_primary_endpoint = "192.168.168.50"
nas_primary_path     = "/export/primary"
nas_backup_endpoint  = "192.168.168.51"
nas_backup_path      = "/export/backup"

# Storage Allocation (in GB)
storage_ollama       = 2000
storage_codeserver   = 500
storage_workspace    = 1000

# GPU Configuration
gpu_count            = 2
gpu_model            = "A100"                    # For documentation
cuda_version         = "12.4"
cudnn_version        = "9.0"

# Ollama Configuration
ollama_models        = ["llama2:70b-chat", "codegemma:latest", "mistral:latest"]
ollama_num_gpu       = 2
ollama_keep_alive    = "24h"

# Caddy/HTTPS
domain_name          = "code-server-31.local"
tls_enabled          = true
