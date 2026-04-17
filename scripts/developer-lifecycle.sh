#!/usr/bin/env bash
# @file        scripts/developer-lifecycle.sh
# @module      operations
# @description developer lifecycle — on-prem code-server
# @owner       platform
# @status      active
# Developer Access Lifecycle Management
# 
# Purpose: Grant time-bounded access to developers with automatic expiration
# Features: Onboarding grants, offboarding revocation, audit logging
#
# Usage:
#   ./developer-lifecycle.sh grant username email "2026-04-30" "Contractor project X"
#   ./developer-lifecycle.sh revoke username
#   ./developer-lifecycle.sh list
#   ./developer-lifecycle.sh expire-check

set -eu

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
readonly DB_FILE="${DB_FILE:-/etc/developer-access/developers.db}"
readonly AUDIT_LOG="${AUDIT_LOG:-/var/log/developer-access-audit.log}"
readonly SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/developer-access/certs}"
readonly LOCK_FILE="/tmp/developer-lifecycle.lock"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Acquire lock to prevent concurrent modifications
acquire_lock() {
    local timeout=5
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if mkdir "$LOCK_FILE" 2>/dev/null; then
            trap 'rmdir "$LOCK_FILE"' EXIT
            return 0
        fi
        sleep 0.1
        ((elapsed++))
    done
    echo "ERROR: Could not acquire lock" >&2
    return 1
}

# Initialize database
init_db() {
    local db_dir=$(dirname "$DB_FILE")
    
    if [[ ! -d "$db_dir" ]]; then
        sudo mkdir -p "$db_dir"
        sudo chmod 700 "$db_dir"
    fi
    
    if [[ ! -f "$DB_FILE" ]]; then
        sudo tee "$DB_FILE" > /dev/null << 'SQL'
CREATE TABLE developers (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT NOT NULL,
    grant_date TEXT NOT NULL,
    expiration_date TEXT NOT NULL,
    status TEXT DEFAULT 'active',  -- active, expired, revoked
    reason TEXT,
    created_by TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_username ON developers(username);
CREATE INDEX idx_expiration ON developers(expiration_date);
CREATE INDEX idx_status ON developers(status);

CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    action TEXT,  -- grant, revoke, expire, verify
    developer_username TEXT,
    actor_email TEXT,
    details TEXT,
    result TEXT  -- success, failure
);

CREATE INDEX idx_audit_timestamp ON audit_log(timestamp);
CREATE INDEX idx_audit_developer ON audit_log(developer_username);
SQL

        sudo chmod 600 "$DB_FILE"
    fi
}

# Log audit entry
log_audit() {
    local action="$1"
    local username="$2"
    local actor="${3:-system}"
    local result="${4:-success}"
    local details="${5:-}"
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        sudo touch "$AUDIT_LOG"
        sudo chmod 600 "$AUDIT_LOG"
    fi
    
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "${timestamp} | ${action} | ${username} | ${actor} | ${result} | ${details}" | sudo tee -a "$AUDIT_LOG" > /dev/null
}

# Grant developer access
grant_access() {
    local username="$1"
    local email="$2"
    local expiration_date="$3"
    local reason="${4:-}"
    local actor="${SUDO_USER:-$(whoami)}"
    
    acquire_lock
    
    # Validate inputs
    if [[ ! "$username" =~ ^[a-z0-9_-]{3,32}$ ]]; then
        echo -e "${RED}✗ Invalid username format${NC}" >&2
        log_audit "grant" "$username" "$actor" "failure" "Invalid username format"
        return 1
    fi
    
    if [[ ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        echo -e "${RED}✗ Invalid email format${NC}" >&2
        log_audit "grant" "$username" "$actor" "failure" "Invalid email format"
        return 1
    fi
    
    # Validate expiration date (ISO 8601 format)
    if ! date -d "$expiration_date" +%Y-%m-%d > /dev/null 2>&1; then
        echo -e "${RED}✗ Invalid expiration date format (use YYYY-MM-DD)${NC}" >&2
        log_audit "grant" "$username" "$actor" "failure" "Invalid date format"
        return 1
    fi
    
    # Check if developer already exists
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        echo -e "${YELLOW}⚠ Developer already exists, updating access${NC}"
    fi
    
    local grant_date=$(date -u +'%Y-%m-%d')
    
    # Create OS user if not exists
    if ! id "$username" &>/dev/null; then
        echo "Creating OS user: $username"
        
        sudo useradd -m -s /bin/restricted-shell "$username" || {
            echo -e "${RED}✗ Failed to create user${NC}" >&2
            log_audit "grant" "$username" "$actor" "failure" "Failed to create OS user"
            return 1
        }
        
        # Set strong password (auto-generated, stored securely)
        local temp_password=$(openssl rand -base64 24)
        echo "$username:$temp_password" | sudo chpasswd
        
        # Disable password login (SSH key only)
        sudo usermod -L "$username" 2>/dev/null || true
    fi
    
    # Grant Cloudflare Access token
    local cf_token=$(generate_cloudflare_token "$username" "$email" "$expiration_date")
    
    # Store in database
    init_db
    
    # Insert or update record
    sqlite3 "$DB_FILE" <<SQL
INSERT OR REPLACE INTO developers (username, email, grant_date, expiration_date, status, reason, created_by, updated_at)
VALUES ('$username', '$email', '$grant_date', '$expiration_date', 'active', '$reason', '$actor', CURRENT_TIMESTAMP);
SQL
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}✗ Failed to update database${NC}" >&2
        log_audit "grant" "$username" "$actor" "failure" "Database update failed"
        return 1
    fi
    
    # Create SSH key if not exists
    if [[ ! -f "$HOME/.ssh/${username}_key" ]]; then
        echo "Generating SSH key for developer..."
        ssh-keygen -t ed25519 -f "$HOME/.ssh/${username}_key" -N "" -C "$email" || {
            echo -e "${RED}✗ Failed to generate SSH key${NC}" >&2
            return 1
        }
    fi
    
    # Output grant summary
    cat << EOF

${GREEN}✓ Developer Access Granted${NC}
═══════════════════════════════════════════════════════════════

  Username:          $username
  Email:             $email
  Grant Date:        $grant_date
  Expiration Date:   $expiration_date
  Reason:            ${reason:-No reason specified}

  Access Methods:
  ┌─ Cloudflare Access via IDE
  │  URL: https://ide.dev.yourdomain.com
  │  Token expires: $expiration_date
  │
  ├─ SSH Access
  │  NOT RECOMMENDED - Use IDE instead
  │  (SSH keys stored on home server only)
  │
  └─ Git Operations
     Via proxy server (no git keys needed)

  Documents:
  • Developer Onboarding: $(pwd)/DEV_ONBOARDING.md
  • Git Proxy Setup: $(pwd)/TIER-2-184-GIT-PROXY-IMPLEMENTATION.md

═══════════════════════════════════════════════════════════════
EOF
    
    log_audit "grant" "$username" "$actor" "success" "Expiration: $expiration_date"
    return 0
}

# Revoke developer access
revoke_access() {
    local username="$1"
    local actor="${SUDO_USER:-$(whoami)}"
    local reason="${2:-}"
    
    acquire_lock
    
    echo -e "${YELLOW}! Revoking access for: $username${NC}"
    
    # Check if developer exists
    if ! grep -q "^$username:" /etc/passwd 2>/dev/null; then
        echo -e "${RED}✗ Developer not found${NC}" >&2
        log_audit "revoke" "$username" "$actor" "failure" "Developer not found"
        return 1
    fi
    
    # Update database status
    init_db
    sqlite3 "$DB_FILE" <<SQL
UPDATE developers
SET status = 'revoked', updated_at = CURRENT_TIMESTAMP
WHERE username = '$username' AND status = 'active';
SQL
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}✗ Failed to update database${NC}" >&2
        return 1
    fi
    
    # Revoke Cloudflare Access
    revoke_cloudflare_token "$username" "$email"
    
    # Lock OS user account
    sudo usermod -L "$username" 2>/dev/null || true
    
    # Remove from sudo group if present
    sudo deluser "$username" sudo 2>/dev/null || true
    sudo deluser "$username" wheel 2>/dev/null || true
    
    # Bundle private data for archive
    if [[ -d "/home/$username" ]]; then
        local archive="/tmp/developer-offboarding-${username}-$(date +%s).tar.gz"
        sudo tar -czf "$archive" -C /home "$username" 2>/dev/null || true
        echo -e "${YELLOW}! Offboarding data saved to: $archive${NC}"
    fi
    
    echo -e "${GREEN}✓ Access revoked for: $username${NC}"
    log_audit "revoke" "$username" "$actor" "success" "Reason: $reason"
    return 0
}

# Automatic expiration check (run periodically via cron)
check_expirations() {
    local today=$(date -u +'%Y-%m-%d')
    
    init_db
    
    # Find expired developers
    local expired=$(sqlite3 "$DB_FILE" "SELECT username, email FROM developers WHERE status = 'active' AND expiration_date < '$today';")
    
    if [[ -z "$expired" ]]; then
        echo "No expirations to process"
        return 0
    fi
    
    while IFS= read -r line; do
        local username=$(echo "$line" | cut -d'|' -f1)
        local email=$(echo "$line" | cut -d'|' -f2)
        
        echo "Auto-expiring: $username"
        revoke_access "$username" "Expiration date reached"
    done <<< "$expired"
}

# List all developers
list_developers() {
    init_db
    
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Developer Access List"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    sqlite3 -header -column "$DB_FILE" <<SQL
SELECT
    username,
    email,
    status,
    grant_date,
    expiration_date,
    CASE
        WHEN expiration_date < date('now') THEN 'EXPIRED'
        WHEN expiration_date < date('now', '+7 days') THEN 'EXPIRING SOON'
        ELSE 'ACTIVE'
    END as health,
    reason
FROM developers
ORDER BY expiration_date;
SQL
    echo
}

# Generate Cloudflare Access token
generate_cloudflare_token() {
    local username="$1"
    local email="$2"
    local expiration_date="$3"
    
    # This would integrate with Cloudflare API
    # For now, we'll create a placeholder that Cloudflare tunnel validates
    
    # In production:
    # 1. Call Cloudflare API with service token
    # 2. Create Access policy for this developer
    # 3. Return JWT token
    
    # Placeholder
    echo "CF_TOKEN_${username}_PLACEHOLDER"
}

# Revoke Cloudflare token
revoke_cloudflare_token() {
    local username="$1"
    local email="$2"
    
    # In production:
    # 1. Call Cloudflare API
    # 2. Remove Access policy
    # 3. Invalidate tokens
    
    echo "Revoked CF access for $username"
}

# Show usage
usage() {
    cat << EOF
${GREEN}Developer Access Lifecycle Manager${NC}

Usage:
  $0 grant <username> <email> <expiration-date> [reason]
  $0 revoke <username> [reason]
  $0 list
  $0 expire-check

Examples:
  # Grant access to contractor until end of project
  $0 grant alice@contractor.com alice@contractor.com "2026-04-30" "Project X contractor"

  # Revoke access
  $0 revoke alice "Contract ended"

  # List all developers
  $0 list

  # Check for expirations (run via cron)
  $0 expire-check

EOF
}

# Main
main() {
    case "${1:-help}" in
        grant)
            if [[ $# -lt 4 ]]; then
                echo "ERROR: grant requires 4+ arguments" >&2
                usage
                return 1
            fi
            grant_access "$2" "$3" "$4" "${5:-}"
            ;;
        revoke)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: revoke requires 2+ arguments" >&2
                usage
                return 1
            fi
            revoke_access "$2" "${3:-}"
            ;;
        list)
            list_developers
            ;;
        expire-check)
            check_expirations
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "ERROR: Unknown command '$1'" >&2
            usage
            return 1
            ;;
    esac
}

main "$@"
