import { appendFileSync, mkdirSync } from 'fs';
import { dirname } from 'path';
import { test, expect } from '@playwright/test';

const PORTAL_BASE_URL = process.env.PORTAL_BASE_URL || process.env.TEST_BASE_URL || 'https://kushnir.cloud';
const IDE_BASE_URL = process.env.IDE_BASE_URL || process.env.TEST_BASE_URL || 'https://ide.kushnir.cloud';
const AUTH_STORAGE_STATE = process.env.PLAYWRIGHT_STORAGE_STATE || '';
const METRICS_FILE = process.env.SYNTHETIC_METRICS_FILE || '';

test.describe.configure({ mode: 'serial' });

if (METRICS_FILE) {
  mkdirSync(dirname(METRICS_FILE), { recursive: true });
}

function labelsToString(labels: Record<string, string>): string {
  const entries = Object.entries(labels)
    .map(([key, value]) => `${key}="${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`)
    .join(',');

  return entries ? `{${entries}}` : '';
}

function writeMetric(metricName: string, value: number, labels: Record<string, string>): void {
  if (!METRICS_FILE) {
    return;
  }

  appendFileSync(METRICS_FILE, `${metricName}${labelsToString(labels)} ${value}\n`, 'utf8');
}

async function runScenario(name: string, scenario: () => Promise<void>): Promise<void> {
  const startedAt = Date.now();

  try {
    await scenario();
    writeMetric('synthetic_check_duration_ms', Date.now() - startedAt, { scenario: name, status: 'success' });
    writeMetric('synthetic_check_success', 1, { scenario: name });
    writeMetric('synthetic_check_failure_total', 0, { scenario: name });
  } catch (error) {
    writeMetric('synthetic_check_duration_ms', Date.now() - startedAt, { scenario: name, status: 'failure' });
    writeMetric('synthetic_check_success', 0, { scenario: name });
    writeMetric('synthetic_check_failure_total', 1, { scenario: name });
    throw error;
  }
}

test.describe('Collaboration Synthetic Monitor', () => {
  test('portal landing page exposes IDE launch surface', async ({ page }) => {
    await runScenario('portal_launch', async () => {
      const response = await page.goto(PORTAL_BASE_URL, { waitUntil: 'domcontentloaded' });
      expect(response).not.toBeNull();
      expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(response?.status() || 0);
      expect(page.url()).toContain('kushnir.cloud');

      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"], a:has-text("IDE")');
      await expect(ideLink.first()).toBeVisible();
    });
  });

  test('launching IDE from portal reaches the workbench shell', async ({ page }) => {
    await runScenario('portal_to_ide_launch', async () => {
      await page.goto(PORTAL_BASE_URL, { waitUntil: 'domcontentloaded' });

      const ideLink = page.locator('a[href*="ide"], [data-testid="ide-launch"], a:has-text("IDE")').first();
      await expect(ideLink).toBeVisible();
      const href = await ideLink.getAttribute('href');
      expect(href).toBeTruthy();

      const destination = new URL(href!, PORTAL_BASE_URL).toString();
      await page.goto(destination, { waitUntil: 'domcontentloaded' });
      expect(page.url()).toContain('kushnir.cloud');
    });
  });

  test('direct IDE access remains on the IDE host across reloads', async ({ page }) => {
    await runScenario('ide_reload_continuity', async () => {
      const response = await page.goto(IDE_BASE_URL, { waitUntil: 'domcontentloaded' });
      expect(response).not.toBeNull();
      expect([200, 301, 302, 303, 307, 308, 401, 403]).toContain(response?.status() || 0);
      expect(page.url()).toContain('kushnir.cloud');

      await page.reload({ waitUntil: 'domcontentloaded' });
      expect(page.url()).toContain('kushnir.cloud');
    });
  });

  test('authenticated IDE context survives a reload when storage state is available', async ({ browser }) => {
    test.skip(!AUTH_STORAGE_STATE, 'PLAYWRIGHT_STORAGE_STATE is required for the authenticated continuity path');

    await runScenario('authenticated_ide_continuity', async () => {
      const context = await browser.newContext({ storageState: AUTH_STORAGE_STATE });
      const page = await context.newPage();

      await page.goto(IDE_BASE_URL, { waitUntil: 'domcontentloaded' });
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);

      await page.reload({ waitUntil: 'domcontentloaded' });
      expect(page.url()).not.toMatch(/oauth2|accounts\.google\.com/);

      await context.close();
    });
  });

  test('voice session creation returns a token and session payload', async ({ request }) => {
    await runScenario('voice_session_create', async () => {
      const response = await request.post(new URL('/api/voice/sessions', IDE_BASE_URL).toString(), {
        data: { workspaceId: 'synthetic-monitor-workspace' },
      });

      expect(response.ok()).toBeTruthy();
      const body = await response.json();
      expect(body.session.sessionId).toBeTruthy();
      expect(body.token).toBeTruthy();
      expect(body.liveKitUrl).toBeTruthy();
    });
  });

  test('voice session join, metrics update, and leave succeed', async ({ request }) => {
    await runScenario('voice_session_join_leave', async () => {
      const createdResponse = await request.post(new URL('/api/voice/sessions', IDE_BASE_URL).toString(), {
        data: { workspaceId: 'synthetic-monitor-workspace' },
      });
      expect(createdResponse.ok()).toBeTruthy();

      const createdBody = await createdResponse.json();
      const sessionId = createdBody.session.sessionId as string;

      const joinResponse = await request.post(new URL(`/api/voice/sessions/${sessionId}/join`, IDE_BASE_URL).toString());
      expect(joinResponse.ok()).toBeTruthy();

      const metricsResponse = await request.post(new URL(`/api/voice/sessions/${sessionId}/metrics`, IDE_BASE_URL).toString(), {
        data: { userId: createdBody.session.userId, latencyMs: 42, audioQualityScore: 96 },
      });
      expect(metricsResponse.ok()).toBeTruthy();

      const leaveResponse = await request.post(new URL(`/api/voice/sessions/${sessionId}/leave`, IDE_BASE_URL).toString());
      expect(leaveResponse.ok()).toBeTruthy();

      const statsResponse = await request.get(new URL('/api/voice/stats', IDE_BASE_URL).toString());
      expect(statsResponse.ok()).toBeTruthy();
    });
  });

  test('file lock acquisition and renewal succeed', async ({ request }) => {
    await runScenario('file_lock_acquire_renew', async () => {
      const assetPath = `synthetic/collaboration-monitor-${Date.now()}.md`;
      const acquireResponse = await request.post(new URL('/api/file-locks/acquire', IDE_BASE_URL).toString(), {
        data: {
          assetPath,
          userId: 'synthetic-monitor',
          reason: 'synthetic collaboration monitor',
          ttlMinutes: 5,
        },
      });

      expect(acquireResponse.status()).toBe(201);
      const lock = await acquireResponse.json();
      expect(lock.lockId).toBeTruthy();

      const renewResponse = await request.post(new URL(`/api/file-locks/${lock.lockId}/renew`, IDE_BASE_URL).toString(), {
        data: {
          userId: 'synthetic-monitor',
          ttlMinutes: 5,
        },
      });

      expect(renewResponse.ok()).toBeTruthy();
      const renewedLock = await renewResponse.json();
      expect(renewedLock.lockId).toBe(lock.lockId);
    });
  });

  test('file lock release, list, and cleanup succeed', async ({ request }) => {
    await runScenario('file_lock_release_cleanup', async () => {
      const assetPath = `synthetic/collaboration-monitor-release-${Date.now()}.md`;
      const acquireResponse = await request.post(new URL('/api/file-locks/acquire', IDE_BASE_URL).toString(), {
        data: {
          assetPath,
          userId: 'synthetic-monitor',
          reason: 'synthetic collaboration monitor release path',
          ttlMinutes: 5,
        },
      });

      expect(acquireResponse.status()).toBe(201);
      const lock = await acquireResponse.json();

      const releaseResponse = await request.delete(
        new URL(`/api/file-locks/${lock.lockId}?userId=synthetic-monitor`, IDE_BASE_URL).toString()
      );
      expect(releaseResponse.ok()).toBeTruthy();

      const listResponse = await request.get(new URL(`/api/file-locks?assetPath=${encodeURIComponent(assetPath)}`, IDE_BASE_URL).toString());
      expect(listResponse.ok()).toBeTruthy();

      const cleanupResponse = await request.post(new URL('/api/file-locks/cleanup', IDE_BASE_URL).toString());
      expect(cleanupResponse.ok()).toBeTruthy();
    });
  });
});