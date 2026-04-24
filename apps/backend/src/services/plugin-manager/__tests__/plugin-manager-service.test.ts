/**
 * Plugin Manager Service Tests
 * @file        apps/backend/src/services/plugin-manager/__tests__/plugin-manager-service.test.ts
 * @module      services/plugin-manager
 * @description Test suite for plugin manager functionality
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { PluginManagerService } from '../plugin-manager-service.js';

describe('Plugin Manager Service', () => {
  let service: PluginManagerService;

  beforeEach(() => {
    PluginManagerService.reset();
    service = PluginManagerService.getInstance();
    vi.useFakeTimers();
  });

  afterEach(() => {
    service.shutdown();
    vi.useRealTimers();
  });

  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined();
      expect((service as any).plugins).toBeDefined();
    });

    it('should return same instance on subsequent calls', () => {
      const instance1 = PluginManagerService.getInstance();
      const instance2 = PluginManagerService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('Plugin Lifecycle', () => {
    it('should install plugin', async () => {
      const result = service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.progressId).toBeDefined();

      vi.runAllTimers();

      const plugin = service.getPlugin('test-plugin');
      expect(plugin).toBeDefined();
      expect(plugin?.status).toBe('installed');
    });

    it('should emit plugin-installed event', () => {
      return new Promise<void>((resolve) => {
        service.once('plugin-installed', (event) => {
          expect(event.data_object.pluginId).toBe('test-plugin');
          resolve();
        });

        service.installPlugin(
          {
            pluginId: 'test-plugin',
            name: 'Test Plugin',
            version: '1.0.0',
            description: 'A test plugin',
            author: 'Test Author',
            type: 'utility',
            source: 'marketplace',
            tags: ['test'],
            dependencies: [],
            permissions: [],
            size: 1024,
            sha256: 'abcde'
          },
          'user1',
          '127.0.0.1',
          'Mozilla'
        );

        vi.runAllTimers();
      });
    });

    it('should enable plugin', async () => {
      service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );

      vi.runAllTimers();

      const result = service.enablePlugin('test-plugin', 'user1', '127.0.0.1', 'Mozilla');
      expect(result.success).toBe(true);

      const plugin = service.getPlugin('test-plugin');
      expect(plugin?.status).toBe('enabled');
    });

    it('should disable plugin', async () => {
      service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );

      vi.runAllTimers();

      service.enablePlugin('test-plugin', 'user1', '127.0.0.1', 'Mozilla');
      const result = service.disablePlugin('test-plugin', 'user1', '127.0.0.1', 'Mozilla');
      expect(result.success).toBe(true);

      const plugin = service.getPlugin('test-plugin');
      expect(plugin?.status).toBe('disabled');
    });

    it('should uninstall plugin', async () => {
      service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );

      vi.runAllTimers();

      const result = service.uninstallPlugin('test-plugin', 'user1', '127.0.0.1', 'Mozilla');
      expect(result.success).toBe(true);

      const plugin = service.getPlugin('test-plugin');
      expect(plugin).toBeUndefined();
    });
  });

  describe('Plugin Configuration', () => {
    beforeEach(() => {
      service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );
      vi.runAllTimers();
    });

    it('should update plugin configuration', () => {
      const settings = { theme: 'dark', fontSize: 14 };
      const result = service.updatePluginConfig('test-plugin', settings, 'user1', '127.0.0.1', 'Mozilla');
      
      expect(result.success).toBe(true);
      
      const config = service.getPluginConfig('test-plugin');
      expect(config?.settings).toEqual(settings);
    });

    it('should emit plugin-config-updated event', () => {
      return new Promise<void>((resolve) => {
        service.once('plugin-config-updated', (event) => {
          expect(event.data_object.pluginId).toBe('test-plugin');
          resolve();
        });

        service.updatePluginConfig('test-plugin', { active: true }, 'user1', '127.0.0.1', 'Mozilla');
      });
    });
  });

  describe('Plugin Information', () => {
    beforeEach(() => {
      service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );
      vi.runAllTimers();
    });

    it('should list plugins', () => {
      const plugins = service.listPlugins();
      expect(plugins.length).toBe(1);
      expect(plugins[0].pluginId).toBe('test-plugin');
    });

    it('should filter plugins by type', () => {
      const plugins = service.listPlugins('utility');
      expect(plugins.length).toBe(1);
      
      const missing = service.listPlugins('ai');
      expect(missing.length).toBe(0);
    });

    it('should get plugin progress', () => {
      const progress = service.getPluginProgress('test-plugin');
      expect(progress).toBeDefined();
      expect(progress?.status).toBe('completed');
    });

    it('should get plugin events', () => {
      const events = service.getPluginEvents('test-plugin');
      expect(events.length).toBeGreaterThan(0);
      expect(events[0].eventType).toBe('plugin_installed');
    });
  });

  describe('Audit & Meta', () => {
    it('should retrieve audit log', () => {
      service.installPlugin(
        {
          pluginId: 'test-plugin',
          name: 'Test Plugin',
          version: '1.0.0',
          description: 'A test plugin',
          author: 'Test Author',
          type: 'utility',
          source: 'marketplace',
          tags: ['test'],
          dependencies: [],
          permissions: [],
          size: 1024,
          sha256: 'abcde'
        },
        'user1',
        '127.0.0.1',
        'Mozilla'
      );
      vi.runAllTimers();

      const log = service.getAuditLog();
      expect(log.length).toBeGreaterThan(0);
      expect(log[0].action).toBe('install-plugin');
    });

    it('should update config', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (event) => {
          expect(event.data_object.config.autoUpdateEnabled).toBe(true);
          resolve();
        });

        service.updateConfig({ autoUpdateEnabled: true });
      });
    });

    it('should shutdown cleanly', () => {
      service.shutdown();
      expect((service as any).plugins.size).toBe(0);
    });
  });
});
