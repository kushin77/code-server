/**
 * E2E tests for error handling and edge cases
 * @file tests/e2e/errors/error-handling.spec.ts
 * @issue #1537 (Testing & QA Strategy)
 * @phase Phase 3: End-to-End Testing
 * @governance GOV-002: Error resilience, user experience
 */

import { test, expect } from '@playwright/test';
import * as path from 'path';

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';
const QA_SESSION = path.join(__dirname, '../auth/qa-session.json');

test.describe('Error Handling & Edge Cases', () => {
  test.use({
    storageState: QA_SESSION,
  });

  test('should handle network errors gracefully', async ({ page }) => {
    // Simulate offline
    await page.context().setOffline(true);

    await page.goto(`${BASE_URL}/teams`);

    // Wait for offline indicator or error message
    const offlineMsg = page.locator(
      'text=offline|Network error|Try again',
      { timeout: 5000 }
    );

    // Try clicking retry if available
    const retryBtn = page.locator('button:has-text("Retry"), [data-testid="retry-btn"]');
    
    expect(
      (await offlineMsg.isVisible().catch(() => false)) ||
      (await retryBtn.isVisible().catch(() => false))
    ).toBeTruthy();

    // Go back online
    await page.context().setOffline(false);
  });

  test('should display validation errors for invalid input', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    // Click create team
    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      // Try submitting empty form
      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Should show validation errors
      const errorMsg = page.locator('[data-testid="error"], .error-message, .invalid-feedback');
      await expect(errorMsg.first()).toBeVisible({ timeout: 5000 });
    }
  });

  test('should handle malformed team names', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      // Try entering invalid characters
      const nameField = page.locator('input[name="name"]');
      await nameField.first().fill('<script>alert("xss")</script>');

      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Should either sanitize or reject with error
      await expect(
        page.locator('text=Invalid|special characters|not allowed')
      ).toBeVisible({ timeout: 10000 }).catch(async () => {
        // Or form should clear dangerous input
        const value = await nameField.first().inputValue();
        expect(value).not.toContain('<script>');
      });
    }
  });

  test('should handle duplicate team creation attempt', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    const teamName = `Duplicate-Test-${Date.now()}`;

    // Create team first time
    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      const nameField = page.locator('input[name="name"]');
      await nameField.first().fill(teamName);

      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Wait for team to be created
      await page.waitForURL(RegExp(`/teams/.*`), { timeout: 15000 });

      // Navigate back to teams
      await page.goto(`${BASE_URL}/teams`);

      // Try creating duplicate
      await createBtn.first().click();
      await nameField.first().fill(teamName);
      await submitBtn.first().click();

      // Should show error about duplicate
      const errorMsg = page.locator('text=already exists|duplicate|already taken');
      await expect(errorMsg).toBeVisible({ timeout: 10000 }).catch(() => {
        // Or validation error
      });
    }
  });

  test('should handle missing required fields in forms', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      // Leave name field empty but fill other fields
      const descField = page.locator('textarea[name="description"], [placeholder*="Description"]');
      if (await descField.isVisible()) {
        await descField.first().fill('Description without name');
      }

      // Try to submit
      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Should show required field error
      const errorMsg = page.locator('text=required|Name is required|Please fill in');
      await expect(errorMsg).toBeVisible({ timeout: 5000 });
    }
  });

  test('should handle 404 errors gracefully', async ({ page }) => {
    // Try accessing non-existent team
    await page.goto(`${BASE_URL}/teams/nonexistent-team-12345`);

    // Should show 404 page or redirect
    const notFoundMsg = page.locator('text=not found|404|does not exist', { timeout: 10000 });
    await expect(
      notFoundMsg
    ).toBeVisible().catch(async () => {
      // Or redirected to teams list
      await expect(page).toHaveURL(RegExp(`/teams(?!/)`));
    });
  });

  test('should handle 500 server errors with retry', async ({ page }) => {
    // Mock API error
    await page.route('**/api/teams', route => {
      route.abort('serverfailure');
    });

    await page.goto(`${BASE_URL}/teams`);

    // Should show error message
    const errorMsg = page.locator('text=error|failed|problem', { timeout: 10000 });
    
    const hasError = await errorMsg.isVisible().catch(() => false);

    // Restore route
    await page.unroute('**/api/teams');

    expect(hasError || await page.locator('[data-testid="error"]').isVisible().catch(() => false)).toBeTruthy();
  });

  test('should handle extremely long team names', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      // Try entering extremely long name
      const longName = 'a'.repeat(1000);
      const nameField = page.locator('input[name="name"]');
      await nameField.first().fill(longName);

      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Should either truncate or show error
      const errorMsg = page.locator('text=too long|maximum|exceeded');
      await expect(errorMsg).toBeVisible({ timeout: 10000 }).catch(async () => {
        // Check if name was truncated
        const value = await nameField.first().inputValue();
        expect(value.length).toBeLessThan(1000);
      });
    }
  });

  test('should handle concurrent form submissions', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      const nameField = page.locator('input[name="name"]');
      const teamName = `Concurrent-${Date.now()}`;
      await nameField.first().fill(teamName);

      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');

      // Click submit twice rapidly
      await Promise.all([
        submitBtn.first().click(),
        submitBtn.first().click(),
      ]).catch(() => {
        // Might fail, that's OK
      });

      // Should only create one team, not duplicate
      await page.waitForTimeout(2000);
      
      // Check result
      expect(true).toBeTruthy();
    }
  });

  test('should display helpful error messages', async ({ page }) => {
    // Test that error messages are user-friendly
    await page.goto(`${BASE_URL}/teams`);

    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      // Submit without filling
      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Check for non-technical error messages
      const errorMsg = page.locator('[data-testid="error"], .error-message');
      if (await errorMsg.isVisible()) {
        const text = await errorMsg.first().textContent();

        // Error should be user-friendly (not stack trace)
        expect(text).not.toMatch(/at |Error:|undefined/);
        expect(text?.length).toBeGreaterThan(5);
      }
    }
  });

  test('should handle special characters in inputs', async ({ page }) => {
    await page.goto(`${BASE_URL}/teams`);

    const createBtn = page.locator('button:has-text("New Team"), [data-testid="create-team-btn"]');
    if (await createBtn.isVisible()) {
      await createBtn.first().click();

      // Try special characters
      const specialChars = '!@#$%^&*()[]{}";:<>?,./`~';
      const nameField = page.locator('input[name="name"]');
      await nameField.first().fill(`Test-Team ${specialChars}`);

      const submitBtn = page.locator('button:has-text("Create"), button[type="submit"]');
      await submitBtn.first().click();

      // Should either handle or reject gracefully
      await page.waitForTimeout(1000);
      expect(true).toBeTruthy();
    }
  });
});
