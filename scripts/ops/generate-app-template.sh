#!/bin/bash
# Generate application from template with user inputs
# Automates creation of new applications following platform standards

set -e
trap 'echo "❌ Generation failed"; exit 1' ERR

APP_NAME=$1
APP_LANGUAGE=${2:-"python"}
APP_PORT=${3:-8080}

if [[ -z "$APP_NAME" ]]; then
  echo "Usage: $0 <app-name> [language] [port]"
  echo "  language: python (default), node, go"
  echo "  port: 8080 (default)"
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Application Template Generator                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Create application directory
APP_DIR="/home/akushnir/code-server/applications/$APP_NAME"
mkdir -p "$APP_DIR"

echo "Creating $APP_LANGUAGE application: $APP_NAME"
echo "  Location: $APP_DIR"
echo "  Port: $APP_PORT"
echo ""

# Create common files
mkdir -p "$APP_DIR/src" "$APP_DIR/tests" "$APP_DIR/.github/workflows"

# Create README
cat > "$APP_DIR/README.md" << EOF
# $APP_NAME

Application deployed on ElevatedIQ platform.

## Quick Start

\`\`\`bash
docker-compose up
\`\`\`

Access at http://localhost:$APP_PORT

### Health Checks
- Liveness: http://localhost:$APP_PORT/health
- Readiness: http://localhost:$APP_PORT/ready
- Metrics: http://localhost:$APP_PORT/metrics

## Environment Variables

- SERVICE_NAME: $APP_NAME
- PORT: $APP_PORT
- DATABASE_URL: postgresql://...
- REDIS_URL: redis://...
EOF

# Create .env.example
cat > "$APP_DIR/.env.example" << EOF
SERVICE_NAME=$APP_NAME
PORT=$APP_PORT
LOG_LEVEL=INFO
DATABASE_URL=postgresql://user:pass@postgres:5432/code_server
REDIS_URL=redis://redis:6379/0
ENV=production
EOF

# Create .gitignore
cat > "$APP_DIR/.gitignore" << EOF
__pycache__/
*.pyc
.pytest_cache/
.coverage
htmlcov/
dist/
build/
*.egg-info/
node_modules/
.env
.vscode/
EOF

# Language-specific setup
if [[ "$APP_LANGUAGE" == "python" ]]; then
  echo "Setting up Python application..."
  
  # Create main.py
  cat > "$APP_DIR/src/main.py" << 'PYTHON_EOF'
from fastapi import FastAPI
import os
import logging

app = FastAPI(title=os.getenv("SERVICE_NAME", "MyApp"))
logger = logging.getLogger(__name__)

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.get("/ready")
async def ready():
    return {"ready": True}

@app.get("/metrics")
async def metrics():
    return {"uptime": 0}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", 8080)))
PYTHON_EOF

  # Create requirements.txt
  cat > "$APP_DIR/requirements.txt" << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.0
psycopg2-binary==2.9.9
redis==5.0.1
prometheus-client==0.18.0
python-multipart==0.0.6
pydantic==2.4.2
EOF

  # Create Dockerfile for Python
  cat > "$APP_DIR/Dockerfile" << 'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

RUN pip install --user --no-cache-dir -r requirements.txt

COPY . .

USER 1000

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8080/health')" || exit 1

EXPOSE 8080
CMD ["python", "src/main.py"]
DOCKERFILE_EOF

  echo "✓ Python application created"

elif [[ "$APP_LANGUAGE" == "node" ]]; then
  echo "Setting up Node.js application..."
  
  # Create package.json
  cat > "$APP_DIR/package.json" << EOF
{
  "name": "$APP_NAME",
  "version": "1.0.0",
  "description": "Application on ElevatedIQ platform",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "test": "jest",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.10.0",
    "redis": "^4.6.10",
    "prom-client": "^15.0.0"
  }
}
EOF

  # Create server.js
  cat > "$APP_DIR/src/server.js" << 'NODE_EOF'
const express = require('express');
const app = express();

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/ready', (req, res) => {
  res.json({ ready: true });
});

app.get('/metrics', (req, res) => {
  res.json({ uptime: process.uptime() });
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
NODE_EOF

  echo "✓ Node.js application created"
fi

# Create docker-compose.yml
cat > "$APP_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  $APP_NAME:
    build: .
    container_name: code-server-$APP_NAME
    environment:
      - SERVICE_NAME=$APP_NAME
      - PORT=$APP_PORT
      - DATABASE_URL=postgresql://user:pass@localhost/code_server
      - REDIS_URL=redis://localhost:6379/0
      - LOG_LEVEL=INFO
    ports:
      - "$APP_PORT:$APP_PORT"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$APP_PORT/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  default:
    name: platform_services
EOF

# Create GitHub Actions workflow
cat > "$APP_DIR/.github/workflows/deploy.yml" << EOF
name: Build and Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build image
        run: docker build -t $APP_NAME:\${{ github.sha }} .
EOF

# Create test file
cat > "$APP_DIR/tests/test_health.py" << 'TEST_EOF'
import pytest

def test_health():
    """Test health check endpoint"""
    # Add test implementation
    assert True

def test_ready():
    """Test readiness check endpoint"""
    # Add test implementation
    assert True
TEST_EOF

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ Application template generated                        ║"
echo "║                                                            ║"
echo "║  Next steps:                                              ║"
echo "║  1. cd $APP_DIR         ║"
echo "║  2. Implement business logic in src/                     ║"
echo "║  3. docker-compose up                                    ║"
echo "║  4. Verify http://localhost:$APP_PORT/health           ║"
echo "╚════════════════════════════════════════════════════════════╝"
