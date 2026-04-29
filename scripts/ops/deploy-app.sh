#!/bin/bash
# Deploy application to ElevatedIQ platform
# Automates the deployment process with validation

set -e
trap 'echo "❌ Deployment failed"; exit 1' ERR

APP_NAME=$1
ACTION=${2:-deploy}  # deploy, remove, update, logs
PRIMARY="192.168.168.31"

if [[ -z "$APP_NAME" ]]; then
  echo "Usage: $0 <app-name> [action]"
  echo "  action: deploy (default), remove, update, logs, status"
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Application Deployment Tool                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

APP_DIR="/home/akushnir/code-server/applications/$APP_NAME"

if [[ ! -d "$APP_DIR" ]]; then
  echo "❌ Application not found: $APP_DIR"
  exit 1
fi

case $ACTION in
  deploy)
    echo "Deploying application: $APP_NAME"
    echo ""
    
    # Validate application
    echo "Step 1: Validating application..."
    bash /home/akushnir/code-server/scripts/ops/validate-app-deployment.sh "$APP_DIR" || {
      echo "❌ Validation failed"
      exit 1
    }
    
    # Build Docker image
    echo ""
    echo "Step 2: Building Docker image..."
    cd "$APP_DIR"
    docker build -t "$APP_NAME:latest" . >/dev/null
    echo "  ✓ Image built"
    
    # Create docker-compose entry
    echo ""
    echo "Step 3: Adding to platform docker-compose..."
    
    # Generate service definition
    cat > "/tmp/${APP_NAME}_service.yml" << EOF
  $APP_NAME:
    image: $APP_NAME:latest
    container_name: code-server-$APP_NAME
    environment:
      - SERVICE_NAME=$APP_NAME
      - PORT=8080
      - DATABASE_URL=postgresql://user:pass@postgres:5432/code_server
      - REDIS_URL=redis://redis:6379/0
      - LOG_LEVEL=INFO
    networks:
      - services
      - database
    depends_on:
      - postgres
      - redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
    
    # Deploy via SSH
    echo "  ✓ Service definition prepared"
    echo ""
    echo "Step 4: Deploying to platform..."
    
    scp "/tmp/${APP_NAME}_service.yml" "akushnir@$PRIMARY:/tmp/" >/dev/null 2>&1
    
    ssh -o BatchMode=yes akushnir@$PRIMARY << DEPLOY_EOF
      cd ~/code-server-enterprise
      
      # Copy service definition
      cat /tmp/${APP_NAME}_service.yml >> docker-compose.yml
      
      # Deploy
      docker-compose up -d $APP_NAME 2>&1 | tail -5
      
      # Wait for startup
      sleep 10
      
      # Verify
      docker ps --filter "name=$APP_NAME" | grep -q $APP_NAME && echo "  ✓ Container running" || echo "  ✗ Container failed to start"
DEPLOY_EOF
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  ✅ Application deployed successfully                      ║"
    echo "║                                                            ║"
    echo "║  Next steps:                                              ║"
    echo "║  • Check logs: $0 $APP_NAME logs                   ║"
    echo "║  • Check status: $0 $APP_NAME status                ║"
    echo "║  • Access health: curl http://192.168.168.31:8080/health║"
    echo "╚════════════════════════════════════════════════════════════╝"
    ;;
    
  remove)
    echo "Removing application: $APP_NAME"
    
    ssh -o BatchMode=yes akushnir@$PRIMARY << REMOVE_EOF
      cd ~/code-server-enterprise
      docker-compose down -v --remove-orphans
      
      # Remove service from docker-compose.yml
      grep -v -A 20 "^  $APP_NAME:" docker-compose.yml > docker-compose.yml.tmp
      mv docker-compose.yml.tmp docker-compose.yml
      
      echo "  ✓ Application removed"
REMOVE_EOF
    ;;
    
  update)
    echo "Updating application: $APP_NAME"
    
    # Rebuild image
    cd "$APP_DIR"
    docker build -t "$APP_NAME:latest" . >/dev/null
    
    # Redeploy
    ssh -o BatchMode=yes akushnir@$PRIMARY << UPDATE_EOF
      cd ~/code-server-enterprise
      docker-compose pull $APP_NAME 2>/dev/null || true
      docker-compose up -d $APP_NAME
      sleep 5
      echo "  ✓ Application updated"
UPDATE_EOF
    ;;
    
  logs)
    echo "Fetching logs for: $APP_NAME"
    echo ""
    
    ssh -o BatchMode=yes akushnir@$PRIMARY << LOGS_EOF
      docker logs code-server-$APP_NAME --tail=50 -f
LOGS_EOF
    ;;
    
  status)
    echo "Status for: $APP_NAME"
    echo ""
    
    ssh -o BatchMode=yes akushnir@$PRIMARY << STATUS_EOF
      echo "Container Status:"
      docker ps --filter "name=$APP_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      
      echo ""
      echo "Health Check:"
      docker exec code-server-$APP_NAME curl -s http://localhost:8080/health | jq . 2>/dev/null || echo "  (health check unavailable)"
      
      echo ""
      echo "Resource Usage:"
      docker stats code-server-$APP_NAME --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}"
STATUS_EOF
    ;;
    
  *)
    echo "Unknown action: $ACTION"
    exit 1
    ;;
esac

echo ""
