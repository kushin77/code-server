#!/usr/bin/env python3
"""
Create QA user in Google Workspace and store credentials in GSM.
Requires:
- Google Admin SDK (google-auth-httplib2, google-auth-oauthlib, google-api-python-client)
- Service account with admin.directory.user scope
- GSM access (gcloud secrets create)
"""

import os
import secrets
import string
import subprocess
import json
import sys

def generate_password(length=32):
    """Generate a cryptographically secure password."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()"
    return ''.join(secrets.choice(alphabet) for i in range(length))

def create_gcp_secret(secret_name, secret_value):
    """Create or update a GCP Secret Manager secret."""
    try:
        # Try to get existing secret first
        result = subprocess.run(
            ["gcloud", "secrets", "describe", secret_name],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            # Secret exists, add new version
            process = subprocess.Popen(
                ["gcloud", "secrets", "versions", "add", secret_name, "--data-file=-"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            stdout, stderr = process.communicate(input=secret_value)
            if process.returncode != 0:
                print(f"Error updating secret {secret_name}: {stderr}")
                return False
            print(f"✓ Updated secret: {secret_name}")
            return True
        else:
            # Create new secret
            process = subprocess.Popen(
                ["gcloud", "secrets", "create", secret_name, 
                 "--replication-policy=automatic", "--data-file=-"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            stdout, stderr = process.communicate(input=secret_value)
            if process.returncode != 0:
                print(f"Error creating secret {secret_name}: {stderr}")
                return False
            print(f"✓ Created secret: {secret_name}")
            return True
    except Exception as e:
        print(f"Error managing secret {secret_name}: {e}")
        return False

def main():
    """Main function to create QA user and store credentials."""
    qa_email = "qa@kushnir.cloud"
    password = generate_password()
    
    print(f"QA User Creation Script")
    print(f"======================")
    print(f"Email: {qa_email}")
    print(f"Generated Password: {password}")
    print(f"")
    
    # Step 1: Create GSM secrets for credentials
    print("Step 1: Creating GSM secrets...")
    print("-" * 50)
    
    secrets_to_create = {
        "qa-user-email": qa_email,
        "qa-user-password": password,
    }
    
    for secret_name, secret_value in secrets_to_create.items():
        if not create_gcp_secret(secret_name, secret_value):
            print(f"Failed to create secret: {secret_name}")
            return 1
    
    print("")
    print("✓ All secrets created/updated in GSM")
    print("")
    
    # Step 2: Document manual creation steps
    print("Step 2: Manual User Creation Steps")
    print("-" * 50)
    print("")
    print("Since gcloud CLI doesn't support Workspace user creation,")
    print("please create the user manually via Google Workspace Admin Console:")
    print("")
    print("1. Go to: https://admin.google.com/")
    print("2. Navigate to: Users and accounts > Users")
    print("3. Click: Create a new user")
    print("4. Enter:")
    print(f"   - First Name: QA")
    print(f"   - Last Name: Testing")
    print(f"   - Email: {qa_email}")
    print(f"   - Password: {password}")
    print("5. Click: Create user")
    print("")
    print("Alternatively, create via gcloud with proper service account:")
    print(f'  gcloud identity users create {qa_email} \\')
    print('    --given-name="QA" \\')
    print('    --family-name="Testing" \\')
    print(f'    --password="{password}"')
    print("")
    
    # Step 3: Next steps
    print("Step 3: Next Steps (After User Creation)")
    print("-" * 50)
    print("")
    print("Once the user is created in Google Workspace:")
    print("")
    print("1. Restart oauth2-proxy to load updated whitelist:")
    print("   ssh akushnir@192.168.168.31 'docker-compose restart oauth2-proxy oauth2-proxy-portal'")
    print("")
    print("2. Verify whitelist contains qa@kushnir.cloud:")
    print("   ssh akushnir@192.168.168.31 'docker-compose exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt'")
    print("")
    print("3. Test E2E authentication:")
    print("   source scripts/fetch-gsm-secrets.sh")
    print("   echo \"E2E_USER_EMAIL=$E2E_USER_EMAIL\"")
    print("   PORTAL_BASE_URL=https://kushnir.cloud IDE_BASE_URL=https://ide.kushnir.cloud npx playwright test tests/e2e/oauth-login.spec.ts")
    print("")
    
    # Step 4: Verify GSM secrets
    print("Step 4: Verify GSM Secrets")
    print("-" * 50)
    print("")
    print("Fetch credentials from GSM:")
    print('  gcloud secrets versions access latest --secret="qa-user-email"')
    print('  gcloud secrets versions access latest --secret="qa-user-password"')
    print("")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
