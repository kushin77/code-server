# GitHub Secrets Configuration

## Required Secrets in GitHub Repository Settings

### Production Secrets
```
TF_VAR_db_password
TF_VAR_db_replication_password
TF_VAR_redis_password
TF_VAR_oauth2_client_secret
TF_VAR_oauth2_cookie_secret
TF_VAR_scheduler_api_key
TF_VAR_qdrant_api_key
TF_VAR_grafana_admin_password
TF_VAR_encryption_key
TF_VAR_signing_key
TF_VAR_apex_domain
TF_VAR_admin_email
TF_VAR_primary_host
TF_VAR_replica_host
TF_VAR_deployment_mode
```

### Access Tokens
```
GITHUB_TOKEN        # For automated releases
TERRAFORM_CLOUD_TOKEN  # For remote state
REGISTRY_USERNAME   # For container registry
REGISTRY_PASSWORD   # For container registry
```

## Setup Instructions

1. Navigate to: Settings → Secrets and variables → Actions

2. Add each secret:
   - Click "New repository secret"
   - Enter name (exact match above)
   - Enter value from .secrets/production/.env.secrets
   - Click "Add secret"

3. Verify secrets are masked in action logs

4. Update CI/CD workflows to use secrets:
   ```yaml
   env:
     TF_VAR_db_password: ${{ secrets.TF_VAR_db_password }}
   ```

## Security Best Practices

- Never commit .secrets/ directory
- Use separate secrets for dev/staging/prod
- Rotate secrets quarterly
- Audit secret access in GitHub logs
- Use fine-grained tokens where possible
