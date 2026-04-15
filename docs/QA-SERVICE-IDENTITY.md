# QA Service Identity - Automated Testing Authentication

## Overview

The **QA Service Account** (`qa-service@ide.kushnir.cloud`) is a dedicated managed identity for automated testing and QA automation. It behaves as a real user with:

- Full OAuth2 authentication through SSO
- Developer role with appropriate restrictions
- Non-interactive session bootstrap capability
- Complete audit trail of all QA actions
- Mock and headless authentication modes

## Configuration

### Terraform-Managed Identity

The QA service account is defined in `terraform/users.tf`:

```hcl
allowed_users = {
  qa-service = {
    email    = "qa-service@ide.kushnir.cloud"
    role     = "developer"
    disabled = false
  }
}
```

### User Metadata

QA service configuration stored in: `config/user-settings/qa-service/user-metadata.json`

```json
{
  "role": "developer",
  "displayName": "QA Service Account",
  "features": {
    "codeEditing": true,
    "terminal": false,
    "fileDownload": false
  }
}
```

## Authentication Modes

### 1. Mock Mode (Development/CI Default)

Non-interactive mock authentication - generates a session token without hitting OAuth provider.

**Use Case**: Local development, CI/CD pipelines, fast test execution

**Configuration**:
```bash
export TEST_AUTH_MODE=mock
bash scripts/qa-service-bootstrap.sh bootstrap
```

**Session Output**:
- Token: `.qa-sessions/session-token`
- Cookie jar: `.qa-sessions/cookies.jar`
- OAuth state: `.qa-sessions/oauth-state`

### 2. Headless Mode (Real OAuth2)

Real OAuth2 Resource Owner Password Credentials flow for production-like testing.

**Use Case**: Production-grade testing, integration testing with real provider

**Configuration**:
```bash
export TEST_AUTH_MODE=headless
export QA_SERVICE_PASSWORD="<generated-password>"
bash scripts/qa-service-bootstrap.sh bootstrap
```

**Requirements**:
- OAuth2 provider configured
- QA service password managed as secret

## Usage Examples

### Example 1: Run E2E Tests as QA Service

```bash
#!/bin/bash
source tests/qa-service-auth-fixture.sh

# Verify QA config
verify_qa_config || exit 1

# Setup QA session
setup_qa_session || exit 1

# Run tests as QA service
run_as_qa_service npm test -- --user qa-service

# Cleanup
cleanup_qa_session
```

### Example 2: Manual Test Execution

```bash
# Bootstrap QA service session
bash scripts/qa-service-bootstrap.sh bootstrap

# Get session token
SESSION_TOKEN=$(bash scripts/qa-service-bootstrap.sh token)

# Use token in API calls
curl -H "Authorization: Bearer $SESSION_TOKEN" \
  http://ide.kushnir.cloud/api/workspaces

# Revoke session when done
bash scripts/qa-service-bootstrap.sh revoke
```

### Example 3: CI/CD Integration

```yaml
- name: Setup QA Service Identity
  run: |
    export TEST_AUTH_MODE=mock
    bash scripts/qa-service-bootstrap.sh bootstrap
    
- name: Run E2E Tests
  env:
    QA_SERVICE_EMAIL: qa-service@ide.kushnir.cloud
    TEST_USER_ROLE: developer
  run: |
    npm test -- --reporter=json --outputFile=test-results.json

- name: Revoke QA Session
  if: always()
  run: bash scripts/qa-service-bootstrap.sh revoke
```

## Environment Variables

| Variable | Default | Mode | Purpose |
|----------|---------|------|---------|
| `TEST_AUTH_MODE` | `mock` | All | Authentication mode: `mock` or `headless` |
| `QA_SERVICE_EMAIL` | `qa-service@ide.kushnir.cloud` | All | QA service email address |
| `QA_SERVICE_PASSWORD` | (unset) | Headless | Password for OAuth2 flow (required) |
| `QA_SERVICE_ROLE` | `developer` | All | Role for permission checks |
| `QA_SESSION_DIR` | `.qa-sessions` | All | Directory for session files |

## Session Management

### Commands

```bash
# Bootstrap new session
bash scripts/qa-service-bootstrap.sh bootstrap

# Validate current session
bash scripts/qa-service-bootstrap.sh validate

# Get current session token
bash scripts/qa-service-bootstrap.sh token

# Revoke current session
bash scripts/qa-service-bootstrap.sh revoke
```

### Session Files

```
.qa-sessions/
├── session-token          # Current OAuth token
├── cookies.jar           # Browser cookie jar
└── oauth-state           # OAuth2 state parameter
```

### Audit Logging

All QA service actions logged to: `audit/qa-sessions.log`

```
2026-04-15T10:30:45+00:00 | QA_SESSION_CREATED | email:qa-service@ide.kushnir.cloud | mode:mock | token:a1b2c3d4...
2026-04-15T10:31:20+00:00 | QA_SESSION_REVOKED | email:qa-service@ide.kushnir.cloud | token:a1b2c3d4...
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: QA Tests with Service Identity

on: [pull_request]

jobs:
  qa-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup QA Service
        run: bash tests/qa-service-auth-fixture.sh setup
      
      - name: Run E2E Tests
        env:
          QA_SERVICE_EMAIL: qa-service@ide.kushnir.cloud
          TEST_AUTH_MODE: mock
        run: npm test
      
      - name: Cleanup
        if: always()
        run: bash tests/qa-service-auth-fixture.sh cleanup
      
      - name: Upload Results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: qa-test-results
          path: test-results/
```

## Security Considerations

### Access Control

QA service has `developer` role restrictions:
- ✅ Can edit code files
- ❌ Cannot access terminal
- ❌ Cannot download files
- ❌ Cannot install extensions

### Audit Trail

All QA service actions are audited:
- Session creation/revocation
- API endpoint access
- File modifications
- Permission changes

### Password Management

For headless mode, QA service password:
- Generated securely (minimum 24 characters)
- Stored as GitHub secret
- Rotated periodically
- Never logged or exposed

## Troubleshooting

### Session Bootstrap Fails

```bash
# Check audit logs
tail -20 audit/qa-sessions.log

# Verify OAuth2 is running
docker-compose ps oauth2-proxy

# Test OAuth2 connectivity
curl -s http://localhost:4180/oauth2/userinfo
```

### Token Validation Fails

```bash
# Check token file exists and is readable
cat .qa-sessions/session-token

# Validate token format
bash scripts/qa-service-bootstrap.sh validate

# Check allowlist includes QA service
grep "qa-service@ide.kushnir.cloud" allowed-emails.txt
```

### Tests Not Running as QA Service

```bash
# Verify session is active
bash scripts/qa-service-bootstrap.sh token

# Check TEST_USER_IDENTITY environment
echo $TEST_USER_IDENTITY

# Verify audit log captures QA actions
grep "qa-service" audit/qa-sessions.log | tail -5
```

## Related Documentation

- [User Management](../docs/user-management.md)
- [OAuth2 Configuration](../docs/oauth2-configuration.md)
- [Audit Logging](../docs/audit-logging.md)
- [Test Strategy](../docs/test-strategy.md)

## Issue Reference

Implements: #318 (QA-IDENTITY-003: Create dedicated QA service account)
