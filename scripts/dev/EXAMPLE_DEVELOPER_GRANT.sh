#!/bin/bash
# EXAMPLE: Developer Grant Script
# This demonstrates the developer-grant command from Phase 4
# Based on GitHub Issue #186: https://github.com/kushin77/code-server/issues/186
#
# Usage: ./developer-grant.sh john@example.com 7 "John Contractor"

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

DEVELOPERS_DB="${HOME}/.code-server-developers/developers.csv"
REVOCATION_LOG="${HOME}/.code-server-developers/revocation.log"
CF_API_TOKEN="${CLOUDFLARE_API_TOKEN}"
CF_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID}"

# ============================================================================
# FUNCTIONS
# ============================================================================

log_event() {
    local event="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $event" >> "$REVOCATION_LOG"
}

send_email() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    # For demo, just save to file. In production, use mail/sendmail
    cat > "/tmp/email-$recipient.txt" << EOF
To: $recipient
Subject: $subject
Date: $(date)

$body
EOF
    echo "Email would be sent to: $recipient"
    echo "Subject: $subject"
    echo ""
    echo "Body:"
    echo "$body"
    echo ""
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================

EMAIL="${1:-}"
DURATION_DAYS="${2:-7}"
NAME="${3:-Developer}"

if [ -z "$EMAIL" ]; then
    echo "Usage: developer-grant <email> [duration_days] [name]"
    echo ""
    echo "Example:"
    echo "  developer-grant john@example.com 7 'John Contractor'"
    exit 1
fi

# Validate email format
if ! [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Error: Invalid email format: $EMAIL"
    exit 1
fi

# Validate duration is numeric
if ! [[ "$DURATION_DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: Duration must be numeric days"
    exit 1
fi

# ============================================================================
# SETUP DIRECTORIES & DATABASE
# ============================================================================

mkdir -p "$(dirname "$DEVELOPERS_DB")"
mkdir -p "$(dirname "$REVOCATION_LOG")"

# Initialize database if it doesn't exist
if [ ! -f "$DEVELOPERS_DB" ]; then
    echo "Initializing developer database..."
    echo "email,name,grant_date,expiry_date,duration_days,status,cloudflare_access_id,notes" > "$DEVELOPERS_DB"
fi

# Check if developer already has active access
if grep -q "^$EMAIL,.*.active" "$DEVELOPERS_DB" 2>/dev/null; then
    echo "Warning: Developer $EMAIL already has active access"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ============================================================================
# CALCULATE DATES
# ============================================================================

GRANT_DATE=$(date '+%Y-%m-%d')
EXPIRY_DATE=$(date -d "+${DURATION_DAYS} days" '+%Y-%m-%d')

echo ""
echo "=========================================="
echo "Developer Access Grant"
echo "=========================================="
echo ""
echo "Email: $EMAIL"
echo "Name: $NAME"
echo "Grant Date: $GRANT_DATE"
echo "Expiry Date: $EXPIRY_DATE"
echo "Duration: $DURATION_DAYS days"
echo ""
echo "Auto-revocation will occur at:"
echo "  $EXPIRY_DATE 23:59:59 UTC"
echo ""

read -p "Grant access? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# ============================================================================
# CREATE CLOUDFLARE ACCESS POLICY (MOCK)
# ============================================================================

echo ""
echo "Creating Cloudflare Access policy..."

# In production, this would call the Cloudflare API:
# curl -X POST https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/access/apps \
#   -H "Authorization: Bearer $CF_API_TOKEN" \
#   -d '{
#     "name": "dev-access-'$EMAIL'",
#     "domain": "dev.yourdomain.com",
#     "type": "self_hosted",
#     "allowed_emails": ["'$EMAIL'"],
#     "expire_on": "'$EXPIRY_DATE'T23:59:59Z"
#   }'

# For demo, just generate a fake access ID
CLOUDFLARE_ACCESS_ID="access_demo_$(echo $RANDOM | md5sum | cut -c1-8)"
echo "  ✅ Created Cloudflare Access policy (ID: $CLOUDFLARE_ACCESS_ID)"

# ============================================================================
# ADD TO DATABASE
# ============================================================================

echo "Updating developer database..."
echo "$EMAIL,$NAME,$GRANT_DATE,$EXPIRY_DATE,$DURATION_DAYS,active,$CLOUDFLARE_ACCESS_ID,Developer grant" >> "$DEVELOPERS_DB"
echo "  ✅ Database updated"

# ============================================================================
# LOG THE ACTION
# ============================================================================

log_event "GRANT: $EMAIL ($NAME) - Duration: $DURATION_DAYS days - Expires: $EXPIRY_DATE"

# ============================================================================
# SEND EMAIL NOTIFICATION
# ============================================================================

echo "Sending notification email..."

EMAIL_BODY="Subject: Developer Access Granted - $DURATION_DAYS Days
To: $EMAIL

Hello,

Your access to the development IDE has been granted.

Access Details:
  IDE URL: https://dev.yourdomain.com
  Duration: $DURATION_DAYS days (until $EXPIRY_DATE)
  Session Timeout: 4 hours (you'll need to re-authenticate)
  Auto-Revocation: $EXPIRY_DATE 23:59:59 UTC

Security Restrictions (for your protection):
  ✓ Code is read-only (you cannot download files)
  ✓ Terminal commands are restricted (no wget, scp, nc, etc.)
  ✓ Git operations are proxied (your SSH key is not exposed)
  ✓ All actions are logged for audit compliance

How to Use:
  1. Go to: https://dev.yourdomain.com
  2. Log in with your email: $EMAIL
  3. You'll receive an MFA code via email
  4. Use the IDE to view code and work with the terminal
  5. Run: git status, git commit, git push (all work normally)
  6. Access will automatically expire on $EXPIRY_DATE

Support:
  If you have questions, contact your administrator.

This is an automated notification from the code-server access system.
Do not reply to this email.

---

Generated: $(date)
"

send_email "$EMAIL" "Developer Access Granted" "$EMAIL_BODY"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "=========================================="
echo "✅ Access Granted Successfully"
echo "=========================================="
echo ""
echo "Developer: $EMAIL ($NAME)"
echo "Valid Until: $EXPIRY_DATE 23:59:59 UTC"
echo "Access ID: $CLOUDFLARE_ACCESS_ID"
echo ""
echo "Actions taken:"
echo "  ✓ Cloudflare Access policy created"
echo "  ✓ Developer database updated"
echo "  ✓ Grant action logged"
echo "  ✓ Notification email queued"
echo ""
echo "Auto-revocation:"
echo "  This developer's access will automatically expire"
echo "  on $EXPIRY_DATE at 23:59:59 UTC via cron job."
echo ""
echo "Manual revocation (if needed):"
echo "  developer-revoke $EMAIL"
echo ""
echo "View all active developers:"
echo "  grep ',active,' $DEVELOPERS_DB"
echo ""
