import { test, expect } from '@playwright/test';
const waitMs = Number(process.env.FAILOVER_WAIT_MS || '45000');
test('unauthenticated continuity across failover window', async ({ page }) => {
    const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
    expect(response).not.toBeNull();
    expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(response?.status() || 0);
    expect(page.url()).toMatch(/kushnir\.cloud/);
    await page.waitForTimeout(waitMs);
    const reloadResponse = await page.reload({ waitUntil: 'domcontentloaded' });
    expect(reloadResponse).not.toBeNull();
    expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(reloadResponse?.status() || 0);
    expect(page.url()).toMatch(/kushnir\.cloud/);
});
//# sourceMappingURL=failover-session-continuity.spec.js.map