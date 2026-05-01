#!/bin/bash
# Comprehensive code quality verification script
# Checks for common anti-patterns, validates Docker configs, verifies test infrastructure

set -e

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

echo "=== Code Quality Verification ==="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

failed=0

# 1. Check for stdlib logging in production code
echo "1. Logger patterns..."
stdlib_logging=$(grep -rl "^import logging" apps/ --include="*.py" | grep -vc "log\.py\|test\|_shared" || true)
if [ "$stdlib_logging" -eq 0 ]; then
    echo -e "   ${GREEN}✓${NC} All production code uses get_logger()"
else
    echo -e "   ${RED}✗${NC} Found $stdlib_logging files with stdlib logging"
    failed=$((failed + 1))
fi
echo ""

# 2. Check for cross-app imports in production (excluding test files)
echo "2. Import patterns..."
cross_imports=$(grep -rl "from apps\." apps/ --include="*.py" | grep -vc "test\|_shared" || true)
if [ "$cross_imports" -eq 0 ]; then
    echo -e "   ${GREEN}✓${NC} All production imports use relative/local paths"
else
    echo -e "   ${YELLOW}⚠${NC} $cross_imports files with from apps.* imports (test files OK)"
fi
echo ""

# 3. Docker config validation
echo "3. Docker hardening..."
dockerfile_count=$(find apps/ -name Dockerfile | wc -l)
nonroot=$(find apps/ -name Dockerfile | xargs grep -l "^USER" 2>/dev/null | wc -l || echo 0)
healthchecks=$(find apps/ -name Dockerfile | xargs grep -l "HEALTHCHECK" 2>/dev/null | wc -l || echo 0)
sha_pinned=$(find apps/ -name Dockerfile | xargs grep -l "@sha256:" 2>/dev/null | wc -l || echo 0)

echo "   Non-root USER: $nonroot/$dockerfile_count"
echo "   HEALTHCHECK: $healthchecks/$dockerfile_count"
echo "   SHA256 pinned: $sha_pinned/$dockerfile_count"

if [ "$nonroot" -eq "$dockerfile_count" ] && [ "$healthchecks" -eq "$dockerfile_count" ] && [ "$sha_pinned" -eq "$dockerfile_count" ]; then
    echo -e "   ${GREEN}✓${NC} All Dockerfiles hardened"
else
    echo -e "   ${YELLOW}⚠${NC} Some Dockerfiles missing hardening"
fi
echo ""

# 4. Dependency manifests
echo "4. Dependency manifests..."
app_count=$(ls -d apps/*/ | grep -vc "_shared\|__pycache__\|extensions" || true)
req_count=$(find apps/ -maxdepth 2 \( -name requirements.txt -o -name pyproject.toml \) | grep -v _shared | wc -l || echo 0)
echo "   Apps with dependency manifest: $req_count/$app_count"
echo ""

# 5. Test infrastructure
echo "5. Test infrastructure..."
pytest_configs=$(find apps/ -name pytest.ini 2>/dev/null | wc -l || echo 0)
test_files=$(find apps/ \( -name "test_*.py" -o -name "*_test.py" \) 2>/dev/null | wc -l || echo 0)
echo "   pytest configs: $pytest_configs"
echo "   Test files: $test_files"
echo ""

# 6. Python syntax check (all app files must parse)
echo "6. Python syntax validation..."
syntax_errors=0
for py_file in $(find apps/ -name "*.py" -not -path "*/__pycache__/*" 2>/dev/null); do
    if ! python3 -m py_compile "$py_file" 2>/dev/null; then
        echo "   ${RED}✗${NC} Syntax error: $py_file"
        syntax_errors=$((syntax_errors + 1))
    fi
done

if [ "$syntax_errors" -eq 0 ]; then
    echo -e "   ${GREEN}✓${NC} All Python files parse correctly"
else
    echo -e "   ${RED}✗${NC} Found $syntax_errors syntax errors"
    failed=$((failed + 1))
fi
echo ""

if [ $failed -gt 0 ]; then
    echo -e "${RED}✗ Quality check failed ($failed critical issues)${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All quality checks passed${NC}"
    exit 0
fi
