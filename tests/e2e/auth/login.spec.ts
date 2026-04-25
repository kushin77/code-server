// @file        tests/e2e/auth/login.spec.ts
// @module      testing/e2e/auth
// @description OAuth2 login flow and session persistence tests
// @governance  GOV-002
// Issue #1537

import { test, expect } from "@playwright/test";
import { isUrlReachable } from "../support/e2e-targets";

const BASE_URL = process.env.BASE_URL || "https://ide.kushnir.cloud";
const PORTAL_URL = process.env.PORTAL_URL || "https://kushnir.cloud";
const INTERACTIVE = process.env.INTERACTIVE_LOGIN === "1";

test.describe("OAuth2 Authentication", () => {
  test.beforeEach(async () => {
    const baseReachable = await isUrlReachable(BASE_URL);
    const portalReachable = await isUrlReachable(PORTAL_URL);

    if (!baseReachable || !portalReachable) {
      test.skip(
        true,
        `External auth targets are not reachable (${BASE_URL}, ${PORTAL_URL}); set BASE_URL/PORTAL_URL to a live deployment to run this suite.`
      );
    }
  });

  test("homepage redirects unauthenticated users to oauth2/sign_in", async ({
    page,
  }) => {
    await page.goto(BASE_URL);
    // oauth2-proxy should redirect to sign-in
    await expect(page).toHaveURL(/oauth2\/sign_in|accounts\.google\.com/);
  });

  test("portal redirects unauthenticated users to oauth2/sign_in", async ({
    page,
  }) => {
    await page.goto(PORTAL_URL);
    await expect(page).toHaveURL(/oauth2\/sign_in|accounts\.google\.com/);
  });

  test("sign-in page has Google OAuth button", async ({ page }) => {
    await page.goto(`${BASE_URL}/oauth2/sign_in`);
    const signinButton = page.locator(
      '[data-testid="google-signin"], a[href*="google"], .btn-google, input[type=submit]'
    );
    await expect(signinButton.first()).toBeVisible({ timeout: 10_000 });
  });

  test("oauth2-proxy health endpoint responds", async ({ request }) => {
    const resp = await request.get(`${BASE_URL}/oauth2/ping`);
    expect(resp.status()).toBe(200);
  });

  test(
    "interactive: complete OAuth2 login flow (manual)",
    async ({ page }) => {
      test.skip(!INTERACTIVE, "Set INTERACTIVE_LOGIN=1 to run this test");

      await page.goto(`${BASE_URL}/oauth2/sign_in`);
      console.log(`[auth] Opened: ${BASE_URL}/oauth2/sign_in`);
      console.log("[auth] Please complete the Google OAuth login in the browser.");
      console.log("[auth] Test will wait up to 5 minutes for completion...");

      // Wait for redirect back to IDE after manual login
      await page.waitForURL(`${BASE_URL}/**`, { timeout: 5 * 60 * 1000 });

      // Verify IDE loaded
      await expect(page).toHaveURL(new RegExp(BASE_URL.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
      console.log("[auth] ✓ OAuth2 login completed successfully");
    }
  );
});
