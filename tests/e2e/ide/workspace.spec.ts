// @file        tests/e2e/ide/workspace.spec.ts
// @module      testing/e2e/ide
// @description IDE workspace E2E flows: file ops, terminal, git, extensions
// @governance  GOV-002
// Issue #1537

import { test, expect } from "@playwright/test";
import * as path from "path";

const BASE_URL = process.env.BASE_URL || "https://ide.kushnir.cloud";

test.describe("VS Code IDE Workspace", () => {
  test.use({
    storageState: path.join(__dirname, "../auth/qa-session.json"),
  });

  test.beforeEach(async ({ page }) => {
    // Navigate to IDE and wait for it to load
    await page.goto(BASE_URL);
    // Wait for VS Code web workbench to initialize
    await page.waitForSelector(".monaco-workbench", { timeout: 30_000 });
  });

  test("IDE loads and workbench is visible", async ({ page }) => {
    const workbench = page.locator(".monaco-workbench");
    await expect(workbench).toBeVisible();
    await expect(page).toHaveTitle(/Visual Studio Code|code-server/i);
  });

  test("activity bar is visible with core icons", async ({ page }) => {
    const activityBar = page.locator(".activitybar");
    await expect(activityBar).toBeVisible();

    // Explorer, Search, Source Control, Extensions icons
    const explorerBtn = page.locator('[aria-label*="Explorer"]');
    await expect(explorerBtn.first()).toBeVisible({ timeout: 10_000 });
  });

  test("open integrated terminal and run command", async ({ page }) => {
    // Open terminal: Ctrl+`
    await page.keyboard.press("Control+Backquote");
    await page.waitForSelector(".terminal-wrapper, .integrated-terminal", {
      timeout: 15_000,
    });

    // Wait for terminal to be ready
    const terminal = page.locator(".xterm-screen").first();
    await expect(terminal).toBeVisible({ timeout: 15_000 });

    // Type echo command
    await terminal.click();
    await page.keyboard.type("echo 'e2e-test-$(date +%s)'");
    await page.keyboard.press("Enter");

    // Verify output appears (loosely match e2e-test- prefix)
    await expect(
      page.locator(".xterm-rows").last()
    ).toContainText("e2e-test-", { timeout: 10_000 });
  });

  test("create a new file from explorer", async ({ page }) => {
    // Open Explorer
    await page.click('[aria-label*="Explorer"]');
    await page.waitForSelector(".explorer-viewlet", { timeout: 10_000 });

    // New File button in Explorer
    const newFileBtn = page.locator('[aria-label="New File"]').first();
    if (await newFileBtn.isVisible()) {
      await newFileBtn.click();

      // Type filename
      const testFileName = `e2e-test-${Date.now()}.txt`;
      await page.keyboard.type(testFileName);
      await page.keyboard.press("Enter");

      // File tab should appear
      await expect(
        page.locator(`.tab[aria-label*="${testFileName}"]`)
      ).toBeVisible({ timeout: 10_000 });
    }
  });

  test("settings page opens via command palette", async ({ page }) => {
    // Open command palette
    await page.keyboard.press("Control+Shift+P");
    await page.waitForSelector(".quick-input-widget", { timeout: 10_000 });

    // Type to open settings
    await page.keyboard.type("Open User Settings");
    await page.keyboard.press("Enter");

    // Settings editor should appear
    await expect(
      page.locator('[aria-label*="Settings"], .settings-editor')
    ).toBeVisible({ timeout: 15_000 });
  });

  test("extension marketplace opens", async ({ page }) => {
    // Click Extensions icon in activity bar
    const extensionsBtn = page.locator('[aria-label*="Extensions"]').first();
    await extensionsBtn.click();

    // Extensions view should load
    await expect(
      page.locator(".extensions-viewlet, .extension-editor")
    ).toBeVisible({ timeout: 15_000 });

    // Search box should be visible
    const searchBox = page.locator(
      '.extensions-viewlet input[placeholder*="Search"]'
    );
    await expect(searchBox).toBeVisible({ timeout: 10_000 });
  });

  test("session persists after page reload", async ({ page }) => {
    // Record current URL
    const urlBefore = page.url();

    // Reload
    await page.reload();
    await page.waitForSelector(".monaco-workbench", { timeout: 30_000 });

    // Should still be authenticated (no redirect to sign_in)
    expect(page.url()).not.toMatch(/sign_in|accounts\.google\.com/);
    await expect(page.locator(".monaco-workbench")).toBeVisible();
  });
});
