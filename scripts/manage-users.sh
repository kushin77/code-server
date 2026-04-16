#!/bin/bash
# scripts/manage-users.sh - IDE User Management CLI

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ─────────────────────────────────────────────────────────────────────────────
# STRICT FILE VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
# Ensure critical paths exist before any operations
validate_required_files() {
  local required_files=(
    "allowed-emails.txt"
  )
  
  local required_dirs=(
    "config/user-settings"
    "config/role-settings"
    "audit"
  )
  
  for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "FATAL: Required file missing: $file" >&2
      exit 1
    fi
    if [[ ! -r "$file" ]]; then
      echo "FATAL: Cannot read required file: $file" >&2
      exit 1
    fi
  done
  
  for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      echo "FATAL: Required directory missing: $dir" >&2
      exit 1
    fi
    if [[ ! -w "$dir" ]]; then
      echo "FATAL: Cannot write to required directory: $dir" >&2
      exit 1
    fi
  done
}

# Validate file paths (prevent path traversal and typos)
validate_file_path() {
  local path="$1"
  
  # Reject any path with ../ or //
  if [[ "$path" =~ \.\. ]] || [[ "$path" =~ // ]]; then
    echo "FATAL: Invalid path: $path" >&2
    exit 1
  fi
  
  # Only allow specific known filenames
  case "$path" in
    allowed-emails.txt|allowed-emails.txt.tmp|audit/user-provisioning.log)
      return 0
      ;;
    *)
      echo "FATAL: Unexpected file path: $path" >&2
      exit 1
      ;;
  esac
}

# Atomic write with validation
atomic_write() {
  local file="$1"
  local content="$2"
  
  validate_file_path "$file"
  
  # Write to temporary file
  local tmpfile="${file}.tmp.$$"
  if ! echo "$content" > "$tmpfile"; then
    rm -f "$tmpfile"
    echo "ERROR: Failed to write temporary file: $tmpfile" >&2
    return 1
  fi
  
  # Verify temporary file was created and is readable
  if [[ ! -f "$tmpfile" ]] || [[ ! -r "$tmpfile" ]]; then
    rm -f "$tmpfile"
    echo "ERROR: Temporary file is not readable: $tmpfile" >&2
    return 1
  fi
  
  # Atomic rename
  if ! mv "$tmpfile" "$file"; then
    rm -f "$tmpfile"
    echo "ERROR: Failed to rename $tmpfile to $file" >&2
    return 1
  fi
  
  return 0
}

# Call validation on script startup
validate_required_files

# ─────────────────────────────────────────────────────────────────────────────
# COLORS & FORMATTING
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
  echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: list-users
# ─────────────────────────────────────────────────────────────────────────────
cmd_list_users() {
  print_header "ACTIVE IDE USERS"

  if [[ ! -f "allowed-emails.txt" ]]; then
    print_error "allowed-emails.txt not found"
    exit 1
  fi

  echo ""
  echo -e "${CYAN}Whitelisted Users (OAuth2):${NC}"
  echo "─────────────────────────────────────────────────────────────────"

  while IFS= read -r email; do
    if [[ -z "$email" || "$email" =~ ^# ]]; then
      continue
    fi

    user_id=$(echo "$email" | sed 's/@.*//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')
    config_dir="config/user-settings/$user_id"

    if [[ -f "$config_dir/user-metadata.json" ]]; then
      role=$(jq -r '.role' "$config_dir/user-metadata.json" 2>/dev/null)
      display=$(jq -r '.displayName' "$config_dir/user-metadata.json" 2>/dev/null)
      provisioned=$(jq -r '.dateProvisioned' "$config_dir/user-metadata.json" 2>/dev/null)

      printf "%-5s | %-30s | %-12s | %s\n" "✅" "$email" "$role" "$display"
      printf "     | Provisioned: %s\n" "$provisioned"
    else
      printf "%-5s | %-30s | %-12s\n" "📋" "$email" "(no profile)"
    fi
  done < allowed-emails.txt

  echo ""
  echo -e "${BLUE}Total: $(wc -l < allowed-emails.txt) users${NC}"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: add-user
# ─────────────────────────────────────────────────────────────────────────────
cmd_add_user() {
  local email="$1"
  local role="${2:-developer}"
  local display="${3:-}"

  if [[ -z "$email" ]]; then
    print_error "Email required. Usage: $0 add-user <email@company.com> [role] [display_name]"
    exit 1
  fi

  # Use provisioning script
  bash scripts/provision-new-user.sh "$email" "$role" "$display"
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: remove-user
# ─────────────────────────────────────────────────────────────────────────────
cmd_remove_user() {
  local email="$1"

  if [[ -z "$email" ]]; then
    print_error "Email required. Usage: $0 remove-user <email@company.com>"
    exit 1
  fi

  if ! grep -q "^$email$" allowed-emails.txt 2>/dev/null; then
    print_error "User not found: $email"
    exit 1
  fi

  print_warning "This will revoke access immediately"
  read -p "Are you sure? (type 'yes' to confirm): " confirm

  if [[ "$confirm" != "yes" ]]; then
    print_info "Cancelled"
    exit 0
  fi

  # Read current allowlist safely
  if [[ ! -f "allowed-emails.txt" ]]; then
    print_error "Allowlist file not found"
    exit 1
  fi
  
  # Create new allowlist without the user
  local new_content
  new_content=$(grep -v "^$email$" allowed-emails.txt 2>/dev/null || true)
  
  # Atomic write
  if ! atomic_write "allowed-emails.txt" "$new_content"; then
    print_error "Failed to update allowlist"
    exit 1
  fi

  # Audit log (append safely)
  {
    echo "$(date -I'seconds') | USER_REVOKED | email:$email | actor:${SUDO_USER:-${USER:-system}}"
  } >> audit/user-provisioning.log || {
    print_error "Failed to write audit log"
    exit 1
  }

  print_success "User removed: $email"
  print_info "Restart OAuth2 to apply: docker compose restart oauth2-proxy"
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: change-role
# ─────────────────────────────────────────────────────────────────────────────
cmd_change_role() {
  local email="$1"
  local new_role="$2"

  if [[ -z "$email" || -z "$new_role" ]]; then
    print_error "Usage: $0 change-role <email@company.com> <viewer|developer|architect|admin>"
    exit 1
  fi

  if ! [[ "$new_role" =~ ^(viewer|developer|architect|admin)$ ]]; then
    print_error "Invalid role: $new_role"
    exit 1
  fi

  user_id=$(echo "$email" | sed 's/@.*//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')
  config_dir="config/user-settings/$user_id"

  if [[ ! -d "$config_dir" ]]; then
    print_error "User profile not found: $config_dir"
    exit 1
  fi

  if [[ ! -f "$config_dir/user-metadata.json" ]]; then
    print_error "User metadata not found: $config_dir/user-metadata.json"
    exit 1
  fi

  # Get current role
  old_role=$(jq -r '.role' "$config_dir/user-metadata.json" 2>/dev/null || echo "unknown")

  # Validate metadata file is readable
  if [[ "$old_role" == "unknown" ]]; then
    print_error "Could not read role from user metadata"
    exit 1
  fi

  # Update metadata with atomic write
  local updated_metadata
  updated_metadata=$(jq ".role = \"$new_role\" | .lastModified = \"$(date -I'seconds')\"" "$config_dir/user-metadata.json" 2>/dev/null)
  
  if [[ -z "$updated_metadata" ]]; then
    print_error "Failed to update metadata JSON"
    exit 1
  fi
  
  echo "$updated_metadata" > "$config_dir/user-metadata.json.tmp" || {
    print_error "Failed to write metadata"
    exit 1
  }
  
  mv "$config_dir/user-metadata.json.tmp" "$config_dir/user-metadata.json" || {
    print_error "Failed to rename metadata file"
    exit 1
  }

  # Update settings from template
  role_template="config/role-settings/${new_role}-profile.json"
  if [[ -f "$role_template" ]]; then
    cp "$role_template" "$config_dir/settings.json" || {
      print_error "Failed to copy role template"
      exit 1
    }
  else
    print_warning "Role template not found: $role_template"
  fi

  # Audit log
  {
    echo "$(date -I'seconds') | USER_ROLE_CHANGED | email:$email | from:$old_role | to:$new_role | actor:${SUDO_USER:-${USER:-system}}"
  } >> audit/user-provisioning.log || {
    print_error "Failed to write audit log"
    exit 1
  }

  print_success "Role changed: $email ($old_role → $new_role)"
  print_info "Settings will reload on next session"
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: show-user
# ─────────────────────────────────────────────────────────────────────────────
cmd_show_user() {
  local email="$1"

  if [[ -z "$email" ]]; then
    print_error "Usage: $0 show-user <email@company.com>"
    exit 1
  fi

  user_id=$(echo "$email" | sed 's/@.*//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')
  config_dir="config/user-settings/$user_id"

  if [[ ! -f "$config_dir/user-metadata.json" ]]; then
    print_error "User not found: $email"
    exit 1
  fi

  print_header "USER PROFILE: $email"
  echo ""

  echo -e "${CYAN}Metadata:${NC}"
  jq '.' "$config_dir/user-metadata.json" | sed 's/^/  /'
  echo ""

  echo -e "${CYAN}Settings:${NC}"
  jq '.settings' "$config_dir/settings.json" | head -20 | sed 's/^/  /'
  echo ""

  echo -e "${CYAN}Workspace:${NC}"
  workspace_dir="workspaces/$user_id"
  if [[ -d "$workspace_dir" ]]; then
    ls -lh "$workspace_dir" | sed 's/^/  /'
  fi
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: list-sessions
# ─────────────────────────────────────────────────────────────────────────────
cmd_list_sessions() {
  print_header "ACTIVE SESSIONS"

  echo ""
  echo -e "${CYAN}Sessions from logs:${NC}"
  echo "─────────────────────────────────────────────────────────────────"

  if docker logs oauth2-proxy 2>&1 | grep -q "authenticated"; then
    docker logs oauth2-proxy 2>&1 | grep "authenticated" | tail -10 | while read line; do
      echo "  $line"
    done
  else
    print_warning "No recent session logs"
  fi

  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: revoke-all-sessions
# ─────────────────────────────────────────────────────────────────────────────
cmd_revoke_all_sessions() {
  print_warning "This will log out all users"
  read -p "Are you sure? (type 'yes' to confirm): " confirm

  if [[ "$confirm" != "yes" ]]; then
    print_info "Cancelled"
    exit 0
  fi

  docker compose restart oauth2-proxy
  sleep 2
  print_success "All sessions revoked"
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: security-status
# ─────────────────────────────────────────────────────────────────────────────
cmd_security_status() {
  print_header "SECURITY STATUS"

  echo ""
  echo -e "${CYAN}Configuration Checks:${NC}"
  echo "─────────────────────────────────────────────────────────────────"

  # Check 1: File downloads disabled
  if grep -q "CS_DISABLE_FILE_DOWNLOADS=true" docker-compose.yml; then
    print_success "File downloads disabled"
  else
    print_error "File downloads NOT disabled!"
  fi

  # Check 2: Terminal disabled
  if grep -q '"terminal.integrated.enabled": false' config/settings.json; then
    print_success "Terminal disabled"
  else
    print_error "Terminal NOT disabled!"
  fi

  # Check 3: Email whitelist active
  if [[ -f "allowed-emails.txt" && -s "allowed-emails.txt" ]]; then
    user_count=$(wc -l < allowed-emails.txt)
    print_success "Email whitelist active ($user_count users)"
  else
    print_error "Email whitelist empty or missing!"
  fi

  # Check 4: Role templates exist
  if [[ -d "config/role-settings" && -n "$(ls config/role-settings/*.json 2>/dev/null)" ]]; then
    role_count=$(ls config/role-settings/*.json 2>/dev/null | wc -l)
    print_success "Role templates configured ($role_count roles)"
  else
    print_error "Role templates missing!"
  fi

  # Check 5: Audit logging
  if [[ -d "logs/audit" ]]; then
    audit_size=$(du -sh logs/audit 2>/dev/null | cut -f1)
    print_success "Audit logging active ($audit_size)"
  else
    print_error "Audit directory missing!"
  fi

  echo ""
  echo -e "${CYAN}Docker Status:${NC}"
  echo "─────────────────────────────────────────────────────────────────"

  docker compose ps --filter 'name=oauth2-proxy' --filter 'name=code-server' 2>/dev/null | sed 's/^/  /'

  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMAND: help
# ─────────────────────────────────────────────────────────────────────────────
cmd_help() {
  cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                    IDE USER MANAGEMENT                                   ║
╚═══════════════════════════════════════════════════════════════════════════╝

USAGE:
  ./scripts/manage-users.sh <command> [options]

COMMANDS:

  list-users              List all whitelisted users
  add-user <email> [role] [display]
                          Provision a new user
                          Roles: viewer, developer, architect, admin

  remove-user <email>     Revoke user access (immediately)

  change-role <email> <role>
                          Change user's role

  show-user <email>       Display user profile and settings

  list-sessions           Show active user sessions

  revoke-all-sessions     Log out all users (immediate)

  security-status         Check security configuration status

  help                    Show this help message

EXAMPLES:

  Add a new developer:
    ./scripts/manage-users.sh add-user dev@company.com developer "John Developer"

  Change role to viewer:
    ./scripts/manage-users.sh change-role dev@company.com viewer

  List all users:
    ./scripts/manage-users.sh list-users

  Check security:
    ./scripts/manage-users.sh security-status

ROLES:

  viewer      - Read-only code access, cannot edit or download
  developer   - Full edit access, cannot clone/push directly
  architect   - Can edit design docs, markdown, configuration; code is read-only
  admin       - Full access with complete audit trail

WORKFLOW:

  1. Provision user:
     ./scripts/manage-users.sh add-user new@company.com developer "New Dev"

  2. Commit changes:
     git add allowed-emails.txt config/user-settings/
     git commit -m "chore: add user new@company.com"
     git push origin main

  3. Verify user can login:
     → User opens https://ide.kushnir.cloud
     → Authenticates with Google OAuth
     → Settings auto-apply based on role

  4. (Optional) Change role later:
     ./scripts/manage-users.sh change-role new@company.com viewer

  5. (Optional) Revoke access:
     ./scripts/manage-users.sh remove-user new@company.com

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  list-users)
    cmd_list_users
    ;;
  add-user)
    cmd_add_user "$@"
    ;;
  remove-user)
    cmd_remove_user "$@"
    ;;
  change-role)
    cmd_change_role "$@"
    ;;
  show-user)
    cmd_show_user "$@"
    ;;
  list-sessions)
    cmd_list_sessions
    ;;
  revoke-all-sessions)
    cmd_revoke_all_sessions
    ;;
  security-status)
    cmd_security_status
    ;;
  help|--help|-h)
    cmd_help
    ;;
  *)
    print_error "Unknown command: $COMMAND"
    cmd_help
    exit 1
    ;;
esac
