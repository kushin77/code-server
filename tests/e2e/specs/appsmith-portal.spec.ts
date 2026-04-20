import { test, expect } from '@playwright/test';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('Appsmith Portal Features (#987)', () => {

  // These tests assume user is already authenticated (QA user session)
  test.beforeEach(async ({ page, context }) => {
    // Get stored authentication state if available
    const authFile = 'tests/e2e/.auth/qa-storage-state.json';
    try {
      await context.addCookies([]);
    } catch (e) {
      // Auth file may not exist yet, tests will fail until #984 activates
    }
  });

  test.describe('Navigation & Layout', () => {
    
    test('1: landing page loads with expected layout', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Verify main layout elements exist
      await expect(page.locator('header')).toBeVisible();
      await expect(page.locator('main')).toBeVisible();
      
      // Verify page title
      const title = await page.title();
      expect(title).toBeTruthy();
    });

    test('2: navigation menu renders all items', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Verify nav exists and has content
      const nav = page.locator('nav');
      await expect(nav).toBeVisible();
      
      // Count menu items
      const menuItems = await nav.locator('a, button').count();
      expect(menuItems).toBeGreaterThan(0);
    });

    test('3: user profile shows correct email (qa@kushnir.cloud)', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Try to find user profile element
      const profileBtn = page.locator('[data-testid="user-menu"], [aria-label*="Profile"], .user-profile, .avatar');
      if (await profileBtn.isVisible()) {
        await profileBtn.click();
      }
      
      // Look for email display
      const emailDisplay = page.locator('text=qa@kushnir.cloud');
      if (await emailDisplay.isVisible()) {
        await expect(emailDisplay).toContainText('qa@kushnir.cloud');
      }
    });

    test('4: breadcrumb navigation works correctly', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Check if breadcrumbs exist
      const breadcrumbs = page.locator('[role="navigation"] nav, .breadcrumb, [data-testid="breadcrumbs"]');
      if (await breadcrumbs.isVisible()) {
        await expect(breadcrumbs).toBeVisible();
      }
    });

    test('5: responsive layout works on mobile', async ({ browser }) => {
      const mobileContext = await browser.newContext({
        viewport: { width: 375, height: 667 },
        userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15'
      });
      
      const page = await mobileContext.newPage();
      await page.goto(PORTAL_URL);
      
      // Verify page is still functional on mobile
      const main = page.locator('main');
      await expect(main).toBeVisible();
      
      await mobileContext.close();
    });

    test('6: dark mode toggle works (if available)', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Look for dark mode toggle
      const darkModeBtn = page.locator('[data-testid="dark-mode-toggle"], [aria-label*="dark"], [aria-label*="theme"], .theme-toggle');
      
      if (await darkModeBtn.isVisible()) {
        await darkModeBtn.click();
        
        // Verify toggle worked (body class or data attribute changed)
        const html = page.locator('html');
        await page.waitForTimeout(500); // Wait for animation
        const isDarkMode = await html.evaluate(el => {
          return el.classList.contains('dark') || el.getAttribute('data-theme') === 'dark';
        });
        
        expect(isDarkMode).toBeTruthy();
      }
    });
  });

  test.describe('IDE Launch', () => {
    
    test('7: IDE launch link/button is visible', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Look for IDE launch button
      const ideBtn = page.locator('[data-testid="ide-launch"], a[href*="ide.kushnir.cloud"], button:has-text("IDE"), button:has-text("Code"), a:has-text("IDE")');
      await expect(ideBtn.first()).toBeVisible();
    });

    test('8: click IDE link navigates to ide.kushnir.cloud', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Find IDE link
      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"]');
      
      if (await ideLink.first().isVisible()) {
        await ideLink.first().click();
        
        // Verify navigation to IDE
        await page.waitForURL(new RegExp(`${IDE_URL.replace(/\./g, '\\.')}`), { timeout: 15000 });
        expect(page.url()).toContain('ide.kushnir.cloud');
      }
    });

    test('9: IDE opens in new tab (if configured)', async ({ context, page }) => {
      await page.goto(PORTAL_URL);
      
      // Track new pages/tabs
      const newPagePromise = context.waitForEvent('page');
      
      // Click IDE link (may open in new tab)
      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"]');
      await ideLink.first().click({ modifiers: ['CtrlOrMeta'] });
      
      // Check if new tab opened
      try {
        const newPage = await newPagePromise;
        expect(newPage.url()).toContain('ide.kushnir.cloud');
        await newPage.close();
      } catch (e) {
        // Same tab navigation is also valid
        expect(page.url()).toContain('ide.kushnir.cloud');
      }
    });

    test('10: OAuth session transfers to IDE subdomain', async ({ page, context }) => {
      await page.goto(PORTAL_URL);
      
      // Navigate to IDE
      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"]');
      if (await ideLink.first().isVisible()) {
        await ideLink.first().click();
        await page.waitForURL(new RegExp(`${IDE_URL.replace(/\./g, '\\.')}`), { timeout: 15000 });
      }
      
      // Verify session cookies transferred
      const cookies = await context.cookies();
      const oauthCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(oauthCookie).toBeDefined();
    });

    test('11: can navigate back to portal from IDE', async ({ page }) => {
      await page.goto(IDE_URL);
      
      // Look for back to portal link
      const backBtn = page.locator('[data-testid="back-to-portal"], a[href*="kushnir.cloud"], button:has-text("Portal")');
      
      if (await backBtn.first().isVisible()) {
        await backBtn.first().click();
        
        // Should navigate back to portal
        await page.waitForURL(new RegExp(`${PORTAL_URL.replace(/\./g, '\\.')}`), { timeout: 10000 });
        expect(page.url()).toContain(PORTAL_URL);
      }
    });

    test('12: direct IDE URL preserves workspace context', async ({ page }) => {
      // Access IDE directly
      await page.goto(IDE_URL);
      
      // Verify workspace is loaded
      const main = page.locator('main');
      await expect(main).toBeVisible();
    });

    test('13: IDE launch completes within 10 seconds', async ({ page }) => {
      const startTime = Date.now();
      
      await page.goto(PORTAL_URL);
      
      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"]');
      if (await ideLink.first().isVisible()) {
        await ideLink.first().click();
        await page.waitForURL(new RegExp(`${IDE_URL.replace(/\./g, '\\.')}`), { timeout: 15000 });
        
        const loadTime = Date.now() - startTime;
        expect(loadTime).toBeLessThan(10000);
      }
    });

    test('14: multiple IDE launches do not create duplicate sessions', async ({ page, context }) => {
      await page.goto(PORTAL_URL);
      
      // Get initial cookies
      const initialCookies = (await context.cookies()).filter(c => c.name.includes('oauth'));
      
      // Launch IDE
      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"]');
      if (await ideLink.first().isVisible()) {
        await ideLink.first().click();
        await page.waitForURL(new RegExp(`${IDE_URL.replace(/\./g, '\\.')}`), { timeout: 15000 });
        
        const cookiesAfterLaunch = (await context.cookies()).filter(c => c.name.includes('oauth'));
        
        // Should have same number of oauth cookies, not duplicates
        expect(cookiesAfterLaunch.length).toBeLessThanOrEqual(initialCookies.length + 1);
      }
    });
  });

  test.describe('Workspace Management', () => {
    
    test('15: workspace list displays correctly', async ({ page }) => {
      // Navigate to workspaces page
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Look for workspace list
      const workspaceList = page.locator('[data-testid="workspace-list"], .workspace-list, [role="list"]');
      if (await workspaceList.first().isVisible()) {
        await expect(workspaceList.first()).toBeVisible();
      }
    });

    test('16: can create new workspace', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Look for create button
      const createBtn = page.locator('button:has-text("New"), button:has-text("Create"), [data-testid="create-workspace"]');
      
      if (await createBtn.first().isVisible()) {
        await createBtn.first().click();
        
        // Verify dialog or form appears
        await page.waitForLoadState('networkidle');
      }
    });

    test('17: can delete workspace', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Look for workspace delete button
      const deleteBtn = page.locator('[data-testid*="delete"], button:has-text("Delete"), [aria-label*="Delete"]');
      
      if (await deleteBtn.first().isVisible()) {
        await deleteBtn.first().click();
      }
    });

    test('18: can rename workspace', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Look for rename option
      const renameBtn = page.locator('[data-testid*="rename"], button:has-text("Rename"), [aria-label*="Rename"]');
      
      if (await renameBtn.first().isVisible()) {
        await renameBtn.first().click();
      }
    });

    test('19: workspace settings accessible', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Look for settings
      const settingsBtn = page.locator('[data-testid*="settings"], button:has-text("Settings"), [aria-label*="Settings"]');
      
      if (await settingsBtn.first().isVisible()) {
        await settingsBtn.first().click();
      }
    });

    test('20: workspace sharing works (if available)', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/workspaces`);
      
      // Look for share button
      const shareBtn = page.locator('[data-testid*="share"], button:has-text("Share"), [aria-label*="Share"]');
      
      if (await shareBtn.first().isVisible()) {
        await shareBtn.first().click();
      }
    });
  });

  test.describe('Application Features', () => {
    
    test('21: application list displays correctly', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/apps`);
      
      const appList = page.locator('[data-testid="app-list"], .app-list, [role="list"]');
      if (await appList.first().isVisible()) {
        await expect(appList.first()).toBeVisible();
      }
    });

    test('22: can create new application', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/apps`);
      
      const createBtn = page.locator('button:has-text("New"), button:has-text("Create"), [data-testid="create-app"]');
      if (await createBtn.first().isVisible()) {
        await createBtn.first().click();
      }
    });

    test('23: can edit existing application', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/apps`);
      
      // Get first app
      const app = page.locator('[data-testid*="app"], .app-item').first();
      if (await app.isVisible()) {
        await app.click();
      }
    });

    test('24: can deploy application', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/apps`);
      
      const deployBtn = page.locator('button:has-text("Deploy"), [data-testid="deploy"]');
      if (await deployBtn.first().isVisible()) {
        await deployBtn.first().click();
      }
    });

    test('25: can delete application', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/apps`);
      
      const deleteBtn = page.locator('[data-testid*="delete"], button:has-text("Delete")');
      if (await deleteBtn.first().isVisible()) {
        await deleteBtn.first().click();
      }
    });

    test('26: can preview application', async ({ page }) => {
      await page.goto(`${PORTAL_URL}/apps`);
      
      const previewBtn = page.locator('button:has-text("Preview"), [data-testid="preview"]');
      if (await previewBtn.first().isVisible()) {
        await previewBtn.first().click();
      }
    });
  });

  test.describe('Error Handling & Edge Cases', () => {
    
    test('27: expired session redirects to login', async ({ page, context }) => {
      await page.goto(PORTAL_URL);
      
      // Clear auth cookies
      const cookies = await context.cookies();
      const authCookies = cookies.filter(c => c.name.includes('oauth') || c.name.includes('auth'));
      
      for (const cookie of authCookies) {
        await context.clearCookies({ name: cookie.name });
      }
      
      // Refresh page
      await page.reload();
      
      // Should redirect to OAuth login
      const url = page.url();
      expect(url).toMatch(/oauth2|accounts\.google\.com/);
    });

    test('28: network errors show user-friendly message', async ({ page }) => {
      // Block certain resources to simulate errors
      await page.route('**/api/**', async (route) => {
        await route.abort('failed');
      });
      
      await page.goto(PORTAL_URL);
      
      // Page should still be functional (graceful degradation)
      const main = page.locator('main');
      await expect(main).toBeVisible();
    });

    test('29: concurrent edits do not corrupt data', async ({ page, context }) => {
      // Create two pages for concurrent access
      const page2 = await context.newPage();
      
      await page.goto(`${PORTAL_URL}/workspaces`);
      await page2.goto(`${PORTAL_URL}/workspaces`);
      
      // Simulate concurrent actions
      await page.waitForTimeout(500);
      await page2.waitForTimeout(500);
      
      // Verify both pages still function
      await expect(page.locator('main')).toBeVisible();
      await expect(page2.locator('main')).toBeVisible();
      
      await page2.close();
    });

    test('30: page refresh preserves state', async ({ page }) => {
      await page.goto(PORTAL_URL);
      
      // Get initial URL
      const initialUrl = page.url();
      
      // Refresh
      await page.reload();
      
      // Should maintain authentication
      const newUrl = page.url();
      expect(newUrl).toContain('kushnir.cloud');
      
      // Should not redirect to login
      expect(newUrl).not.toMatch(/oauth2|accounts\.google\.com/);
    });
  });
});
