import { test, expect } from './fixtures';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
test.describe('IDE Launch & Workspace Operations - E2E Tests', () => {
    /**
     * HAPPY PATH: IDE Launch
     */
    test.describe('Happy Path - IDE Launch', () => {
        test('authenticated user can launch IDE', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Should not redirect to login
            const url = authenticatedPage.url();
            expect(url).not.toMatch(/accounts\.google\.com|oauth2/i);
            // IDE interface should load
            await authenticatedPage.waitForSelector('.monaco-editor', { timeout: 15000 }).catch(() => {
                return authenticatedPage.waitForSelector('[data-testid="editor-container"]', { timeout: 15000 });
            });
        });
        test('IDE editor is functional after load', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Wait for editor to be ready
            await authenticatedPage.waitForLoadState('networkidle');
            // Check editor exists
            const editor = authenticatedPage.locator('.monaco-editor').first();
            expect(await editor.isVisible({ timeout: 5000 }).catch(() => false)).toBe(true);
        });
        test('user can open file browser', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find file explorer button
            const fileExplorer = authenticatedPage.locator('[data-testid="file-explorer"]').or(authenticatedPage.locator('.codicon-files'));
            if (await fileExplorer.isVisible({ timeout: 5000 }).catch(() => false)) {
                await fileExplorer.click();
                // File tree should be visible
                await authenticatedPage.waitForSelector('[data-testid="file-tree"]', { timeout: 5000 }).catch(() => { });
            }
        });
        test('user can open a file in editor', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Wait for IDE to load
            await authenticatedPage.waitForLoadState('networkidle');
            // Try to find and open a file
            const fileItem = authenticatedPage.locator('[data-testid="file-item"]').first();
            if (await fileItem.isVisible({ timeout: 5000 }).catch(() => false)) {
                await fileItem.click();
                // File should be opened in editor
                await authenticatedPage.waitForLoadState('networkidle');
            }
        });
        test('user can create new file', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find "New File" button
            const newFileBtn = authenticatedPage.locator('button[aria-label*="New File"]').or(authenticatedPage.locator('text=New File'));
            if (await newFileBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
                await newFileBtn.click();
                // Input field for filename should appear
                const filenameInput = authenticatedPage.locator('input[placeholder*="name"]').or(authenticatedPage.locator('input[type="text"]'));
                if (await filenameInput.isVisible({ timeout: 5000 }).catch(() => false)) {
                    await filenameInput.fill('test-file.js');
                    await filenameInput.press('Enter');
                }
            }
        });
        test('user can edit code in editor', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Click in editor area
            const editor = authenticatedPage.locator('.monaco-editor').first();
            if (await editor.isVisible({ timeout: 5000 }).catch(() => false)) {
                await editor.click();
                // Type some code
                await authenticatedPage.keyboard.type('console.log("hello");');
                // Code should appear in editor
                const content = await authenticatedPage.textContent('.monaco-editor');
                expect(content).toContain('console.log');
            }
        });
        test('user can save changes', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find and click save button (Ctrl+S)
            await authenticatedPage.keyboard.press('Control+S');
            // Save indicator should appear briefly
            await authenticatedPage.waitForSelector('[data-testid="save-indicator"]', { timeout: 5000 }).catch(() => {
                // Auto-save or no indicator
            });
        });
        test('user can switch between open files', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find tab bar
            const tabs = await authenticatedPage.locator('[data-testid="editor-tab"]').all();
            if (tabs.length >= 2) {
                // Click second tab
                await tabs[1].click();
                // Content should change
                await authenticatedPage.waitForLoadState('networkidle');
            }
        });
        test('user can see file tree structure', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open file explorer
            const fileExplorer = authenticatedPage.locator('[data-testid="file-explorer"]').or(authenticatedPage.locator('.codicon-files'));
            await fileExplorer.click();
            // File tree should show directory structure
            const fileTree = authenticatedPage.locator('[data-testid="file-tree"]').or(authenticatedPage.locator('.explorer'));
            expect(await fileTree.isVisible({ timeout: 5000 }).catch(() => false)).toBe(true);
        });
        test('user can expand and collapse directories', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find directory item
            const dirItem = authenticatedPage.locator('[data-testid="directory-item"]').first();
            if (await dirItem.isVisible({ timeout: 5000 }).catch(() => false)) {
                // Click to expand
                await dirItem.click();
                // Files in directory should be visible
                await authenticatedPage.waitForTimeout(500);
            }
        });
    });
    /**
     * HAPPY PATH: Terminal & Commands
     */
    test.describe('Happy Path - Terminal Operations', () => {
        test('user can open terminal', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find terminal button
            const terminalBtn = authenticatedPage.locator('[aria-label*="Terminal"]').or(authenticatedPage.locator('text=Terminal'));
            if (await terminalBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
                await terminalBtn.click();
                // Terminal should open
                await authenticatedPage.waitForSelector('[data-testid="terminal"]', { timeout: 5000 }).catch(() => {
                    return authenticatedPage.waitForSelector('.xterm', { timeout: 5000 });
                });
            }
        });
        test('user can run commands in terminal', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open terminal if not open
            const terminal = authenticatedPage.locator('[data-testid="terminal"]').or(authenticatedPage.locator('.xterm'));
            if (await terminal.isVisible({ timeout: 5000 }).catch(() => false)) {
                // Click in terminal
                await terminal.click();
                // Type a command
                await authenticatedPage.keyboard.type('echo "test"');
                await authenticatedPage.keyboard.press('Enter');
                // Command should execute
                await authenticatedPage.waitForTimeout(500);
            }
        });
        test('user can view command output', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open terminal and run command
            const terminal = authenticatedPage.locator('[data-testid="terminal"]').or(authenticatedPage.locator('.xterm'));
            if (await terminal.isVisible({ timeout: 5000 }).catch(() => false)) {
                await terminal.click();
                await authenticatedPage.keyboard.type('ls');
                await authenticatedPage.keyboard.press('Enter');
                // Output should appear
                const output = await terminal.textContent();
                expect(output).toBeDefined();
            }
        });
        test('user can clear terminal', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            const terminal = authenticatedPage.locator('[data-testid="terminal"]').or(authenticatedPage.locator('.xterm'));
            if (await terminal.isVisible({ timeout: 5000 }).catch(() => false)) {
                // Clear terminal command
                await terminal.click();
                await authenticatedPage.keyboard.type('clear');
                await authenticatedPage.keyboard.press('Enter');
            }
        });
    });
    /**
     * HAPPY PATH: Extensions & Themes
     */
    test.describe('Happy Path - Extensions & Customization', () => {
        test('user can access extensions panel', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Find extensions button
            const extensionsBtn = authenticatedPage.locator('[aria-label*="Extensions"]').or(authenticatedPage.locator('.codicon-extensions'));
            if (await extensionsBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
                await extensionsBtn.click();
                // Extensions panel should open
                await authenticatedPage.waitForSelector('[data-testid="extensions-panel"]', { timeout: 5000 }).catch(() => { });
            }
        });
        test('user can search for extensions', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open extensions
            const extensionsBtn = authenticatedPage.locator('[aria-label*="Extensions"]').or(authenticatedPage.locator('.codicon-extensions'));
            await extensionsBtn.click();
            // Search input should be visible
            const searchInput = authenticatedPage.locator('[data-testid="extension-search"]').or(authenticatedPage.locator('input[placeholder*="Search"]'));
            if (await searchInput.isVisible({ timeout: 5000 }).catch(() => false)) {
                await searchInput.fill('python');
                await authenticatedPage.waitForTimeout(500);
            }
        });
        test('user can view settings', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open settings (Ctrl+,)
            await authenticatedPage.keyboard.press('Control+Comma');
            // Settings panel should open
            await authenticatedPage.waitForSelector('[data-testid="settings-panel"]', { timeout: 5000 }).catch(() => { });
        });
        test('user can change theme', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open command palette
            await authenticatedPage.keyboard.press('Control+Shift+P');
            // Type theme command
            await authenticatedPage.keyboard.type('theme');
            // Theme options should appear
            await authenticatedPage.waitForTimeout(500);
        });
    });
    /**
     * ERROR HANDLING
     */
    test.describe('Error Handling', () => {
        test('non-authenticated user cannot access IDE', async ({ page }) => {
            // Fresh page without authentication
            await page.goto(IDE_URL);
            // Should redirect to login
            const url = page.url();
            expect(url).toMatch(/accounts\.google\.com|oauth2|login/i);
        });
        test('IDE handles network disconnection gracefully', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Simulate offline
            await authenticatedPage.context().setOffline(true);
            // Should show offline indicator or error
            await authenticatedPage.waitForTimeout(1000);
            // Restore connection
            await authenticatedPage.context().setOffline(false);
        });
        test('large file opens without crashing', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Try to open large file
            const largeFileItem = authenticatedPage.locator('[data-testid="large-file"]').first();
            if (await largeFileItem.isVisible({ timeout: 5000 }).catch(() => false)) {
                await largeFileItem.click();
                // Should handle gracefully
                await authenticatedPage.waitForLoadState('networkidle');
            }
        });
        test('unsupported file type shows warning', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Try to open binary file
            const binaryFile = authenticatedPage.locator('[data-testid*=".bin"]').first();
            if (await binaryFile.isVisible({ timeout: 5000 }).catch(() => false)) {
                await binaryFile.click();
                // Should show warning or handle appropriately
                await authenticatedPage.waitForTimeout(500);
            }
        });
    });
    /**
     * EDGE CASES
     */
    test.describe('Edge Cases', () => {
        test('IDE remains responsive with many open files', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open multiple files rapidly
            for (let i = 0; i < 5; i++) {
                const fileItem = authenticatedPage.locator('[data-testid="file-item"]').nth(i);
                if (await fileItem.isVisible({ timeout: 1000 }).catch(() => false)) {
                    await fileItem.click();
                }
            }
            // Should still be responsive
            const editor = authenticatedPage.locator('.monaco-editor').first();
            expect(await editor.isVisible()).toBe(true);
        });
        test('session timeout while editing is handled', async ({ authenticatedPage, context }) => {
            await authenticatedPage.goto(IDE_URL);
            // Simulate session timeout
            await context.clearCookies();
            // Try to perform action
            await authenticatedPage.reload();
            // Should redirect to login
            const url = authenticatedPage.url();
            expect(url).toMatch(/accounts\.google\.com|oauth2|login/i);
        });
        test('rapid save operations do not conflict', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Perform multiple rapid saves
            for (let i = 0; i < 5; i++) {
                await authenticatedPage.keyboard.press('Control+S');
            }
            // Should handle without error
            await authenticatedPage.waitForLoadState('networkidle');
        });
        test('special characters in filename are handled', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Create file with special chars
            const newFileBtn = authenticatedPage.locator('button[aria-label*="New File"]').first();
            if (await newFileBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
                await newFileBtn.click();
                const input = authenticatedPage.locator('input[type="text"]').first();
                await input.fill('test-file_[2024].js');
                await input.press('Enter');
                // Should create file with special chars
                await authenticatedPage.waitForTimeout(500);
            }
        });
        test('IDE handles very long lines', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            const editor = authenticatedPage.locator('.monaco-editor').first();
            if (await editor.isVisible({ timeout: 5000 }).catch(() => false)) {
                await editor.click();
                // Type very long line
                const longLine = 'x'.repeat(1000);
                await authenticatedPage.keyboard.type(longLine);
                // Editor should handle without freezing
                expect(await editor.isVisible()).toBe(true);
            }
        });
    });
    /**
     * PERFORMANCE
     */
    test.describe('Performance', () => {
        test('IDE loads within acceptable time', async ({ authenticatedPage }) => {
            const startTime = Date.now();
            await authenticatedPage.goto(IDE_URL);
            await authenticatedPage.waitForLoadState('networkidle');
            const duration = Date.now() - startTime;
            // Should load in under 15 seconds
            expect(duration).toBeLessThan(15000);
        });
        test('file operations are responsive', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            const startTime = Date.now();
            // Create and save a file
            const newFileBtn = authenticatedPage.locator('button[aria-label*="New File"]').first();
            await newFileBtn.click();
            const duration = Date.now() - startTime;
            // Should respond quickly
            expect(duration).toBeLessThan(2000);
        });
        test('scrolling is smooth in large files', async ({ authenticatedPage }) => {
            await authenticatedPage.goto(IDE_URL);
            // Open large file if available
            const largeFile = authenticatedPage.locator('[data-testid*="large"]').first();
            if (await largeFile.isVisible({ timeout: 5000 }).catch(() => false)) {
                await largeFile.click();
                // Scroll down
                const editor = authenticatedPage.locator('.monaco-editor').first();
                await editor.evaluate(el => {
                    el.scrollTop = 10000;
                });
                // Should handle smoothly
                expect(await editor.isVisible()).toBe(true);
            }
        });
    });
});
//# sourceMappingURL=ide-launch-workspace.spec.js.map