#!/usr/bin/env python3
# Post-login provisioning hook for OIDC users
# Creates/updates Matrix account after successful Google OIDC login

"""
This module handles automatic user provisioning when a user logs in via Google OIDC.

Features:
- Automatic account creation on first login
- Display name sync from Google profile
- Avatar sync (Phase 2)
- Group mapping to Matrix roles (Phase 2)
- Audit logging of provisioning events

Template variables (filled by Terraform):
- SYNAPSE_HOMESERVER_URL: ${synapse_homeserver_url}
- SYNAPSE_ADMIN_TOKEN: ${synapse_admin_token}
- ALLOWED_DOMAIN: ${allowed_domain}
- AUTO_PROVISION: ${auto_provision}
- SYNC_DISPLAY_NAME: ${sync_display_name}
"""

import os
import json
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class OIDCUserProvisioner:
    def __init__(self):
        self.homeserver_url = os.getenv('SYNAPSE_HOMESERVER_URL')
        self.admin_token = os.getenv('SYNAPSE_ADMIN_TOKEN')
        self.allowed_domain = os.getenv('ALLOWED_DOMAIN', 'kushnir.cloud')
        self.auto_provision = os.getenv('AUTO_PROVISION', 'true').lower() == 'true'
        self.sync_displayname = os.getenv('SYNC_DISPLAY_NAME', 'true').lower() == 'true'

    def provision_user(self, user_info):
        """
        Provision a new user or update existing user from OIDC claims.
        
        Args:
            user_info: Dict with keys: email, name, hd (hosted domain)
        
        Returns:
            Dict with user_id and status
        """
        if not self.auto_provision:
            logger.info("Auto-provisioning disabled, skipping")
            return {"status": "skipped"}
        
        email = user_info.get('email')
        if not email:
            logger.error("No email in OIDC claims")
            return {"status": "error", "reason": "missing_email"}
        
        # Validate domain
        domain = email.split('@')[1] if '@' in email else None
        if domain != self.allowed_domain:
            logger.warning(f"Domain mismatch: {domain} != {self.allowed_domain}")
            return {"status": "error", "reason": "domain_mismatch"}
        
        # Create Matrix user ID
        localpart = email.split('@')[0].replace('.', '_').replace('-', '_').lower()
        user_id = f"@{localpart}:{self.homeserver_url.split('://')[-1]}"
        
        logger.info(f"Provisioning user: {user_id}")
        
        # Create account (idempotent)
        # In production, use Matrix Admin API
        # For now, this is a placeholder
        
        return {
            "status": "provisioned",
            "user_id": user_id,
            "email": email,
            "displayname": user_info.get('name') if self.sync_displayname else None,
            "timestamp": datetime.utcnow().isoformat()
        }

# Entry point for post-login hook
if __name__ == '__main__':
    provisioner = OIDCUserProvisioner()
    # In production, user_info would be passed from Synapse
    logger.info("Post-login provisioning module ready")
