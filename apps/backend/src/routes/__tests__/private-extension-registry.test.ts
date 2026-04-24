import express from 'express';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import request from 'supertest';
import { afterEach, describe, expect, it, vi } from 'vitest';

const mockAuditService = { emit: vi.fn() };

vi.mock('../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

vi.mock('../../services/audit/audit-service', () => ({
  getAuditService: () => mockAuditService,
}));

import { initializePrivateExtensionRegistryRoutes } from '../private-extension-registry';
import { PrivateExtensionRegistryService } from '../../services/private-extension-registry';

describe('private extension registry routes', () => {
  let tempDir = '';

  afterEach(() => {
    mockAuditService.emit.mockReset();
    if (tempDir) {
      fs.rmSync(tempDir, { recursive: true, force: true });
      tempDir = '';
    }
  });

  function createService() {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'private-extension-registry-'));
    const approvedManifestPath = path.join(tempDir, 'extensions-approved.json');
    const blockedManifestPath = path.join(tempDir, 'extensions-blocked.json');

    fs.writeFileSync(
      approvedManifestPath,
      JSON.stringify(
        {
          policy_version: '2026.04.22',
          policy_date: '2026-04-22',
          manifest_signature: 'signature-1',
          extensions: [
            {
              id: 'publisher.allowed-extension',
              version: '1.2.3',
              tier: 'core',
              reason: 'Approved for enterprise use',
              pre_installed: true,
              user_can_uninstall: false,
            },
          ],
        },
        null,
        2
      ),
      'utf8'
    );

    fs.writeFileSync(
      blockedManifestPath,
      JSON.stringify(
        {
          policy_version: '2026.04.22',
          policy_date: '2026-04-22',
          blocked: [
            {
              pattern: '^publisher\\.blocked-.*$',
              reason: 'Blocked by policy',
              alternative: 'publisher.allowed-extension',
            },
          ],
        },
        null,
        2
      ),
      'utf8'
    );

    return new PrivateExtensionRegistryService({
      approvedManifestPath,
      blockedManifestPath,
    });
  }

  it('exposes the registry snapshot', async () => {
    const app = express();
    app.use(initializePrivateExtensionRegistryRoutes(createService()));

    await request(app)
      .get('/api/extensions/registry')
      .expect(200)
      .expect(({ body }) => {
        expect(body.policyVersion).toBe('2026.04.22');
        expect(body.approvedExtensions).toHaveLength(1);
        expect(body.blockedExtensions).toHaveLength(1);
      });
  });

  it('audits a blocked validation decision', async () => {
    const app = express();
    app.use(initializePrivateExtensionRegistryRoutes(createService()));

    await request(app)
      .get('/api/extensions/registry/validate')
      .query({
        extensionId: 'publisher.blocked-helper',
        actor: 'ci-bot',
      })
      .expect(200)
      .expect(({ body }) => {
        expect(body.allowed).toBe(false);
        expect(body.status).toBe('blocked');
        expect(body.actor).toBe('ci-bot');
      });

    expect(
      mockAuditService.emit.mock.calls.some(([event]) =>
        event && typeof event === 'object' && 'action' in event
          ? (event as { userId?: string; action?: string; resourceType?: string; resource?: string; fileAction?: string }).userId === 'ci-bot' &&
            (event as { userId?: string; action?: string; resourceType?: string; resource?: string; fileAction?: string }).action === 'deny' &&
            (event as { userId?: string; action?: string; resourceType?: string; resource?: string; fileAction?: string }).resourceType === 'config' &&
            (event as { userId?: string; action?: string; resourceType?: string; resource?: string; fileAction?: string }).resource === 'publisher.blocked-helper' &&
            (event as { userId?: string; action?: string; resourceType?: string; resource?: string; fileAction?: string }).fileAction === 'read'
          : false
      )
    ).toBe(true);
  });
});