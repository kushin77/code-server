## Create qa@kushnir.cloud Google Workspace User

### Objective
Create a dedicated QA service account `qa@kushnir.cloud` in Google Workspace for automated E2E testing.

### Prerequisites
- Google Workspace admin access via `akushnir@bioenergystrategies.com`
- kushnir.cloud domain verified in Google Workspace

### Manual Steps (Google Admin Console)

```
1. Navigate to: https://admin.google.com
2. Sign in as: akushnir@bioenergystrategies.com
3. Go to: Directory → Users → Add new user
4. Fill in:
   - First name: QA
   - Last name: Testing
   - Primary email: qa@kushnir.cloud
   - Password: [Generate secure password, store in GSM]
   - Require password change on next sign-in: NO (service account)
5. Click: Add new user
6. Note the password for GSM storage
```

### Alternative: gcloud CLI (if Workspace API enabled)

```bash
# Requires: Cloud Identity API enabled + service account with admin.directory.user scope
gcloud identity users create qa@kushnir.cloud \
  --given-name="QA" \
  --family-name="Testing" \
  --password="$(openssl rand -base64 32)"
```

### User Configuration

| Setting | Value |
|---------|-------|
| Email | qa@kushnir.cloud |
| Display Name | QA Testing |
| Organizational Unit | /Users (or /QA if exists) |
| License | Google Workspace Business Starter (minimum) |
| 2FA | Disabled (service account) |
| Password Policy | Strong password, no rotation required |
| Groups | None (minimal permissions) |

### Security Constraints

1. **NO admin permissions** - QA user is a standard user
2. **NO access to admin console** - cannot manage other users
3. **NO access to Google Drive** shared content (isolate test data)
4. **NO membership in shared groups** - prevent email leakage
5. **Password stored in GSM** - never in code or plaintext files

### Post-Creation Validation

```bash
# Test OAuth login (manual)
1. Open incognito browser
2. Navigate to: https://kushnir.cloud
3. Click "Sign in with Google"
4. Enter: qa@kushnir.cloud
5. Enter: [password from GSM]
6. Expected: Redirect back to kushnir.cloud with authenticated session

# Expected failures (should not work):
- admin.google.com access should be denied
- Other user's Drive files should not be visible
- Cannot create/delete users
```

### Definition of Done

- [ ] qa@kushnir.cloud user exists in Google Workspace
- [ ] User can authenticate via Google OAuth
- [ ] User has minimal permissions (standard user only)
- [ ] Password stored in GSM (not committed to code)
- [ ] Manual login test successful
- [ ] User added to allowed-emails.txt (separate issue #984)

### Owner
@kushin77 (requires Google Workspace admin access)

Parent: #982
