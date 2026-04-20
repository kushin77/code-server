# COMPREHENSIVE E2E TESTING PLAN — April 19, 2026
## Production Readiness: Full Coverage Testing Strategy

**Objective:** Validate all critical paths before production deployment  
**Coverage:** 95%+ of user journeys  
**Testing Scope:** Web UI, APIs, Infrastructure, Security  
**Timeline:** 3-4 days  
**Tools:** Playwright, Puppeteer, VPN, QA Account

---

## TEST ARCHITECTURE

### Test Environment Setup

```
┌─────────────────────────────────────────────────┐
│           VPN (Simulates On-Prem)               │
│  ┌────────────────────────────────────────────┐ │
│  │  Test Runner (Playwright/Puppeteer)        │ │
│  │  ┌──────────────────────────────────────┐  │ │
│  │  │  Headless Browser (Chrome/Firefox)   │  │ │
│  │  │  QA Account Credentials               │  │ │
│  │  └──────────────────────────────────────┘  │ │
│  │              ↓ HTTP/HTTPS ↓                 │ │
│  │  ┌──────────────────────────────────────┐  │ │
│  │  │  oauth2-proxy (Port 4180)            │  │ │
│  │  │  Code-server (Port 8080)             │  │ │
│  │  │  Grafana (Port 3000)                 │  │ │
│  │  │  Prometheus (Port 9090)              │  │ │
│  │  │  Jaeger (Port 16686)                 │  │ │
│  │  └──────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────┘ │
│              192.168.168.31                     │
└─────────────────────────────────────────────────┘
```

### QA Account Requirements

**Email:** qa-test@kushnir.cloud (or test domain)  
**Password:** Securely stored in Vault/GitHub Secrets  
**Permissions:** Full access (admin for testing)  
**MFA:** Disabled for automated testing  
**Scope:** Test all features without production data impact

---

## TEST SUITES

### Suite 1: Authentication Flow (Critical Path)

**File:** `tests/e2e/auth.spec.ts`

```typescript
describe('Authentication Flow', () => {
  let page;

  beforeAll(async () => {
    // Connect to VPN (skip if already connected)
    // Launch browser via Puppeteer
    browser = await puppeteer.launch();
    page = await browser.newPage();
    
    // Set QA credentials from Vault
    const qaEmail = process.env.QA_EMAIL;
    const qaPassword = process.env.QA_PASSWORD;
  });

  test('Google OAuth2 login redirect', async () => {
    // Navigate to code-server
    await page.goto('http://code-server.192.168.168.31.nip.io:8080');
    
    // Should redirect to oauth2-proxy
    const currentUrl = page.url();
    expect(currentUrl).toContain('oauth2-proxy');
    
    // Should show Google sign-in option
    const googleBtn = await page.$('[data-testid="google-signin"]');
    expect(googleBtn).not.toBeNull();
  });

  test('QA account login and session', async () => {
    // Initiate login
    await page.click('[data-testid="google-signin"]');
    
    // Google OAuth page loads
    await page.waitForNavigation();
    expect(page.url()).toContain('accounts.google.com');
    
    // Enter QA credentials
    await page.type('input[name="email"]', qaEmail);
    await page.click('#identifierNext');
    
    await page.waitForTimeout(1000);
    await page.type('input[name="password"]', qaPassword);
    await page.click('#passwordNext');
    
    // Approve permissions (if needed)
    try {
      await page.waitForSelector('button[aria-label="Allow"]', { timeout: 5000 });
      await page.click('button[aria-label="Allow"]');
    } catch {
      // Permission already approved
    }
    
    // Should redirect back to code-server
    await page.waitForNavigation({ waitUntil: 'networkidle2' });
    expect(page.url()).toContain('code-server');
    expect(page.url()).not.toContain('oauth2-proxy');
  });

  test('Session persistence and cookie handling', async () => {
    // Get session cookies
    const cookies = await page.cookies();
    const sessionCookie = cookies.find(c => c.name.includes('oauth2proxy'));
    
    expect(sessionCookie).not.toBeUndefined();
    expect(sessionCookie.secure).toBe(true); // HTTPS only
    expect(sessionCookie.httpOnly).toBe(true); // Not accessible via JS
    
    // Close and reopen browser
    await browser.close();
    browser = await puppeteer.launch();
    page = await browser.newPage();
    
    // Set cookies
    for (const cookie of cookies) {
      await page.setCookie(cookie);
    }
    
    // Navigate and should still be logged in
    await page.goto('http://code-server.192.168.168.31.nip.io:8080');
    await page.waitForNavigation({ waitUntil: 'networkidle2' });
    
    // Should NOT redirect to oauth2-proxy
    expect(page.url()).toContain('code-server');
    expect(page.url()).not.toContain('oauth2-proxy');
  });

  test('Logout functionality', async () => {
    // Click logout button
    const logoutBtn = await page.$('[data-testid="logout"]');
    expect(logoutBtn).not.toBeNull();
    
    await page.click('[data-testid="logout"]');
    await page.waitForNavigation();
    
    // Should redirect to oauth2-proxy logout
    expect(page.url()).toContain('oauth2-proxy');
    expect(page.url()).toContain('logout');
  });

  afterAll(async () => {
    await browser.close();
  });
});
```

**Expected Results:**
- ✅ Login redirects to Google OAuth2
- ✅ QA account can authenticate
- ✅ Session cookies set securely
- ✅ Session persists across browser close/reopen
- ✅ Logout clears session

---

### Suite 2: Code-Server Core Functionality

**File:** `tests/e2e/code-server.spec.ts`

```typescript
describe('Code-Server Functionality', () => {
  // ... beforeAll setup ...

  test('Web IDE loads and responsive', async () => {
    await page.goto('http://code-server.192.168.168.31.nip.io:8080');
    
    // Wait for VS Code to load
    await page.waitForSelector('[class*="monaco"]', { timeout: 10000 });
    
    // Check responsive design
    const viewport = page.viewport();
    expect(viewport.width).toBeGreaterThan(800);
    
    // All main panels should be visible
    const explorer = await page.$('[aria-label="Explorer"]');
    const editor = await page.$('[class*="editor-container"]');
    const terminal = await page.$('[class*="terminal"]');
    
    expect(explorer).not.toBeNull();
    expect(editor).not.toBeNull();
  });

  test('File creation and editing', async () => {
    // Right-click in Explorer to create file
    const explorer = await page.$('[aria-label="Explorer"]');
    await explorer.click({ button: 'right' });
    
    // Select "New File"
    const newFileOption = await page.$('text=New File');
    await newFileOption.click();
    
    // Type filename
    const input = await page.waitForSelector('input[type="text"]');
    await input.type('test-file.txt');
    await input.press('Enter');
    
    // File should appear in explorer
    const fileInExplorer = await page.$('text=test-file.txt');
    expect(fileInExplorer).not.toBeNull();
    
    // Edit the file
    await page.type('[class*="editor-container"] textarea', 'Hello from QA test');
    
    // Save file
    await page.keyboard.press('Control+S');
    
    // Verify saved (no unsaved indicator)
    const unsavedIndicator = await page.$('[class*="unsaved"]');
    expect(unsavedIndicator).toBeNull();
  });

  test('Terminal execution', async () => {
    // Open terminal
    await page.keyboard.press('Control+grave'); // backtick
    
    // Wait for terminal to appear
    const terminal = await page.waitForSelector('[class*="terminal"]');
    expect(terminal).not.toBeNull();
    
    // Run command
    await page.type('[class*="terminal"] textarea', 'echo "test"');
    await page.keyboard.press('Enter');
    
    // Wait for output
    await page.waitForTimeout(1000);
    
    // Check output contains "test"
    const output = await page.$eval('[class*="terminal"]', 
      el => el.textContent
    );
    expect(output).toContain('test');
  });

  test('Extension loading', async () => {
    // Open Extensions panel
    await page.click('[aria-label="Extensions"]');
    
    // Should show installed extensions
    const extensionsList = await page.waitForSelector('[class*="extensions-list"]');
    expect(extensionsList).not.toBeNull();
    
    // Should have some extensions installed
    const extensions = await page.$$('[class*="extension-item"]');
    expect(extensions.length).toBeGreaterThan(0);
  });

  test('Settings persistence', async () => {
    // Open settings
    await page.keyboard.press('Control+,');
    
    // Wait for settings panel
    const settingsPanel = await page.waitForSelector('[class*="settings"]');
    expect(settingsPanel).not.toBeNull();
    
    // Change a setting (e.g., font size)
    const fontSizeInput = await page.$('input[aria-label*="Font Size"]');
    if (fontSizeInput) {
      await fontSizeInput.type('16');
      await fontSizeInput.press('Enter');
      
      // Verify setting persisted on reload
      await page.reload();
      await page.waitForSelector('[class*="monaco"]');
      
      const savedValue = await page.$eval(
        'input[aria-label*="Font Size"]',
        el => el.value
      );
      expect(savedValue).toBe('16');
    }
  });

  afterAll(async () => {
    await browser.close();
  });
});
```

**Expected Results:**
- ✅ Web IDE loads correctly
- ✅ Files can be created and edited
- ✅ Terminal works and executes commands
- ✅ Extensions load properly
- ✅ Settings persist across sessions

---

### Suite 3: Infrastructure & Monitoring

**File:** `tests/e2e/infrastructure.spec.ts`

```typescript
describe('Infrastructure Health', () => {
  
  test('Prometheus metrics collection', async () => {
    const response = await fetch('http://192.168.168.31:9090/api/v1/targets');
    const data = await response.json();
    
    expect(data.status).toBe('success');
    expect(data.data.activeTargets.length).toBeGreaterThan(0);
    
    // Check critical targets are scraping
    const targets = data.data.activeTargets.map(t => t.labels.job);
    expect(targets).toContain('code-server');
    expect(targets).toContain('oauth2-proxy');
    expect(targets).toContain('postgres');
  });

  test('Grafana dashboard accessibility', async () => {
    const page = await browser.newPage();
    await page.goto('http://192.168.168.31:3000');
    
    // Should show login page
    const loginForm = await page.waitForSelector('form');
    expect(loginForm).not.toBeNull();
    
    // Default credentials (test only!)
    await page.type('input[name="user"]', 'admin');
    await page.type('input[name="password"]', 'admin123');
    await page.click('button[type="submit"]');
    
    // Should load dashboard
    await page.waitForNavigation();
    const dashboard = await page.$('[class*="dashboard"]');
    expect(dashboard).not.toBeNull();
    
    await page.close();
  });

  test('AlertManager alerts firing', async () => {
    const response = await fetch('http://192.168.168.31:9093/api/v1/alerts');
    const data = await response.json();
    
    // Should have alerts endpoint
    expect(response.status).toBe(200);
    
    // Note: May be empty if no alerts triggered
    // Just verify endpoint works
    expect(data).toHaveProperty('data');
  });

  test('Jaeger tracing available', async () => {
    const page = await browser.newPage();
    await page.goto('http://192.168.168.31:16686');
    
    // Should load Jaeger UI
    const jaegerUI = await page.waitForSelector('[class*="jaeger"]');
    expect(jaegerUI).not.toBeNull();
    
    // Should be able to query for traces
    const traces = await page.$('[class*="service-selector"]');
    expect(traces).not.toBeNull();
    
    await page.close();
  });

  test('NAS mount accessibility', async () => {
    // This test runs commands via SSH to check NAS mounts
    const response = await fetch('http://192.168.168.31:8080/api/nas-status', {
      headers: { 'Authorization': `Bearer ${process.env.API_TOKEN}` }
    });
    
    expect(response.status).toBe(200);
    const data = await response.json();
    expect(data.mounts).toContain('/var/lib/nas');
  });

  test('Database connectivity', async () => {
    const response = await fetch('http://192.168.168.31:8080/api/db-health');
    expect(response.status).toBe(200);
    
    const data = await response.json();
    expect(data.database).toBe('connected');
    expect(data.replication).toBe('active');
  });

  test('Redis cache accessibility', async () => {
    const response = await fetch('http://192.168.168.31:8080/api/redis-health');
    expect(response.status).toBe(200);
    
    const data = await response.json();
    expect(data.redis).toBe('connected');
  });
});
```

**Expected Results:**
- ✅ Prometheus scraping all targets
- ✅ Grafana dashboard accessible
- ✅ AlertManager responding
- ✅ Jaeger collecting traces
- ✅ NAS mounts accessible
- ✅ Database connected
- ✅ Redis cache working

---

### Suite 4: Security & Compliance

**File:** `tests/e2e/security.spec.ts`

```typescript
describe('Security & Compliance', () => {
  
  test('HTTPS enforcement', async () => {
    // Test that HTTP redirects to HTTPS
    const response = await fetch('http://code-server.192.168.168.31.nip.io:8080', {
      redirect: 'manual'
    });
    
    // Should redirect to HTTPS
    expect([301, 302, 307, 308]).toContain(response.status);
    expect(response.headers.get('location')).toContain('https');
  });

  test('Security headers present', async () => {
    const response = await fetch('https://code-server.192.168.168.31.nip.io', {
      rejectUnauthorized: false // Self-signed cert
    });
    
    // Check security headers
    expect(response.headers.get('X-Frame-Options')).toBe('DENY');
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('X-XSS-Protection')).toBeTruthy();
  });

  test('No secrets in responses', async () => {
    const page = await browser.newPage();
    
    // Monitor network requests
    const requests = [];
    page.on('response', async (response) => {
      const text = await response.text();
      requests.push({ url: response.url(), body: text });
    });
    
    // Perform typical user actions
    await page.goto('https://code-server.192.168.168.31.nip.io');
    await page.waitForTimeout(5000);
    
    // Check no secrets in responses
    for (const req of requests) {
      expect(req.body).not.toContain('password');
      expect(req.body).not.toContain('token');
      expect(req.body).not.toContain('secret');
      expect(req.body).not.toContain('GOCSPX'); // Google secret pattern
      expect(req.body).not.toContain('ghp_'); // GitHub token pattern
    }
    
    await page.close();
  });

  test('Cookie security attributes', async () => {
    const page = await browser.newPage();
    await page.goto('https://code-server.192.168.168.31.nip.io');
    
    await page.waitForNavigation(); // OAuth redirect
    await page.waitForTimeout(2000); // Login
    
    const cookies = await page.cookies();
    
    for (const cookie of cookies) {
      if (cookie.name.includes('session') || cookie.name.includes('oauth')) {
        expect(cookie.httpOnly).toBe(true); // JS can't access
        expect(cookie.secure).toBe(true); // HTTPS only
        expect(cookie.sameSite).toBe('Lax'); // CSRF protection
      }
    }
    
    await page.close();
  });

  test('Rate limiting enforcement', async () => {
    // Attempt rapid requests
    const requests = [];
    for (let i = 0; i < 100; i++) {
      requests.push(
        fetch('https://code-server.192.168.168.31.nip.io/api/test', {
          rejectUnauthorized: false
        })
      );
    }
    
    const responses = await Promise.all(requests);
    const rateLimited = responses.filter(r => r.status === 429);
    
    // Should get some 429 responses
    expect(rateLimited.length).toBeGreaterThan(0);
  });
});
```

**Expected Results:**
- ✅ HTTPS enforced
- ✅ Security headers present
- ✅ No secrets in responses
- ✅ Cookies properly secured
- ✅ Rate limiting active

---

## TEST EXECUTION PLAN

### Day 1: Environment Setup (2 hours)

```bash
# 1. Setup VPN connection
vpn-connect --config on-prem.ovpn

# 2. Verify network connectivity
ping 192.168.168.31
ping 192.168.168.42

# 3. Install test dependencies
npm install --save-dev playwright puppeteer
npm install --save-dev @playwright/test

# 4. Setup QA account
export QA_EMAIL=qa-test@kushnir.cloud
export QA_PASSWORD=<from-vault>
export API_TOKEN=<from-vault>

# 5. Create test configuration
cat > tests/playwright.config.ts <<'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 30000,
  use: {
    baseURL: 'https://code-server.192.168.168.31.nip.io',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
  ],
  webServer: {
    // If testing locally built services
    url: 'https://code-server.192.168.168.31.nip.io',
    timeout: 120000,
  },
});
EOF
```

### Day 2-3: Test Execution (6 hours per day)

```bash
# Run all test suites
npm test

# Run specific suite
npm test auth.spec.ts

# Run with verbose output
npm test -- --reporter=verbose

# Run in headed mode (see browser)
npm test -- --headed

# Debug specific test
npm test auth.spec.ts --debug
```

### Day 4: Analysis & Reporting (2 hours)

```bash
# Generate test report
npm test -- --reporter=html > test-report.html

# Coverage analysis (if applicable)
npm test -- --coverage

# Performance metrics
npm test -- --reporter=json > test-results.json
```

---

## EXPECTED FINDINGS & REMEDIATION

### Critical Issues (Stop Deployment)

| Issue | Expected Detection | Remediation |
|-------|-------------------|-------------|
| OAuth2-proxy not responding | E2E timeout in auth suite | Restart service, check logs |
| Database not connected | Infrastructure suite fails | Verify credentials, check replication |
| TLS certificate invalid | Browser security error | Renew certificate (letsencrypt) |
| NAS unmounted | Infrastructure test fails | Check mount script, NAS IP |

### High Priority Issues (Delay Deployment)

| Issue | Expected Detection | Remediation |
|--------|-------------------|-------------|
| Missing security headers | Security suite fails | Update Caddyfile |
| Terminal doesn't work | Code-server suite fails | Check exec permissions |
| Slow performance | Timeouts in tests | Profile bottlenecks |
| Memory leaks | Long test hangs | Review process memory |

### Medium Priority Issues (Document for Post-Launch)

| Issue | Expected Detection | Remediation |
|-------|-------------------|-------------|
| Intermittent failures | Flaky tests | Add retry logic, stabilize |
| Warning logs | Check stderr | Address deprecations |
| Performance regression | Timing in tests | Optimize code paths |

---

## SUCCESS CRITERIA

✅ **All Suites Passing:**
- [ ] Authentication suite: 100% pass
- [ ] Code-server suite: 100% pass
- [ ] Infrastructure suite: 100% pass
- [ ] Security suite: 100% pass

✅ **Performance Thresholds:**
- [ ] Page load time < 3 seconds
- [ ] File save < 1 second
- [ ] Terminal response < 500ms
- [ ] No memory leaks over 1 hour

✅ **Coverage:**
- [ ] All critical user paths tested
- [ ] All infrastructure components verified
- [ ] Security controls validated
- [ ] VPN + QA account confirmed working

---

## RESOURCES & SETUP

### Test Environment Files

```
tests/
├── e2e/
│   ├── auth.spec.ts
│   ├── code-server.spec.ts
│   ├── infrastructure.spec.ts
│   └── security.spec.ts
├── fixtures/
│   ├── test-user.json
│   └── test-data.json
├── helpers/
│   ├── browser.ts
│   ├── api.ts
│   └── assertions.ts
└── playwright.config.ts
```

### VPN Setup (Example)

```bash
# Ubuntu/Linux
sudo openvpn --config on-prem.ovpn

# macOS
brew install openvpn
sudo openvpn --config on-prem.ovpn

# Windows
# Use OpenVPN GUI or command line
openvpn.exe --config on-prem.ovpn
```

### QA Account Credentials (Vault)

```bash
vault kv get secret/qa-account
```

---

## REPORTING & SIGN-OFF

### Test Report Template

```markdown
# E2E Test Report — April 19, 2026

## Executive Summary
- Tests Run: 24
- Passed: 24
- Failed: 0
- Flaky: 0
- Coverage: 98%

## Test Results by Suite
- Authentication: ✅ PASS (4/4)
- Code-Server: ✅ PASS (5/5)
- Infrastructure: ✅ PASS (7/7)
- Security: ✅ PASS (5/5)

## Issues Found
None blocking production

## Sign-Off
- [ ] QA Lead: _________
- [ ] DevOps Lead: ________
- [ ] Security Lead: _______

Date: 2026-04-22
```

---

**Plan Created:** 2026-04-19T16:00:00Z  
**Status:** Ready for Implementation  
**VPN Required:** Yes  
**QA Account Required:** Yes  
**Estimated Duration:** 3-4 days  
**Timeline:** April 22-25, 2026
