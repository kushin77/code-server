# Air-Gapped Deployment Runbook - Issue #1013

**Objective**: Deploy code-server + Matrix on isolated infrastructure with zero external network dependencies

**Owner**: DevOps / Platform team  
**Time Estimate**: 2-4 hours (depending on image transfer method)  
**Prerequisites**: 
- Air-gapped host with Docker + Docker Compose
- Network isolation (no external routing)
- Internal DNS or /etc/hosts configured
- Storage for pre-loaded images (USB/internal network)

---

## Phase 1: Prepare Images on Connected Host (30-60 min)

### Step 1.1: Prerequisites

```bash
# Verify you have internet access on this host
ping -c 1 1.1.1.1

# Verify Docker is installed and running
docker --version
docker-compose --version
```

### Step 1.2: Pull and Save All Images

```bash
# Navigate to repository
cd /path/to/code-server-enterprise

# Pre-load all images to local storage (requires ~20GB disk space)
bash scripts/air-gapped/pre-load-images.sh --save /tmp/images/

# Expected output:
#   ✓ Image pre-loading complete
#   Total images saved: 10
#   Total size: ~18GB
```

### Step 1.3: Verify Images

```bash
# Check that all images saved successfully
ls -lh /tmp/images/*.tar.gz

# Expected: 10 files, ~18GB total
```

### Step 1.4: Transfer Images to Air-Gapped Host

**Option A**: USB Drive (most reliable for heavily firewalled)
```bash
# Copy to USB
cp -r /tmp/images/ /media/usb/images/

# On air-gapped host, mount USB and copy
sudo mount /dev/sdb1 /mnt/usb
cp -r /mnt/usb/images /tmp/images/
```

**Option B**: Internal Network (if available)
```bash
# On connected host
tar czf images.tar.gz /tmp/images/
scp images.tar.gz akushnir@192.168.168.31:/tmp/

# On air-gapped host
tar xzf /tmp/images.tar.gz -C /tmp/
```

**Option C**: SSH via bastion (if internal network gateway available)
```bash
# On connected host
rsync -az /tmp/images/ akushnir@192.168.168.31:/tmp/images/
```

---

## Phase 2: Configure Air-Gapped Host (20-30 min)

### Step 2.1: SSH to Air-Gapped Host

```bash
ssh akushnir@192.168.168.31

# Verify Docker is running
docker ps
docker-compose --version
```

### Step 2.2: Load Images from Storage

```bash
cd /mnt/c/code-server-enterprise  # or /home/akushnir/code-server-enterprise

# Load all pre-saved images
bash scripts/air-gapped/load-images.sh /tmp/images/

# Expected output:
#   ✓ Loaded 10 images
#   Total: 10 loaded, 0 failed
#
#   code-server-enterprise:dev
#   ollama/ollama:0.1.27
#   postgres:15-alpine
#   ... etc
```

### Step 2.3: Verify Images Are Loaded

```bash
# List loaded images
docker images | grep -E "code-server|postgres|redis|synapse|element-web|caddy|prometheus|grafana|alertmanager"

# Should show ~10 images with correct tags
```

### Step 2.4: Configure Internal DNS

Edit `/etc/hosts`:
```bash
sudo tee -a /etc/hosts << 'EOF'
# Air-Gapped Infrastructure
127.0.0.1       localhost
192.168.168.31  matrix.internal synapse.internal element.internal
192.168.168.31  prometheus.internal grafana.internal
EOF
```

### Step 2.5: Create Environment File

```bash
# Create .env for air-gapped deployment
cat > .env.air-gapped << 'EOF'
# Core Credentials (generate secure values)
CODE_SERVER_PASSWORD=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PASSWORD=$(openssl rand -base64 32)

# Disable all external integrations
GSM_ENABLED=false
OLLAMA_NUM_THREAD=8

# Air-gapped mode markers
DEPLOYMENT_MODE=air-gapped
NETWORK_ISOLATION=enabled
EOF

# Load environment
export $(cat .env.air-gapped | grep -v '^#' | xargs)
```

---

## Phase 3: Deploy Services (10-15 min)

### Step 3.1: Start All Services

```bash
# Deploy using air-gapped configuration
docker-compose -f docker-compose-air-gapped.yml up -d

# Expected output:
#   Creating postgres    ... done
#   Creating redis       ... done
#   Creating synapse     ... done
#   Creating element-web ... done
#   Creating caddy       ... done
#   Creating prometheus  ... done
#   Creating grafana     ... done
#   Creating alertmanager... done
```

### Step 3.2: Monitor Startup (2-3 minutes)

```bash
# Watch services come up
docker-compose -f docker-compose-air-gapped.yml logs -f

# Wait for Synapse to initialize database (~30 seconds)
# Watch for: "Server started on 0.0.0.0:8008"
```

### Step 3.3: Verify Services Are Healthy

```bash
# Check all services
docker-compose -f docker-compose-air-gapped.yml ps

# Expected: All services showing "Up (healthy)" or "Up"
```

---

## Phase 4: Validation & Testing (30-45 min)

### Step 4.1: Run Validation Script

```bash
# Comprehensive validation of air-gapped deployment
bash scripts/air-gapped/validate-deployment.sh

# Expected output:
#   ✓ Passed: 45
#   ✗ Failed: 0
#   ⚠ Warnings: 0-2 (acceptable)
#
#   ✓ All critical checks passed!
```

### Step 4.2: Test Code-Server Access

```bash
# From your local machine (if accessible)
curl -k https://matrix.internal:8080/

# Or access via browser (if local)
# https://192.168.168.31:8080/
# Login with: PASSWORD=$CODE_SERVER_PASSWORD
```

### Step 4.3: Test Matrix Homeserver

```bash
# Check homeserver is running
curl -k https://matrix.internal/_matrix/client/versions

# Expected response:
# {"versions": ["r0.0.1", "r0.0.2", ..., "v1.5"]}
```

### Step 4.4: Test Element Web

```bash
# Access Element (internal network)
curl -k https://matrix.internal/

# Should return Element Web HTML (no 404 or gateway error)
```

### Step 4.5: Verify Isolation (Critical)

```bash
# Attempt external connection (should fail/timeout)
timeout 5 curl -v https://www.google.com || echo "✓ External access blocked"

# Check federation is disabled
curl -k https://matrix.internal:8448/.well-known/matrix/server

# Expected: 404 (not found) or connection refused
```

---

## Phase 5: Generate Compliance Attestation (15 min)

### Step 5.1: Create Attestation Document

Use the template: `COMPLIANCE-ATTESTATION-AIR-GAPPED.md`

```bash
# Fill out compliance document
sudo cat > COMPLIANCE-ATTESTATION-AIR-GAPPED.md << 'EOF'
# Air-Gapped Deployment Compliance Attestation

## Network Isolation Verification
- [x] No external DNS resolution (nslookup external.com fails)
- [x] No outbound HTTP/HTTPS connections (firewall blocks)
- [x] Federation disabled in Matrix homeserver
- [x] All container images loaded from internal storage

## Data Sovereignty
- [x] All data stored on internal storage (not cloud)
- [x] No external cloud service connections
- [x] Backups stored on internal backup system

## Identity Management
- [x] Authentication via internal directory (none configured for MVP)
- [x] No external identity provider connections
- [x] No SSO to cloud providers

## Audit Trail
- [x] All administrative actions logged to container logs
- [x] Logs stored on internal system (/var/log/docker/)
- [x] Retention policy: 30 days (configurable)

## Security Baseline
- [x] TLS certificates generated locally
- [x] All service communication encrypted
- [x] Database connections require passwords
- [x] No debug/insecure modes enabled

## Certification

Certified Compliant By: _________________________ (Signature)
Date: _________________________ (ISO 8601)
Organization: _________________________ (Name)

## Approvals

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Infrastructure Lead | | | |
| Security Officer | | | |
| Compliance Officer | | | |

EOF

# Sign and date the document
```

### Step 5.2: Archive Evidence

```bash
# Create dated backup of deployment configuration
mkdir -p /var/lib/backups/air-gapped
cp docker-compose-air-gapped.yml /var/lib/backups/air-gapped/
cp synapse-air-gapped.yaml /var/lib/backups/air-gapped/
cp element-config-air-gapped.json /var/lib/backups/air-gapped/
cp .env.air-gapped /var/lib/backups/air-gapped/ 2>/dev/null || true

# Create hash manifest for integrity
cd /var/lib/backups/air-gapped
find . -type f -exec sha256sum {} \; > MANIFEST.sha256

# Store date of certification
echo "Certified: $(date -Iseconds)" > CERTIFICATION.txt
```

---

## Phase 6: Operational Procedures

### Regular Backups

```bash
# Daily backup (internal storage only)
docker-compose -f docker-compose-air-gapped.yml exec postgres \
  pg_dump -U postgres synapse_db | \
  gzip > /var/lib/backups/synapse-backup-$(date +%Y%m%d).sql.gz

# Retention: Keep 30 days
find /var/lib/backups -name "synapse-backup-*.sql.gz" -mtime +30 -delete
```

### Image Updates in Air-Gapped Mode

When new container versions are needed:

1. **On connected host**:
   ```bash
   # Pull new version
   docker pull synapse:v1.96
   
   # Save to storage
   docker save synapse:v1.96 | gzip > /tmp/images/synapse__v1.96.tar.gz
   ```

2. **Transfer to air-gapped host** (via USB/internal network)

3. **On air-gapped host**:
   ```bash
   # Load new image
   gunzip -c /tmp/images/synapse__v1.96.tar.gz | docker load
   
   # Update docker-compose-air-gapped.yml with new version
   # Recreate container with new image
   docker-compose -f docker-compose-air-gapped.yml up -d synapse
   ```

### Health Monitoring

```bash
# Monitor service health
watch -n 5 'docker-compose -f docker-compose-air-gapped.yml ps'

# Check logs for errors
docker-compose -f docker-compose-air-gapped.yml logs --tail=50

# Alert on service restart
docker events --filter 'status=start' --format '{{.Actor.Attributes.name}} restarted at {{.Time}}'
```

---

## Troubleshooting

### Problem: "Image not found" on deployment

**Solution**: Images must be pre-loaded via `load-images.sh`
```bash
bash scripts/air-gapped/load-images.sh /path/to/images/
```

### Problem: "Cannot reach synapse/element" after deployment

**Solution**: Check internal DNS and network
```bash
# Verify DNS
nslookup synapse.internal

# Check container network
docker network inspect net-app | grep -A5 '"Containers"'

# Check firewall rules
sudo iptables -L -n
```

### Problem: "Connection refused" to external services

**This is expected!** In air-gapped mode, all external connections should be blocked. If your deployment requires external connectivity (e.g., for SSO), that's a different deployment mode.

### Problem: "Out of disk space"

**Solution**: Check volume usage
```bash
docker volume ls
docker volume inspect <volume-name>

# Remove old backup images
docker image prune -a --force
```

---

## Verification Checklist

Before considering deployment complete:

- [ ] All 10 required images are pre-loaded
- [ ] All services healthy in `docker-compose ps`
- [ ] `validate-deployment.sh` passes all critical checks
- [ ] Code-Server accessible on port 8080
- [ ] Matrix Synapse responding on port 8008
- [ ] Element Web accessible
- [ ] Federation disabled (404 on :8448)
- [ ] No external network connectivity (DNS fails)
- [ ] Compliance attestation document created and signed
- [ ] Backups configured and tested
- [ ] Operational runbooks reviewed by team

---

## Rollback / Decommission

To completely remove air-gapped deployment:

```bash
# Stop all services
docker-compose -f docker-compose-air-gapped.yml down -v

# Remove image files
rm -rf /tmp/images/

# Clear data volumes
docker volume prune -a --force

# Restore /etc/hosts (remove matrix.internal entries)
# Remove environment file
rm -f .env.air-gapped
```

---

## Contact & Support

**Deployment Issues**: See `TROUBLESHOOTING.md` section above  
**Architecture Questions**: Review `DEPLOYMENT-ARCHITECTURE-SUMMARY.md`  
**Security Review**: Contact compliance@organization  
**Emergency**: See `EMERGENCY-PROCEDURES.md`  

---

**Document Version**: 1.0  
**Last Updated**: April 20, 2026  
**Status**: Ready for Production Deployment  
**Next Review**: May 20, 2026  
