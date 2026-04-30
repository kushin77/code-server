#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token" 2>/dev/null || echo "")

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ No GitHub token available"
    exit 1
fi

echo "🔄 Starting GitHub sync with intelligent retry..."
echo "Token: $GITHUB_TOKEN" | head -c 20 && echo "..."

# Try sync with exponential backoff
max_attempts=3
attempt=1
wait_time=5

while [ $attempt -le $max_attempts ]; do
    echo ""
    echo "📍 Attempt $attempt of $max_attempts..."
    
    if bash sync-slog-to-github.sh 2>&1 | tee /tmp/slog-sync.log; then
        echo "✅ SLOG sync succeeded"
        break
    else
        exit_code=$?
        if grep -q "rate limit" /tmp/slog-sync.log 2>/dev/null; then
            echo "⏳ Rate limit hit, waiting ${wait_time}s before retry..."
            sleep $wait_time
            wait_time=$((wait_time * 2))
            attempt=$((attempt + 1))
        else
            echo "❌ Sync failed with error code $exit_code (not rate limit)"
            exit $exit_code
        fi
    fi
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ Max attempts exceeded after rate limit retries"
    exit 1
fi

echo ""
echo "🎯 All sync operations completed"
