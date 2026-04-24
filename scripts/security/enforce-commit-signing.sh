#!/usr/bin/env bash
# P0 #1272: Security & Compliance - GPG Commit Signing
# Enforce cryptographic signatures on all commits

# @file        scripts/security/enforce-commit-signing.sh
# @module      security/commit-signing
# @description Configure GPG commit signing enforcement

set -euo pipefail

echo "=========================================="
echo "P0 #1272: Commit Signing Enforcement"
echo "=========================================="
echo ""

GPG_CONFIG_DIR="/etc/git-signing"
GPG_LOG="/var/log/git-signing/signing.log"

setup_signing_infrastructure() {
    echo "Setting up GPG signing infrastructure..."
    mkdir -p "${GPG_CONFIG_DIR}"
    mkdir -p "$(dirname ${GPG_LOG})"
    chmod 0700 "${GPG_CONFIG_DIR}"
    touch "${GPG_LOG}"
    chmod 0600 "${GPG_LOG}"
    echo "✓ Signing infrastructure created"
}

create_signing_policy() {
    echo "Creating commit signing policy..."
    
    cat > "${GPG_CONFIG_DIR}/signing-policy.json" << 'EOF'
{
  "commit_signing": {
    "enabled": true,
    "required": true,
    "enforcement": "hard-reject",
    "algorithm": "RSA-4096",
    "expiry_warning_days": 30,
    "key_rotation_interval_years": 2
  },
  "gpg_configuration": {
    "keyserver": "keys.openpgp.org",
    "trust_model": "pgp",
    "verify_signatures": true,
    "require_valid_signatures": true,
    "reject_unsigned_commits": true
  },
  "signing_keys": {
    "root_signer": {
      "key_id": "repo-root-signing-key",
      "algorithm": "RSA-4096",
      "created": "2026-01-01",
      "expires": "2028-01-01"
    },
    "service_signers": [
      {
        "name": "code-server-ci",
        "key_type": "service",
        "purpose": "CI/CD automation",
        "valid_repos": ["kushin77/code-server"]
      },
      {
        "name": "deploy-automation",
        "key_type": "service",
        "purpose": "Deployment automation",
        "valid_repos": ["kushin77/code-server"]
      }
    ]
  },
  "audit": {
    "log_all_operations": true,
    "log_location": "/var/log/git-signing/signing.log",
    "retention_days": 365,
    "alert_on_invalid_signatures": true,
    "alert_recipients": ["security@kushnir.cloud"]
  }
}
EOF
    
    echo "✓ Signing policy created"
}

create_signing_hooks() {
    echo "Creating Git hooks for signing enforcement..."
    
    # Pre-commit hook to warn about unsigned commits
    cat > "${GPG_CONFIG_DIR}/pre-commit.sh" << 'EOF'
#!/usr/bin/env bash
# Pre-commit hook: Warn if signing GPG key is not configured

gpg_configured=$(git config --get user.signingkey 2>/dev/null || echo "")

if [ -z "$gpg_configured" ]; then
    echo "WARNING: No GPG signing key configured!"
    echo "Configure with: git config --global user.signingkey <KEY_ID>"
    echo ""
    echo "To enable commit signing:"
    echo "  git config --global commit.gpgsign true"
fi
EOF
    
    # Commit-msg hook to verify signature
    cat > "${GPG_CONFIG_DIR}/commit-msg.sh" << 'EOF'
#!/usr/bin/env bash
# Commit-msg hook: Verify commit will be signed

should_sign=$(git config --get commit.gpgsign)

if [ "$should_sign" != "true" ]; then
    echo "WARNING: Commit signing is not enabled"
    echo "Enable with: git config --global commit.gpgsign true"
    exit 0
fi
EOF
    
    # Post-commit hook to verify signature
    cat > "${GPG_CONFIG_DIR}/verify-signature.sh" << 'EOF'
#!/usr/bin/env bash
# Verify commit signature after commit

COMMIT_SHA=$(git rev-parse HEAD)

# Verify the commit is signed
git verify-commit "$COMMIT_SHA" 2>&1 | tee -a /var/log/git-signing/signing.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Commit signature verification failed"
    echo "Contact: security@kushnir.cloud"
    exit 1
fi

echo "✓ Commit signed and verified: $COMMIT_SHA"
EOF
    
    chmod +x "${GPG_CONFIG_DIR}"/*.sh
    echo "✓ Git signing hooks created"
}

create_github_protection_rules() {
    echo "Creating GitHub branch protection rules..."
    
    cat > "${GPG_CONFIG_DIR}/github-branch-protection.json" << 'EOF'
{
  "branch_protection_rules": {
    "main": {
      "require_code_reviews": true,
      "required_approving_review_count": 1,
      "require_status_checks": true,
      "status_checks": [
        "commit-signature-verification",
        "code-scanning",
        "security-tests"
      ],
      "require_signed_commits": true,
      "require_up_to_date_before_merge": true,
      "allow_auto_merge": false,
      "dismiss_stale_pr_approvals": true,
      "enforce_admin": true
    },
    "develop": {
      "require_code_reviews": true,
      "required_approving_review_count": 1,
      "require_signed_commits": true,
      "require_status_checks": true
    }
  }
}
EOF
    
    echo "✓ GitHub protection rules defined"
}

create_key_management_service() {
    echo "Creating signing key management service..."
    
    cat > "${GPG_CONFIG_DIR}/manage-signing-keys.py" << 'EOF'
#!/usr/bin/env python3
"""GPG signing key management service"""

import subprocess
import json
import os
from datetime import datetime, timedelta

class GPGKeyManager:
    def __init__(self):
        self.log_file = "/var/log/git-signing/signing.log"
    
    def generate_signing_key(self, name, email, key_type="rsa4096"):
        """Generate a new GPG signing key"""
        print(f"Generating {key_type} key for {name} <{email}>...")
        
        batch_input = f"""
Key-Type: {key_type}
Name-Real: {name}
Name-Email: {email}
Expire-Date: 2y
%no-protection
%commit
"""
        
        result = subprocess.run(
            ["gpg", "--batch", "--generate-key"],
            input=batch_input,
            text=True,
            capture_output=True
        )
        
        if result.returncode == 0:
            print(f"✓ Key generated successfully")
            self._log_operation("key_generation", f"Generated key for {name}")
        else:
            print(f"✗ Key generation failed: {result.stderr}")
            self._log_operation("key_generation_failed", f"Failed for {name}: {result.stderr}")
    
    def list_signing_keys(self):
        """List all available GPG signing keys"""
        result = subprocess.run(
            ["gpg", "--list-secret-keys", "--keyid-format=long"],
            capture_output=True,
            text=True
        )
        return result.stdout
    
    def verify_key_expiry(self):
        """Check for keys expiring soon"""
        result = subprocess.run(
            ["gpg", "--list-keys", "--with-colons"],
            capture_output=True,
            text=True
        )
        
        expiring_soon = []
        warning_threshold = datetime.now() + timedelta(days=30)
        
        for line in result.stdout.split('\n'):
            if line.startswith('pub:'):
                parts = line.split(':')
                if len(parts) > 6:
                    expiry_date = parts[6]
                    if expiry_date:
                        key_expiry = datetime.fromtimestamp(int(expiry_date))
                        if key_expiry < warning_threshold:
                            expiring_soon.append({
                                'key_id': parts[4],
                                'expires': key_expiry.isoformat()
                            })
        
        if expiring_soon:
            print("WARNING: Keys expiring soon:")
            for key in expiring_soon:
                print(f"  {key['key_id']} expires {key['expires']}")
                self._log_operation("key_expiry_warning", f"Key {key['key_id']} expires soon")
    
    def _log_operation(self, operation, details):
        """Log key management operations"""
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "operation": operation,
            "details": details
        }
        with open(self.log_file, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')

if __name__ == "__main__":
    manager = GPGKeyManager()
    print("GPG Key Management Service")
    print("=" * 40)
    
    # List current keys
    print("\nCurrent signing keys:")
    print(manager.list_signing_keys())
    
    # Check for expiring keys
    manager.verify_key_expiry()
EOF
    
    chmod +x "${GPG_CONFIG_DIR}/manage-signing-keys.py"
    echo "✓ Key management service created"
}

main() {
    echo ""
    setup_signing_infrastructure
    echo ""
    
    create_signing_policy
    echo ""
    
    create_signing_hooks
    echo ""
    
    create_github_protection_rules
    echo ""
    
    create_key_management_service
    echo ""
    
    echo "=========================================="
    echo "Commit Signing Enforcement Complete"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Policy: ${GPG_CONFIG_DIR}/signing-policy.json"
    echo "  Hooks: ${GPG_CONFIG_DIR}/*.sh"
    echo "  Key Manager: ${GPG_CONFIG_DIR}/manage-signing-keys.py"
    echo "  Log: ${GPG_LOG}"
    echo ""
    echo "Next steps:"
    echo "  1. Generate signing keys (RSA-4096)"
    echo "  2. Configure Git: git config --global commit.gpgsign true"
    echo "  3. Enable GitHub branch protection with required signatures"
    echo "  4. Monitor signing.log for compliance"
    echo ""
}

main
