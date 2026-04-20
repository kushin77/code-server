## Infrastructure Preparation Complete ✅

Groundwork for QA user OAuth whitelist and GSM credential configuration is ready. Once #983 (QA user creation) is completed, #984 can proceed immediately.

### Preparation Steps Completed

1. **allowed-emails.txt** - QA email added
   - Added: qa@kushnir.cloud
   - Status: Ready for oauth2-proxy whitelist restart

2. **.env.schema.json** - Testing credential variables defined
   - E2E_USER_EMAIL: QA service account email (source: gsm:qa-user-email)
   - E2E_USER_PASSWORD: QA service account password (source: gsm:qa-user-password, secret)
   - E2E_USER_OAUTH_TOKEN: Optional cached OAuth token (source: gsm:qa-oauth-token)
   - All properly marked as secret/sensitive with GSM source references

3. **scripts/fetch-gsm-secrets.sh** - GSM credential fetching added
   - Added E2E credential section with graceful fallbacks
   - Tries to fetch qa-user-email, qa-user-password from GSM
   - Warns if credentials not found (expected until #983 completes)
   - Includes optional oauth-token fetching for test optimization

### Remaining Work (After #983 Completes)

Once qa@kushnir.cloud user exists and password is known:

**Step 1: Create GSM secrets**
```bash
gcloud secrets create qa-user-email --replication-policy=automatic
echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=-

gcloud secrets create qa-user-password --replication-policy=automatic
echo -n "[PASSWORD_FROM_#983]" | gcloud secrets versions add qa-user-password --data-file=-
```

**Step 2: Restart oauth2-proxy services**
```bash
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal"
```

**Step 3: Verify whitelist loaded**
```bash
ssh akushnir@192.168.168.31 "docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt"
```

**Step 4: Test E2E authentication setup**
```bash
source scripts/fetch-gsm-secrets.sh
echo "E2E_USER_EMAIL=$E2E_USER_EMAIL"
echo "E2E_USER_PASSWORD=<redacted>"
```

### Definition of Done (Ready to Complete on #984)

- [x] qa@kushnir.cloud added to allowed-emails.txt (infrastructure-ready)
- [x] .env.schema.json defines E2E credential variables
- [x] fetch-gsm-secrets.sh handles E2E credential fetching
- ⏳ Awaiting #983 to create GSM secrets and actual user
- [ ] oauth2-proxy restarted with updated whitelist
- [ ] E2E test can authenticate as QA user

### Commit

f5787454: chore(#984): Prepare infrastructure for QA user OAuth whitelist and GSM credentials

Unblocks: All E2E test suites (#986-990) after #983 completion
Parent: #982
