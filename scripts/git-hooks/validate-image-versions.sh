#!/bin/bash
# Pre-commit hook to validate image tag versioning
# Prevents floating tags (latest, master, main) from entering production code
# 
# Installation: cp scripts/git-hooks/validate-image-versions.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
# Manual run: ./scripts/git-hooks/validate-image-versions.sh

set -e
trap 'echo "Error: Script failed at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/validate-image-versions-*.tmp 2>/dev/null || true' EXIT

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Configuration
ALLOWED_FLOATING_TAGS=()  # Leave empty or add exceptions like "localhost:5000/myimage:dev"
STRICT_MODE="${STRICT_MODE:-true}"  # Fail on any floating tag

# Floating tag patterns to reject
FLOATING_TAG_PATTERNS=(
  ":latest"
  ":master"
  ":main"
  ":develop"
  ":dev"
  ":nightly"
)

# Files to scan
COMPOSE_FILES=$(git diff --cached --name-only | grep -E 'docker-compose.*\.ya?ml$' || true)
DOCKERFILE_FILES=$(git diff --cached --name-only | grep -i 'dockerfile' || true)
SCRIPT_FILES=$(git diff --cached --name-only | grep -E '\.(sh|bash)$' || true)

if [[ -z "$COMPOSE_FILES" ]] && [[ -z "$DOCKERFILE_FILES" ]] && [[ -z "$SCRIPT_FILES" ]]; then
  exit 0
fi

VIOLATIONS=()
WARNINGS=()

# Function to check if a tag is in the allowlist
is_allowed() {
  local tag="$1"
  for allowed in "${ALLOWED_FLOATING_TAGS[@]}"; do
    if [[ "$tag" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

# Function to extract image references from docker-compose files
check_compose_files() {
  if [[ -z "$COMPOSE_FILES" ]]; then
    return
  fi

  echo -e "${YELLOW}Scanning docker-compose files for floating tags...${NC}" >&2

  while IFS= read -r file; do
    while IFS= read -r line; do
      # Look for image: lines (various formats)
      if [[ $line =~ image:\ *([a-zA-Z0-9._/:-]+) ]]; then
        image="${BASH_REMATCH[1]}"
        
        # Check for floating tags
        for pattern in "${FLOATING_TAG_PATTERNS[@]}"; do
          if [[ $image == *"$pattern" ]]; then
            if is_allowed "$image"; then
              WARNINGS+=("ALLOWED: $file - $image")
            else
              VIOLATIONS+=("FLOATING TAG: $file - $image")
            fi
          fi
        done

        # Check for images without explicit tags (assumed :latest)
        if [[ ! $image =~ : ]] && [[ ! $image =~ \$ ]]; then
          VIOLATIONS+=("MISSING TAG: $file - $image (will default to :latest)")
        fi
      fi
    done < <(git show ":$file")
  done <<< "$COMPOSE_FILES"
}

# Function to extract image references from Dockerfiles
check_dockerfiles() {
  if [[ -z "$DOCKERFILE_FILES" ]]; then
    return
  fi

  echo -e "${YELLOW}Scanning Dockerfiles for floating tags...${NC}" >&2

  while IFS= read -r file; do
    while IFS= read -r line; do
      # Look for FROM lines
      if [[ $line =~ ^FROM\ ([a-zA-Z0-9._/:-]+)(@sha256:[a-f0-9]+)?(.*)$ ]]; then
        image="${BASH_REMATCH[1]}"
        digest="${BASH_REMATCH[2]}"
        
        # Check for floating tags (unless pinned by digest)
        if [[ -z "$digest" ]]; then
          for pattern in "${FLOATING_TAG_PATTERNS[@]}"; do
            if [[ $image == *"$pattern" ]]; then
              if is_allowed "$image"; then
                WARNINGS+=("ALLOWED: $file - $image")
              else
                VIOLATIONS+=("FLOATING TAG: $file - $image")
              fi
            fi
          done

          # Check for images without explicit tags
          if [[ ! $image =~ : ]] && [[ ! $image =~ \$ ]]; then
            VIOLATIONS+=("MISSING TAG: $file - $image (will default to :latest)")
          fi
        fi
      fi

      # Also check RUN commands that build images
      if [[ $line =~ docker\ build.*-t\ ([a-zA-Z0-9._/:-]+) ]]; then
        image="${BASH_REMATCH[1]}"
        for pattern in "${FLOATING_TAG_PATTERNS[@]}"; do
          if [[ $image == *"$pattern" ]]; then
            WARNINGS+=("BUILD TAG: $file - $image")
          fi
        done
      fi
    done < <(git show ":$file")
  done <<< "$DOCKERFILE_FILES"
}

# Function to check for hardcoded image tags in shell scripts
check_script_files() {
  if [[ -z "$SCRIPT_FILES" ]]; then
    return
  fi

  echo -e "${YELLOW}Scanning shell scripts for docker pull/build commands...${NC}" >&2

  while IFS= read -r file; do
    while IFS= read -r line; do
      # Look for docker pull or build with floating tags
      if [[ $line =~ docker\ (pull|run|build).*:latest ]] || \
         [[ $line =~ docker\ (pull|run|build).*:master ]] || \
         [[ $line =~ docker\ (pull|run|build).*:main ]]; then
        WARNINGS+=("HARDCODED TAG: $file - $line")
      fi
    done < <(git show ":$file" | grep -E 'docker (pull|run|build)' || true)
  done <<< "$SCRIPT_FILES"
}

# Main execution
check_compose_files
check_dockerfiles
check_script_files

# Report results
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "\n${YELLOW}Warnings (allowed but noted):${NC}" >&2
  for warning in "${WARNINGS[@]}"; do
    echo -e "  ⚠ $warning" >&2
  done
fi

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo -e "\n${RED}❌ VIOLATIONS FOUND - Commit blocked:${NC}" >&2
  echo "" >&2
  for violation in "${VIOLATIONS[@]}"; do
    echo -e "  ${RED}✗${NC} $violation" >&2
  done
  echo "" >&2
  echo -e "${RED}Action Required:${NC}" >&2
  echo "  1. Replace :latest with explicit versions (e.g., :1.13.0)" >&2
  echo "  2. Or add image to ALLOWED_FLOATING_TAGS in this hook" >&2
  echo "  3. Or disable with: git commit --no-verify (NOT recommended)" >&2
  echo "" >&2
  echo -e "${YELLOW}Examples of fixes:${NC}" >&2
  echo "  WRONG:  image: myservice:latest" >&2
  echo "  RIGHT:  image: myservice:1.2.3" >&2
  echo "" >&2
  echo "  WRONG:  FROM python:3.11" >&2
  echo "  RIGHT:  FROM python:3.11-slim@sha256:..." >&2
  echo "" >&2
  exit 1
fi

if [[ ${#VIOLATIONS[@]} -eq 0 ]]; then
  echo -e "${GREEN}✓ All image tags are properly versioned${NC}" >&2
  exit 0
fi
