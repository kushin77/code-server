#!/bin/bash
set -e

# Generate password
PASSWORD=$(openssl rand -base64 32)
QA_EMAIL="qa@kushnir.cloud"

echo "QA User Creation - GSM Setup"
echo "============================"
echo "Email: $QA_EMAIL"
echo "Password: $PASSWORD"
echo ""

# Create or update GSM secrets
echo "Creating GSM secrets..."

# Try to update existing secret, if it fails, create new one
echo -n "$QA_EMAIL" | gcloud secrets versions add qa-user-email --data-file=- 2>/dev/null || \
  gcloud secrets create qa-user-email --replication-policy=automatic --data-file=/dev/stdin <<< "$QA_EMAIL"

echo "✓ Created/Updated qa-user-email"

# Create password secret
echo -n "$PASSWORD" | gcloud secrets versions add qa-user-password --data-file=- 2>/dev/null || \
  gcloud secrets create qa-user-password --replication-policy=automatic --data-file=/dev/stdin <<< "$PASSWORD"

echo "✓ Created/Updated qa-user-password"

echo ""
echo "GSM Secrets Created Successfully!"
echo ""
echo "Next Steps:"
echo "=========="
echo "1. Create user in Google Workspace Admin Console"
echo "   - Email: $QA_EMAIL"
echo "   - Password: $PASSWORD"
echo ""
echo "2. Restart oauth2-proxy:"
echo "   docker-compose restart oauth2-proxy oauth2-proxy-portal"
echo ""
echo "3. Test E2E authentication with new credentials"
