# Kushnir.cloud Sovereign Terraform Drop Package

> Deploy a complete, air-gapped, production-ready IDE + AI stack in < 15 minutes.

**This package contains everything needed to deploy Kushnir.cloud (KC) DevOS to any organization — on-prem, private cloud, or air-gapped.**

---

## 📦 What's Included

```
drop-package/
├── README.md                          # This file
├── terraform.tfvars.example           # Configuration template
├── modules/
│   ├── core/                          # Base networking, DNS, Caddy
│   ├── identity/                      # OAuth2-proxy, OIDC, SSO
│   ├── ide/                           # Code-server, KC IDE customization
│   ├── ai/                            # Ollama, Prompt Gateway, Model Router
│   ├── observability/                 # Prometheus, Grafana, Loki
│   ├── policy/                        # OPA policy engine
│   └── storage/                       # NAS mounts, volumes, backups
├── environments/
│   ├── private/                       # Single-org on-prem (kushnir.cloud reference)
│   └── air-gapped/                    # No external dependencies
└── scripts/
    ├── verify-drop-deployment.sh      # Post-deploy health check
    └── preflight-air-gap-images.sh    # Download images for air-gapped mode
```

---

## 🚀 Quick Start (5 Steps)

### 1. **Extract & Configure**

```bash
# Extract drop package
unzip kushnir-cloud-drop-package-v1.0.tar.gz
cd drop-package

# Copy template configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars  # or use your editor
```

### 2. **Configure Deployment Parameters**

Edit `terraform.tfvars` with your infrastructure details:

```hcl
# Your domain
apex_domain = "yourdomain.com"
ide_domain  = "ide.yourdomain.com"

# Your hosts (on-prem IPs or cloud VMs)
primary_host = "192.168.1.31"    # Primary replica
replica_host = "192.168.1.42"    # Secondary replica (HA)
nas_host     = "192.168.1.56"    # NAS for persistent storage

# Admin email for Let's Encrypt TLS
admin_email = "admin@yourdomain.com"

# Secure password (min 8 chars)
code_server_password = "your-secure-password-here"
```

### 3. **Initialize Terraform**

```bash
terraform init
```

**Output:**
```
Terraform has been successfully configured!
Your working directory is now configured to use Terraform.
```

### 4. **Deploy Stack**

```bash
terraform apply
```

**Expected time:** 5-12 minutes depending on network speed

**Output:**
```
Apply complete! Resources have been created.

Outputs:
service_urls = {
  ide_url = "https://ide.yourdomain.com"
  prometheus_url = "https://prometheus.yourdomain.com"
  ...
}
```

### 5. **Verify Deployment**

```bash
bash scripts/verify-drop-deployment.sh
```

**Expected output:**
```
✅ Primary host (192.168.1.31): Responding to health checks
✅ Replica host (192.168.1.42): Responding to health checks
✅ NAS (192.168.1.56): Mounted and accessible
✅ PostgreSQL: Primary replication active
✅ Redis: Sentinel failover ready
✅ Ollama: 4 models ready (llama3:8b, llama3:70b, codellama, mistral)
✅ Prompt Gateway: /health responding
✅ OPA: Policy engine evaluating rules
✅ Prometheus: Scraping 42 targets
✅ Grafana: Dashboards loaded

🎉 All services operational and healthy!
```

---

## 📋 Prerequisites

**Hardware (Per Replica):**
- CPU: 8+ cores (16+ recommended)
- RAM: 32 GB minimum (64 GB recommended)
- Disk: 500 GB SSD (1 TB recommended)
- Network: 1 Gbps minimum (10 Gbps recommended)

**Software:**
- Terraform >= 1.5.0
- Docker >= 24.0.0
- Docker Compose >= 2.20.0
- bash >= 4.0
- curl >= 7.0

**Network:**
- Static IPs for both replicas and NAS
- Port 443 (HTTPS), 80 (HTTP redirect) open to clients
- Internal network connectivity (replicas to each other, to NAS)
- Internet access for TLS certificate generation (can be air-gapped after initial cert)

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────┐
│              Kushnir.cloud Multi-Replica Cluster          │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  HAProxy / Cloudflare LB (health-check round-robin)      │
│              ↓              ↓                             │
│  ┌─────────────────────┐  ┌─────────────────────┐        │
│  │  Replica 1          │  │  Replica 2          │        │
│  │  (192.168.1.31)     │  │  (192.168.1.42)     │        │
│  │  ─────────────────  │  │  ─────────────────  │        │
│  │  • Code-Server      │  │  • Code-Server      │        │
│  │  • Ollama           │  │  • Ollama           │        │
│  │  • Prompt Gateway   │  │  • Prompt Gateway   │        │
│  │  • OPA              │  │  • OPA              │        │
│  │  • Prometheus       │  │  • Prometheus       │        │
│  │  • PostgreSQL       │  │  • PostgreSQL       │        │
│  │    (streaming repl) │  │    (streaming repl) │        │
│  │  • Redis            │  │  • Redis            │        │
│  │    (Sentinel HA)    │  │    (Sentinel HA)    │        │
│  └─────────────────────┘  └─────────────────────┘        │
│              ↓              ↓                             │
│  ┌─────────────────────────────────────┐                 │
│  │  NAS Storage (192.168.1.56)         │                 │
│  │  ─────────────────────────────────  │                 │
│  │  • /persistent/ → PostgreSQL data   │                 │
│  │  • /backup/     → Database backups  │                 │
│  │  • /code/       → Shared workspace  │                 │
│  └─────────────────────────────────────┘                 │
│                                                            │
└────────────────────────────────────────────────────────────┘

ACTIVE-ACTIVE HA: Both replicas handle traffic simultaneously
FAILOVER: < 5 seconds automatic detection + redirect
SESSION STATE: Shared Redis (all replicas see same sessions)
```

---

## 🌐 Deployment Modes

### Private (On-Prem) — Default
```hcl
deployment_mode = "private"
```

Single organization, on-prem network. Perfect for:
- Internal teams running private IDE
- Compliance-sensitive workloads (HIPAA, SOC2)
- Existing on-prem infrastructure integration

---

### Air-Gapped (No External Network)
```hcl
deployment_mode = "air-gapped"
```

Complete isolation with pre-downloaded images. Perfect for:
- High-security environments (no external internet)
- Classified/regulated workloads
- Environments with strict egress filtering

**Setup Steps:**

```bash
# 1. On connected machine, download all images to NAS
bash scripts/preflight-air-gap-images.sh

# 2. Mount NAS on deployment hosts
mount -t nfs 192.168.1.56:/air-gap-images /opt/images

# 3. Deploy (uses local images only)
terraform apply
```

---

### Federated (Multi-Org) — Phase 3
```hcl
deployment_mode = "federated"
```

Multiple organizations sharing cluster infrastructure (future feature).

---

## 🔐 Security

**Built-In:**
- TLS 1.3 on all endpoints (Let's Encrypt auto-renewal)
- OAuth2 + OIDC single sign-on
- OPA declarative policy enforcement
- Secrets never logged (redacted in all outputs)
- Read-only root filesystems for all containers
- Non-root user execution (uid 1000)
- Network policies enforcing service-to-service communication
- PostgreSQL streaming replication (audit log immutability)
- Redis Sentinel failover (session continuity)

**Post-Deployment:**
1. Change all default passwords
2. Update IAM policies in `modules/identity/`
3. Configure backup retention (adjust PostgreSQL backups in terraform)
4. Set up monitoring alerts (Prometheus alert rules included)
5. Enable MFA for admin users

---

## 📊 Observability

Included dashboards for:
- Cluster health (CPU, memory, disk, network)
- Service latency and error rates
- PostgreSQL replication lag and connections
- Redis memory usage and key statistics
- Ollama model performance and token usage
- OPA policy evaluation times
- Code-Server user sessions and resource usage

**Access:**
- Grafana: `https://grafana.yourdomain.com` (admin/admin by default)
- Prometheus: `https://prometheus.yourdomain.com`
- Loki logs: `https://loki.yourdomain.com`

---

## 🆘 Troubleshooting

### "terraform validate" fails

```bash
# Validate all modules
terraform validate

# Fix linting issues
tflint --init
tflint
```

### Deployment hangs on "Waiting for PostgreSQL replication"

```bash
# SSH to primary host
ssh admin@192.168.1.31

# Check PostgreSQL status
docker compose logs postgres

# Verify replication
psql -h localhost -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Services not responding after deploy

```bash
# Run health check script
bash scripts/verify-drop-deployment.sh

# Check service logs
ssh admin@192.168.1.31
docker compose ps
docker compose logs <service_name>
```

### TLS certificate failed to generate

```bash
# Check Caddy logs
docker compose logs caddy

# Manually renew certificate
curl https://yourdomain.com/health  # Should show cert details
```

---

## 📚 Advanced Configuration

### Custom Modules

Each module is independently deployable:

```hcl
# Deploy only observability stack
terraform apply -target=module.observability
```

### Environment-Specific Overrides

```bash
# Different config per environment
cp environments/private/main.tf environments/staging/main.tf
# Edit environments/staging/terraform.tfvars
terraform apply -var-file=environments/staging/terraform.tfvars
```

### Scaling Up

Add more replicas:

```hcl
# In terraform.tfvars
tertiary_host = "192.168.1.50"      # Add 3rd replica
quaternary_host = "192.168.1.51"    # Add 4th replica

# Redeploy
terraform apply
```

---

## 🔄 Operational Commands

**Start All Services:**
```bash
ssh admin@192.168.1.31
cd /opt/code-server-enterprise
docker compose up -d
```

**Stop All Services:**
```bash
docker compose down     # Stop (data persists)
```

**View Logs:**
```bash
docker compose logs -f  # Follow all services
docker compose logs -f postgres  # Specific service
```

**Backup Database:**
```bash
docker compose exec postgres pg_dump -U postgres > backup.sql
```

**Restore Database:**
```bash
docker compose exec -T postgres psql -U postgres < backup.sql
```

**Failover to Replica:**
```bash
# If primary is down, promote replica
bash scripts/ops/promote-replica.sh
```

---

## 📞 Support

For issues or questions:

1. **Documentation**: See docs/ folder in repository
2. **GitHub Issues**: https://github.com/kushin77/code-server/issues
3. **Community**: See CONTRIBUTING.md for contribution guidelines

---

## 📝 License

Kushnir.cloud is licensed under the [Kushnir.cloud Enterprise License](LICENSE.md).

Commercial licensing and deployment support available. Contact: support@kushnir.cloud

---

## 🎯 What's Next?

After successful deployment:

1. **Add Team Members**: Configure OAuth2 for your domain
2. **Enable AI Models**: Download additional Ollama models
3. **Customize Policies**: Edit OPA rules for your compliance needs
4. **Set Up Backups**: Configure off-site backup retention
5. **Add Monitoring**: Enable custom Prometheus scrape targets

---

**Last Updated**: 2026-04-24  
**Package Version**: 1.0.0  
**Compatible With**: Terraform 1.5+, Docker 24.0+

Happy deploying! 🚀
