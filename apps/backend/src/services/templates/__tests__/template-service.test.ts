/**
 * Workspace Templates Service Tests
 * Test coverage for template creation, provisioning, and management
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { TemplateService } from '../template-service.js';
import { WorkspaceTemplate } from '../types.js';

describe('TemplateService', () => {
  let service: TemplateService;

  const createTestTemplate = (): Omit<WorkspaceTemplate, 'id' | 'createdAt' | 'updatedAt'> => ({
    name: 'React Web App',
    description: 'Full-stack React app with TypeScript',
    version: '1.0.0',
    author: 'test-user',
    tags: ['react', 'typescript', 'web'],
    visibility: 'public',
    templateType: 'standard',
    settings: {
      theme: 'dark',
      fontSize: 14,
      fontFamily: 'Fira Code',
      formatOnSave: true,
      tabSize: 2,
      wordWrap: true,
      extensions: [
        { id: 'ms-python.python', name: 'Python', version: '2024.0.0', publisher: 'Microsoft', enabled: true },
      ],
    },
    extensions: [
      { id: 'ms-react.react', name: 'React', version: '1.0.0', publisher: 'Microsoft', enabled: true },
      { id: 'dbaeumer.vscode-eslint', name: 'ESLint', version: '2.4.0', publisher: 'Dirk', enabled: true },
    ],
    devcontainer: {
      name: 'react-app',
      image: 'mcr.microsoft.com/devcontainers/javascript-node:18-bullseye',
      forwardPorts: [3000],
      postCreateCommand: 'npm install',
      customizations: {
        vscode: {
          extensions: ['ms-react.react'],
          settings: { 'editor.formatOnSave': true },
        },
      },
    },
    envSchema: {
      version: '1.0',
      variables: [
        { name: 'NODE_ENV', required: true, type: 'string', default: 'development', description: 'Environment' },
        { name: 'API_KEY', required: true, type: 'secret', description: 'API key' },
      ],
    },
    files: [
      { path: 'package.json', content: '{}', isTemplate: false },
      { path: '.env.example', content: 'NODE_ENV=development\nAPI_KEY={{API_KEY}}', isTemplate: true },
      { path: 'src/index.ts', content: 'console.log("Hello");', isTemplate: false },
    ],
    gitConfig: {
      defaultBranch: 'main',
      remoteOrigin: 'https://github.com/example/react-app.git',
    },
    metadata: {
      category: 'web',
      framework: 'react',
      language: ['typescript', 'javascript'],
      estimatedProvisionTime: 15000,
    },
  });

  beforeEach(async () => {
    service = new TemplateService();
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  // ==================== Initialization Tests ====================

  it('should initialize successfully', async () => {
    expect(service).toBeDefined();
    const stats = await service.getStatistics();
    expect(stats.totalTemplates).toBe(0);
  });

  it('should emit initialized event', () => {
    return new Promise<void>((resolve) => {
      const newService = new TemplateService();
      newService.once('initialized', () => {
        resolve();
      });
      newService.initialize();
    });
  });

  it('should emit shutdown event', () => {
    return new Promise<void>((resolve) => {
      const newService = new TemplateService();
      newService.initialize().then(() => {
        newService.once('shutdown', () => {
          resolve();
        });
        newService.shutdown();
      });
    });
  });

  // ==================== Create Template Tests ====================

  it('should create template', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    expect(tpl.name).toBe('React Web App');
    expect(tpl.author).toBe('test-user');
    expect(tpl.extensions).toHaveLength(2);
  });

  it('should emit template-created event', () => {
    return new Promise<void>((resolve) => {
      service.once('template-created', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.createTemplate(
        'user1',
        'user1@example.com',
        createTestTemplate()
      );
    });
  });

  it('should assign unique template IDs', async () => {
    const tpl1 = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    await new Promise((resolve) => setTimeout(resolve, 1));

    const tpl2 = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    expect(tpl1.id).not.toBe(tpl2.id);
  });

  it('should track creation timestamp', async () => {
    const before = Date.now();
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );
    const after = Date.now();

    expect(tpl.createdAt).toBeGreaterThanOrEqual(before);
    expect(tpl.createdAt).toBeLessThanOrEqual(after);
  });

  // ==================== Get Template Tests ====================

  it('should retrieve template by ID', async () => {
    const created = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const retrieved = await service.getTemplate(created.id);
    expect(retrieved?.id).toBe(created.id);
  });

  it('should return undefined for missing template', async () => {
    const tpl = await service.getTemplate('nonexistent');
    expect(tpl).toBeUndefined();
  });

  // ==================== Provision Template Tests ====================

  it('should provision template', async () => {
    const created = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const result = await service.provisionTemplate({
      templateId: created.id,
      userId: 'user1',
      userEmail: 'user1@example.com',
      workspaceName: 'my-workspace',
      workspacePath: '/workspace/my-workspace',
    });

    expect(result.successful).toBe(true);
    expect(result.filesCreated).toBeGreaterThan(0);
    expect(result.extensionsInstalled).toBeGreaterThan(0);
  });

  it('should emit template-provisioned event', () => {
    return new Promise<void>((resolve) => {
      service
        .createTemplate(
          'user1',
          'user1@example.com',
          createTestTemplate()
        )
        .then((created) => {
          service.once('template-provisioned', (data) => {
            expect(data.successful).toBe(true);
            resolve();
          });
          service.provisionTemplate({
            templateId: created.id,
            userId: 'user1',
            userEmail: 'user1@example.com',
            workspaceName: 'my-workspace',
            workspacePath: '/workspace/my-workspace',
          });
        });
    });
  });

  it('should provision in under 30 seconds', async () => {
    const created = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const result = await service.provisionTemplate({
      templateId: created.id,
      userId: 'user1',
      userEmail: 'user1@example.com',
      workspaceName: 'my-workspace',
      workspacePath: '/workspace/my-workspace',
    });

    expect(result.duration).toBeLessThan(30000);
  });

  it('should handle missing template on provision', async () => {
    const result = await service.provisionTemplate({
      templateId: 'nonexistent',
      userId: 'user1',
      userEmail: 'user1@example.com',
      workspaceName: 'my-workspace',
      workspacePath: '/workspace/my-workspace',
    });

    expect(result.successful).toBe(false);
    expect(result.errors).toBeDefined();
  });

  it('should skip specified extensions', async () => {
    const created = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const result = await service.provisionTemplate({
      templateId: created.id,
      userId: 'user1',
      userEmail: 'user1@example.com',
      workspaceName: 'my-workspace',
      workspacePath: '/workspace/my-workspace',
      skipExtensions: ['ms-react.react'],
    });

    expect(result.extensionsInstalled).toBeLessThan(2);
  });

  // ==================== Delete Template Tests ====================

  it('should delete template', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    await service.deleteTemplate('user1', 'user1@example.com', tpl.id);

    const retrieved = await service.getTemplate(tpl.id);
    expect(retrieved).toBeUndefined();
  });

  it('should emit template-deleted event', () => {
    return new Promise<void>((resolve) => {
      service
        .createTemplate(
          'user1',
          'user1@example.com',
          createTestTemplate()
        )
        .then((tpl) => {
          service.once('template-deleted', (data) => {
            expect(data.templateId).toBe(tpl.id);
            resolve();
          });
          service.deleteTemplate('user1', 'user1@example.com', tpl.id);
        });
    });
  });

  // ==================== List Templates Tests ====================

  it('should list templates for user', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    await service.createTemplate(
      'user1',
      'user1@example.com',
      { ...createTestTemplate(), name: 'Vue App' }
    );

    const list = await service.listTemplates('user1');
    expect(list.length).toBe(2);
  });

  it('should sort templates by update time', async () => {
    const tpl1 = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    await new Promise((resolve) => setTimeout(resolve, 10));

    const tpl2 = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const list = await service.listTemplates('user1');
    expect(list[0].updatedAt).toBeGreaterThanOrEqual(list[1].updatedAt);
  });

  // ==================== Query Templates Tests ====================

  it('should query templates', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const result = await service.queryTemplates({ userId: 'user1' });
    expect(result.total).toBeGreaterThan(0);
  });

  it('should paginate template queries', async () => {
    for (let i = 0; i < 5; i++) {
      await service.createTemplate(
        'user1',
        'user1@example.com',
        { ...createTestTemplate(), name: `App ${i}` }
      );
    }

    const page1 = await service.queryTemplates({ userId: 'user1', limit: 2 });
    expect(page1.templates.length).toBe(2);
    expect(page1.total).toBe(5);
  });

  it('should filter by visibility', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      { ...createTestTemplate(), visibility: 'private' }
    );

    const result = await service.queryTemplates({ visibility: 'private' });
    expect(result.templates.length).toBeGreaterThan(0);
  });

  it('should filter by tags', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      { ...createTestTemplate(), tags: ['python', 'datascience'] }
    );

    const result = await service.queryTemplates({ tags: ['python'] });
    expect(result.total).toBeGreaterThan(0);
  });

  // ==================== Update Template Tests ====================

  it('should update template', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const updated = await service.updateTemplate(
      'user1',
      'user1@example.com',
      tpl.id,
      { name: 'Updated React App', version: '1.1.0' }
    );

    expect(updated.name).toBe('Updated React App');
    expect(updated.version).toBe('1.1.0');
  });

  it('should emit template-updated event', () => {
    return new Promise<void>((resolve) => {
      service
        .createTemplate(
          'user1',
          'user1@example.com',
          createTestTemplate()
        )
        .then((tpl) => {
          service.once('template-updated', (data) => {
            expect(data.templateId).toBe(tpl.id);
            resolve();
          });
          service.updateTemplate('user1', 'user1@example.com', tpl.id, {
            name: 'Updated',
          });
        });
    });
  });

  // ==================== Export/Import Tests ====================

  it('should export template', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const exported = await service.exportTemplate('user1', 'user1@example.com', tpl.id);
    expect(exported).toContain('React Web App');
  });

  it('should emit template-exported event', () => {
    return new Promise<void>((resolve) => {
      service
        .createTemplate(
          'user1',
          'user1@example.com',
          createTestTemplate()
        )
        .then((tpl) => {
          service.once('template-exported', (data) => {
            expect(data.templateId).toBe(tpl.id);
            resolve();
          });
          service.exportTemplate('user1', 'user1@example.com', tpl.id);
        });
    });
  });

  // ==================== Audit Logging Tests ====================

  it('should log audit entry for template creation', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate(),
      '192.168.1.1',
      'Mozilla/5.0'
    );

    const log = await service.getAuditLog('user1');
    expect(log.length).toBeGreaterThan(0);
    expect(log[0].operation).toBe('created');
    expect(log[0].ipAddress).toBe('192.168.1.1');
  });

  it('should log audit entry for provisioning', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    await service.provisionTemplate(
      {
        templateId: tpl.id,
        userId: 'user1',
        userEmail: 'user1@example.com',
        workspaceName: 'my-workspace',
        workspacePath: '/workspace/my-workspace',
      },
      '192.168.1.1',
      'Mozilla/5.0'
    );

    const log = await service.getAuditLog('user1');
    const provEntry = log.find((e) => e.operation === 'provisioned');
    expect(provEntry).toBeDefined();
  });

  it('should emit audit-logged event', () => {
    return new Promise<void>((resolve) => {
      service.once('audit-logged', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.createTemplate(
        'user1',
        'user1@example.com',
        createTestTemplate()
      );
    });
  });

  // ==================== Statistics Tests ====================

  it('should calculate statistics', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const stats = await service.getStatistics();
    expect(stats.totalTemplates).toBe(1);
  });

  it('should track templates by type', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      { ...createTestTemplate(), templateType: 'standard' }
    );

    await service.createTemplate(
      'user1',
      'user1@example.com',
      { ...createTestTemplate(), templateType: 'minimal' }
    );

    const stats = await service.getStatistics();
    expect(stats.templatesByType['standard']).toBeGreaterThan(0);
    expect(stats.templatesByType['minimal']).toBeGreaterThan(0);
  });

  it('should track extensions per template', async () => {
    await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    const stats = await service.getStatistics();
    expect(stats.totalExtensions).toBeGreaterThan(0);
    expect(stats.averageExtensionsPerTemplate).toBeGreaterThan(0);
  });

  // ==================== Error Handling Tests ====================

  it('should throw error if not initialized', async () => {
    const newService = new TemplateService();
    await expect(newService.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    )).rejects.toThrow();
  });

  // ==================== Singleton Pattern Tests ====================

  it('should use singleton pattern', () => {
    const instance1 = TemplateService.getInstance();
    const instance2 = TemplateService.getInstance();
    expect(instance1).toBe(instance2);
  });

  // ==================== Multiple Users Tests ====================

  it('should handle multiple users', async () => {
    for (let i = 1; i <= 3; i++) {
      await service.createTemplate(
        `user${i}`,
        `user${i}@example.com`,
        createTestTemplate()
      );
    }

    const stats = await service.getStatistics();
    expect(stats.totalTemplates).toBe(3);
  });

  // ==================== DevContainer Tests ====================

  it('should preserve devcontainer configuration', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    expect(tpl.devcontainer.image).toContain('devcontainers');
    expect(tpl.devcontainer.forwardPorts).toContain(3000);
  });

  // ==================== Environment Schema Tests ====================

  it('should preserve environment schema', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    expect(tpl.envSchema.variables).toHaveLength(2);
    expect(tpl.envSchema.variables[0].name).toBe('NODE_ENV');
    expect(tpl.envSchema.variables[1].type).toBe('secret');
  });

  // ==================== Files and Templates Tests ====================

  it('should track template files', async () => {
    const tpl = await service.createTemplate(
      'user1',
      'user1@example.com',
      createTestTemplate()
    );

    expect(tpl.files).toHaveLength(3);
    expect(tpl.files[1].isTemplate).toBe(true);
  });
});
