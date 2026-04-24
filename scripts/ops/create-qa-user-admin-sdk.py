#!/usr/bin/env python3
"""
Create QA user in Google Workspace using Admin SDK Directory API.

Requirements:
- Service account with domain-wide delegation enabled
- service-account.json key file in current directory or GOOGLE_APPLICATION_CREDENTIALS env var
- Admin SDK enabled in GCP project
- Service account authorized for admin.directory.user scope

Setup steps:
1. Create service account in GCP Console
2. Download JSON key file
3. Enable domain-wide delegation
4. In Google Workspace Admin Console:
   - Go to Security > API controls > Domain-wide delegation
   - Add service account and grant scope: https://www.googleapis.com/auth/admin.directory.user
"""

import json
import os
import sys
import secrets
import string
import subprocess
from pathlib import Path

def load_service_account():
    """Load service account credentials from file or environment."""
    # Try environment variable first
    cred_path = os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
    if cred_path and Path(cred_path).exists():
        return cred_path
    
    # Try common locations
    for path in [
        'service-account.json',
        'service-account-key.json',
        '~/.config/gcloud/service-account.json',
        Path.home() / '.config/gcloud/service-account.json'
    ]:
        p = Path(path).expanduser()
        if p.exists():
            return str(p)
    
    return None

def create_workspace_user_via_sdk(service_account_file, admin_email, qa_email, qa_password, given_name="QA", family_name="Testing"):
    """
    Create a Google Workspace user using the Admin SDK Directory API.
    
    Args:
        service_account_file: Path to service account JSON key
        admin_email: Admin email for domain-wide delegation (e.g., admin@kushnir.cloud)
        qa_email: New user email (e.g., qa@kushnir.cloud)
        qa_password: New user password
        given_name: First name
        family_name: Last name
    """
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        print("ERROR: Required Google libraries not installed")
        print("Install with: pip install google-auth google-auth-httplib2 google-api-python-client")
        return False
    
    try:
        # Load credentials
        credentials = service_account.Credentials.from_service_account_file(
            service_account_file,
            scopes=['https://www.googleapis.com/auth/admin.directory.user']
        )
        
        # Use domain-wide delegation to act as admin
        delegated_credentials = credentials.with_subject(admin_email)
        
        # Build Admin SDK service
        service = build('admin', 'directory_v1', credentials=delegated_credentials)
        
        # Prepare user body
        user_body = {
            "name": {
                "givenName": given_name,
                "familyName": family_name
            },
            "password": qa_password,
            "primaryEmail": qa_email,
            "changePasswordAtNextLogin": True  # Force password change on first login
        }
        
        print(f"Creating user: {qa_email}")
        user = service.users().insert(body=user_body).execute()
        
        print(f"✓ User created successfully!")
        print(f"  Email: {user['primaryEmail']}")
        print(f"  Name: {user['name']['givenName']} {user['name']['familyName']}")
        print(f"  Status: {user['suspended']}")
        
        return True
        
    except Exception as e:
        print(f"ERROR creating user: {e}")
        return False

def generate_password(length=32):
    """Generate a cryptographically secure password."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()"
    return ''.join(secrets.choice(alphabet) for i in range(length))

def create_gcp_secret(secret_name, secret_value):
    """Create or update a GCP Secret Manager secret."""
    try:
        # Try to update existing secret first
        result = subprocess.run(
            ["gcloud", "secrets", "describe", secret_name],
            capture_output=True,
            text=True,
            timeout=10
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
            stdout, stderr = process.communicate(input=secret_value, timeout=10)
            if process.returncode == 0:
                print(f"✓ Updated GSM secret: {secret_name}")
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
            stdout, stderr = process.communicate(input=secret_value, timeout=10)
            if process.returncode == 0:
                print(f"✓ Created GSM secret: {secret_name}")
                return True
    except subprocess.TimeoutExpired:
        print(f"ERROR: Timeout creating/updating secret {secret_name}")
    except Exception as e:
        print(f"ERROR managing secret {secret_name}: {e}")
    
    return False

def main():
    """Main function to create QA user."""
    qa_email = "qa@kushnir.cloud"
    admin_email = "admin@kushnir.cloud"  # Need to update this for your domain
    
    # Generate password
    password = generate_password()
    
    print("=" * 70)
    print("Google Workspace QA User Creation via Admin SDK")
    print("=" * 70)
    print()
    
    # Check for service account
    sa_file = load_service_account()
    if not sa_file:
        print("ERROR: Service account JSON file not found!")
        print()
        print("Setup Required:")
        print("1. Create service account in GCP Console")
        print("2. Download JSON key file")
        print("3. Enable domain-wide delegation on the service account")
        print("4. In Google Workspace Admin Console:")
        print("   - Go to Security > API controls > Domain-wide delegation")
        print("   - Add service account with scope: https://www.googleapis.com/auth/admin.directory.user")
        print()
        print("Then set GOOGLE_APPLICATION_CREDENTIALS environment variable:")
        print("  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json")
        return 1
    
    print(f"Using service account: {sa_file}")
    print()
    
    # Create the user
    print(f"Generated Password: {password}")
    print()
    print("Creating Google Workspace user...")
    print("-" * 70)
    
    if not create_workspace_user_via_sdk(sa_file, admin_email, qa_email, password):
        print()
        print("ERROR: Failed to create user. Check:")
        print("1. Service account has domain-wide delegation enabled")
        print("2. Correct admin email is specified")
        print("3. Admin SDK is enabled in GCP project")
        return 1
    
    print()
    print("-" * 70)
    print("Creating GSM secrets...")
    print("-" * 70)
    
    # Store credentials in GSM
    if not create_gcp_secret("qa-user-email", qa_email):
        return 1
    
    if not create_gcp_secret("qa-user-password", password):
        return 1
    
    print()
    print("=" * 70)
    print("✓ QA User Creation Complete!")
    print("=" * 70)
    print()
    print("Next Steps:")
    print("-" * 70)
    print("1. Restart oauth2-proxy to load updated whitelist:")
    print("   ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose restart oauth2-proxy oauth2-proxy-portal'")
    print()
    print("2. Verify credentials in GSM:")
    print("   gcloud secrets versions access latest --secret='qa-user-email'")
    print("   gcloud secrets versions access latest --secret='qa-user-password'")
    print()
    print("3. Test E2E authentication:")
    print("   source scripts/fetch-gsm-secrets.sh")
    print("   echo $E2E_USER_EMAIL")
    print()
    print("4. Run E2E tests:")
    print("   npx playwright test tests/e2e/oauth-login.spec.ts")
    print()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
