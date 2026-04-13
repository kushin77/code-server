# DEPLOYMENT EXECUTION GUIDE
## Step-by-Step Instructions for IaC Production Deployment

**Status:** Ready for deployment validation  
**Target Host:** 192.168.168.31  
**Domain:** ide.kushnir.cloud  
**Deployment User:** akushnir  
**Created:** 2026-04-14  

---

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Environment Configuration](#environment-configuration)
3. [Credential Setup](#credential-setup)
4. [Deployment Execution](#deployment-execution)
5. [Validation & Testing](#validation--testing)
6. [Troubleshooting](#troubleshooting)
7. [Post-Deployment](#post-deployment)

---

## Pre-Deployment Checklist

### ✅ Step 1: Run Pre-Flight Validation

This script verifies all prerequisites are met:

```bash
cd /path/to/code-server-enterprise/scripts
bash pre-flight-checklist.sh
```

**Expected Output:**
- All environment prerequisites ✅
- All configuration files present ✅
- All automation scripts present and executable ✅
- Git repository clean or only expected changes ✅
- Docker available and running ✅
- SSH connectivity verified ✅

**If Pre-Flight Fails:**
- Read the failures carefully (❌ items)
- Fix each blocker before continuing
- Re-run pre-flight-checklist.sh to confirm all pass
- Do not proceed to deployment until all prerequisites pass

### ✅ Step 2: Verify SSH Access

Test SSH connectivity to the deployment host:

```bash
# Test connectivity
ssh -v akushnir@192.168.168.31 "echo 'SSH access verified'"

# View system info (optional, for confidence)
ssh akushnir@192.168.168.31 "uname -a && docker --version && docker-compose --version"
```

**Expected Output:**
```
SSH access verified
Linux deploy-host 5.x.x-x #x SMP ... x86_64 GNU/Linux
Docker version 28.x.x
Docker Compose version v2.x.x
```

**If SSH Fails:**
- Check network connectivity: `ping 192.168.168.31`
- Verify SSH key setup: `ssh-keyscan -H 192.168.168.31 >> ~/.ssh/known_hosts`
- Check firewall rules: `nmap -p 22 192.168.168.31`
- Verify deployment user has SSH access

---

## Environment Configuration

### ✅ Step 3: Set Deployment Environment Variables

Configure variables for your deployment. Create a `.env.deployment` file:

```bash
cat > .env.deployment << 'EOF'
# Domain Configuration
DOMAIN="ide.kushnir.cloud"

# Deployment Target
DEPLOY_HOST="192.168.168.31"
DEPLOY_USER="akushnir"
DEPLOY_PORT="22"

# CloudFlare API (for DNS automation)
CLOUDFLARE_API_TOKEN="your_cloudflare_api_token_here"
CLOUDFLARE_ZONE_ID="your_zone_id_here"

# Google OAuth (for authentication)
GOOGLE_CLIENT_ID="your_client_id_here"
GOOGLE_CLIENT_SECRET="your_client_secret_here"

# Email (for Let's Encrypt ACME)
ACME_EMAIL="your-email@example.com"

# Code Server Configuration
CODE_SERVER_PASSWORD=""  # Leave empty to auto-generate
OLLAMA_MODEL="llama2"

# Code Server Admin Email (for OAuth)
ADMIN_EMAIL="admin@example.com"
EOF
```

**Note:** The following will be auto-generated:
- `CODE_SERVER_PASSWORD` (32-byte random)
- `OAUTH2_PROXY_COOKIE_SECRET` (32-byte random)
- `REDIS_PASSWORD` (16-byte random)

You can optionally provide these in the .env.deployment file.

### ✅ Step 4: Load Environment Variables

```bash
# Load your deployment configuration
source .env.deployment

# Verify variables loaded
echo "Domain: $DOMAIN"
echo "Deploy Host: $DEPLOY_HOST"
echo "Deploy User: $DEPLOY_USER"
```

---

## Credential Setup

### ✅ Step 5: Prepare Credential Files

The deployment process requires some credentials. Prepare them now:

#### Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create or select your project
3. Navigate to: APIs & Services → Credentials
4. Create OAuth 2.0 Client ID (Web application)
5. Authorized redirect URIs: `https://ide.kushnir.cloud/oauth2/callback`
6. Copy Client ID and Client Secret
7. Export environment variables:

```bash
export GOOGLE_CLIENT_ID="YOUR_CLIENT_ID"
export GOOGLE_CLIENT_SECRET="YOUR_CLIENT_SECRET"
```

#### CloudFlare API Token

1. Go to [CloudFlare Dashboard](https://dash.cloudflare.com)
2. Navigate to: My Profile → API Tokens
3. Create Token → DNS (template recommended)
4. Permissions: Zone:DNS:Edit, Zone:Zone:Read
5. Specific zone resources: ide.kushnir.cloud (or your domain)
6. Export token:

```bash
export CLOUDFLARE_API_TOKEN="YOUR_API_TOKEN"
```

#### Let's Encrypt ACME Email

```bash
export ACME_EMAIL="your-email@example.com"
```

### ✅ Step 6: Validate Credentials

Run the pre-flight checklist again to verify credentials:

```bash
bash pre-flight-checklist.sh
```

All environment variables should now be validated.

---

## Deployment Execution

### ✅ Step 7: Execute Deployment

The deployment orchestration script automates all steps:

```bash
# Make script executable if needed
chmod +x automated-deployment-orchestration.sh

# Execute deployment
bash automated-deployment-orchestration.sh
```

**Deployment Flow (8 Steps):**

| Step | Description | Duration | Status |
|------|-------------|----------|--------|
| 1. Validate Environment | Checks local prerequisites | 30s | Pre-deployment |
| 2. Configure OAuth | Setup Google OAuth | 1m | Interactive |
| 3. Generate Configuration | Create .env + secrets | 1m | Automated |
| 4. Configure DNS | Update CloudFlare records | 2m | API-driven |
| 5. Deploy Services | Execute docker-compose up | 3m | Container orchestration |
| 6. Validate Services | Verify 5/5 services running | 1m | Health checks |
| 7. Configure TLS | Setup ACME + Let's Encrypt | 2m | Caddy auto-provisioning |
| 8. Generate Summary | Create deployment report | 1m | Documentation |

**Total Expected Duration:** 10-15 minutes

### Expected Output

```
╔══════════════════════════════════════════════════╗
║    AUTOMATED DEPLOYMENT ORCHESTRATION            ║
║    Production IaC Deployment                     ║
╚══════════════════════════════════════════════════╝

[→] STEP 1: VALIDATE ENVIRONMENT
    ✓ SSH connectivity verified
    ✓ Docker commands available
    ✓ CloudFlare credentials valid
    ✓ Prerequisites validated

[→] STEP 2: CONFIGURE OAUTH
    ✓ Google OAuth client credentials provided
    ✓ OAuth configuration generated

[→] STEP 3: GENERATE CONFIGURATION
    ✓ Auto-generated CODE_SERVER_PASSWORD
    ✓ Auto-generated OAUTH2_PROXY_COOKIE_SECRET
    ✓ Auto-generated REDIS_PASSWORD
    ✓ Generated .env file

... (continues through steps 4-8) ...

╔══════════════════════════════════════════════════╗
║  DEPLOYMENT COMPLETE ✅                          ║
╚══════════════════════════════════════════════════╝

Deployment Summary:
- Deployment ID: deploy-20260414-120000
- Target: ide.kushnir.cloud (192.168.168.31)
- Services: 5/5 running
- Status: SUCCESS
```

---

## Validation & Testing

### ✅ Step 8: Run Comprehensive Validation Suite

After deployment completes, run the full validation:

```bash
# Make script executable if needed
chmod +x deployment-validation-suite.sh

# Execute validation
bash deployment-validation-suite.sh
```

**Validation Phases (8 Phases):**

| Phase | Tests | Duration | Pass Criteria |
|-------|-------|----------|---------------|
| 1 | Local prerequisites | 1m | All checks pass |
| 2 | SSH connectivity to host | 1m | Remote system info retrieved |
| 3 | Deploy services | 5m | All services deployed |
| 4 | Service availability | 1m | 5/5 services responding |
| 5 | Health checks | 2m | Config valid, resources adequate |
| 6 | Performance benchmarks | 3m | Response times <1s |
| 7 | Security audit | 2m | No hardcoded secrets, proper permissions |
| 8 | Report generation | 1m | DEPLOYMENT-VALIDATION-REPORT.md created |

**Total Expected Duration:** 15-20 minutes

### ✅ Step 9: Review Validation Report

After validation completes:

```bash
# View the validation report
cat DEPLOYMENT-VALIDATION-REPORT.md

# Or open in your editor
code DEPLOYMENT-VALIDATION-REPORT.md
```

**Report Should Show:**
- ✅ All phases completed successfully
- ✅ 5/5 services running and healthy
- ✅ Performance metrics within targets
- ✅ Security audit passed
- ✅ System ready for production use

### ✅ Step 10: Manual Smoke Tests

Perform basic manual testing:

```bash
# 1. Test Code Server accessibility
curl -k https://ide.kushnir.cloud/

# 2. Test OAuth integration
# Visit https://ide.kushnir.cloud in browser
# Should redirect to Google login

# 3. Test API availability
curl https://ide.kushnir.cloud/api/health

# 4. SSH into deployment host and check services
ssh akushnir@192.168.168.31
docker ps  # Should show 5 containers
docker-compose logs -f  # Watch logs
```

---

## Troubleshooting

### Issue: Pre-flight Fails - Missing Commands

**Symptom:** Pre-flight checklist reports missing commands (docker, git, etc.)

**Solution:**
```bash
# Linux/macOS - Install required tools
# Ubuntu/Debian:
sudo apt-get update && sudo apt-get install -y \
  docker.io docker-compose git curl jq openssl

# macOS (with Homebrew):
brew install docker docker-compose git curl jq openssl

# Windows - Use WSL or install Docker Desktop
```

### Issue: SSH Connection Refused

**Symptom:** `ssh: connect to host 192.168.168.31 port 22: Connection refused`

**Solution:**
```bash
# 1. Verify network connectivity
ping 192.168.168.31

# 2. Check SSH service on remote
ssh -vv akushnir@192.168.168.31

# 3. Verify SSH keys are configured
ls -la ~/.ssh/id_rsa

# 4. Add remote to known_hosts
ssh-keyscan -H 192.168.168.31 >> ~/.ssh/known_hosts

# 5. Test with explicit identity
ssh -i ~/.ssh/id_rsa akushnir@192.168.168.31
```

### Issue: CloudFlare API Fails

**Symptom:** `Error: CloudFlare API token invalid or zone not found`

**Solution:**
```bash
# 1. Verify token is set
echo $CLOUDFLARE_API_TOKEN

# 2. Test CloudFlare API directly
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" | jq

# 3. Verify zone ID
curl -X GET "https://api.cloudflare.com/client/v4/zones?name=kushnir.cloud" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# 4. Update environment variables and retry
export CLOUDFLARE_ZONE_ID="correct_zone_id"
bash automated-deployment-orchestration.sh
```

### Issue: Docker Compose Fails

**Symptom:** `docker-compose: command not found` or `version mismatch`

**Solution:**
```bash
# 1. Verify Docker Compose version
docker-compose --version

# 2. Update to latest
# Ubuntu/Debian:
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 3. Or use docker compose (v2 integrated)
docker compose --version
docker compose up -d  # Note: no hyphen
```

### Issue: Services Don't Start

**Symptom:** `docker ps` shows stopped containers or they crash immediately

**Solution:**
```bash
# 1. Check container logs
ssh akushnir@192.168.168.31
docker-compose logs --tail=50 -f

# 2. Verify environment variables are set
docker-compose config | grep -E "DOMAIN|PASSWORD|SECRET"

# 3. Check disk space
df -h

# 4. Restart services
docker-compose down
docker-compose up -d

# 5. Re-run validation
bash deployment-validation-suite.sh
```

### Issue: HTTPS Certificate Not Provisioned

**Symptom:** Browser shows untrusted certificate warning

**Solution:**
```bash
# 1. Check Caddy logs for ACME errors
ssh akushnir@192.168.168.31
docker-compose logs caddy | grep acme

# 2. Verify DNS records exist
nslookup ide.kushnir.cloud

# 3. Wait for DNS propagation (can take up to 10 minutes)
dig ide.kushnir.cloud

# 4. Manual certificate request (Caddy will retry automatically)
# But if needed, restart Caddy
docker-compose restart caddy

# 5. Watch the logs
docker-compose logs -f caddy

# Certificate should be provisioned on next request
curl https://ide.kushnir.cloud/
```

---

## Post-Deployment

### ✅ Step 11: Documentation & Handoff

1. **Archive Deployment Report**
   ```bash
   cp DEPLOYMENT-VALIDATION-REPORT.md \
      deployments/DEPLOYMENT-VALIDATION-REPORT-$(date +%Y%m%d-%H%M%S).md
   ```

2. **Commit to Git**
   ```bash
   git add .
   git commit -m "Deployment: Production IaC deployment completed on 192.168.168.31"
   git push origin main
   ```

3. **Document Known Issues**
   ```bash
   # Create issue tracker if any issues found
   # Update TROUBLESHOOTING.md with any discovered issues
   ```

### ✅ Step 12: Monitoring & Operations

1. **Enable Monitoring**
   ```bash
   # Monitor logs continuously
   ssh akushnir@192.168.168.31
   docker-compose logs -f
   ```

2. **Set Up Alerting** (Optional)
   - Monitor disk space: `df -h`
   - Monitor services: `docker ps`
   - Monitor network: `netstat -an | grep ESTABLISHED`

3. **Scheduled Backups**
   ```bash
   # Add to crontab for automatic backups
   0 2 * * * ssh akushnir@192.168.168.31 \
     "docker-compose exec redis redis-cli BGSAVE"
   ```

### ✅ Step 13: Team Communication

1. Send deployment notification to team
2. Share access instructions to authorized users
3. Point users to authentication setup guide
4. Provide support contact information

---

## Quick Reference Commands

### Deployment Commands
```bash
# Full deployment
bash automated-deployment-orchestration.sh

# Full validation
bash deployment-validation-suite.sh

# Pre-flight check
bash pre-flight-checklist.sh
```

### Remote SSH Commands
```bash
# Check services
ssh akushnir@192.168.168.31 "docker ps"

# View logs
ssh akushnir@192.168.168.31 "docker-compose logs -f"

# Restart services
ssh akushnir@192.168.168.31 "docker-compose restart"

# Access Code Server
# Browser: https://ide.kushnir.cloud
# Login with Google OAuth
```

### Debugging Commands
```bash
# Local environment check
bash pre-flight-checklist.sh

# SSH connectivity test
ssh -vv akushnir@192.168.168.31 "echo test"

# Docker status on remote
ssh akushnir@192.168.168.31 "docker stats"

# View specific service logs
ssh akushnir@192.168.168.31 "docker-compose logs caddy"
```

---

## Success Criteria

✅ **Deployment is successful when:**

- [x] Pre-flight checklist passes with no blockers
- [x] SSH connectivity to 192.168.168.31 established
- [x] Orchestration script runs to completion
- [x] All 5 services deployed and running
- [x] Validation suite completes all 8 phases
- [x] Security audit passes
- [x] HTTPS accessible at ide.kushnir.cloud
- [x] OAuth login works
- [x] Code Server accessible and functional
- [x] Performance benchmarks acceptable
- [x] All logs show normal operation

🎉 **When all criteria met:** Production deployment is complete and ready for use.

---

## Contact & Support

For issues or questions:
1. Review troubleshooting section above
2. Check deployment logs: `DEPLOYMENT-VALIDATION-REPORT.md`
3. Review script output for specific error messages
4. Consult documentation: `PRODUCTION-DEPLOYMENT-IAC.md`

---

**Document Version:** 1.0  
**Created:** 2026-04-14  
**Status:** Ready for Execution  
**Next Phase:** Execute pre-flight checklist → deployment orchestration → validation suite

