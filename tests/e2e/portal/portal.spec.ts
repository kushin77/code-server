// @file        tests/e2e/portal/portal.spec.ts
// @module      testing/e2e/portal
// @description Portal landing page and authenticated navigation tests
// @governance  GOV-002
// Issue #1545

import { test, expect } from "@playwright/test";
import { isUrlReachable, resolveQaSessionState } from "../support/e2e-targets";

const PORTAL_URL = process.env.PORTAL_URL || "https://kushnir.cloud";
const IDE_URL = process.env.IDE_URL || "https://ide.kushnir.cloud";
const QA_SESSION_STATE = resolveQaSessionState();

test.describe("Kushnir Cloud Portal", () => {
  test.use(QA_SESSION_STATE ? { storageState: QA_SESSION_STATE } : {});

  test.beforeEach(async () => {
    if (!QA_SESSION_STATE) {
      test.skip(
        true,
        "auth/qa-session.json is missing; create a QA session to run authenticated portal tests."
      );
    }

    if (!(await isUrlReachable(PORTAL_URL))) {
      test.skip(
        true,
        `Portal target is not reachable at ${PORTAL_URL}; set PORTAL_URL to a live deployment to run this suite.`
      );
    }
  });

  test("portal dashboard renders with enterprise navigation", async ({ page }) => {
    await page.goto(PORTAL_URL);

    await expect(page).toHaveURL(/kushnir\.cloud/);
    await expect(page.getByRole("heading", { name: /Dashboard|Kushnir Cloud Portal/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /Open IDE/i })).toHaveAttribute("href", IDE_URL);
    await expect(page.getByRole("link", { name: /Documentation/i })).toHaveAttribute("href", "/docs");
    await expect(page.getByRole("link", { name: /Repositories/i })).toHaveAttribute("href", "/repos");
  });

  test("portal subroutes render their section copy", async ({ page }) => {
    const routes = [
      ["/dashboard", /Dashboard/],
      ["/repos", /Repository Management/],
      ["/settings", /Settings & Identity/],
      ["/docs", /Documentation Hub/],
    ] as const;

    for (const [route, heading] of routes) {
      await page.goto(`${PORTAL_URL}${route}`);
      await expect(page.getByRole("heading", { name: heading })).toBeVisible();
    }
  });
});