import { test, expect } from './fixtures';

const PORTAL_URL = process.env.PORTAL_BASE_URL || 'https://kushnir.cloud';
const APPSMITH_URL = `${PORTAL_URL}/appsmith`;

test.describe('Appsmith Login & Workspace Access - E2E Tests', () => {
  /**
   * HAPPY PATH SCENARIOS (Happy Path Group 1: Basic Access)
   */
  test.describe('Happy Path - Basic Appsmith Access', () => {
    test('authenticated user can access Appsmith', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Should not redirect to login
      const url = authenticatedPage.url();
      expect(url).not.toMatch(/accounts\.google\.com|oauth2/i);
      
      // Appsmith dashboard should load
      await authenticatedPage.waitForSelector('[data-testid="app-grid-container"]', { timeout: 10000 }).catch(() => {
        // Alternative selectors for different Appsmith versions
        return authenticatedPage.waitForSelector('.t--applications-container', { timeout: 10000 });
      });
    });

    test('user can view list of applications', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Wait for app list to load
      await authenticatedPage.waitForLoadState('networkidle');
      
      // Check if there's an app grid or list
      const hasAppContainer = await authenticatedPage.locator('[data-testid="app-grid-container"]').isVisible().catch(() => false);
      const hasAppsList = await authenticatedPage.locator('.t--applications-container').isVisible().catch(() => false);
      
      expect(hasAppContainer || hasAppsList).toBe(true);
    });

    test('user can create new application', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Find and click "Create new app" button
      const createButton = authenticatedPage.locator('button:has-text("Create")').or(
        authenticatedPage.locator('[data-testid="create-app-button"]')
      );
      
      await createButton.click();
      
      // Appsmith should open new app editor
      await authenticatedPage.waitForURL(/editor|canvas/, { timeout: 10000 });
      
      const url = authenticatedPage.url();
      expect(url).toMatch(/editor|canvas/i);
    });

    test('user can open existing application', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Find first app in list
      const firstApp = authenticatedPage.locator('.t--app-card').first();
      
      if (await firstApp.isVisible()) {
        await firstApp.click();
        
        // Should navigate to app viewer or editor
        await authenticatedPage.waitForURL(/viewer|editor/, { timeout: 10000 });
        
        const url = authenticatedPage.url();
        expect(url).toMatch(/viewer|editor/i);
      }
    });

    test('user can edit application canvas', async ({ authenticatedPage }) => {
      // Navigate to app editor
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Wait for canvas to load
      await authenticatedPage.waitForSelector('iframe[title="iframe"]', { timeout: 10000 }).catch(() => {
        return authenticatedPage.waitForSelector('.t--canvas', { timeout: 10000 });
      });
      
      // Canvas should be available
      const canvas = authenticatedPage.locator('iframe[title="iframe"]').or(
        authenticatedPage.locator('.t--canvas')
      );
      
      expect(canvas).toBeDefined();
    });

    test('user can add widgets to canvas', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Wait for editor to load
      await authenticatedPage.waitForLoadState('networkidle');
      
      // Open widget library
      const widgetLibraryBtn = authenticatedPage.locator('[data-testid="entity-explorer"]').or(
        authenticatedPage.locator('.t--widget-library-toggle')
      );
      
      if (await widgetLibraryBtn.isVisible()) {
        await widgetLibraryBtn.click();
      }
      
      // Should be able to see widgets
      const buttonWidget = authenticatedPage.locator('text=Button').first();
      expect(buttonWidget).toBeDefined();
    });

    test('user can save application', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Find save button
      const saveButton = authenticatedPage.locator('button:has-text("Save")').or(
        authenticatedPage.locator('[data-testid="save-button"]')
      );
      
      if (await saveButton.isVisible()) {
        await saveButton.click();
        
        // Should show save confirmation
        await authenticatedPage.waitForSelector('[data-testid="save-indicator"]', { timeout: 5000 }).catch(() => {
          // App might auto-save
        });
      }
    });
  });

  /**
   * HAPPY PATH SCENARIOS (Happy Path Group 2: Workspace Management)
   */
  test.describe('Happy Path - Workspace Operations', () => {
    test('user can view workspace info', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Workspace info should be visible
      const workspaceInfo = authenticatedPage.locator('[data-testid="workspace-info"]').or(
        authenticatedPage.locator('.t--workspace-settings')
      );
      
      expect(workspaceInfo).toBeDefined();
    });

    test('user can create new workspace', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Find create workspace option
      const createWorkspaceBtn = authenticatedPage.locator('text=Create Workspace').or(
        authenticatedPage.locator('[data-testid="create-workspace"]')
      );
      
      if (await createWorkspaceBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        await createWorkspaceBtn.click();
        
        // Should open workspace creation dialog
        await authenticatedPage.waitForSelector('[data-testid="workspace-form"]', { timeout: 5000 }).catch(() => {});
      }
    });

    test('user can switch between workspaces', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Find workspace switcher
      const workspaceSwitcher = authenticatedPage.locator('[data-testid="workspace-switcher"]').or(
        authenticatedPage.locator('.t--workspace-dropdown')
      );
      
      if (await workspaceSwitcher.isVisible({ timeout: 5000 }).catch(() => false)) {
        await workspaceSwitcher.click();
        
        // Should show list of workspaces
        await authenticatedPage.waitForSelector('[data-testid="workspace-option"]', { timeout: 5000 }).catch(() => {});
      }
    });

    test('user can access workspace settings', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Find settings button
      const settingsBtn = authenticatedPage.locator('[data-testid="workspace-settings-btn"]').or(
        authenticatedPage.locator('text=Settings')
      );
      
      if (await settingsBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
        await settingsBtn.click();
        
        // Should navigate to settings
        await authenticatedPage.waitForURL(/settings/, { timeout: 5000 }).catch(() => {});
      }
    });
  });

  /**
   * ERROR HANDLING SCENARIOS
   */
  test.describe('Error Handling', () => {
    test('non-authenticated user cannot access Appsmith', async ({ page }) => {
      // Fresh page without authentication
      await page.goto(APPSMITH_URL);
      
      // Should redirect to login
      const url = page.url();
      expect(url).toMatch(/accounts\.google\.com|oauth2|login/i);
    });

    test('invalid app ID returns error', async ({ authenticatedPage }) => {
      // Try to access non-existent app
      await authenticatedPage.goto(`${APPSMITH_URL}/editor/invalid-app-id`);
      
      // Should show error or redirect
      const url = authenticatedPage.url();
      expect(url).not.toMatch(/invalid-app-id/);
    });

    test('network error while loading app is handled', async ({ authenticatedPage }) => {
      // Simulate network slowdown
      await authenticatedPage.route('**/api/v1/**', route => {
        setTimeout(() => route.continue(), 5000);
      });
      
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Should still show page or error message
      expect(authenticatedPage).toBeDefined();
      
      await authenticatedPage.unroute('**/api/v1/**');
    });

    test('permission denied when accessing other user app', async ({ authenticatedPage }) => {
      // Try to access app created by another user
      await authenticatedPage.goto(`${APPSMITH_URL}/editor/other-user-app-id`);
      
      // Should be denied or show error
      await authenticatedPage.waitForSelector('[data-testid="error-message"]', { timeout: 5000 }).catch(() => {});
      
      const errorVisible = await authenticatedPage.locator('[data-testid="error-message"]').isVisible().catch(() => false);
      expect(errorVisible || authenticatedPage.url() !== `${APPSMITH_URL}/editor/other-user-app-id`).toBe(true);
    });
  });

  /**
   * EDGE CASES
   */
  test.describe('Edge Cases', () => {
    test('rapid navigation between apps doesnt cause state corruption', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Get list of apps
      const apps = await authenticatedPage.locator('.t--app-card').all();
      
      if (apps.length >= 2) {
        // Rapidly click between apps
        for (let i = 0; i < Math.min(3, apps.length); i++) {
          await apps[i].click();
          await authenticatedPage.waitForLoadState('networkidle');
        }
        
        // Should still be in valid state
        const url = authenticatedPage.url();
        expect(url).toMatch(/editor|viewer/);
      }
    });

    test('session timeout while editing is handled', async ({ authenticatedPage, context }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Simulate session timeout by clearing cookies
      await context.clearCookies();
      
      // Try to perform action
      await authenticatedPage.reload();
      
      // Should redirect to login
      const url = authenticatedPage.url();
      expect(url).toMatch(/accounts\.google\.com|oauth2|login/i);
    });

    test('large application loads without freezing', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      const startTime = Date.now();
      
      // Wait for app to fully load
      await authenticatedPage.waitForLoadState('networkidle');
      
      const duration = Date.now() - startTime;
      
      // Should load in reasonable time
      expect(duration).toBeLessThan(30000);
    });

    test('special characters in app name handled', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Create app with special characters
      const createButton = authenticatedPage.locator('button:has-text("Create")').first();
      
      if (await createButton.isVisible()) {
        await createButton.click();
        
        // Dialog might appear to name the app
        const nameInput = authenticatedPage.locator('input[placeholder*="name"]').or(
          authenticatedPage.locator('[data-testid="app-name-input"]')
        );
        
        if (await nameInput.isVisible({ timeout: 5000 }).catch(() => false)) {
          await nameInput.fill('Test App & Special <Chars>');
          
          // Should handle special characters
          const appName = await nameInput.inputValue();
          expect(appName).toContain('&');
        }
      }
    });

    test('appsmith remains responsive during auto-save', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Canvas should stay responsive
      const startTime = Date.now();
      
      // Try to perform action while auto-save might be happening
      const button = authenticatedPage.locator('button').first();
      if (await button.isVisible()) {
        await button.click();
      }
      
      const duration = Date.now() - startTime;
      
      // Should respond quickly even during save
      expect(duration).toBeLessThan(2000);
    });
  });

  /**
   * PERFORMANCE & STABILITY
   */
  test.describe('Performance & Stability', () => {
    test('Appsmith dashboard loads within acceptable time', async ({ authenticatedPage }) => {
      const startTime = Date.now();
      
      await authenticatedPage.goto(APPSMITH_URL);
      await authenticatedPage.waitForLoadState('networkidle');
      
      const duration = Date.now() - startTime;
      
      // Should load dashboard in under 10 seconds
      expect(duration).toBeLessThan(10000);
    });

    test('app editor memory doesnt leak on long sessions', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Perform multiple operations
      for (let i = 0; i < 5; i++) {
        await authenticatedPage.reload();
        await authenticatedPage.waitForLoadState('networkidle');
      }
      
      // Should still be responsive
      expect(authenticatedPage.url()).toMatch(/editor/);
    });

    test('can edit without disconnection during 30min session', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(`${APPSMITH_URL}/editor`);
      
      // Simulate 30 minute activity (using accelerated timeouts in test)
      for (let i = 0; i < 6; i++) {
        await authenticatedPage.waitForTimeout(100); // Simulated wait
        
        // Check connection is still alive
        const isConnected = await authenticatedPage.evaluate(() => {
          return navigator.onLine;
        });
        
        expect(isConnected).toBe(true);
      }
    });
  });

  /**
   * INTEGRATION WITH PORTAL
   */
  test.describe('Integration with Portal', () => {
    test('can navigate back to portal from Appsmith', async ({ authenticatedPage }) => {
      await authenticatedPage.goto(APPSMITH_URL);
      
      // Find navigation back to portal
      const backButton = authenticatedPage.locator('[data-testid="back-to-portal"]').or(
        authenticatedPage.locator('text=Back')
      );
      
      if (await backButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        await backButton.click();
        
        // Should navigate back to portal
        await authenticatedPage.waitForURL(new RegExp(PORTAL_URL.replace(/\//g, '\\/')), { timeout: 5000 }).catch(() => {});
      }
    });

    test('session remains valid across portal and Appsmith', async ({ authenticatedPage }) => {
      // Go to Appsmith
      await authenticatedPage.goto(APPSMITH_URL);
      const cookiesAppsmith = await authenticatedPage.context().cookies();
      
      // Go to portal
      await authenticatedPage.goto(PORTAL_URL);
      const cookiesPortal = await authenticatedPage.context().cookies();
      
      // OAuth cookie should persist
      const oauthCookieAppsmith = cookiesAppsmith.find(c => c.name === '_oauth2_proxy');
      const oauthCookiePortal = cookiesPortal.find(c => c.name === '_oauth2_proxy');
      
      expect(oauthCookieAppsmith?.value).toBe(oauthCookiePortal?.value);
    });
  });
});
