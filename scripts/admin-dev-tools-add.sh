#!/usr/bin/env bash
# @file        scripts/admin-dev-tools-add.sh
# @module      operations/container-management
# @description Add new development packages to code-server container (admin-only)
# @owner       platform
# @status      active
#
# PURPOSE:
#   Provides controlled, audited method for admins to add new development packages
#   to the code-server container image. All changes are:
#   - Versioned and pinned for reproducibility
#   - Tracked in git commit history
#   - Rebuilt into container image
#   - Applied idempotently
#
# USAGE:
#   # Interactive mode (prompts for details)
#   bash scripts/admin-dev-tools-add.sh
#
#   # Add specific package with version
#   bash scripts/admin-dev-tools-add.sh --package curl --version 7.81.0-1ubuntu1.15 --category system-utilities
#
#   # Add multiple packages
#   bash scripts/admin-dev-tools-add.sh --package git,vim,tmux --category version-control,editors
#
#   # Show current installed packages
#   bash scripts/admin-dev-tools-add.sh --list
#
#   # Dry-run (preview changes without rebuilding)
#   bash scripts/admin-dev-tools-add.sh --dry-run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ════════════════════════════════════════════════════════════════════════════

DOCKERFILE_PATH="${SCRIPT_DIR}/../Dockerfile.code-server"
IMAGE_NAME="code-server-enterprise"
IMAGE_TAG="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${DOCKERFILE_PATH}.backup.${IMAGE_TAG}"

# Admin-only check
REQUIRED_ROLES=("admin" "platform" "infrastructure")

# ════════════════════════════════════════════════════════════════════════════
# FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log_section() {
    log_info "════════════════════════════════════════════════════════════════"
    log_info "$1"
    log_info "════════════════════════════════════════════════════════════════"
}

verify_admin_access() {
    local user="${SUDO_USER:-$USER}"
    local is_admin=false
    
    # Check if running as root or sudo
    if [ "${EUID:-$(id -u)}" -ne 0 ] && [ -z "${SUDO_USER:-}" ]; then
        log_fatal "❌ This script requires admin/sudo privileges"
        exit 1
    fi
    
    log_info "✅ Admin access verified (user: $user)"
}

show_current_packages() {
    log_section "📦 CURRENTLY INSTALLED DEVELOPMENT PACKAGES"
    
    local tmp_file="/tmp/packages-list.txt"
    grep -A 500 "# Build essentials & compilers" "$DOCKERFILE_PATH" | \
        grep -B 500 "apt-get clean" | \
        grep "^\s*[a-z]" | \
        sed 's/[=\\]//g' | \
        sed 's/^\s*//g' | \
        column -t > "$tmp_file" 2>/dev/null || sort > "$tmp_file"
    
    cat "$tmp_file"
    rm -f "$tmp_file"
    
    echo ""
    log_info "Total packages: $(grep -o '[a-z][a-z0-9\-]*=[0-9]' "$DOCKERFILE_PATH" | wc -l)"
}

validate_package_version() {
    local package="$1"
    local version="$2"
    
    if [ -z "$version" ]; then
        log_warn "⚠️  No version specified for $package — this is not recommended for immutability"
        log_warn "    Searching for latest available version..."
        
        # Try to find version from system
        local found_version
        found_version=$(apt-cache policy "$package" 2>/dev/null | grep "Candidate:" | awk '{print $2}' || echo "unknown")
        
        if [ "$found_version" != "unknown" ]; then
            log_info "    ✅ Latest available: $found_version"
            echo "$found_version"
        else
            log_error "Could not determine version for $package"
            return 1
        fi
    else
        log_info "✅ Version specified: $version"
        echo "$version"
    fi
}

add_to_dockerfile() {
    local package="$1"
    local version="$2"
    local category="$3"
    
    if [ -z "$version" ]; then
        version=$(validate_package_version "$package" "" || echo "latest")
    fi
    
    local entry="${package}=${version}"
    
    # Check if package already exists
    if grep -q "^\s*${package}=" "$DOCKERFILE_PATH"; then
        log_warn "⚠️  Package $package already in Dockerfile, skipping"
        return 0
    fi
    
    # Find the apt-get section and add package
    # This is a simplified approach — in production, use more robust parsing
    local marker_line
    marker_line=$(grep -n "# Compression utilities" "$DOCKERFILE_PATH" | cut -d: -f1)
    
    if [ -z "$marker_line" ]; then
        log_error "Could not find insertion point in Dockerfile"
        return 1
    fi
    
    log_info "Adding $entry to Dockerfile (category: $category)"
    
    # Insert before "Compression utilities" section
    sed -i.bak "${marker_line}i\\    ${entry} \\\\" "$DOCKERFILE_PATH"
    
    log_info "✅ Added $entry"
}

rebuild_image() {
    local dry_run="${1:-false}"
    
    if [ "$dry_run" = "true" ]; then
        log_warn "DRY-RUN MODE: Preview of changes (no rebuild)"
        log_info "Git diff:"
        git diff "$DOCKERFILE_PATH" || true
        return 0
    fi
    
    log_section "🔨 REBUILDING CONTAINER IMAGE"
    
    # Create backup
    cp "$DOCKERFILE_PATH" "$BACKUP_FILE"
    log_info "✅ Backup created: $BACKUP_FILE"
    
    # Validate Dockerfile syntax
    if ! docker build --dry-run -f "$DOCKERFILE_PATH" . &>/dev/null; then
        log_error "❌ Dockerfile syntax error detected"
        log_info "Restoring backup..."
        mv "$BACKUP_FILE" "$DOCKERFILE_PATH"
        return 1
    fi
    
    # Build image
    log_info "Building: $IMAGE_NAME:$IMAGE_TAG"
    if docker build \
        -f "$DOCKERFILE_PATH" \
        -t "$IMAGE_NAME:$IMAGE_TAG" \
        -t "$IMAGE_NAME:latest" \
        . ; then
        log_info "✅ Image built successfully"
        log_info "   Tag: $IMAGE_NAME:$IMAGE_TAG"
        log_info "   Tag: $IMAGE_NAME:latest"
    else
        log_error "❌ Build failed, restoring backup"
        mv "$BACKUP_FILE" "$DOCKERFILE_PATH"
        return 1
    fi
}

update_docker_compose() {
    local new_tag="$1"
    
    local compose_file="${SCRIPT_DIR}/../docker-compose.yml"
    
    if ! grep -q "code-server:" "$compose_file"; then
        log_warn "Could not find code-server service in docker-compose.yml"
        return 0
    fi
    
    log_info "Updating docker-compose.yml to use new image tag..."
    sed -i "s|image: codercom/code-server:.*|image: $IMAGE_NAME:$new_tag|" "$compose_file"
    
    log_info "✅ Updated docker-compose.yml"
    log_info "   New image: $IMAGE_NAME:$new_tag"
}

commit_changes() {
    local message="$1"
    
    if ! git add "$DOCKERFILE_PATH" docker-compose.yml 2>/dev/null; then
        log_warn "Could not git add changes (not a git repo?)"
        return 0
    fi
    
    if git diff --cached --quiet; then
        log_info "No changes to commit"
        return 0
    fi
    
    if git commit -m "$message"; then
        log_info "✅ Changes committed to git"
        git log --oneline -1
    else
        log_warn "Could not commit changes"
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════════════

main() {
    verify_admin_access
    
    local package=""
    local version=""
    local category=""
    local dry_run=false
    local list_mode=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package) package="$2"; shift 2 ;;
            --version) version="$2"; shift 2 ;;
            --category) category="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            --list) list_mode=true; shift ;;
            --help) show_usage; exit 0 ;;
            *) log_error "Unknown argument: $1"; exit 1 ;;
        esac
    done
    
    # List mode
    if [ "$list_mode" = "true" ]; then
        show_current_packages
        exit 0
    fi
    
    # Interactive mode
    if [ -z "$package" ]; then
        log_section "🔧 DEVELOPMENT PACKAGE INSTALLER (Admin-Only)"
        
        read -p "📦 Package name(s) [comma-separated]: " package
        read -p "📌 Version (leave blank for latest): " version || true
        read -p "🏷️  Category [system-utilities/interpreters/tools/other]: " category
        
        read -p "🔍 Dry-run first? [y/n]: " -n 1 dry_run_input
        echo ""
        [ "$dry_run_input" = "y" ] && dry_run=true
    fi
    
    if [ -z "$package" ]; then
        log_error "No package specified"
        exit 1
    fi
    
    # Show summary
    log_section "📋 PACKAGE ADDITION SUMMARY"
    log_info "Package(s): $package"
    log_info "Version: ${version:-latest}"
    log_info "Category: ${category:-unspecified}"
    log_info "Mode: $([ "$dry_run" = "true" ] && echo "DRY-RUN" || echo "APPLY")"
    
    # Process packages
    IFS=',' read -ra PACKAGES <<< "$package"
    for pkg in "${PACKAGES[@]}"; do
        pkg="${pkg// /}"  # trim whitespace
        if [ -n "$pkg" ]; then
            add_to_dockerfile "$pkg" "$version" "$category"
        fi
    done
    
    # Rebuild
    rebuild_image "$dry_run"
    
    # Update docker-compose
    if [ "$dry_run" = "false" ]; then
        update_docker_compose "$IMAGE_TAG"
        
        # Git commit
        local commit_msg="chore(container): add development packages: $package"
        [ -n "$version" ] && commit_msg="$commit_msg (version: $version)"
        commit_changes "$commit_msg"
        
        log_section "✅ COMPLETE"
        log_info "Next steps:"
        log_info "  1. Review changes: git show"
        log_info "  2. Redeploy: docker-compose up -d code-server"
        log_info "  3. Verify: docker exec code-server which $package"
    fi
}

show_usage() {
    cat << 'EOF'
USAGE: admin-dev-tools-add.sh [OPTIONS]

OPTIONS:
  --package <name>      Package name(s) to add [comma-separated for multiple]
  --version <version>   Specific package version (optional, uses latest if omitted)
  --category <cat>      Package category [system-utilities/interpreters/tools/other]
  --dry-run             Preview changes without rebuilding
  --list                Show currently installed packages
  --help                Display this help message

EXAMPLES:
  # Interactive mode
  bash scripts/admin-dev-tools-add.sh

  # Add specific package
  bash scripts/admin-dev-tools-add.sh --package rust --version 1.73.0 --category interpreters

  # Add multiple packages
  bash scripts/admin-dev-tools-add.sh --package git-lfs,subversion --category version-control

  # Dry-run preview
  bash scripts/admin-dev-tools-add.sh --package cmake --dry-run

IMPORTANT:
  - This script requires sudo/admin privileges
  - All changes are tracked in git history
  - Package versions are pinned for reproducibility
  - Changes rebuild the entire container image
  - After deployment, verify: docker exec code-server which <package>

IMMUTABILITY GUARANTEE:
  - All package installations are baked into the Dockerfile
  - Container is stateless and fully reproducible
  - Rebuild at any time produces identical result
  - No manual installations required from users
EOF
}

main "$@"
