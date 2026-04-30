# Development Team Guide - Hermes Agent Portal IDE Integration

**Date:** April 30, 2026 | **Audience:** Development Team | **Status:** READY

---

## What You Have

A fully integrated IDE extension that connects you directly to all 250 Hermes phases through keyboard shortcuts and a control panel.

**Keyboard Shortcuts:**
- `Ctrl+Shift+H` - Open Hermes Portal Control Panel
- `Ctrl+Shift+T` - Run test on current phase
- `Ctrl+Shift+Q` - Check quality metrics
- `Ctrl+Shift+C` - Execute phase (commit)

---

## Getting Started (5 minutes)

### 1. Install Extension
```bash
# Extension is already installed in your VS Code
# Verify: Look for "Hermes Agent" in Extensions panel
# Should show: "Hermes Agent Portal Integration"
```

### 2. Open Control Panel
Press `Ctrl+Shift+H` in VS Code
- Should see: Real-time metrics
- Should see: Phase tree on left
- Should see: Action buttons below

### 3. Test It Works
```bash
# In control panel:
1. Click on any phase in tree (left panel)
2. Metrics appear on right (CPU, Memory, Response time)
3. Action buttons light up (Test, Quality, Commit)
4. Click "Test" - should see test results
```

### 4. First Command
```bash
# Try: Ctrl+Shift+H
# Then: Select Phase 1 from tree
# Then: Click "Test"
# Result: Test results shown in real-time
```

---

## Using the Extension

### Phase Tree Navigation
- **Left Panel:** Shows all 250 Hermes phases
- **Click on Phase:** Selects it and shows metrics
- **Color coding:**
  - 🟢 Green: Phase healthy and passing
  - 🟡 Yellow: Phase has warnings
  - 🔴 Red: Phase has failures

### Metrics Display (Right Panel)
- **Uptime:** Platform uptime percentage
- **Response Time:** API average response time
- **Error Rate:** Percentage of failed requests
- **Container Health:** Number of healthy containers
- **Last Test:** When phase was last tested
- **Status:** Current phase status

### Action Buttons

**Test Phase** (`Ctrl+Shift+T`)
- Runs all tests for selected phase
- Shows results in panel
- Indicates pass/fail/warning status

**Quality Check** (`Ctrl+Shift+Q`)
- Runs quality metrics for phase
- Shows code coverage
- Shows performance metrics
- Indicates optimization opportunities

**Execute Phase** (`Ctrl+Shift+C`)
- Commits phase changes
- Updates production
- Starts automated deployment
- Shows confirmation

---

## Common Tasks

### Check Phase Status
1. Open Control Panel: `Ctrl+Shift+H`
2. Click phase in tree
3. View metrics and status
4. Status badge shows: ✅ Healthy, ⚠️ Warning, ❌ Failed

### Run Tests
1. Select phase from tree
2. Press `Ctrl+Shift+T` (or click Test button)
3. Watch test progress in real-time
4. See results: Pass/Fail with error details

### Deploy Phase
1. Select phase from tree
2. Press `Ctrl+Shift+C` (or click Commit button)
3. Review changes dialog
4. Confirm deployment
5. Watch deployment progress

### Check Performance
1. Select phase from tree
2. Press `Ctrl+Shift+Q` (or click Quality button)
3. View performance metrics:
   - Response time
   - CPU usage
   - Memory usage
   - Error rate

### View Platform Health
1. Open Control Panel: `Ctrl+Shift+H`
2. Check top metrics:
   - Platform Uptime
   - Average Response Time
   - Error Rate
   - Container Health

---

## Integration with API

### Available Endpoints
The extension connects to these endpoints:

**Health Check**
```
GET /api/hermes/health
Response: { "status": "healthy", "service": "hermes-integration" }
```

**Platform Status**
```
GET /api/hermes/status
Response: { "total_phases": 250, "passing": 248, ... }
```

**Metrics**
```
GET /api/hermes/metrics
Response: { "uptime": "99.9%", "response_time": "245ms", ... }
```

**Run Tests**
```
POST /api/hermes/phases/{n}/test
Response: { "phase": 1, "tests": 50, "passed": 50, "failed": 0 }
```

**Quality Check**
```
GET /api/hermes/phases/{n}/quality
Response: { "coverage": "98%", "performance": "excellent", ... }
```

---

## Dashboard Access

### Appsmith Dashboard
Access: https://kushnir.cloud

**Features:**
1. **Dashboard Page**
   - Live metrics (uptime, response time, errors)
   - Container health status
   - Recent activity feed

2. **Phase Management Page**
   - Browse all 250 phases
   - Run tests directly
   - View phase details
   - Execute deployments

3. **Batch Operations Page**
   - Run tests on multiple phases
   - Deploy multiple phases at once
   - Monitor batch progress

### Dashboard Login
1. Go to: https://kushnir.cloud
2. Click "Sign in with Google"
3. Use your company Google account
4. Access granted automatically

---

## Troubleshooting

### Extension Not Appearing
1. Reload VS Code: `Ctrl+Shift+P` → "Reload Window"
2. Check: Extensions panel shows "Hermes Agent"
3. If still missing: Contact DevOps

### Keyboard Shortcut Not Working
1. Make sure you're in a Python file (`.py`)
2. Try: `Ctrl+Shift+P` → Search "Hermes"
3. Should show commands: "Hermes: Open Panel", etc.
4. Click to execute

### Can't Connect to API
1. Check: Are you connected to VPN?
2. Check: Is https://kushnir.cloud accessible?
3. Try: `curl -k https://kushnir.cloud/api/hermes/health`
4. If fails: Contact DevOps

### Dashboard Not Loading
1. Check: VPN connected?
2. Try: Different browser or incognito mode
3. Try: Clear browser cache
4. Check: https (not http)

### Tests Not Running
1. Check: API health: `Ctrl+Shift+H` → Top metrics
2. Check: Container health (should be 100%)
3. Try: Run validation: `./validate-deployment.sh`
4. Contact: DevOps if persists

---

## Best Practices

1. **Always Test Before Deploy**
   - Run tests: `Ctrl+Shift+T`
   - Check quality: `Ctrl+Shift+Q`
   - Review metrics before commit

2. **Monitor Platform Health**
   - Check control panel daily
   - Review metrics trends
   - Alert DevOps if degradation

3. **Use Dashboard for Complex Tasks**
   - Batch operations: Use Appsmith
   - Performance analysis: Use metrics
   - Detailed status: Use Dashboard

4. **Keep Production Stable**
   - Test locally first
   - Deploy during business hours
   - Monitor after each deployment
   - Rollback if issues appear

5. **Communicate**
   - Alert team of deployments
   - Report issues immediately
   - Document changes
   - Update runbooks as needed

---

## Commands Reference

| Shortcut | Action | Use When |
|----------|--------|----------|
| `Ctrl+Shift+H` | Open Control Panel | Check phase status |
| `Ctrl+Shift+T` | Run Tests | Before deployment |
| `Ctrl+Shift+Q` | Quality Check | Validate code quality |
| `Ctrl+Shift+C` | Deploy Phase | Ready to deploy |

---

## Quick Reference

```bash
# Check if extension works
Ctrl+Shift+H  # Should open panel with metrics

# Test a phase
1. Ctrl+Shift+H (open panel)
2. Click phase in tree
3. Ctrl+Shift+T (run tests)
4. Review results

# Deploy a phase
1. Ensure all tests pass
2. Ctrl+Shift+C (execute)
3. Confirm in dialog
4. Monitor progress

# Access dashboard
1. Open browser
2. Go to: https://kushnir.cloud
3. Click: "Sign in with Google"
4. Explore dashboard pages
```

---

## Support

**Questions:**
- Check: This guide first
- Ask: Your team lead
- Email: dev-team@company.com

**Issues:**
- Report to: DevOps team
- Include: What you did, what happened, logs if available
- Priority: Based on impact

---

**The IDE extension is your direct connection to Hermes. Learn these shortcuts and master your workflow.**
