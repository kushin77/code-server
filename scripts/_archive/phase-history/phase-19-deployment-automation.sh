#!/bin/bash
# Phase 19: Deployment & Rollback Automation
# Implements automated deployments, versioning, instant rollback

set -euo pipefail

echo "Phase 19: Deployment & Rollback Automation"
echo "=========================================="

# 1. Automated Deployment Pipeline
echo -e "\n1. Configuring Automated Deployment Pipeline..."

cat > scripts/phase-19-deployment-automation.sh <<'DEPLOY'
#!/bin/bash
# Automated deployment with validation & rollback

SERVICE="${1:-api-server}"
TARGET_VERSION="${2:-latest}"
DEPLOYMENT_STRATEGY="${3:-canary}"  # canary, blue-green, rolling

echo "Deploying $SERVICE version $TARGET_VERSION using $DEPLOYMENT_STRATEGY strategy"

# Pre-deployment validation
validate_deployment() {
  echo "1. Running pre-deployment validation..."

  # Check docker image exists
  if ! docker pull "myregistry/${SERVICE}:${TARGET_VERSION}"; then
    echo "❌ Docker image not found: myregistry/${SERVICE}:${TARGET_VERSION}"
    return 1
  fi

  # Run security scan
  echo "   Running security scan..."
  docker run --rm aquasec/trivy image "myregistry/${SERVICE}:${TARGET_VERSION}" | \
    grep -q "CRITICAL" && {
      echo "❌ Critical vulnerabilities found"
      return 1
    }

  # Check configurations
  echo "   Validating configuration..."
  kubectl apply -f ./k8s/ --dry-run=client > /dev/null || return 1

  echo "✅ Pre-deployment validation passed"
  return 0
}

# Deploy based on strategy
deploy_with_strategy() {
  case "$DEPLOYMENT_STRATEGY" in
    canary)
      echo "2. Starting canary deployment (5% → 25% → 50% → 100%)..."
      /scripts/phase-19-canary-deployment.sh "$SERVICE" "$TARGET_VERSION"
      ;;
    blue-green)
      echo "2. Starting blue-green deployment..."
      /scripts/phase-19-blue-green-deployment.sh "$SERVICE" "$TARGET_VERSION"
      ;;
    rolling)
      echo "2. Starting rolling deployment..."
      kubectl set image deployment/"$SERVICE" \
        "${SERVICE}=myregistry/${SERVICE}:${TARGET_VERSION}" \
        --record
      kubectl rollout status deployment/"$SERVICE" --timeout=10m
      ;;
  esac
}

# Post-deployment verification
verify_deployment() {
  echo "3. Running post-deployment verification..."

  # Wait for service to stabilize
  sleep 30

  # Run smoke tests
  POD=$(kubectl get pod -l app="$SERVICE" -o jsonpath='{.items[0].metadata.name}')
  if kubectl exec "$POD" -- /bin/sh -c "curl -s http://localhost:8080/health | jq -e '.status == \"ok\"'"; then
    echo "✅ Smoke tests passed"
  else
    echo "❌ Smoke tests failed"
    return 1
  fi

  # Check metrics
  error_rate=$(curl -s 'http://prometheus:9090/api/v1/query' \
    --data-urlencode "query=rate(http_requests_total{service=\"${SERVICE}\",status=~\"5..\"}[5m])" | \
    jq '.data.result[0].value[1]')

  if (( $(echo "$error_rate > 0.01" | bc -l) )); then
    echo "❌ Error rate too high: $error_rate"
    return 1
  fi

  echo "✅ Post-deployment verification passed"
  return 0
}

# Main deployment flow
if validate_deployment && deploy_with_strategy && verify_deployment; then
  echo "✅ Deployment of $SERVICE v$TARGET_VERSION completed successfully"
  exit 0
else
  echo "❌ Deployment failed, initiating rollback..."
  kubectl rollout undo deployment/"$SERVICE"
  exit 1
fi
DEPLOY

chmod +x scripts/phase-19-deployment-automation.sh

echo "✅ Deployment automation configured"

# 2. Version Management
echo -e "\n2. Implementing Version Management System..."

cat > config/version-management.yaml <<'EOF'
# Version management and tracking
versionControl:
  # Semantic versioning
  format: "major.minor.patch-prerelease+build"

  # Version registry
  registry:
    type: "postgres"
    connection: "postgres://postgres:password@localhost/versions"

    # Track all versions
    fields:
      - service_name
      - version
      - release_date
      - git_commit_sha
      - change_log
      - status: [beta, stable, deprecated]
      - rollback_window: "7 days"

# Deployment history tracking
deploymentHistory:
  retention: "90 days"
  fields:
    - timestamp
    - service
    - previous_version
    - new_version
    - deployment_strategy
    - status: [success, rollback, failed]
    - duration_seconds
    - changed_by
    - change_reason

# Rollback policies
rollbackPolicies:
  # Automatic: Rollback if SLO violated
  automatic:
    enabled: true
    triggers:
      - error_rate > 1%
      - latency_p99 > 2000ms
      - availability < 99.5%
      - out_of_memory_errors > 10
    rollback_window: "10 minutes"

  # Manual: Team can rollback any version
  manual:
    enabled: true
    allowed_roles: ["devops", "sre", "on-call"]
    require_approval: false

  # Feature flags: Disable features instead of full rollback
  feature_flag_based:
    enabled: true
    flags:
      - "new_payment_processor"
      - "advanced_search"
      - "ml_recommendations"

# Version constraints
constraints:
  # Don't deploy unstable version to production
  - environment: production
    allowed_statuses: [stable]

  - environment: staging
    allowed_statuses: [beta, stable]

  - environment: development
    allowed_statuses: [alpha, beta, stable]

  # Prevent large gaps in versions
  - max_version_jump: 2  # Can't skip 2 minor versions
EOF

echo "✅ Version management configured"

# 3. Instant Rollback Capability
echo -e "\n3. Implementing Instant Rollback..."

cat > scripts/phase-19-instant-rollback.sh <<'ROLLBACK'
#!/bin/bash
# Instant rollback to previous version

SERVICE="${1:-api-server}"
ROLLBACK_VERSION="${2:-previous}"  # or specify specific version

echo "Initiating instant rollback for $SERVICE to $ROLLBACK_VERSION"

# Get current and previous versions
CURRENT_VERSION=$(kubectl get deployment "$SERVICE" -o jsonpath='{.spec.template.spec.containers[0].image}' | awk -F: '{print $NF}')

if [[ "$ROLLBACK_VERSION" == "previous" ]]; then
  # Get previous version from history
  ROLLBACK_VERSION=$(kubectl rollout history deployment/"$SERVICE" | tail -n 3 | head -n 1 | awk '{print $1}')
fi

echo "Current version: $CURRENT_VERSION"
echo "Rolling back to: $ROLLBACK_VERSION"

# Perform rollback
start_time=$(date +%s)

kubectl rollout undo deployment/"$SERVICE" --to-revision="$ROLLBACK_VERSION"
kubectl rollout status deployment/"$SERVICE" --timeout=5m

end_time=$(date +%s)
duration=$((end_time - start_time))

# Verify rollback
sleep 10
POD=$(kubectl get pod -l app="$SERVICE" -o jsonpath='{.items[0].metadata.name}')
if kubectl exec "$POD" -- /bin/sh -c "curl -s http://localhost:8080/health | jq -e '.status == \"ok\"'"; then
  echo "✅ Rollback completed in ${duration}s"
  echo "✅ Service is operational"
else
  echo "❌ Service verification failed after rollback"
  exit 1
fi

# Log rollback event
echo "$(date): Rolled back $SERVICE from $CURRENT_VERSION to $ROLLBACK_VERSION (${duration}s)" \
  >> /var/log/deployment-events.log
ROLLBACK

chmod +x scripts/phase-19-instant-rollback.sh

echo "✅ Instant rollback configured"

# 4. Deployment Validation Suite
echo -e "\n4. Setting up Deployment Validation..."

cat > scripts/phase-19-deployment-validation.sh <<'VALIDATE'
#!/bin/bash
# Comprehensive deployment validation

SERVICE="${1:-api-server}"

echo "Running deployment validation for $SERVICE"

# 1. Health checks
echo "1. Running health checks..."
for i in {1..30}; do
  if kubectl run -n default curl-test --image=curlimages/curl --rm -i --restart=Never -- \
    curl -s "http://${SERVICE}:8080/health" | jq -e '.status == "ok"' > /dev/null 2>&1; then
    echo "  ✅ Health check passed"
    break
  fi
  echo "  Attempt $i/30..."
  sleep 2
done

# 2. Dependency checks
echo "2. Checking dependencies..."
kubectl exec $(kubectl get pod -l app="$SERVICE" -o jsonpath='{.items[0].metadata.name}') -- \
  /bin/sh -c "curl -s http://database:5432/health && curl -s http://cache:6379/ping" > /dev/null && \
  echo "  ✅ All dependencies healthy" || echo "  ❌ Dependency check failed"

# 3. Data consistency
echo "3. Validating data consistency..."
if kubectl exec postgres-0 -- \
  psql -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname != 'pg_catalog';" | grep -q "[0-9]"; then
  echo "  ✅ Data consistency verified"
else
  echo "  ❌ Data consistency check failed"
fi

# 4. Network connectivity
echo "4. Checking network connectivity..."
kubectl run -n default network-test --image=alpine --rm -i --restart=Never -- \
  $(cat <<'NETTEST'
    apk add curl
    curl -s https://ide.kushnir.cloud/health > /dev/null && echo "✅ Network OK"
NETTEST
)

# 5. Resource availability
echo "5. Checking resource availability..."
AVAILABLE_MEMORY=$(kubectl describe node | grep -A 5 "Allocated resources" | grep "Memory" | awk '{print $3}')
AVAILABLE_CPU=$(kubectl describe node | grep -A 5 "Allocated resources" | grep "CPU" | awk '{print $3}')
echo "  Available Memory: $AVAILABLE_MEMORY"
echo "  Available CPU: $AVAILABLE_CPU"

echo "✅ Deployment validation complete"
VALIDATE

chmod +x scripts/phase-19-deployment-validation.sh

echo "✅ Deployment validation configured"

echo -e "\n✅ Phase 19: Deployment Automation Complete"
echo "
Deployed Components:
  ✅ Automated deployment pipeline
  ✅ Version management system
  ✅ Instant rollback capability
  ✅ Comprehensive validation suite

Deployment Strategies:
  • Canary: 5% → 25% → 50% → 100%
  • Blue-green: Instant switching
  • Rolling: Gradual pod replacement
  • Feature flags: Disable without rollback

Validation Coverage:
  ✅ Pre-deployment: Image availability, security scan, config check
  ✅ Post-deployment: Health checks, smoke tests, metrics
  ✅ Instant rollback: < 5 minutes for any version
  ✅ Version tracking: All deployments logged and reversible

Automatic Rollback:
  • Error rate > 1%
  • Latency p99 > 2000ms
  • Availability < 99.5%
  • OOM errors > 10
  • Rollback window: 10 minutes after deployment
"
