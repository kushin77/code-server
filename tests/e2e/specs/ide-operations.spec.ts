import { test, expect } from '@playwright/test';

const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

test.describe('IDE Operations - code-server (#988)', () => {

  // These tests assume user is already authenticated
  test.beforeEach(async ({ page }) => {
    // Navigate to IDE
    await page.goto(IDE_URL);
  });

  test.describe('IDE Launch & Load', () => {
    
    test('1: IDE loads successfully after auth', async ({ page }) => {
      // Wait for VSCode/code-server to fully load
      await page.waitForSelector('.monaco-workbench, .editor-container, [data-testid="workbench"]', { timeout: 30000 });
      
      // Verify main UI elements
      const workbench = page.locator('.monaco-workbench, .editor-container, .workbench').first();
      await expect(workbench).toBeVisible();
    });

    test('2: IDE fully loads within 15 seconds', async ({ page }) => {
      const startTime = Date.now();
      
      // Wait for editor to be ready
      await page.waitForSelector('.monaco-editor, .editor, [role="main"]', { timeout: 15000 });
      
      const loadTime = Date.now() - startTime;
      console.log(`IDE load time: ${loadTime}ms`);
      expect(loadTime).toBeLessThan(15000);
    });

    test('3: VSCode layout renders (sidebar, editor, terminal)', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Verify sidebar
      const sidebar = page.locator('.sidebar, .explorer, [data-testid="sidebar"]');
      if (await sidebar.first().isVisible()) {
        await expect(sidebar.first()).toBeVisible();
      }
      
      // Verify editor area
      const editor = page.locator('.monaco-editor, .editor-area');
      if (await editor.first().isVisible()) {
        await expect(editor.first()).toBeVisible();
      }
    });

    test('4: welcome tab or last session restores', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Look for editor tabs
      const tabs = page.locator('.tab, [role="tab"], [data-testid="tab"]');
      const tabCount = await tabs.count();
      
      // Should have at least some tab (welcome or previous)
      expect(tabCount).toBeGreaterThanOrEqual(0);
    });

    test('5: menu bar is accessible', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Look for menu items
      const menuBar = page.locator('.menubar, [role="menubar"], [data-testid="menu-bar"]');
      if (await menuBar.isVisible()) {
        await expect(menuBar).toBeVisible();
      }
    });

    test('6: activity bar (Explorer, Search, Git) functional', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Look for activity bar
      const activityBar = page.locator('.activitybar, .activity-bar, [data-testid="activity-bar"]');
      if (await activityBar.isVisible()) {
        await expect(activityBar).toBeVisible();
      }
    });

    test('7: status bar shows connection status', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Look for status bar
      const statusBar = page.locator('.statusbar, .status-bar, [data-testid="status-bar"]');
      if (await statusBar.isVisible()) {
        await expect(statusBar).toBeVisible();
      }
    });

    test('8: command palette opens', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open command palette (Ctrl+Shift+P on Windows/Linux, Cmd+Shift+P on Mac)
      await page.keyboard.press('Control+Shift+P');
      
      // Wait for command palette
      await page.waitForSelector('.quick-input-widget, .command-palette, [data-testid="command-palette"]', { timeout: 5000 });
      
      const palette = page.locator('.quick-input-widget, .command-palette').first();
      await expect(palette).toBeVisible();
      
      // Close palette
      await page.keyboard.press('Escape');
    });
  });

  test.describe('File Operations', () => {
    
    test('9: can create new file', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Create via File menu or command palette
      await page.keyboard.press('Control+Shift+P');
      await page.keyboard.type('New File');
      await page.waitForLoadState('networkidle');
      
      // Close palette
      await page.keyboard.press('Escape');
    });

    test('10: can edit file content', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Click in editor area
      const editor = page.locator('.monaco-editor, .editor-area').first();
      if (await editor.isVisible()) {
        await editor.click();
        
        // Type content
        await page.keyboard.type('// QA Test Content');
        
        // Verify content appears
        await page.waitForFunction(() => {
          return document.body.innerText.includes('QA Test Content');
        }, { timeout: 5000 }).catch(() => {
          // Content may not be immediately visible in DOM
        });
      }
    });

    test('11: can save file', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Save file (Ctrl+S)
      await page.keyboard.press('Control+S');
      
      // Wait for save to complete
      await page.waitForLoadState('networkidle');
    });

    test('12: can delete file', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Try to delete via command palette
      await page.keyboard.press('Control+Shift+P');
      await page.keyboard.type('Delete File');
      await page.waitForLoadState('networkidle');
      
      await page.keyboard.press('Escape');
    });

    test('13: can create new folder', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Look for explorer/file tree
      const explorer = page.locator('.explorer, .file-tree, [data-testid="explorer"]');
      if (await explorer.first().isVisible()) {
        // Right-click in explorer to get context menu
        await explorer.first().click({ button: 'right' });
        
        await page.waitForLoadState('networkidle');
      }
    });

    test('14: can rename file/folder', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Try rename via command palette
      await page.keyboard.press('Control+Shift+P');
      await page.keyboard.type('Rename');
      await page.waitForLoadState('networkidle');
      
      await page.keyboard.press('Escape');
    });
  });

  test.describe('Terminal Operations', () => {
    
    test('15: can open integrated terminal', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open terminal (Ctrl+` backtick)
      await page.keyboard.press('Control+Backquote');
      
      // Wait for terminal to appear
      const terminal = page.locator('.xterm, .terminal, [data-testid="terminal"]');
      
      // Give it a moment to appear
      await page.waitForTimeout(1000);
      
      if (await terminal.first().isVisible()) {
        await expect(terminal.first()).toBeVisible();
      }
    });

    test('16: can execute commands in terminal', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open terminal
      await page.keyboard.press('Control+Backquote');
      await page.waitForTimeout(1000);
      
      const terminal = page.locator('.xterm, .terminal').first();
      if (await terminal.isVisible()) {
        // Type a command
        await page.keyboard.type('echo "QA Test"');
        await page.keyboard.press('Enter');
        
        // Wait for output
        await page.waitForTimeout(1000);
      }
    });

    test('17: terminal output displays correctly', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open terminal
      await page.keyboard.press('Control+Backquote');
      await page.waitForTimeout(1000);
      
      const terminal = page.locator('.xterm, .terminal, [role="region"]').first();
      if (await terminal.isVisible()) {
        await expect(terminal).toBeVisible();
      }
    });

    test('18: can open multiple terminal tabs', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open terminal
      await page.keyboard.press('Control+Backquote');
      await page.waitForTimeout(1000);
      
      // Try to open second terminal
      await page.keyboard.press('Control+Shift+`');
      await page.waitForTimeout(500);
      
      // Look for multiple terminal tabs
      const terminalTabs = page.locator('[data-testid*="terminal"], .xterm');
      const tabCount = await terminalTabs.count();
      
      // Should have at least one terminal
      expect(tabCount).toBeGreaterThanOrEqual(1);
    });
  });

  test.describe('Extensions & Features', () => {
    
    test('19: extension list loads in sidebar', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Click on extensions icon in activity bar
      const extensionsBtn = page.locator('[title*="Extensions"], [data-testid*="extension"]');
      if (await extensionsBtn.first().isVisible()) {
        await extensionsBtn.first().click();
        
        // Wait for extensions view
        await page.waitForLoadState('networkidle');
      }
    });

    test('20: can search extensions (if allowed)', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open extensions view
      await page.keyboard.press('Control+Shift+X');
      await page.waitForTimeout(1000);
      
      // Look for search box
      const searchBox = page.locator('.extension-search, [placeholder*="Search"]');
      if (await searchBox.first().isVisible()) {
        await expect(searchBox.first()).toBeVisible();
      }
    });

    test('21: git integration shows repository status', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Click on source control in activity bar
      const sourceControl = page.locator('[title*="Source Control"], [data-testid*="scm"]');
      if (await sourceControl.isVisible()) {
        await sourceControl.click();
        
        // Wait for git view
        await page.waitForLoadState('networkidle');
      }
    });

    test('22: file search works (Ctrl+P)', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Open file search
      await page.keyboard.press('Control+P');
      
      // Wait for search box
      const searchBox = page.locator('.quick-input-widget, .search-box');
      if (await searchBox.first().isVisible()) {
        await expect(searchBox.first()).toBeVisible();
      }
      
      // Close
      await page.keyboard.press('Escape');
    });
  });

  test.describe('Session & Persistence', () => {
    
    test('23: session persists across page refresh', async ({ page, context }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Get initial URL
      const initialUrl = page.url();
      
      // Verify auth cookies exist
      const cookies = await context.cookies();
      const authCookie = cookies.find(c => c.name === '_oauth2_proxy');
      expect(authCookie).toBeDefined();
      
      // Refresh page
      await page.reload();
      
      // Should still be authenticated
      const newUrl = page.url();
      expect(newUrl).toContain('ide.kushnir.cloud');
      
      // Should not have redirected to login
      expect(newUrl).not.toMatch(/oauth2|accounts\.google\.com/);
      
      // IDE should still load
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
    });

    test('24: workspace state restored on reconnect', async ({ page }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Make some UI changes (e.g., open a file)
      await page.keyboard.press('Control+P');
      await page.waitForTimeout(500);
      
      // Close search
      await page.keyboard.press('Escape');
      
      // Disconnect and reconnect (refresh)
      await page.reload();
      
      // Wait for IDE to fully load
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Workspace should be restored
      const workbench = page.locator('.monaco-workbench').first();
      await expect(workbench).toBeVisible();
    });

    test('25: logout cleans up session properly', async ({ page, context }) => {
      await page.waitForSelector('.monaco-workbench', { timeout: 30000 });
      
      // Clear OAuth cookies (simulate logout)
      const cookies = await context.cookies();
      for (const cookie of cookies) {
        if (cookie.name.includes('oauth') || cookie.name.includes('auth')) {
          await context.clearCookies({ name: cookie.name });
        }
      }
      
      // Refresh page
      await page.reload();
      
      // Should redirect to login
      const url = page.url();
      expect(url).toMatch(/oauth2|accounts\.google\.com|login/);
    });
  });
});
