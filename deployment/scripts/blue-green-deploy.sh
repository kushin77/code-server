#!/bin/bash
# Blue-Green Deployment - Zero-Downtime Deployments

set -e

BLUE_PORT=8080
GREEN_PORT=8081
LOAD_BALANCER_PORT=80
BLUE_NAME="code-server-blue"
GREEN_NAME="code-server-green"

echo "=== Blue-Green Deployment Script ==="

# Function to get current active environment
get_active() {
  curl -s http://localhost/health 2>/dev/null | grep -q "blue" && echo "blue" || echo "green"
}

# Function to deploy to inactive environment
deploy_to_inactive() {
  local target=$1
  local port=$2
  
  echo "Deploying to $target environment on port $port..."
  
  # Pull latest image
  docker pull code-server:prod
  
  # Stop old container
  docker stop code-server-$target 2>/dev/null || true
  
  # Start new container
  docker run -d --name code-server-$target \
    -p $port:8080 \
    -e CODE_SERVER_ENV=$target \
    code-server:prod
  
  echo "✓ Deployed to $target on port $port"
}

# Function to smoke test inactive environment
smoke_test() {
  local port=$1
  local retries=5
  
  echo "Running smoke tests on port $port..."
  
  for i in $(seq 1 $retries); do
    if curl -sf http://localhost:$port/health > /dev/null; then
      echo "✓ Smoke tests passed"
      return 0
    fi
    echo "Attempt $i/$retries: Waiting for service..."
    sleep 5
  done
  
  echo "✗ Smoke tests failed"
  return 1
}

# Function to switch traffic
switch_traffic() {
  local target=$1
  local port=$2
  
  echo "Switching traffic to $target environment..."
  
  # Update load balancer config
  cat > /etc/load-balancer/config.yml <<EOF
upstream backend {
  server localhost:$port;
}

server {
  listen 80;
  location / {
    proxy_pass http://backend;
  }
}
EOF
  
  # Reload load balancer
  systemctl reload nginx
  
  echo "✓ Traffic switched to $target (port $port)"
}

# Main deployment flow
main() {
  active=$(get_active)
  inactive=$([[ "$active" == "blue" ]] && echo "green" || echo "blue")
  inactive_port=$([[ "$inactive" == "green" ]] && echo $GREEN_PORT || echo $BLUE_PORT)
  
  echo "Current active: $active"
  echo "Deploying to: $inactive ($inactive_port)"
  
  # 1. Deploy to inactive environment
  deploy_to_inactive $inactive $inactive_port
  
  # 2. Run smoke tests
  if ! smoke_test $inactive_port; then
    echo "Deployment failed, rolling back..."
    docker stop code-server-$inactive || true
    exit 1
  fi
  
  # 3. Switch traffic
  switch_traffic $inactive $inactive_port
  
  # 4. Wait before stopping old environment
  echo "Waiting 5 minutes before stopping old environment..."
  sleep 300
  
  # 5. Stop old environment
  echo "Stopping $active environment..."
  docker stop code-server-$active || true
  
  echo ""
  echo "=== Deployment Complete ==="
  echo "New active: $inactive"
  echo "Rollback: docker stop code-server-$inactive && systemctl reload nginx"
}

main "$@"
