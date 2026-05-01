# Secrets Rotation Procedure

## Quarterly Rotation Schedule

### Database Passwords
1. Update DB_PASSWORD in .secrets/production/.env.secrets
2. Run: terraform apply -target=module.database.docker_container.postgres
3. Update PostgreSQL password with new value
4. Verify all apps reconnect successfully
5. Document rotation in audit log

### API Keys
1. Generate new API key
2. Update in .secrets/production/.env.secrets
3. Deploy new containers: docker-compose up -d
4. Verify services authenticate with new key
5. Revoke old API key after verification window (24h)

### OAuth2 Secrets
1. Generate new OAuth2_COOKIE_SECRET
2. Update in .secrets/production/.env.secrets
3. Restart auth-server: docker-compose restart auth-server
4. Existing sessions will require re-authentication
5. Document change in changelog

### Encryption Keys
⚠️  WARNING: Encryption key rotation requires data re-encryption
    Contact security team before rotating

## Emergency Rotation

If a secret is compromised:
1. Immediately update in .secrets/production/.env.secrets
2. Run: bash scripts/security/validate-secrets.sh
3. Deploy changes: terraform apply
4. Notify all team members
5. Document incident in security log

## Automation

Set calendar reminders for:
- DB Password: Every 90 days
- API Keys: Every 60 days
- OAuth2 Secrets: Every 120 days
