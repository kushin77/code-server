#!/usr/bin/env python3
# @file        scripts/ops/rotate-qa-credentials.py
# @module      operations/secrets-management
# @description Rotate QA user credentials in Google Workspace and GSM - Issue #983/#984
# @status      Ready for execution after initial QA user creation
#

import os
import sys
import json
import argparse
import subprocess
from datetime import datetime
from google.cloud import secretmanager
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build


class QACredentialRotator:
    """Handles QA user credential rotation in Google Workspace and GSM."""
    
    def __init__(self, gcp_project: str, workspace_domain: str, admin_email: str):
        self.gcp_project = gcp_project
        self.workspace_domain = workspace_domain
        self.qa_email = f"qa@{workspace_domain}"
        self.admin_email = admin_email
        self.secret_client = secretmanager.SecretManagerServiceClient()
        
    def _get_admin_api(self):
        """Build Admin API client with service account credentials."""
        scopes = ['https://www.googleapis.com/auth/admin.directory.user.security']
        credentials = Credentials.from_service_account_file(
            os.environ.get('GOOGLE_APPLICATION_CREDENTIALS', ''),
            scopes=scopes,
            subject=self.admin_email
        )
        return build('admin', 'directory_v1', credentials=credentials)
    
    def generate_new_password(self) -> str:
        """Generate a cryptographically secure random password."""
        import secrets
        import string
        
        # 16 character password with mix of letters, numbers, symbols
        chars = string.ascii_letters + string.digits + "!@#$%^&*"
        return ''.join(secrets.choice(chars) for _ in range(16))
    
    def rotate_workspace_password(self, new_password: str) -> bool:
        """Reset QA user password in Google Workspace."""
        try:
            service = self._get_admin_api()
            
            print(f"[INFO] Resetting password for {self.qa_email}...")
            
            service.users().update(
                userKey=self.qa_email,
                body={
                    'password': new_password,
                    'changePasswordAtNextLogin': False
                }
            ).execute()
            
            print(f"[✓] Password reset in Google Workspace")
            return True
            
        except Exception as e:
            print(f"[ERROR] Failed to reset password: {str(e)}")
            return False
    
    def update_gsm_secret(self, secret_name: str, new_value: str) -> bool:
        """Update GSM secret with new value."""
        try:
            parent = f"projects/{self.gcp_project}"
            name = f"{parent}/secrets/{secret_name}"
            
            print(f"[INFO] Updating GSM secret: {secret_name}...")
            
            # Add new version
            response = self.secret_client.add_secret_version(
                request={
                    "parent": name,
                    "payload": {"data": new_value.encode("UTF-8")}
                }
            )
            
            print(f"[✓] GSM secret updated: {secret_name}")
            print(f"    Version: {response.name.split('/')[-1]}")
            return True
            
        except Exception as e:
            print(f"[ERROR] Failed to update GSM secret: {str(e)}")
            return False
    
    def rotate_credentials(self) -> bool:
        """Perform full credential rotation."""
        print("=" * 60)
        print("QA User Credential Rotation")
        print("=" * 60)
        print(f"Workspace Domain: {self.workspace_domain}")
        print(f"QA Email: {self.qa_email}")
        print(f"GCP Project: {self.gcp_project}")
        print()
        
        # Generate new password
        print("[INFO] Generating new password...")
        new_password = self.generate_new_password()
        print(f"[✓] Generated 16-character password")
        
        # Rotate password in Workspace
        print()
        if not self.rotate_workspace_password(new_password):
            return False
        
        # Update GSM secret
        print()
        if not self.update_gsm_secret("qa-user-password", new_password):
            return False
        
        # Audit log
        print()
        print("[INFO] Recording rotation in audit log...")
        audit_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "action": "CREDENTIAL_ROTATION",
            "user": self.qa_email,
            "status": "success",
            "gcp_project": self.gcp_project
        }
        print(f"[✓] Audit entry: {json.dumps(audit_entry)}")
        
        print()
        print("=" * 60)
        print("[✓] Credential rotation completed successfully!")
        print("=" * 60)
        return True


def main():
    parser = argparse.ArgumentParser(
        description="Rotate QA user credentials in Google Workspace and GSM"
    )
    parser.add_argument(
        "--gcp-project",
        default=os.environ.get("GCP_PROJECT", "kushin77-ops"),
        help="GCP Project ID (default: kushin77-ops)"
    )
    parser.add_argument(
        "--workspace-domain",
        default=os.environ.get("WORKSPACE_DOMAIN", "kushnir.cloud"),
        help="Google Workspace domain (default: kushnir.cloud)"
    )
    parser.add_argument(
        "--admin-email",
        default=os.environ.get("WORKSPACE_ADMIN_EMAIL", "admin@kushnir.cloud"),
        help="Workspace admin email for authentication"
    )
    parser.add_argument(
        "--service-account-json",
        default=os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"),
        help="Path to service account JSON file"
    )
    
    args = parser.parse_args()
    
    # Verify service account file exists
    if args.service_account_json and not os.path.exists(args.service_account_json):
        print(f"[ERROR] Service account file not found: {args.service_account_json}")
        sys.exit(1)
    
    # Set environment variable for Google client
    if args.service_account_json:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = args.service_account_json
    
    # Execute rotation
    rotator = QACredentialRotator(
        gcp_project=args.gcp_project,
        workspace_domain=args.workspace_domain,
        admin_email=args.admin_email
    )
    
    success = rotator.rotate_credentials()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
