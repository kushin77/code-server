#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/extension-registry.test.ts
// @module      routes
// @description Tests for extension registry routes

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import router from '../extension-registry';
import { RegistryManagerService } from '../../services/extension-registry/registry-manager';

let app: express.Application;
let service: RegistryManagerService;

describe('Extension Registry Routes', () => {
  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/api/extension-registry', router);

    service = RegistryManagerService.getInstance();
    service.reset();
  });

  afterEach(() => {
    service.removeAllListeners();
  });

  describe('POST /register', () => {
    it('should register extension', async () => {
      const response = await request(app)
        .post('/api/extension-registry/register')
        .send({
          id: 'test.extension',
          name: 'Test Extension',
          publisher: 'test-org',
          version: '1.0.0',
          displayName: 'Test Ext',
          description: 'A test extension',
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.id).toBe('test.extension');
      expect(response.body.data.version).toBe('1.0.0');
    });

    it('should validate required fields', async () => {
      const response = await request(app)
        .post('/api/extension-registry/register')
        .send({
          id: 'test.ext',
          // Missing publisher and version
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
      expect(response.body.error).toContain('Missing required fields');
    });
  });

  describe('GET /extension/:id', () => {
    beforeEach(() => {
      service.registerExtension('test.ext', {
        id: 'test.ext',
        name: 'test',
        publisher: 'org',
        version: '1.0.0',
        displayName: 'Test',
      });
    });

    it('should get extension metadata', async () => {
      const response = await request(app)
        .get('/api/extension-registry/extension/test.ext');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.id).toBe('test.ext');
      expect(response.body.data.version).toBe('1.0.0');
    });

    it('should return 404 for non-existent extension', async () => {
      const response = await request(app)
        .get('/api/extension-registry/extension/nonexistent.ext');

      expect(response.status).toBe(404);
      expect(response.body.success).toBe(false);
    });
  });

  describe('GET /extensions', () => {
    beforeEach(() => {
      service.registerExtension('ext1', {
        id: 'ext1',
        name: 'ext1',
        publisher: 'pub1',
        version: '1.0.0',
      });

      service.registerExtension('ext2', {
        id: 'ext2',
        name: 'ext2',
        publisher: 'pub2',
        version: '2.0.0',
      });
    });

    it('should get all extensions', async () => {
      const response = await request(app)
        .get('/api/extension-registry/extensions');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.extensions.length).toBe(2);
      expect(response.body.data.total).toBe(2);
    });
  });

  describe('POST /block', () => {
    it('should block extension', async () => {
      const response = await request(app)
        .post('/api/extension-registry/block')
        .send({
          id: 'malicious.ext',
          reason: 'Contains malware',
          severity: 'critical',
          alternatives: ['safe.ext'],
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.blocked).toBe(true);
      expect(response.body.data.blockSeverity).toBe('critical');
    });

    it('should validate required fields', async () => {
      const response = await request(app)
        .post('/api/extension-registry/block')
        .send({
          id: 'test.ext',
          // Missing reason
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /unblock/:id', () => {
    beforeEach(() => {
      service.blockExtension('blocked.ext', 'CVE', 'high');
    });

    it('should unblock extension', async () => {
      const response = await request(app)
        .post('/api/extension-registry/unblock/blocked.ext');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);

      expect(service.isBlocked('blocked.ext')).toBe(false);
    });
  });

  describe('GET /blocklist', () => {
    beforeEach(() => {
      service.blockExtension('ext1', 'CVE-1', 'high');
      service.blockExtension('ext2', 'CVE-2', 'medium');
    });

    it('should get blocklist', async () => {
      const response = await request(app)
        .get('/api/extension-registry/blocklist');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.blocked.length).toBe(2);
      expect(response.body.data.total).toBe(2);
    });
  });

  describe('POST /pin-version', () => {
    it('should set version pinning', async () => {
      const response = await request(app)
        .post('/api/extension-registry/pin-version')
        .send({
          extensionId: 'pinned.ext',
          allowedVersions: ['1.0.0', '1.5.0'],
          workspaceId: 'ws-1',
          reason: 'Tested versions',
        });

      expect(response.status).toBe(201);
      expect(response.body.success).toBe(true);
      expect(response.body.data.extensionId).toBe('pinned.ext');
      expect(response.body.data.allowedVersions.length).toBe(2);
    });

    it('should validate required fields', async () => {
      const response = await request(app)
        .post('/api/extension-registry/pin-version')
        .send({
          extensionId: 'ext',
          // Missing allowedVersions
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });

    it('should validate allowedVersions is array', async () => {
      const response = await request(app)
        .post('/api/extension-registry/pin-version')
        .send({
          extensionId: 'ext',
          allowedVersions: '1.0.0', // Not an array
        });

      expect(response.status).toBe(400);
      expect(response.body.success).toBe(false);
    });
  });

  describe('POST /validate-version', () => {
    beforeEach(() => {
      service.setPinning('pinned.ext', ['1.0.0', '1.5.0'], 'ws-1');
    });

    it('should validate allowed version', async () => {
      const response = await request(app)
        .post('/api/extension-registry/validate-version')
        .send({
          extensionId: 'pinned.ext',
          version: '1.5.0',
          workspaceId: 'ws-1',
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.allowed).toBe(true);
    });

    it('should reject disallowed version', async () => {
      const response = await request(app)
        .post('/api/extension-registry/validate-version')
        .send({
          extensionId: 'pinned.ext',
          version: '2.0.0',
          workspaceId: 'ws-1',
        });

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.allowed).toBe(false);
      expect(response.body.data.reason).toBeDefined();
    });
  });

  describe('POST /record-install/:id', () => {
    it('should record installation', async () => {
      const response = await request(app)
        .post('/api/extension-registry/record-install/test.ext');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.extensionId).toBe('test.ext');
      expect(response.body.data.count).toBe(1);
    });

    it('should increment installation count', async () => {
      await request(app).post('/api/extension-registry/record-install/test.ext');
      await request(app).post('/api/extension-registry/record-install/test.ext');

      const response = await request(app)
        .post('/api/extension-registry/record-install/test.ext');

      expect(response.body.data.count).toBe(3);
    });
  });

  describe('GET /statistics', () => {
    beforeEach(() => {
      service.registerExtension('internal.ext', {
        id: 'internal.ext',
        name: 'internal',
        publisher: 'kushnircloud',
        version: '1.0.0',
      });

      service.registerExtension('external.ext', {
        id: 'external.ext',
        name: 'external',
        publisher: 'microsoft',
        version: '1.0.0',
      });

      service.registerExtension('blocked.ext', {
        id: 'blocked.ext',
        name: 'blocked',
        publisher: 'badactor',
        version: '1.0.0',
      });

      service.blockExtension('blocked.ext', 'CVE', 'high');
      service.recordInstallation('internal.ext');
      service.recordInstallation('external.ext');
    });

    it('should get registry statistics', async () => {
      const response = await request(app)
        .get('/api/extension-registry/statistics');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.totalExtensions).toBe(3);
      expect(response.body.data.blockedExtensions).toBe(1);
      expect(response.body.data.totalInstallations).toBe(2);
    });

    it('should report sync status', async () => {
      service.recordSync();

      const response = await request(app)
        .get('/api/extension-registry/statistics');

      expect(response.status).toBe(200);
      expect(response.body.data.syncStatus).toBe('healthy');
      expect(response.body.data.lastSync).toBeGreaterThan(0);
    });
  });

  describe('POST /sync', () => {
    it('should trigger sync', async () => {
      const response = await request(app)
        .post('/api/extension-registry/sync');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.message).toContain('synced');
      expect(response.body.data.stats.syncStatus).toBe('healthy');
    });
  });

  describe('GET /health', () => {
    it('should return health status', async () => {
      const response = await request(app)
        .get('/api/extension-registry/health');

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.status).toBe('ok');
      expect(response.body.data.service).toBe('extension-registry');
    });
  });

  describe('Integration Tests', () => {
    it('should handle complete registry workflow', async () => {
      // Register internal extension
      await request(app)
        .post('/api/extension-registry/register')
        .send({
          id: 'internal.tool',
          publisher: 'kushnircloud',
          version: '1.0.0',
        });

      // Register and block external extension
      await request(app)
        .post('/api/extension-registry/register')
        .send({
          id: 'dangerous.ext',
          publisher: 'badactor',
          version: '1.0.0',
        });

      await request(app)
        .post('/api/extension-registry/block')
        .send({
          id: 'dangerous.ext',
          reason: 'CVE-2024-1234',
          severity: 'critical',
        });

      // Pin version for workspace
      await request(app)
        .post('/api/extension-registry/pin-version')
        .send({
          extensionId: 'internal.tool',
          allowedVersions: ['1.0.0', '1.1.0'],
          workspaceId: 'ws-prod',
        });

      // Record installations
      await request(app).post('/api/extension-registry/record-install/internal.tool');
      await request(app).post('/api/extension-registry/record-install/internal.tool');

      // Sync registry
      const syncResponse = await request(app).post('/api/extension-registry/sync');

      // Verify final state
      const statsResponse = await request(app).get('/api/extension-registry/statistics');

      expect(statsResponse.body.data.totalExtensions).toBe(2);
      expect(statsResponse.body.data.blockedExtensions).toBe(1);
      expect(statsResponse.body.data.totalInstallations).toBe(2);
      expect(statsResponse.body.data.syncStatus).toBe('healthy');
    });
  });
});
