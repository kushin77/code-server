# Post-Deployment Verification Checklist

**Deployment Date:** April 30, 2026  
**Primary Server:** 192.168.168.31  
**Expected Duration:** 2-3 minutes from deployment start  

---

## Phase 1: Immediate Verification (Immediately After Deployment)

### Container Status Verification

- [ ] **All services running**
  ```bash
  docker-compose -f docker-compose.enterprise.yml ps
  ```
  Expected: All services show "Up (healthy)"
  
- [ ] **Appsmith container healthy**
  ```bash
  docker ps | grep appsmith
  ```
  Expected: Status shows "(healthy)"
  
- [ ] **API service container healthy**
  ```bash
  docker ps | grep hermes-integration
  ```
  Expected: Status shows "(healthy)"
  
- [ ] **Database container healthy**
  ```bash
  docker ps | grep postgres
  ```
  Expected: Status shows "(healthy)"
  
- [ ] **Redis container healthy**
  ```bash
  docker ps | grep redis
  ```
  Expected: Status shows "(healthy)"
  
- [ ] **IDE container healthy**
  ```bash
  docker ps | grep code-server-ide
  ```
  Expected: Status shows "(healthy)"

### Service Health Checks

- [ ] **API health endpoint responds**
  ```bash
  curl -k https://kushnir.cloud/api/hermes/health
  ```
  Expected: `{"status": "healthy", "service": "hermes-integration"}`
  
- [ ] **Platform metrics accessible**
  ```bash
  curl -k https://kushnir.cloud/api/hermes/metrics
  ```
  Expected: JSON response with platform_phases: 250, total_tests: 2542
  
- [ ] **Database connectivity verified**
  ```bash
  docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT 1;"
  ```
  Expected: "(1 row)"
  
- [ ] **Redis connectivity verified**
  ```bash
  docker exec code-server-redis redis-cli ping
  ```
  Expected: "PONG"

### Network Verification

- [ ] **DNS resolution working**
  ```bash
  nslookup kushnir.cloud
  ```
  Expected: Resolves to 192.168.168.31
  
- [ ] **HTTPS certificate valid**
  ```bash
  echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep "subject="
  ```
  Expected: Contains "CN=kushnir.cloud"
  
- [ ] **Port 80 redirects to 443**
  ```bash
  curl -i http://kushnir.cloud/ 2>&1 | head -5
  ```
  Expected: "301" or "302" redirect to HTTPS
  
- [ ] **HSTS header present**
  ```bash
  curl -i -k https://kushnir.cloud/ 2>&1 | grep "Strict-Transport-Security"
  ```
  Expected: "max-age=31536000"

### Log Verification

- [ ] **No error messages in startup logs**
  ```bash
  docker-compose -f docker-compose.enterprise.yml logs | grep -i "error\|failed\|critical"
  ```
  Expected: No critical errors
  
- [ ] **API logs show successful startup**
  ```bash
  docker logs hermes-integration | tail -10
  ```
  Expected: Shows listening on port 8000
  
- [ ] **Appsmith logs show successful startup**
  ```bash
  docker logs appsmith | tail -10
  ```
  Expected: Shows server running successfully

---

## Phase 2: User Access Verification (5 Minutes After Deployment)

### Dashboard Access

- [ ] **Dashboard URL accessible**
  ```bash
  curl -i -k https://kushnir.cloud/ 2>&1 | head -1
  ```
  Expected: "200 OK" or "401" (OAuth redirect)
  
- [ ] **Dashboard login page loads (browser)**
  - Open: https://kushnir.cloud
  - Expected: See Appsmith login page with "Sign in with Google"
  
- [ ] **OAuth button is clickable**
  - Look for "Sign in with Google" button
  - Expected: Button is visible and clickable

### IDE Access

- [ ] **IDE URL accessible**
  ```bash
  curl -i -k https://kushnir.cloud/ide 2>&1 | head -1
  ```
  Expected: "200 OK" or "302" (redirect to login)
  
- [ ] **IDE loads in browser**
  - Open: https://kushnir.cloud/ide
  - Expected: code-server interface loads
  
- [ ] **IDE terminal functional**
  - Click "Terminal" menu
  - Try typing command
  - Expected: Terminal accepts input

### API Endpoint Tests

- [ ] **Health endpoint responds**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/health | jq '.status'
  ```
  Expected: "healthy"
  
- [ ] **Get all phases**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/phases | jq '.phases | length'
  ```
  Expected: "250"
  
- [ ] **Get specific phase**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/phases/250 | jq '.phase'
  ```
  Expected: "250"
  
- [ ] **Get git log**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/git/log | jq '.commits | length'
  ```
  Expected: Number > 0
  
- [ ] **Metrics available**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/metrics | jq '.quality_percentage'
  ```
  Expected: "100" or similar

---

## Phase 3: OAuth Login Test (10 Minutes After Deployment)

### OAuth Setup Verification

- [ ] **OAuth client ID set in .env**
  ```bash
  cat .env | grep OAUTH_GOOGLE_CLIENT_ID
  ```
  Expected: Shows CLIENT_ID value (not empty)
  
- [ ] **OAuth client secret set in .env**
  ```bash
  cat .env | grep OAUTH_GOOGLE_CLIENT_SECRET
  ```
  Expected: Shows CLIENT_SECRET value (not empty)

### OAuth Flow Test

- [ ] **Navigate to dashboard**
  - Open: https://kushnir.cloud
  - Expected: See login/OAuth options
  
- [ ] **Click "Sign in with Google"**
  - Expected: Redirects to Google login page
  
- [ ] **Complete Google authentication**
  - Sign in with test Google account
  - Expected: Redirects back to dashboard
  
- [ ] **Dashboard accessible after OAuth**
  - Expected: See dashboard metrics and pages
  
- [ ] **Session persists**
  - Refresh page (F5)
  - Expected: Still logged in, dashboard visible

---

## Phase 4: Dashboard Feature Test (15 Minutes After Deployment)

### Dashboard Page

- [ ] **Dashboard page loads**
  - Click "Dashboard" in sidebar
  - Expected: Page loads with no errors
  
- [ ] **Metrics display correctly**
  - Expected to see:
    - Total Phases: 250
    - Total Tests: 2,542
    - Quality Score: 100%
  
- [ ] **Charts render**
  - Expected: Visual charts display data
  
- [ ] **Status is green**
  - Expected: Platform status shows "Healthy"

### Phase Management Page

- [ ] **Phase Management page loads**
  - Click "Phase Management"
  - Expected: Page displays phase selector
  
- [ ] **Phase dropdown works**
  - Click dropdown, select Phase 250
  - Expected: Phase 250 is selected
  
- [ ] **Get Phase Info works**
  - Click "Get Phase Info" button
  - Expected: Phase information displays
  
- [ ] **Run Tests works**
  - Click "Run Tests" button
  - Expected: Test execution starts and completes
  
- [ ] **Run Quality Check works**
  - Click "Run Quality Check"
  - Expected: Quality check executes and results display

### Batch Operations Page

- [ ] **Batch Operations page loads**
  - Click "Batch Operations"
  - Expected: Page loads with batch options
  
- [ ] **Phase range selector works**
  - Set range: 231-250
  - Expected: Range is valid and selectable
  
- [ ] **Run Batch Tests works**
  - Click "Run Batch Tests"
  - Expected: Batch execution starts and progress updates

---

## Phase 5: API Integration Test (20 Minutes After Deployment)

### Phase Operations

- [ ] **Run Phase Test via API**
  ```bash
  curl -s -k -X POST https://kushnir.cloud/api/hermes/phases/250/test | jq '.status'
  ```
  Expected: "success" or "passed"
  
- [ ] **Run Quality Check via API**
  ```bash
  curl -s -k -X POST https://kushnir.cloud/api/hermes/phases/250/quality | jq '.status'
  ```
  Expected: "success"
  
- [ ] **Commit Phase via API**
  ```bash
  curl -s -k -X POST https://kushnir.cloud/api/hermes/phases/250/commit | jq '.status'
  ```
  Expected: "success"

### Batch Operations

- [ ] **Run Batch Test via API**
  ```bash
  curl -s -k -X POST https://kushnir.cloud/api/hermes/batch/test \
    -H "Content-Type: application/json" \
    -d '{"phase_start": 240, "phase_end": 250}' | jq '.status'
  ```
  Expected: "success" or "in-progress"

### Git Integration

- [ ] **Get commit history**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/git/log | jq '.commits[0]'
  ```
  Expected: Shows recent commits
  
- [ ] **Commits are recent**
  - Expected: Latest commits show today's date

---

## Phase 6: Performance & Load Test (30 Minutes After Deployment)

### Response Time

- [ ] **Dashboard loads quickly**
  - Open https://kushnir.cloud
  - Expected: < 2 seconds load time
  
- [ ] **API responds quickly**
  ```bash
  time curl -s -k https://kushnir.cloud/api/hermes/health > /dev/null
  ```
  Expected: < 200ms response time
  
- [ ] **IDE loads quickly**
  - Open https://kushnir.cloud/ide
  - Expected: < 3 seconds

### Resource Usage

- [ ] **CPU usage acceptable**
  ```bash
  docker stats --no-stream | grep -E "CPU|appsmith|hermes"
  ```
  Expected: Each service < 50% CPU
  
- [ ] **Memory usage acceptable**
  ```bash
  docker stats --no-stream | grep -E "MEM|appsmith|hermes"
  ```
  Expected: Each service < 500MB
  
- [ ] **Disk usage acceptable**
  ```bash
  df -h /home
  ```
  Expected: Used < 80%, Free > 20%

### Stability

- [ ] **Services stay healthy**
  - Wait 5 minutes
  - Run: `docker-compose -f docker-compose.enterprise.yml ps`
  - Expected: All still "Up (healthy)"
  
- [ ] **No restart loops**
  ```bash
  docker-compose -f docker-compose.enterprise.yml logs | grep -i "restart"
  ```
  Expected: No restart messages
  
- [ ] **Memory not leaking**
  - Monitor for 5 minutes: `watch -n 2 'docker stats --no-stream'`
  - Expected: Memory usage stable, not increasing

---

## Phase 7: Security Verification (45 Minutes After Deployment)

### TLS/SSL

- [ ] **Certificate is valid**
  ```bash
  echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep "verify OK"
  ```
  Expected: "verify OK"
  
- [ ] **TLS 1.2+ enforced**
  ```bash
  echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep "Protocol"
  ```
  Expected: Shows TLSv1.2 or higher
  
- [ ] **HTTP redirects to HTTPS**
  ```bash
  curl -I http://kushnir.cloud 2>/dev/null | grep Location
  ```
  Expected: Redirects to https://

### Security Headers

- [ ] **HSTS header present**
  ```bash
  curl -I -k https://kushnir.cloud 2>/dev/null | grep "Strict-Transport"
  ```
  Expected: Shows HSTS header
  
- [ ] **CSP header present**
  ```bash
  curl -I -k https://kushnir.cloud 2>/dev/null | grep "Content-Security"
  ```
  Expected: Shows CSP header
  
- [ ] **X-Frame-Options set**
  ```bash
  curl -I -k https://kushnir.cloud 2>/dev/null | grep "X-Frame-Options"
  ```
  Expected: "SAMEORIGIN"

### Authentication

- [ ] **Unauthorized access blocked**
  ```bash
  curl -k https://kushnir.cloud/api/hermes/admin 2>/dev/null | jq '.error' 2>/dev/null || echo "Access denied (expected)"
  ```
  Expected: Access denied or error
  
- [ ] **OAuth session required**
  - Open incognito/private browser window
  - Navigate to https://kushnir.cloud
  - Expected: OAuth login required, cannot access dashboard

---

## Phase 8: Error Handling Test (60 Minutes After Deployment)

### Graceful Error Handling

- [ ] **Invalid phase number returns error**
  ```bash
  curl -s -k https://kushnir.cloud/api/hermes/phases/999 | jq '.error'
  ```
  Expected: Error message, not 500
  
- [ ] **Invalid request format returns error**
  ```bash
  curl -s -k -X POST https://kushnir.cloud/api/hermes/batch/test -d "invalid"
  ```
  Expected: 400 Bad Request, not 500
  
- [ ] **Database connection lost - recovery**
  - Optional: Test by stopping database and verifying behavior
  - Expected: Graceful error, not crash
  
- [ ] **Service restart handles gracefully**
  - Optional: Restart one service and verify others continue
  - Expected: Only restarted service affected

---

## Phase 9: Log Review (At End of First Hour)

### Error Log Review

- [ ] **No critical errors logged**
  ```bash
  docker-compose -f docker-compose.enterprise.yml logs | grep -i "critical\|fatal"
  ```
  Expected: No critical/fatal errors
  
- [ ] **No permission denied errors**
  ```bash
  docker-compose -f docker-compose.enterprise.yml logs | grep -i "permission denied"
  ```
  Expected: No permission errors
  
- [ ] **No out of memory errors**
  ```bash
  docker-compose -f docker-compose.enterprise.yml logs | grep -i "out of memory"
  ```
  Expected: No OOM errors
  
- [ ] **OAuth errors resolved**
  ```bash
  docker logs appsmith | grep -i "oauth.*error" | head -5
  ```
  Expected: No ongoing OAuth errors

### Performance Log Review

- [ ] **No slow query warnings**
  ```bash
  docker logs code-server-postgres | grep "slow query"
  ```
  Expected: No slow queries
  
- [ ] **No connection pool exhausted**
  ```bash
  docker logs hermes-integration | grep "connection pool"
  ```
  Expected: No pool exhaustion messages

---

## Final Checklist Summary

**Critical Items (Must All Pass):**
- [ ] All containers "Up (healthy)"
- [ ] API health endpoint responds
- [ ] Dashboard accessible via HTTPS
- [ ] OAuth login works
- [ ] Dashboard displays metrics
- [ ] No critical errors in logs
- [ ] TLS certificate valid

**Important Items (Should All Pass):**
- [ ] IDE accessible
- [ ] API endpoints functional
- [ ] Performance acceptable
- [ ] No restart loops
- [ ] Security headers present

**Optional Items (Nice to Have):**
- [ ] Performance under 2 seconds
- [ ] Resources under 50% CPU
- [ ] Full feature tests pass

---

## Sign-Off

**Deployment Status:** ✅ VERIFIED IF ALL CRITICAL ITEMS CHECKED

**Date Verified:** ________________  
**Verified By:** ________________  
**Duration:** ________________ minutes  

**Notes:**
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

---

## Next Actions After Verification

If all critical items pass:
1. ✅ Notify stakeholders of successful deployment
2. ✅ Schedule 24-hour monitoring
3. ✅ Document any issues found
4. ✅ Begin weekly maintenance schedule

If any critical items fail:
1. ❌ Review DEPLOYMENT_EXECUTION_GUIDE.md troubleshooting section
2. ❌ Check logs for specific error messages
3. ❌ Attempt recovery procedure
4. ❌ If unable to recover, execute rollback

---

**Prepared:** April 30, 2026  
**Status:** Ready for Post-Deployment Verification  
