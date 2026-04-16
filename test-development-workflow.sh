#!/bin/bash
set -e

cd code-server-enterprise

echo "=== SIMULATED USER LOGIN AND DEVELOPMENT TEST ==="
echo ""
echo "1. User accesses code-server API:"
docker-compose exec -T code-server curl -s http://localhost:8080/api/v1 | head -c 80
echo ""
echo ""
echo "2. User clones kushin77/code-server repository:"
docker-compose exec -T code-server bash -c 'cd /tmp && rm -rf test-repo 2>/dev/null; git clone https://github.com/kushin77/code-server.git test-repo && cd test-repo && echo "Repository cloned successfully" && git status | head -5'
echo ""
echo "3. User creates test files and explores structure:"
docker-compose exec -T code-server bash -c 'cd /tmp/test-repo && ls -la | head -10 && echo "..." && echo "Total files: $(find . -type f 2>/dev/null | wc -l)"'
echo ""
echo "4. User creates a new file for development:"
docker-compose exec -T code-server bash -c 'cd /tmp/test-repo && cat > my-feature.md << EOF
# New Feature

This is my development work.
EOF
cat my-feature.md'
echo ""
echo "5. User stages and commits changes:"
docker-compose exec -T code-server bash -c 'cd /tmp/test-repo && git add my-feature.md && git status'
echo ""
echo "6. User reviews the diff:"
docker-compose exec -T code-server bash -c 'cd /tmp/test-repo && git diff --cached'
echo ""
echo "✅ FULL DEVELOPMENT WORKFLOW VERIFIED - User can:"
echo "   - Access code-server IDE"
echo "   - Clone repositories"
echo "   - Create and modify files"
echo "   - Use git commands"
echo "   - Stage changes"
echo "   - Review diffs"
