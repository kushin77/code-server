#!/bin/bash
###############################################################################
# Git SSH Blocker - Issue #187 Integration with Issue #184 Git Proxy
#
# This script blocks SSH authentication for git and redirects to git proxy.
# When git tries to use SSH:
#   1. This script is invoked (via GIT_SSH env var)
#   2. We block direct SSH connection
#   3. Git falls back to credential helper
#   4. Credential helper uses git-proxy (Issue #184)
#
# Installation:
#   sudo cp git-ssh-blocked.sh /usr/local/bin/
#   sudo chmod 755 /usr/local/bin/git-ssh-blocked.sh
#
###############################################################################

echo "ERROR: SSH authentication for git is not permitted in this environment." >&2
echo "Git operations must use the authenticated HTTPS proxy." >&2
echo "" >&2
echo "This is a security feature to prevent SSH key exposure." >&2
echo "All git operations are securely proxied and audited." >&2
echo "" >&2
echo "Attempting to use credential helper (git-credential-cloudflare-proxy)..." >&2
echo "" >&2

# Exit with error to force git to try alternative auth methods
exit 1
