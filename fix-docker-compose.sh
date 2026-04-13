#!/bin/bash

FILE="/home/akushnir/code-server-phase13/docker-compose.yml"

# Create backup
cp "$FILE" "$FILE.backup"

# Simple fix: Just add redis-cache-data to the existing volumes section and remove the duplicate section
# Replace the volumes section to include redis-cache-data
sed -i '388 a\  redis-cache-data:\n    driver: local' "$FILE"

# Remove the duplicate/malformed volumes section (lines 412+)
sed -i '413,415d' "$FILE"

# Verify the new file is valid YAML
if docker-compose config > /dev/null 2>&1; then
    echo "✓ docker-compose.yml fixed successfully"
    echo "Testing docker-compose ps:"
    docker-compose ps
else
    echo "✗ File still has YAML errors, reverting..."
    mv "$FILE.backup" "$FILE"
    docker-compose config 2>&1
    exit 1
fi
