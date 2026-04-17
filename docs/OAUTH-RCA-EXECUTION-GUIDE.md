# OAuth RCA Execution Guide - Issue #644 & #645

**Status**: Ready to Execute (Diagnostic Runbook in PR #648)  
**Target Issues**: #643 (parent), #644 (RCA), #645 (implementation)  
**Timeline**: 3-4 hours (RCA + initial findings)  
**Owner**: @kushin77  

---

## Executive Summary

This guide walks through executing the OAuth RCA diagnostic runbook (docs/OAUTH-RCA-DIAGNOSTIC-RUNBOOK.md from PR #648) against the production environment at `192.168.168.31`.

**Objective**: Diagnose why users see `org_internal` 403 errors when attempting to log into kushnir.cloud.

**Expected Outcome**: Root cause identified, findings documented, implementation scenarios prepared for #645.

---

## Pre-Execution Checklist

### Environment Requirements
- [ ] SSH access to production host: `ssh akushnir@192.168.168.31`
- [ ] Docker Compose running on 192.168.168.31
- [ ] Access to Google Cloud Console (OAuth app configuration)
- [ ] Access to production logs (code-server, oauth2-proxy, caddy)
- [ ] Browser access to kushnir.cloud for manual testing

### Documentation Requirements
- [ ] Have docs/OAUTH-RCA-DIAGNOSTIC-RUNBOOK.md available (in PR #648)
- [ ] Have docs/OAUTH-IMPLEMENTATION-PLAYBOOK.md available (scenarios reference)
- [ ] Have Google OAuth app configuration details available
- [ ] Have production Caddyfile and docker-compose.yml available

### Access Credentials
- [ ] Gather Google OAuth credentials (client ID, secret)
- [ ] Gather code-server admin credentials (if needed for testing)
- [ ] Gather portal admin credentials (if needed for testing)

---

## RCA Execution Plan (4-Phase Approach)

### Phase 1: Routing & Connectivity (30 minutes)

**Goal**: Verify OAuth proxy instances are accessible and routing is correct

#### Step 1.1: Verify Proxy Instances

```bash
# SSH to production
ssh akushnir@192.168.168.31

# Check oauth2-proxy containers
docker compose ps | grep oauth2-proxy
```

**Expected Output**:
```
oauth2-proxy:4180    UP    (IDE proxy)
oauth2-proxy-portal:4181    UP    (Portal proxy)
```

**What to Check**:
- [ ] Both containers are running (Status: Up)
- [ ] Port mappings correct (4180 for IDE, 4181 for portal)
- [ ] Container health status (should be "healthy" or "starting")

#### Step 1.2: Test Proxy Connectivity

```bash
# From production host
curl -v http://oauth2-proxy:4180/oauth2/start
curl -v http://oauth2-proxy-portal:4181/oauth2/start
```

**Expected**:
- Both should return HTTP 302 or 307 (redirect to Google)
- Should NOT return 503 (Service Unavailable) or 500 (Internal Error)

**If Failed**:
- Check proxy logs: `docker compose logs oauth2-proxy`
- Check for configuration errors in oauth2-proxy.cfg

#### Step 1.3: Verify Caddy Routing

```bash
# From production host
curl -v https://kushnir.cloud/ -H "Host: kushnir.cloud"
curl -v https://ide.kushnir.cloud/ -H "Host: ide.kushnir.cloud"
```

**Expected**:
- kushnir.cloud → redirects to oauth2-proxy-portal (port 4181)
- ide.kushnir.cloud → redirects to oauth2-proxy (port 4180)
- Should see Location: header with redirect

**If Failed**:
- Check Caddyfile for routing rules
- Check Caddy logs: `docker compose logs caddy`

### Phase 2: OAuth Configuration (45 minutes)

**Goal**: Verify Google OAuth app is configured correctly

#### Step 2.1: Inspect OAuth Configuration

```bash
# From production host
docker compose exec oauth2-proxy-portal env | grep -i google
docker compose exec oauth2-proxy-portal env | grep -i oauth
```

**Expected**:
```
OAUTH2_PROXY_CLIENT_ID=<client-id>.apps.googleusercontent.com
OAUTH2_PROXY_CLIENT_SECRET=<secret>
OAUTH2_PROXY_REDIRECT_URI=https://kushnir.cloud/oauth2/callback
OAUTH2_PROXY_COOKIE_SECRET=<secret>
```

**What to Check**:
- [ ] CLIENT_ID matches Google Cloud Console app
- [ ] CLIENT_SECRET is not blank and matches Console
- [ ] REDIRECT_URI matches domain (https://kushnir.cloud/oauth2/callback)
- [ ] COOKIE_SECRET is set (min 16 bytes)

#### Step 2.2: Verify Google OAuth App Configuration

**In Google Cloud Console**:
1. Navigate to OAuth 2.0 > Application Credentials
2. Edit the OAuth 2.0 Client ID for code-server

**Verify**:
- [ ] Authorized JavaScript origins: `https://kushnir.cloud`
- [ ] Authorized redirect URIs: `https://kushnir.cloud/oauth2/callback`
- [ ] Authorized users (if org_internal is set): Check email domain restrictions
- [ ] Note if "org_internal" restriction is present (Google's way of limiting to org)

**Document Findings**:
- [ ] Current origins allowed: _______________
- [ ] Current redirect URIs: _______________
- [ ] Org restriction active: YES / NO
- [ ] If YES, allowed domain(s): _______________

#### Step 2.3: Check oauth2-proxy Configuration

```bash
# From production host
docker compose exec oauth2-proxy-portal cat /etc/oauth2-proxy/oauth2-proxy.cfg | grep -A 10 "client_id\|redirect_uri\|cookie_secret\|whitelist"
```

**Expected**:
- `client_id` matches Google Console
- `redirect_uri` matches domain
- `cookie_secret` is set
- If org_internal, should see `org_internal` setting or similar

**What to Verify**:
- [ ] All values match environment variables from Phase 2.1
- [ ] No typos in URLs
- [ ] Cookie secret is not too short (DL4006 errors earlier)

### Phase 3: Token Flow & Session Handling (45 minutes)

**Goal**: Test actual login flow and verify token exchange

#### Step 3.1: Manual Login Test

```bash
# From your local machine
# 1. Navigate to https://kushnir.cloud
# 2. Click login (should redirect to Google OAuth)
# 3. Note the redirect URL and any errors
# 4. Attempt to sign in with personal Gmail account
# 5. Note the response

# Document:
# - Was Google login page shown? YES / NO
# - After Gmail sign-in, what happened?
#   a) Redirected back to kushnir.cloud (SUCCESS)
#   b) Error page? (document error code)
#   c) Blank page?
#   d) 403 Forbidden?
```

#### Step 3.2: Check oauth2-proxy Token Exchange Logs

```bash
# From production host
docker compose logs oauth2-proxy-portal --tail 100 | grep -i "oauth\|redirect\|token\|callback\|403\|unauthorized"
```

**Key Log Messages to Look For**:
- "Redirecting to Google for login" - Normal
- "Token validation failed" - Problem with token exchange
- "Org restriction failed" - **org_internal issue**
- "Cookie too short" - Cookie secret problem (already fixed in Phase 1)
- "Invalid redirect_uri" - Redirect URL mismatch

**Document Findings**:
- [ ] Last 5 relevant log lines: _______________

#### Step 3.3: Check Cookie Configuration

```bash
# From production host
docker compose exec oauth2-proxy-portal env | grep -i cookie
```

**Expected**:
```
OAUTH2_PROXY_COOKIE_SECRET=<32-char hex string>
OAUTH2_PROXY_COOKIE_NAME=_oauth2_proxy
OAUTH2_PROXY_COOKIE_SECURE=true
OAUTH2_PROXY_COOKIE_HTTPONLY=true
OAUTH2_PROXY_COOKIE_SAMESITE=Lax
```

**Verify**:
- [ ] COOKIE_SECRET is 32 hex characters (16 bytes encoded)
- [ ] COOKIE_SECURE=true (enforces HTTPS)
- [ ] COOKIE_HTTPONLY=true (protects from JavaScript)
- [ ] COOKIE_SAMESITE set correctly

**If Cookie Issues**:
- Generate new secret: `openssl rand -hex 16`
- Update `.env` file
- Redeploy: `docker compose up -d oauth2-proxy-portal`

### Phase 4: Diagnosis & Root Cause Analysis (30 minutes)

**Goal**: Synthesize findings and identify root cause

#### Step 4.1: Map Findings to Scenarios

Using findings from Phases 1-3, determine which scenario from OAUTH-IMPLEMENTATION-PLAYBOOK.md matches:

**Scenario A: Wrong OAuth App Configured**
- Symptom: Login works but shows wrong app name
- Check: Is CLIENT_ID correct?
- **Our finding**: _______________

**Scenario B: Redirect URI Mismatch**
- Symptom: Redirect error after Google login
- Check: Does REDIRECT_URI match Google Console?
- **Our finding**: _______________

**Scenario C: Org Internal Policy Enforcement**
- Symptom: 403 Forbidden, "org_internal" in Google response
- Check: Is org_internal restriction set?
- **Our finding**: _______________

**Scenario D: Cookie/Session Handling**
- Symptom: Login works but session lost on page refresh
- Check: Is cookie secret correct length?
- **Our finding**: _______________

#### Step 4.2: Document Root Cause

```markdown
# RCA Findings for Issue #644

## Problem Statement
Users see [INSERT ERROR] when attempting to log into kushnir.cloud

## Root Cause Analysis

### Phase 1: Routing & Connectivity
- oauth2-proxy-portal container status: [RUNNING/FAILED]
- Proxy accessible from Caddy: [YES/NO]
- Caddy routing correct: [YES/NO]
- **Finding**: [summarize]

### Phase 2: OAuth Configuration
- Google OAuth app credentials configured: [YES/NO]
- Redirect URI correct: [YES/NO]
- Org internal restriction active: [YES/NO]
- **Finding**: [summarize]

### Phase 3: Token Flow
- Manual login attempt result: [SUCCESS/FAILED - describe]
- oauth2-proxy logs show errors: [NONE/ERROR TYPE]
- Cookie configuration correct: [YES/NO]
- **Finding**: [summarize]

### Identified Root Cause
[MAIN CAUSE]

### Recommendations
1. [Fix 1]
2. [Fix 2]
3. [Testing verification]

### Related Scenario
This matches Scenario [A/B/C/D] from OAUTH-IMPLEMENTATION-PLAYBOOK.md
```

---

## Execution Log Template

Use this template to document your RCA execution:

```markdown
# OAuth RCA Execution - [DATE/TIME]

## Phase 1: Routing & Connectivity

### Step 1.1 Results
```

### Step 1.2 Results
```

### Step 1.3 Results
```

### Phase 1 Conclusion
[Summary of routing status]

---

## Phase 2: OAuth Configuration

### Step 2.1 Results
```

### Step 2.2 Google Console Findings
```

### Step 2.3 oauth2-proxy Config Findings
```

### Phase 2 Conclusion
[Summary of OAuth config status]

---

## Phase 3: Token Flow & Session

### Step 3.1 Manual Test Results
```

### Step 3.2 Log Analysis
```

### Step 3.3 Cookie Verification
```

### Phase 3 Conclusion
[Summary of token flow status]

---

## Phase 4: Root Cause Analysis

### Scenario Mapping
- Scenario A (Wrong App): [Match/No Match - why]
- Scenario B (Redirect URI): [Match/No Match - why]
- Scenario C (Org Internal): [Match/No Match - why]
- Scenario D (Cookie): [Match/No Match - why]

### Final Root Cause
[PRIMARY CAUSE with evidence]

### Secondary Issues (if any)
1. [Issue 2]
2. [Issue 3]

### Recommended Fixes
1. [Fix from scenario]
2. [Follow-up verification]

## Next Steps
- [ ] Update issue #644 with findings
- [ ] Create implementation PR based on scenario
- [ ] Plan testing for verification
```

---

## Post-RCA Actions

### If Root Cause Identified
1. **Document Findings**: Post RCA summary to issue #644
2. **Create Implementation PR**: Use matching scenario from OAUTH-IMPLEMENTATION-PLAYBOOK.md
3. **Reference Scenario**: Include scenario steps in implementation PR

### If Multiple Issues Found
1. **Prioritize**: Identify critical path (must-fix for login to work)
2. **Sequence**: Order fixes to minimize risk
3. **Test Each Fix**: Verify each step before proceeding to next

### If Root Cause Not Found
1. **Extend Investigation**: Review additional logs
2. **Check Dependencies**: Verify Caddy, DNS, certificate validity
3. **Engage Team**: Post findings to #644 for wider perspective

---

## Success Criteria

**RCA Complete When**:
- [ ] All 4 phases executed
- [ ] Findings documented for each phase
- [ ] Root cause identified with evidence
- [ ] Matching scenario identified from implementation playbook
- [ ] Issue #644 updated with findings
- [ ] Recommended fix documented
- [ ] Ready to create implementation PR (#645)

---

## Appendix: Quick Reference Commands

```bash
# Quick diagnostics from production host
ssh akushnir@192.168.168.31

# Check containers
docker compose ps | grep oauth

# View proxy config
docker compose exec oauth2-proxy-portal cat /etc/oauth2-proxy/oauth2-proxy.cfg

# View environment variables
docker compose exec oauth2-proxy-portal env | grep -i oauth

# View recent logs
docker compose logs oauth2-proxy-portal --tail 50

# Test connectivity
curl -v http://oauth2-proxy-portal:4181/oauth2/start

# Manual curl test to Caddy
curl -v https://kushnir.cloud/ \
  -H "Host: kushnir.cloud" \
  --cacert /path/to/cert  # if needed
```

---

**Estimated Execution Time**: 3-4 hours  
**Expected Deliverable**: Completed RCA findings posted to #644  
**Next Phase**: Implementation based on identified scenario
