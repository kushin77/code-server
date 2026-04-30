# Appsmith OAuth Setup - Deployment Checklist & Summary

**Date:** April 30, 2026  
**Status:** 🟡 IN PROGRESS - Awaiting Google OAuth Credentials  
**Estimated Time:** 2 hours (includes 15-20 min Google OAuth setup + 30 min deployment + 1 hour testing)

---

## What Was Done

### ✅ Completed

1. **Code Review & RCA Analysis**
   - Identified root cause: OAuth credentials missing (empty defaults)
   - Documented security concerns and fixes
   - File: [CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md](CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md)

2. **docker-compose.enterprise.yml Updated**
   - Changed Google OAuth from optional to required
   - Added comments explaining OAuth configuration
   - GitHub OAuth remains optional
   - Before: `${OAUTH_GOOGLE_CLIENT_ID:-}` (empty default)
   - After: `${OAUTH_GOOGLE_CLIENT_ID}` (required, will fail if not set)

3. **Verification Script Created**
   - File: `verify-appsmith-oauth.sh`
   - Checks .env file, OAuth credentials, docker-compose, Caddyfile, DNS, service status
   - Usage: `./verify-appsmith-oauth.sh`

4. **Google OAuth Setup Guide Created**
   - File: [GOOGLE_OAUTH_SETUP_GUIDE.md](GOOGLE_OAUTH_SETUP_GUIDE.md)
   - Step-by-step instructions for creating OAuth credentials
   - Deployment instructions with verification
   - VPN test verification included
   - Troubleshooting section

5. **Documentation**
   - All guides and checklists are production-ready
   - Security best practices included
   - Troubleshooting procedures documented

---

## What You Need to Do

### 🔴 CRITICAL - Required to Deploy

#### Step 1: Create Google OAuth Credentials (15-20 minutes)

**Reference:** [GOOGLE_OAUTH_SETUP_GUIDE.md](GOOGLE_OAUTH_SETUP_GUIDE.md) - Steps 1-3

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create new project: "kushnir-cloud"
3. Enable Google+ API
4. Configure OAuth consent screen with:
   - App name: "Hermes Agent Portal"
   - Authorized domain: "kushnir.cloud"
5. Create OAuth 2.0 Web Application credentials
6. **Important:** Add these redirect URIs in Google Cloud Console:
   ```
   https://kushnir.cloud/
   https://kushnir.cloud/auth/oauth2/google/callback
   https://kushnir.cloud/oauth/callback
   http://localhost:8084/
   ```
7. Copy the Client ID and Client Secret

**You'll get:**
```
CLIENT_ID:     your-client-id.apps.googleusercontent.com
CLIENT_SECRET: your-client-secret-here
```

#### Step 2: Create .env File (5 minutes)

**Reference:** [GOOGLE_OAUTH_SETUP_GUIDE.md](GOOGLE_OAUTH_SETUP_GUIDE.md) - Step 4

```bash
# SSH to code-server host
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server

# Create .env file with your credentials from Step 1
cat > .env << 'EOF'
OAUTH_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
OAUTH_GOOGLE_CLIENT_SECRET=your-client-secret
APPSMITH_INSTANCE_NAME=kushnir-cloud-ide
APPSMITH_DISABLE_TELEMETRY=true
APPSMITH_MAIL_ENABLED=false
EOF

# Secure the file
chmod 600 .env
```

#### Step 3: Verify Configuration (5 minutes)

```bash
# Run verification script
cd /home/akushnir/code-server
chmod +x verify-appsmith-oauth.sh
./verify-appsmith-oauth.sh

# Expected output:
# ✓ .env file exists
# ✓ OAUTH_GOOGLE_CLIENT_ID is set
# ✓ OAUTH_GOOGLE_CLIENT_SECRET is set
# ✓ ALL CRITICAL CHECKS PASSED
# ✓ READY FOR DEPLOYMENT
```

#### Step 4: Deploy Appsmith with OAuth (10 minutes)

**Reference:** [GOOGLE_OAUTH_SETUP_GUIDE.md](GOOGLE_OAUTH_SETUP_GUIDE.md) - Step 5

```bash
# Navigate to code-server directory
cd /home/akushnir/code-server

# Stop any running Appsmith
docker compose -f docker-compose.enterprise.yml stop code-server-appsmith

# Start Appsmith with OAuth credentials
source .env
docker compose -f docker-compose.enterprise.yml up -d code-server-appsmith

# Wait for startup (60 seconds)
sleep 60

# Verify it's running
docker compose -f docker-compose.enterprise.yml ps code-server-appsmith

# Should show: Running (healthy)
```

#### Step 5: Test OAuth Login (10 minutes)

1. Open browser and go to: **https://kushnir.cloud/**
2. Verify you see "Sign in with Google" button
3. Click button
4. Log in with your Google account
5. After login, verify Appsmith dashboard loads
6. Check browser console (F12) for any errors

---

## VPN Test Verification

### Post-VPN Checklist

After the VPN test, run this verification:

```bash
# SSH to code-server
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server

# 1. Check DNS resolution
nslookup kushnir.cloud
# Should resolve to: 192.168.168.31

# 2. Verify Appsmith is running
docker compose ps code-server-appsmith
# Should show: Running (healthy)

# 3. Check OAuth credentials are still configured
source .env
echo "OAuth configured: ${OAUTH_GOOGLE_CLIENT_ID:0:20}..."

# 4. Verify HTTPS works
curl -I https://kushnir.cloud/
# Should return: 200 OK or similar

# 5. Full verification
./verify-appsmith-oauth.sh
# Should show: ✓ ALL CRITICAL CHECKS PASSED
```

---

## Expected Results

### After Deployment (Success Criteria)

- ✅ HTTPS://kushnir.cloud loads without ERR_CONNECTION_CLOSED
- ✅ "Sign in with Google" button is visible
- ✅ OAuth login redirects to Google
- ✅ After authentication, user sees Appsmith dashboard
- ✅ No JavaScript errors in browser console
- ✅ Appsmith logs show no OAuth errors: `docker logs code-server-appsmith | grep -i oauth`
- ✅ VPN test connectivity verified
- ✅ Services remain operational after VPN restoration

### Verification Commands

```bash
# Check no OAuth errors in logs
docker logs code-server-appsmith | grep -i "oauth.*error"
# Should show: (nothing)

# Check Appsmith is healthy
curl -s http://localhost:8084/health
# Should return: OK or success

# Check HTTPS connectivity
curl -I https://kushnir.cloud/
# Should show: HTTP/1.1 200 OK or 301/302 redirect

# Check environment variables are loaded
docker exec code-server-appsmith env | grep OAUTH_GOOGLE
# Should show: OAUTH_GOOGLE_CLIENT_ID=your-client-id...
```

---

## Troubleshooting During Deployment

### If Appsmith Won't Start

```bash
# Check logs
docker logs code-server-appsmith

# Common issues:
# 1. "OAUTH_GOOGLE_CLIENT_ID not found"
#    → .env file not created or not loaded
#    → Run: source .env && docker compose up
#
# 2. "Port 8084 already in use"
#    → Stop conflicting container or change port
#
# 3. "Connection refused"
#    → Docker may not be running
#    → Run: docker ps to check
```

### If OAuth Login Fails

```bash
# Check OAuth configuration in container
docker exec code-server-appsmith env | grep OAUTH

# Should show:
# OAUTH_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
# OAUTH_GOOGLE_CLIENT_SECRET=your-client-secret

# If empty, restart with .env loaded
source .env
docker compose restart code-server-appsmith
sleep 60
```

### If DNS Resolution Fails (Post-VPN)

```bash
# Verify hosts file
cat /etc/hosts | grep kushnir

# If missing, add manually
echo "192.168.168.31 kushnir.cloud" | sudo tee -a /etc/hosts

# Test resolution
nslookup kushnir.cloud
```

---

## Files Created/Modified

| File | Status | Purpose |
|------|--------|---------|
| [CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md](CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md) | ✅ Created | Comprehensive code review & RCA |
| [GOOGLE_OAUTH_SETUP_GUIDE.md](GOOGLE_OAUTH_SETUP_GUIDE.md) | ✅ Created | Step-by-step OAuth setup |
| `verify-appsmith-oauth.sh` | ✅ Created | Automated verification |
| [docker-compose.enterprise.yml](docker-compose.enterprise.yml) | ✅ Modified | Google OAuth now required |
| `.env` | ⏳ TO CREATE | OAuth credentials (user provides) |
| `APPSMITH_DEPLOYMENT_GUIDE.md` | ✓ Existing | Reference |
| `APPSMITH_KUSHNIR_CLOUD_SECURE_INTEGRATION.md` | ✓ Existing | Reference |

---

## Next Steps (Recommended Order)

### Phase 1: Setup (Today)
- [ ] User creates Google OAuth credentials ([Guide](GOOGLE_OAUTH_SETUP_GUIDE.md))
- [ ] User creates `.env` file with credentials
- [ ] Run `verify-appsmith-oauth.sh` to confirm
- [ ] Deploy Appsmith: `docker compose up -d code-server-appsmith`

### Phase 2: Testing (Today + 1)
- [ ] Test OAuth login works
- [ ] Verify Appsmith dashboard loads
- [ ] Check for any errors in logs
- [ ] Document any custom settings

### Phase 3: VPN Test (Tomorrow)
- [ ] Perform VPN test/maintenance
- [ ] Run post-VPN verification checklist
- [ ] Verify OAuth still works after VPN
- [ ] Confirm kushnir.cloud is accessible

### Phase 4: Documentation (After Verification)
- [ ] Document actual OAuth setup details
- [ ] Note any environment-specific settings
- [ ] Create runbook for OAuth troubleshooting
- [ ] Archive this checklist as completed

---

## Security Notes

⚠️ **Important - Keep These Safe:**

1. **Never commit .env to git**
   ```bash
   echo ".env" >> .gitignore
   git add .gitignore && git commit -m "Add .env to gitignore"
   ```

2. **Protect OAuth secret**
   ```bash
   chmod 600 .env          # Only owner can read
   ls -la .env             # Verify permissions show: -rw-------
   ```

3. **Rotate credentials every 90 days**
   - Create new OAuth credentials in Google Cloud
   - Update .env file
   - Delete old credentials

4. **Monitor OAuth usage**
   - Check Appsmith logs regularly
   - Review Google Cloud Console audit logs
   - Alert on authentication failures

---

## Support Resources

- 📖 [Google OAuth Setup Guide](GOOGLE_OAUTH_SETUP_GUIDE.md) - Full instructions
- 📋 [Code Review Document](CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md) - Technical details
- 🔍 [Verification Script](verify-appsmith-oauth.sh) - Automated checks
- 📚 [Appsmith Docs](https://docs.appsmith.com/) - Official documentation
- 🔐 [Google OAuth Docs](https://developers.google.com/identity/protocols/oauth2) - OAuth reference

---

## Completion Status

### Before You Start
- [ ] You have Google account access
- [ ] You have SSH access to 192.168.168.31
- [ ] You understand OAuth flow (see guide)
- [ ] You have 2 hours available for full setup + testing

### After Completion
- ✅ OAuth is configured and working
- ✅ Users can log in with Google account
- ✅ All services verified operational
- ✅ VPN test passed with connectivity intact
- ✅ Documentation is complete

---

**Ready to proceed?** Start with [GOOGLE_OAUTH_SETUP_GUIDE.md](GOOGLE_OAUTH_SETUP_GUIDE.md) - Step 1.

Questions? Check the [Code Review](CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md) for technical details or [Troubleshooting](#troubleshooting-during-deployment) section above.
