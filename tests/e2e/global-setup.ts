// @file        tests/e2e/global-setup.ts
// @module      testing/e2e
// @description Global setup: VPN check + auth session bootstrapping
// @governance  GOV-002
// Issue #1537

import { chromium, FullConfig } from "@playwright/test";
import { execSync } from "child_process";

async function globalSetup(config: FullConfig) {
  const requireVpn = process.env.REQUIRE_VPN === "1";
  const baseUrl = process.env.BASE_URL || "https://ide.kushnir.cloud";
  const qaEmail = process.env.QA_EMAIL || "qa@kushnir.cloud";
  const qaPassword = process.env.QA_PASSWORD || "";
  const primaryHost = process.env.PRIMARY_HOST;

  // ── VPN connectivity check ───────────────────────────────────────────────
  if (requireVpn) {
    if (!primaryHost) {
      throw new Error("[setup] PRIMARY_HOST must be set for VPN connectivity checks.");
    }

    console.log("[setup] Verifying VPN connectivity...");
    try {
      execSync(`ping -c 1 ${primaryHost}`, { stdio: "pipe" });
      console.log(`[setup] ✓ VPN active — ${primaryHost} reachable`);
    } catch {
      throw new Error(
        `[setup] VPN check FAILED. REQUIRE_VPN=1 but ${primaryHost} unreachable. ` +
          "Connect to WireGuard VPN before running E2E tests."
      );
    }
  }

  // ── QA auth session creation ──────────────────────────────────────────────
  // Only bootstrap session if QA_PASSWORD is set (skip in manual/interactive mode)
  if (!qaPassword) {
    console.log(
      "[setup] QA_PASSWORD not set — skipping automated auth session creation."
    );
    console.log(
      "[setup] Run `INTERACTIVE_LOGIN=1 playwright test auth/login.spec.ts` for manual login."
    );
    return;
  }

  const browser = await chromium.launch();
  const context = await browser.newContext({
    ignoreHTTPSErrors: process.env.IGNORE_SSL === "1",
  });
  const page = await context.newPage();

  try {
    console.log(`[setup] Bootstrapping QA session for ${qaEmail}...`);
    await page.goto(`${baseUrl}/oauth2/sign_in`);

    // oauth2-proxy sign-in page
    await page.waitForSelector('[data-testid="google-signin"]', { timeout: 10_000 });
    await page.click('[data-testid="google-signin"]');

    // Google OAuth form (will only work with real credentials)
    await page.fill('input[type="email"]', qaEmail);
    await page.click("#identifierNext");
    await page.fill('input[type="password"]', qaPassword);
    await page.click("#passwordNext");

    // Wait for redirect back to IDE
    await page.waitForURL(`${baseUrl}/**`, { timeout: 30_000 });

    // Persist session state
    await context.storageState({ path: "auth/qa-session.json" });
    console.log("[setup] ✓ QA session saved to auth/qa-session.json");
  } finally {
    await browser.close();
  }
}

export default globalSetup;
