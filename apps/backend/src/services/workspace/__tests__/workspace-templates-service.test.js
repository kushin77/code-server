#!/usr/bin/env node
// @file        apps/backend/src/services/workspace/__tests__/workspace-templates-service.test.ts
// @module      workspace/templates
// @description Comprehensive tests for workspace templates service
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import service from '../workspace-templates-service';
describe('WorkspaceTemplatesService', () => {
    beforeEach(() => {
        service.reset();
    });
    afterEach(() => {
        service.reset();
    });
    describe('createTemplate', () => {
        it('should create a new template with correct properties', () => {
            const template = service.createTemplate('Full Stack Dev', 'full-stack', 'Complete full-stack development environment', 'user123', false);
            expect(template).toMatchObject({
                name: 'Full Stack Dev',
                category: 'full-stack',
                description: 'Complete full-stack development environment',
                author: 'user123',
                public: false,
                extensions: [],
                usageCount: 0,
                createdAt: expect.any(Number),
                updatedAt: expect.any(Number),
            });
            expect(template.id).toMatch(/^template-/);
        });
        it('should emit templateCreated event', () => {
            const spy = vi.spyOn(service, 'emit');
            service.createTemplate('Test', 'backend', 'Test template', 'user1', true);
            expect(spy).toHaveBeenCalledWith('templateCreated', expect.objectContaining({
                name: 'Test',
                category: 'backend',
                author: 'user1',
            }));
        });
        it('should create templates with default settings', () => {
            const template = service.createTemplate('Default Settings', 'custom', 'Test', 'user1');
            expect(template.settings).toMatchObject({
                theme: 'One Dark+',
                fontSize: 13,
                autoSave: 'onFocusChange',
                formatOnSave: true,
                tabSize: 2,
            });
        });
        it('should support all template categories', () => {
            const categories = [
                'full-stack',
                'frontend',
                'backend',
                'data-science',
                'custom',
            ];
            for (const category of categories) {
                const template = service.createTemplate(`${category} template`, category, 'Test', 'user1');
                expect(template.category).toBe(category);
            }
        });
    });
    describe('addPinnedExtension', () => {
        it('should add extension to template', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const result = service.addPinnedExtension(template.id, 'ms-python.python', '2024.1.0');
            expect(result).toBe(true);
            const updated = service.getTemplate(template.id);
            expect(updated?.extensions).toHaveLength(1);
            expect(updated?.extensions[0]).toMatchObject({
                extensionId: 'ms-python.python',
                version: '2024.1.0',
                pinned: true,
            });
        });
        it('should update existing extension version', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addPinnedExtension(template.id, 'ms-python.python', '2024.1.0');
            service.addPinnedExtension(template.id, 'ms-python.python', '2024.2.0');
            const updated = service.getTemplate(template.id);
            expect(updated?.extensions).toHaveLength(1);
            expect(updated?.extensions[0].version).toBe('2024.2.0');
        });
        it('should emit extensionPinned event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addPinnedExtension(template.id, 'extension-id', '1.0.0');
            expect(spy).toHaveBeenCalledWith('extensionPinned', expect.objectContaining({
                templateId: template.id,
                extensionId: 'extension-id',
            }));
        });
        it('should return false for non-existent template', () => {
            const result = service.addPinnedExtension('non-existent', 'ext-id', '1.0.0');
            expect(result).toBe(false);
        });
        it('should handle multiple extensions', () => {
            const template = service.createTemplate('Multi-ext', 'custom', 'Test', 'user1');
            service.addPinnedExtension(template.id, 'ext-1', '1.0.0');
            service.addPinnedExtension(template.id, 'ext-2', '2.0.0');
            service.addPinnedExtension(template.id, 'ext-3', '3.0.0');
            const updated = service.getTemplate(template.id);
            expect(updated?.extensions).toHaveLength(3);
        });
    });
    describe('updateSettings', () => {
        it('should update template settings', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const updated = service.updateSettings(template.id, { fontSize: 16, tabSize: 4 });
            expect(updated).toBe(true);
            const result = service.getTemplate(template.id);
            expect(result?.settings.fontSize).toBe(16);
            expect(result?.settings.tabSize).toBe(4);
            expect(result?.settings.theme).toBe('One Dark+'); // unchanged
        });
        it('should emit settingsUpdated event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.updateSettings(template.id, { fontSize: 18 });
            expect(spy).toHaveBeenCalledWith('settingsUpdated', expect.objectContaining({
                templateId: template.id,
            }));
        });
        it('should return false for non-existent template', () => {
            const result = service.updateSettings('non-existent', { fontSize: 16 });
            expect(result).toBe(false);
        });
    });
    describe('setDevContainerConfig', () => {
        it('should set devcontainer configuration', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const config = {
                image: 'node:20-alpine',
                forwardPorts: [3000, 5173],
                postCreateCommand: 'npm install',
            };
            const result = service.setDevContainerConfig(template.id, config);
            expect(result).toBe(true);
            const updated = service.getTemplate(template.id);
            expect(updated?.devcontainer).toMatchObject(config);
        });
        it('should emit devcontainerConfigured event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const config = { image: 'node:20' };
            service.setDevContainerConfig(template.id, config);
            expect(spy).toHaveBeenCalledWith('devcontainerConfigured', expect.objectContaining({
                templateId: template.id,
            }));
        });
    });
    describe('setEnvironmentSchema', () => {
        it('should set environment schema', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const schema = {
                variables: [
                    {
                        name: 'PORT',
                        description: 'Server port',
                        required: true,
                        default: '3000',
                        type: 'number',
                    },
                    {
                        name: 'ENV',
                        description: 'Environment',
                        required: true,
                        type: 'enum',
                        enum: ['dev', 'prod'],
                    },
                ],
                secrets: [
                    {
                        name: 'API_KEY',
                        description: 'API key',
                        required: true,
                        source: 'gsm',
                    },
                ],
            };
            const result = service.setEnvironmentSchema(template.id, schema);
            expect(result).toBe(true);
            const updated = service.getTemplate(template.id);
            expect(updated?.environmentSchema).toEqual(schema);
        });
        it('should emit schemaConfigured event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const schema = { variables: [], secrets: [] };
            service.setEnvironmentSchema(template.id, schema);
            expect(spy).toHaveBeenCalledWith('schemaConfigured', expect.objectContaining({
                templateId: template.id,
            }));
        });
    });
    describe('setGitRepository', () => {
        it('should set git repository configuration', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const result = service.setGitRepository(template.id, 'https://github.com/example/repo', 'develop', '/backend');
            expect(result).toBe(true);
            const updated = service.getTemplate(template.id);
            expect(updated).toMatchObject({
                gitRepo: 'https://github.com/example/repo',
                gitBranch: 'develop',
                gitPath: '/backend',
            });
        });
        it('should use default branch if not specified', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.setGitRepository(template.id, 'https://github.com/example/repo');
            const updated = service.getTemplate(template.id);
            expect(updated?.gitBranch).toBe('main');
            expect(updated?.gitPath).toBe('/');
        });
        it('should emit gitConfigured event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.setGitRepository(template.id, 'https://github.com/example/repo');
            expect(spy).toHaveBeenCalledWith('gitConfigured', expect.objectContaining({
                gitRepo: 'https://github.com/example/repo',
            }));
        });
    });
    describe('tag management', () => {
        it('should add tags to template', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addTag(template.id, 'python');
            service.addTag(template.id, 'backend');
            const updated = service.getTemplate(template.id);
            expect(updated?.tags).toEqual(['python', 'backend']);
        });
        it('should not add duplicate tags', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addTag(template.id, 'python');
            service.addTag(template.id, 'python');
            const updated = service.getTemplate(template.id);
            expect(updated?.tags).toHaveLength(1);
        });
        it('should remove tags from template', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addTag(template.id, 'python');
            service.addTag(template.id, 'backend');
            service.removeTag(template.id, 'python');
            const updated = service.getTemplate(template.id);
            expect(updated?.tags).toEqual(['backend']);
        });
        it('should emit tagAdded and tagRemoved events', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addTag(template.id, 'python');
            service.removeTag(template.id, 'python');
            expect(spy).toHaveBeenCalledWith('tagAdded', expect.objectContaining({ tag: 'python' }));
            expect(spy).toHaveBeenCalledWith('tagRemoved', expect.objectContaining({ tag: 'python' }));
        });
    });
    describe('getTemplate', () => {
        it('should retrieve existing template', () => {
            const created = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const retrieved = service.getTemplate(created.id);
            expect(retrieved).toEqual(created);
        });
        it('should return undefined for non-existent template', () => {
            const result = service.getTemplate('non-existent');
            expect(result).toBeUndefined();
        });
    });
    describe('listTemplates', () => {
        beforeEach(() => {
            service.createTemplate('Frontend Starter', 'frontend', 'React setup', 'user1', true);
            service.createTemplate('Backend API', 'backend', 'Node.js API', 'user2', false);
            service.createTemplate('Full Stack', 'full-stack', 'Complete setup', 'user1', true);
            service.createTemplate('Data Science', 'data-science', 'ML environment', 'user3', true);
        });
        it('should list all templates', () => {
            const templates = service.listTemplates();
            expect(templates).toHaveLength(4);
        });
        it('should filter by category', () => {
            const backend = service.listTemplates({ category: 'backend' });
            expect(backend).toHaveLength(1);
            expect(backend[0].name).toBe('Backend API');
        });
        it('should filter by author', () => {
            const user1 = service.listTemplates({ author: 'user1' });
            expect(user1).toHaveLength(2);
        });
        it('should filter by public only', () => {
            const publicOnly = service.listTemplates({ publicOnly: true });
            expect(publicOnly).toHaveLength(3);
            expect(publicOnly.every((t) => t.public)).toBe(true);
        });
        it('should filter by tag', () => {
            const t1 = service.getTemplate(service.listTemplates()[0].id);
            service.addTag(t1.id, 'recommended');
            const recommended = service.listTemplates({ tag: 'recommended' });
            expect(recommended).toHaveLength(1);
        });
        it('should sort by usage count', () => {
            const templates = service.listTemplates();
            const first = templates[0];
            // Manually update usage count (via provisioning)
            if (first) {
                first.usageCount = 10;
            }
            const sorted = service.listTemplates();
            expect(sorted[0].usageCount).toBeGreaterThanOrEqual(sorted[sorted.length - 1].usageCount);
        });
    });
    describe('searchTemplates', () => {
        beforeEach(() => {
            service.createTemplate('Python Backend', 'backend', 'FastAPI setup', 'user1');
            service.createTemplate('React Frontend', 'frontend', 'Next.js setup', 'user2');
            service.createTemplate('Full Stack Python', 'full-stack', 'Django + React', 'user3');
        });
        it('should search by name', () => {
            const results = service.searchTemplates('Python');
            expect(results).toHaveLength(2);
            expect(results.every((t) => t.name.includes('Python'))).toBe(true);
        });
        it('should search by description', () => {
            const results = service.searchTemplates('FastAPI');
            expect(results).toHaveLength(1);
            expect(results[0].name).toBe('Python Backend');
        });
        it('should be case-insensitive', () => {
            const results = service.searchTemplates('python');
            expect(results).toHaveLength(2);
        });
        it('should return empty array for no matches', () => {
            const results = service.searchTemplates('NonExistent');
            expect(results).toHaveLength(0);
        });
    });
    describe('applyTemplate', () => {
        it('should apply template to workspace', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.setGitRepository(template.id, 'https://github.com/example/repo');
            const result = await service.applyTemplate({
                templateId: template.id,
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            expect(result).toBe(true);
        }, 15000);
        it('should emit provisioningStarted and provisioningComplete events', async () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            await service.applyTemplate({
                templateId: template.id,
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            expect(spy).toHaveBeenCalledWith('provisioningStarted', expect.objectContaining({
                workspaceId: 'ws-123',
                templateId: template.id,
            }));
            expect(spy).toHaveBeenCalledWith('provisioningComplete', expect.objectContaining({
                workspaceId: 'ws-123',
            }));
        }, 15000);
        it('should return false for non-existent template', async () => {
            const result = await service.applyTemplate({
                templateId: 'non-existent',
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            expect(result).toBe(false);
        });
        it('should increment usage count on successful provision', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const initialCount = template.usageCount;
            await service.applyTemplate({
                templateId: template.id,
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            const updated = service.getTemplate(template.id);
            expect(updated.usageCount).toBe(initialCount + 1);
        }, 15000);
        it('should complete provisioning in under 30 seconds', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const startTime = Date.now();
            await service.applyTemplate({
                templateId: template.id,
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            const elapsedTime = Date.now() - startTime;
            expect(elapsedTime).toBeLessThan(30000);
        }, 15000);
    });
    describe('updateTemplate', () => {
        it('should update allowed fields', () => {
            const template = service.createTemplate('Original', 'custom', 'Test', 'user1', false);
            const result = service.updateTemplate(template.id, {
                name: 'Updated Name',
                public: true,
            });
            expect(result).toBe(true);
            const updated = service.getTemplate(template.id);
            expect(updated?.name).toBe('Updated Name');
            expect(updated?.public).toBe(true);
        });
        it('should emit templateUpdated event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.updateTemplate(template.id, { name: 'New Name' });
            expect(spy).toHaveBeenCalledWith('templateUpdated', expect.objectContaining({
                templateId: template.id,
            }));
        });
        it('should return false for non-existent template', () => {
            const result = service.updateTemplate('non-existent', { name: 'New' });
            expect(result).toBe(false);
        });
    });
    describe('deleteTemplate', () => {
        it('should delete template', () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const result = service.deleteTemplate(template.id);
            expect(result).toBe(true);
            expect(service.getTemplate(template.id)).toBeUndefined();
        });
        it('should emit templateDeleted event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.deleteTemplate(template.id);
            expect(spy).toHaveBeenCalledWith('templateDeleted', expect.objectContaining({
                templateId: template.id,
            }));
        });
        it('should return false for non-existent template', () => {
            const result = service.deleteTemplate('non-existent');
            expect(result).toBe(false);
        });
    });
    describe('cloneTemplate', () => {
        it('should clone template with new ID and name', () => {
            const original = service.createTemplate('Original', 'backend', 'Test', 'user1', true);
            service.addPinnedExtension(original.id, 'ext-1', '1.0.0');
            service.addTag(original.id, 'important');
            const clone = service.cloneTemplate(original.id, 'Cloned Template', 'user2');
            expect(clone).toBeDefined();
            expect(clone.id).not.toBe(original.id);
            expect(clone.name).toBe('Cloned Template');
            expect(clone.author).toBe('user2');
            expect(clone.extensions).toEqual(original.extensions);
            expect(clone.tags).toEqual(original.tags);
            expect(clone.usageCount).toBe(0);
        });
        it('should emit templateCloned event', () => {
            const spy = vi.spyOn(service, 'emit');
            const original = service.createTemplate('Original', 'custom', 'Test', 'user1');
            service.cloneTemplate(original.id, 'Clone', 'user2');
            expect(spy).toHaveBeenCalledWith('templateCloned', expect.objectContaining({
                sourceId: original.id,
                newName: 'Clone',
            }));
        });
        it('should return null for non-existent source', () => {
            const result = service.cloneTemplate('non-existent', 'Clone', 'user2');
            expect(result).toBeNull();
        });
    });
    describe('getStatistics', () => {
        beforeEach(() => {
            const t1 = service.createTemplate('Backend 1', 'backend', 'Test', 'user1');
            const t2 = service.createTemplate('Frontend 1', 'frontend', 'Test', 'user2');
            const t3 = service.createTemplate('Backend 2', 'backend', 'Test', 'user1');
            const t4 = service.createTemplate('FullStack 1', 'full-stack', 'Test', 'user3');
            // Simulate usage
            if (t1)
                t1.usageCount = 10;
            if (t2)
                t2.usageCount = 5;
            if (t3)
                t3.usageCount = 15;
        });
        it('should return statistics', () => {
            const stats = service.getStatistics();
            expect(stats).toMatchObject({
                totalTemplates: 4,
                totalProvisioned: 30,
                averageProvisionTime: 0,
                topCategories: expect.any(Array),
            });
        });
        it('should count templates by category', () => {
            const stats = service.getStatistics();
            expect(stats.categoryCounts).toMatchObject({
                backend: 2,
                frontend: 1,
                'full-stack': 1,
            });
        });
        it('should identify most used template', () => {
            const stats = service.getStatistics();
            expect(stats.mostUsedTemplate).toBeDefined();
            expect(stats.mostUsedTemplate?.usageCount).toBe(15);
        });
        it('should return null for mostUsedTemplate when no templates exist', () => {
            service.reset();
            const stats = service.getStatistics();
            expect(stats.mostUsedTemplate).toBeNull();
        });
    });
    describe('validateTemplate', () => {
        it('should validate complete template', () => {
            const template = service.createTemplate('Valid', 'backend', 'Test', 'user1', false);
            service.addPinnedExtension(template.id, 'ext-1', '1.0.0');
            service.setGitRepository(template.id, 'https://github.com/example/repo');
            const result = service.validateTemplate(template.id);
            expect(result.valid).toBe(true);
            expect(result.issues).toHaveLength(0);
        });
        it('should report missing name', () => {
            const template = service.createTemplate('', 'custom', 'Test', 'user1');
            template.name = '';
            const result = service.validateTemplate(template.id);
            expect(result.valid).toBe(false);
            expect(result.issues).toContain('Template name is required');
        });
        it('should report missing extensions', () => {
            const template = service.createTemplate('No Extensions', 'custom', 'Test', 'user1');
            const result = service.validateTemplate(template.id);
            expect(result.valid).toBe(false);
            expect(result.issues).toContain('At least one extension should be pinned');
        });
        it('should report missing git or devcontainer', () => {
            const template = service.createTemplate('No Git', 'custom', 'Test', 'user1');
            service.addPinnedExtension(template.id, 'ext-1', '1.0.0');
            const result = service.validateTemplate(template.id);
            expect(result.valid).toBe(false);
            expect(result.issues).toContain('Either git repository or devcontainer configuration is recommended');
        });
        it('should return false for non-existent template', () => {
            const result = service.validateTemplate('non-existent');
            expect(result.valid).toBe(false);
            expect(result.issues).toContain('Template not found');
        });
    });
    describe('importExport', () => {
        it('should export template as JSON', () => {
            const template = service.createTemplate('Export Test', 'backend', 'Test', 'user1');
            const json = service.exportTemplate(template.id);
            expect(json).toBeDefined();
            expect(() => JSON.parse(json)).not.toThrow();
            const parsed = JSON.parse(json);
            expect(parsed.name).toBe('Export Test');
            expect(parsed.category).toBe('backend');
        });
        it('should import template from JSON', () => {
            const original = service.createTemplate('Import Test', 'backend', 'Test', 'user1');
            service.addPinnedExtension(original.id, 'ext-1', '1.0.0');
            const json = service.exportTemplate(original.id);
            const imported = service.importTemplate(json);
            expect(imported).toBeDefined();
            expect(imported?.name).toBe('Import Test');
            expect(imported?.category).toBe('backend');
            expect(imported?.extensions).toHaveLength(1);
        });
        it('should handle invalid JSON on import', () => {
            const result = service.importTemplate('{ invalid json }');
            expect(result).toBeNull();
        });
        it('should emit templateImported event', () => {
            const spy = vi.spyOn(service, 'emit');
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const json = service.exportTemplate(template.id);
            service.importTemplate(json);
            expect(spy).toHaveBeenCalledWith('templateImported', expect.objectContaining({
                name: 'Test',
            }));
        });
    });
    describe('singleton pattern', () => {
        it('should return same instance', () => {
            const instance1 = service;
            const instance2 = service;
            expect(instance1).toBe(instance2);
        });
        it('should reset properly', () => {
            const instance = service;
            instance.createTemplate('Test', 'custom', 'Test', 'user1');
            expect(instance.listTemplates()).toHaveLength(1);
            instance.reset();
            expect(instance.listTemplates()).toHaveLength(0);
        });
    });
});
//# sourceMappingURL=workspace-templates-service.test.js.map