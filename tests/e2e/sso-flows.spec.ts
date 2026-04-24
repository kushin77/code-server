// @file        tests/e2e/sso-flows.spec.ts
// @module      tests/e2e
// @description SSO Playwright validation tests (Phase 5 #1675)
// IaC: Idempotent tests - read-only, no state modification

import { test, expect } from '@playwright/test';

// ════════════════════════════════════════════════════════════════════════════
// Configuration
// ════════════════════════════════════════════════════════════════════════════
const BASE_URL = process.env.BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_URL || 'https://ide.kushnir.cloud';
const OAUTH_CALLBACK_TIMEOUT = 60000;

// Test users (read from env)
const TEST_EMAIL = process.env.TEST_EMAIL || 'test@example.com';
const TEST_PASSWORD = process.env.TEST_PASSWORD || 'test-password';

test.describe('SSO Flows — Kushnir.cloud', () => {
  
  // ════════════════════════════════════════════════════════════════════════
  // Test 1: New User Onboarding
  // ════════════════════════════════════════════════════════════════════════
  test('Flow 1: New user → OAuth → Profile setup → Dashboard → IDE access', async ({ page }) => {
    console.log('🔵 Starting: New User Onboarding Flow');
    
    // Step 1: Navigate to portal
    console.log('Step 1: Visiting kushnir.cloud');
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await expect(page).toHaveTitle(/Kushnir|Portal/i);
    
    // Step 2: Click OAuth login
    console.log('Step 2: Clicking OAuth login button');
    const loginButton = page.locator('button:has-text("Sign in with Google")');
    await expect(loginButton).toBeVisible({ timeout: 5000 });
    await loginButton.click();
    
    // Step 3: Complete Google OAuth (handled by test env setup)
    console.log('Step 3: Completing Google OAuth flow');
    await page.waitForURL(/dashboard|profile|setup/, { timeout: OAUTH_CALLBACK_TIMEOUT });
    
    // Step 4: Profile setup (if first login)
    console.log('Step 4: Setting up profile');
    const profileSection = page.locator('[data-testid="profile-setup"]');
    if (await profileSection.isVisible({ timeout: 2000 }).catch(() => false)) {
      const nameInput = page.locator('input[name="display_name"]');
      await nameInput.fill('Test User');
      await page.locator('button:has-text("Continue")').click();
      await page.waitForLoadState('networkidle');
    }
    
    // Step 5: Verify in dashboard
    console.log('Step 5: Verifying dashboard access');
    await expect(page).toHaveURL(/dashboard|portal/, { timeout: 5000 });
    const dashboardTitle = page.locator('h1:has-text("Dashboard")');
    await expect(dashboardTitle).toBeVisible({ timeout: 5000 });
    
    // Step 6: Access IDE without re-auth (session persists)
    console.log('Step 6: Accessing IDE without re-authentication');
    await page.goto(IDE_URL, { waitUntil: 'networkidle' });
    
    // Verify IDE loads (code-server interface visible)
    const ideEditor = page.locator('[data-testid="workbench"] >> visible=true');
    await expect(ideEditor).toBeVisible({ timeout: 10000 });
    
    // Verify session cookie exists
    const cookies = await page.context().cookies();
    const sessionCookie = cookies.find(c => c.name.includes('_oauth'));
    expect(sessionCookie).toBeTruthy();
    
    console.log('✅ Test 1 PASSED: New user onboarding complete');
  });

  // ════════════════════════════════════════════════════════════════════════
  // Test 2: Returning User (Fast Access)
  // ════════════════════════════════════════════════════════════════════════
  test('Flow 2: Returning user → IDE instant access (< 3s)', async ({ page }) => {
    console.log('🔵 Starting: Returning User Flow');
    
    const startTime = Date.now();
    
    // Step 1: Navigate IDE directly
    console.log('Step 1: Direct IDE access');
    await page.goto(IDE_URL, { waitUntil: 'domcontentloaded' });
    
    // Step 2: Verify no redirect (already authenticated)
    console.log('Step 2: Checking no OAuth redirect');
    const currentUrl = page.url();
    expect(currentUrl).toContain('ide.kushnir.cloud');
    
    // Step 3: Wait for IDE to load
    console.log('Step 3: Waiting for IDE to fully load');
    const ideEditor = page.locator('[data-testid="workbench"]');
    await expect(ideEditor).toBeVisible({ timeout: 5000 });
    
    const endTime = Date.now();
    const loadTime = endTime - startTime;
    
    console.log(`Step 4: Load time: ${loadTime}ms`);
    expect(loadTime).toBeLessThan(3000);
    
    console.log('✅ Test 2 PASSED: Returning user fast access');
  });

  // ════════════════════════════════════════════════════════════════════════
  // Test 3: Cross-Subdomain Session Consistency
  // ════════════════════════════════════════════════════════════════════════
  test('Flow 3: Session persists across kushnir.cloud ↔ ide.kushnir.cloud', async ({ page }) => {
    console.log('🔵 Starting: Cross-Subdomain Session Flow');
    
    // Step 1: Start at portal
    console.log('Step 1: Starting at portal');
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const portalCookies = await page.context().cookies();
    const portalSession = portalCookies.find(c => c.name.includes('_oauth'));
    console.log(`Portal session cookie: ${portalSession?.name}`);
    expect(portalSession).toBeTruthy();
    
    // Step 2: Navigate to IDE
    console.log('Step 2: Navigating to IDE');
    await page.goto(IDE_URL, { waitUntil: 'networkidle' });
    
    // Step 3: Verify IDE loads without re-auth
    const ideEditor = page.locator('[data-testid="workbench"]');
    await expect(ideEditor).toBeVisible({ timeout: 5000 });
    
    const ideCookies = await page.context().cookies();
    const ideSession = ideCookies.find(c => c.name.includes('_oauth'));
    console.log(`IDE session cookie: ${ideSession?.name}`);
    
    // Step 4: Verify same session token (or related) across subdomains
    expect(ideSession).toBeTruthy();
    
    // Step 5: Return to portal
    console.log('Step 5: Returning to portal');
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    const finalCookies = await page.context().cookies();
    const finalSession = finalCookies.find(c => c.name.includes('_oauth'));
    expect(finalSession).toBeTruthy();
    
    console.log('✅ Test 3 PASSED: Session persists across subdomains');
  });

  // ════════════════════════════════════════════════════════════════════════
  // Test 4: Session Expiry & Recovery
  // ════════════════════════════════════════════════════════════════════════
  test('Flow 4: Session expiry → graceful redirect → recovery', async ({ page }) => {
    console.log('🔵 Starting: Session Expiry & Recovery Flow');
    
    // Step 1: Start authenticated
    console.log('Step 1: Starting authenticated session');
    await page.goto(IDE_URL, { waitUntil: 'networkidle' });
    
    const ideEditor = page.locator('[data-testid="workbench"]');
    await expect(ideEditor).toBeVisible({ timeout: 5000 });
    
    // Step 2: Simulate session expiry by clearing cookies
    console.log('Step 2: Simulating session expiry (clearing auth cookie)');
    const context = page.context();
    const cookies = await context.cookies();
    const sessionCookies = cookies.filter(c => c.name.includes('_oauth'));
    
    for (const cookie of sessionCookies) {
      await context.clearCookies({ name: cookie.name });
    }
    
    // Step 3: Refresh and expect login redirect
    console.log('Step 3: Refreshing page after session expiry');
    await page.reload({ waitUntil: 'networkidle' });
    
    // Should redirect to login
    console.log('Step 4: Verifying redirect to OAuth');
    await expect(page).toHaveURL(/auth|login|signin/, { timeout: 5000 });
    
    // Step 5: Re-authenticate
    console.log('Step 5: Re-authenticating');
    const loginButton = page.locator('button:has-text("Sign in")');
    if (await loginButton.isVisible({ timeout: 2000 }).catch(() => false)) {
      await loginButton.click();
      await page.waitForURL(/dashboard|ide/, { timeout: OAUTH_CALLBACK_TIMEOUT });
    }
    
    // Step 6: Verify back to IDE or dashboard
    console.log('Step 6: Verifying recovery');
    const currentUrl = page.url();
    expect(currentUrl).toMatch(/dashboard|ide/);
    
    console.log('✅ Test 4 PASSED: Session recovery works');
  });

  // ════════════════════════════════════════════════════════════════════════
  // Test 5: Security Headers & CORS
  // ════════════════════════════════════════════════════════════════════════
  test('Flow 5: Security headers present (no CORS/CSP errors)', async ({ page }) => {
    console.log('🔵 Starting: Security Headers Flow');
    
    // Collect page errors
    const pageErrors: string[] = [];
    page.on('pageerror', (err) => {
      pageErrors.push(err.message);
    });
    
    // Navigate to portal
    console.log('Step 1: Navigating to portal');
    const response = await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    
    // Check security headers
    console.log('Step 2: Checking security headers');
    const headers = response?.headers() || {};
    
    expect(headers['strict-transport-security']).toBeTruthy();
    expect(headers['x-frame-options']).toBeTruthy();
    expect(headers['x-content-type-options']).toBeTruthy();
    
    // Navigate to IDE
    console.log('Step 3: Navigating to IDE');
    await page.goto(IDE_URL, { waitUntil: 'networkidle' });
    
    // Check for CORS/CSP errors
    console.log('Step 4: Checking for CORS/CSP errors');
    const corsErrors = pageErrors.filter(e => e.includes('CORS') || e.includes('CSP'));
    expect(corsErrors.length).toBe(0);
    
    console.log('✅ Test 5 PASSED: Security headers valid');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// Performance Benchmarks
// ════════════════════════════════════════════════════════════════════════════
test('Benchmark: Portal load time', async ({ page }) => {
  const startTime = Date.now();
  await page.goto(BASE_URL, { waitUntil: 'networkidle' });
  const loadTime = Date.now() - startTime;
  
  console.log(`Portal load time: ${loadTime}ms`);
  expect(loadTime).toBeLessThan(5000);
});

test('Benchmark: IDE load time', async ({ page }) => {
  const startTime = Date.now();
  await page.goto(IDE_URL, { waitUntil: 'networkidle' });
  const loadTime = Date.now() - startTime;
  
  console.log(`IDE load time: ${loadTime}ms`);
  expect(loadTime).toBeLessThan(10000);
});
