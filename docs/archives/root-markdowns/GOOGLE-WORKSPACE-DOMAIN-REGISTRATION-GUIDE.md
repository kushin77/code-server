# Google Workspace Domain Registration Guide

## Executive Summary

Register **kushnir.cloud** in your Google Workspace (bioenergystrategies.com) to enable the critical path for Issue #983 (QA user creation) and all downstream production deployment work.

**Timeline**: ~20 minutes (15 min automated + 5 min DNS propagation)

---

## Prerequisites Checklist

- [ ] Google Workspace admin access (`akushnir@bioenergystrategies.com` with admin role)
- [ ] GoDaddy API credentials in Google Secret Manager (GODADDY_KEY, GODADDY_SECRET)
- [ ] Domain already registered with GoDaddy (`kushnir.cloud`)
- [ ] `scripts/fetch-gsm-secrets.sh` script available (for credential bootstrap)
- [ ] `scripts/register-google-workspace-domain.sh` script available

---

## Phase 1: Prepare Credentials (2 minutes)

### 1.1 Load GoDaddy API Credentials

Open a terminal in the code-server-enterprise directory and run:

```bash
# This sources GoDaddy credentials from Google Secret Manager
source scripts/fetch-gsm-secrets.sh
```

**Expected Output:**
```
[INFO] Loaded GODADDY_KEY
[INFO] Loaded GODADDY_SECRET
[SUCCESS] GoDaddy credentials ready
```

### 1.2 Verify Credentials

```bash
# Check that both variables are loaded
echo "GODADDY_KEY: ${GODADDY_KEY:0:10}... (truncated)"
echo "GODADDY_SECRET: ${GODADDY_SECRET:0:10}... (truncated)"
```

**Expected Output:**
```
GODADDY_KEY: sso-key-ab... (truncated)
GODADDY_SECRET: xxxxxxxxxxxx... (truncated)
```

---

## Phase 2: Start Domain Registration in Google Workspace (5 minutes)

### 2.1 Access Google Workspace Admin Console

1. Open **admin.google.com** in your browser
2. Use credentials: `akushnir@bioenergystrategies.com` (must have admin role)
3. Navigate to **Domains** (in left sidebar under "Account")

### 2.2 Add New Domain

1. Click **"+ Add a domain"** button
2. Enter domain: `kushnir.cloud`
3. Click **"Continue and verify domain"**

### 2.3 Choose DNS Verification Method

**Important**: Select **"Verify with DNS TXT record"** (NOT other methods)

1. Google Workspace displays a verification value like:
   ```
   google-site-verification=gSxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```
2. **Copy the entire verification value** (including `google-site-verification=` prefix)
3. **Do NOT click "Verify" yet** — you'll do that in Phase 4

---

## Phase 3: Add DNS Record via GoDaddy API (5 minutes)

### 3.1 Run the Domain Registration Script

In your terminal, run the automation script with the verification value from Phase 2:

```bash
bash scripts/register-google-workspace-domain.sh \
  --verification-value "google-site-verification=gSxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

**Replace** `gSxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` with the actual value from Google Workspace Admin.

### 3.2 Expected Script Output

**Success Case:**
```
[INFO] Google Workspace Domain Registration Script
[SUCCESS] GoDaddy credentials loaded
[INFO] Adding TXT record for Google Workspace domain verification...
[INFO] Domain: kushnir.cloud
[INFO] Value: google-site-verification=gSxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
[INFO] TTL: 3600
[INFO] Sending to GoDaddy API...
[SUCCESS] TXT record added successfully
[SUCCESS] DNS configuration complete
[INFO] Next: Go to admin.google.com and click 'Verify' to complete domain registration
```

**Error Case (credentials not loaded):**
```
[ERROR] GODADDY_KEY not set. Run: source scripts/fetch-gsm-secrets.sh
```
→ Go back to Phase 1 and run: `source scripts/fetch-gsm-secrets.sh`

### 3.3 Verify DNS Propagation

The TXT record is now in GoDaddy's DNS system. Google will poll DNS to find it.

**Optional verification** — check if record exists (may take 1-5 minutes to propagate):

```bash
nslookup -type=TXT kushnir.cloud
```

Expected DNS output includes:
```
google-site-verification=gSxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

## Phase 4: Complete Verification in Google Workspace (3 minutes)

### 4.1 Return to Google Workspace Admin Console

1. Go back to **admin.google.com** 
2. Navigate to **Domains**
3. Find **kushnir.cloud** in the domain list (status: "Pending verification")

### 4.2 Click Verify Button

1. Click the **"Verify"** button next to kushnir.cloud
2. Google's DNS checker will:
   - Query for the TXT record on kushnir.cloud
   - Compare it to the expected verification value
   - Mark domain as "Verified" on success

### 4.3 Expected Result

**Success State** — domain status changes to:
```
kushnir.cloud [Verified] ✓
```

**If verification fails** — see troubleshooting section below

---

## Verification Checklist (Confirm All Pass)

After Phase 4 completes, verify these items:

- [ ] Domain status in Google Workspace Admin shows: **"Verified"** (not "Pending verification")
- [ ] Green checkmark (✓) appears next to kushnir.cloud
- [ ] Users section is now available for the domain
- [ ] You can see "Add Users" or "Users" option for kushnir.cloud
- [ ] You can add `qa@kushnir.cloud` user (needed for Issue #983)

---

## DNS Record Reference

For manual verification or troubleshooting:

**TXT Record Details:**
- **Name/Host**: `kushnir.cloud` (root domain, `@`)
- **Type**: TXT
- **Value**: `google-site-verification=gSxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
- **TTL**: 3600 seconds (1 hour)
- **Provider**: GoDaddy API
- **Script**: `scripts/register-google-workspace-domain.sh`

**GoDaddy API Endpoint Used:**
```
PUT https://api.godaddy.com/v1/domains/kushnir.cloud/records/TXT
```

---

## Troubleshooting

### Issue: "Verification Failed" in Google Workspace Admin

**Symptom:** Google Workspace shows "Verification failed" when you click "Verify"

**Root Causes & Fixes:**

1. **DNS not yet propagated** (Most Common)
   - **Fix**: Wait 1-5 minutes and retry (DNS caches vary by ISP)
   - **Verify**: Run `nslookup -type=TXT kushnir.cloud` and check output

2. **Typo in verification value**
   - **Symptom**: Verification value was copied wrong in Phase 2
   - **Fix**: Go back to Phase 2, copy the value again (carefully), re-run Phase 3 script
   - **Example wrong**: Missing `google-site-verification=` prefix

3. **GoDaddy credentials expired/invalid**
   - **Symptom**: Script output shows `[ERROR] Failed to add TXT record`
   - **Fix**: Check GSM (Google Secret Manager) — credentials may need refresh
   - **Verify**: `source scripts/fetch-gsm-secrets.sh` and check `echo $GODADDY_KEY`

4. **TXT record not actually added**
   - **Symptom**: `nslookup` returns no TXT record
   - **Fix**: Run Phase 3 script again with `--dry-run` first to debug:
     ```bash
     bash scripts/register-google-workspace-domain.sh \
       --verification-value "..." --dry-run
     ```

### Issue: Can't add QA user after domain verified

**Symptom:** Domain shows "Verified" but can't add `qa@kushnir.cloud` user

**Root Causes & Fixes:**

1. **Domain not fully activated yet**
   - **Fix**: Wait 10 minutes after verification — Google Workspace needs time to configure domain
   - **Check**: Refresh admin.google.com and verify domain still shows "Verified"

2. **Admin role not sufficient**
   - **Fix**: Verify `akushnir@bioenergystrategies.com` has "Super Admin" role
   - **How**: In admin.google.com → Admin roles and privileges → check your user

3. **Domain still has pending verification**
   - **Fix**: Go back to Phase 4 and verify the domain is truly marked "Verified"

### Issue: "GODADDY_KEY not set" error in Phase 3

**Symptom:** Script says `GODADDY_KEY not set`

**Root Causes & Fixes:**

1. **Forgot to source credentials**
   - **Fix**: Run in the same terminal session:
     ```bash
     source scripts/fetch-gsm-secrets.sh
     ```

2. **Credentials not in Google Secret Manager**
   - **Fix**: Create/update GSM secrets (requires GCP access)
   - **Or**: Ask team member with GSM access to verify credentials

3. **Running script in new terminal/shell**
   - **Fix**: Always run `source scripts/fetch-gsm-secrets.sh` BEFORE calling the script
   - **Better**: Create shell function that sources first, then calls script

---

## Impact on Critical Path

Once kushnir.cloud is verified in Google Workspace:

| Milestone | Duration | Status |
|-----------|----------|--------|
| **Domain registration (this guide)** | 20 min | 🟢 UNBLOCKS #983 |
| Issue #983: Create QA user | 40 min | ⏭️ Next (depends on this) |
| Issue #984: Setup credentials | 30 min | ⏭️ After #983 |
| Issues #986-990: E2E tests | 110 min | ⏭️ After #984 |
| **Production Live** | ~3.5 hours total | ⏭️ After E2E |

---

## Reference Materials

**Related Issues:**
- #983 — QA user creation (blocked by this)
- #984 — Credential setup (depends on #983)
- #986-990 — E2E test execution (depends on #984)

**Google Workspace Docs:**
- [Google Workspace Domain Verification](https://support.google.com/a/answer/60216)
- [Custom Domain Setup](https://support.google.com/a/answer/54693)

**GoDaddy API Docs:**
- [GoDaddy DNS Records API](https://developer.godaddy.com/docs/endpoint/domains)
- [API Authentication](https://developer.godaddy.com/docs#section/API-Authentication)

---

## Summary

1. ✅ Load GoDaddy credentials (Phase 1)
2. ✅ Start registration in Google Workspace Admin (Phase 2)
3. ✅ Add DNS TXT record via script (Phase 3)
4. ✅ Complete verification in Google Workspace (Phase 4)
5. ✅ Verify domain status = "Verified"
6. ✅ Proceed to Issue #983 (QA user creation)

**Total Time:** ~20 minutes | **Effort:** Mostly automated | **Next:** Issue #983
