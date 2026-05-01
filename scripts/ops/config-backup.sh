#!/bin/bash
# Git-based configuration backup
# Tags configuration snapshots in git for version control backup

set -e
trap 'echo "❌ Config backup failed at line $LINENO"; exit 1' ERR

REPO_DIR="${REPO_DIR:-/home/akushnir/code-server}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Configuration Backup (Git-based)                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd "$REPO_DIR"

# Verify git repository
if [[ ! -d ".git" ]]; then
  echo "❌ Not a git repository: $REPO_DIR"
  exit 1
fi

echo "Repository: $REPO_DIR"
echo "Current branch: $(git rev-parse --abbrev-ref HEAD)"
echo ""

# Check for uncommitted changes
CHANGES=$(git status --porcelain | wc -l)

if [[ $CHANGES -gt 0 ]]; then
  echo "⚠️  Uncommitted changes detected:"
  git status --porcelain
  echo ""
  echo "Commit changes before backup? (yes/no)"
  read -r confirm
  
  if [[ "$confirm" == "yes" ]]; then
    git add -A
    git commit -m "ops: pre-backup configuration snapshot - $(date +%Y%m%d_%H%M%S)"
    echo "✅ Changes committed"
  else
    echo "⚠️  Skipping backup tag (changes not committed)"
    exit 0
  fi
fi

# Create backup tag
TAG="backup-$(date +%Y%m%d-%H%M%S)"
COMMIT=$(git rev-parse HEAD)

echo "Creating backup tag: $TAG"
git tag -a "$TAG" -m "Configuration backup - $(date -R)"

echo "✅ Tag created: $TAG"
echo "  Commit: $COMMIT"
echo "  Date: $(date)"

echo ""
echo "Recent backup tags:"
git tag | grep "^backup-" | sort -V | tail -5

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Configuration backup complete                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
