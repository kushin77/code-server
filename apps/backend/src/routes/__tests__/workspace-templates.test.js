#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/workspace-templates.test.ts
// @module      routes/workspace-templates
// @description Comprehensive tests for workspace templates routes
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import workspaceTemplatesRouter from '../workspace-templates';
import service from '../../services/workspace/workspace-templates-service';
describe('Workspace Templates Routes', () => {
    let app;
    beforeEach(() => {
        app = express();
        app.use(express.json());
        app.use('/api/templates', workspaceTemplatesRouter);
        service.reset();
    });
    afterEach(() => {
        service.reset();
    });
    describe('POST /create', () => {
        it('should create a new template', async () => {
            const res = await request(app)
                .post('/api/templates/create')
                .send({
                name: 'Test Template',
                category: 'backend',
                description: 'Test description',
                author: 'user1',
                isPublic: false,
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.template).toBeDefined();
            expect(res.body.template.name).toBe('Test Template');
            expect(res.body.template.category).toBe('backend');
        });
        it('should return 400 for missing fields', async () => {
            const res = await request(app)
                .post('/api/templates/create')
                .send({
                name: 'Test Template',
                // missing other fields
            });
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
        });
    });
    describe('POST /:templateId/add-extension', () => {
        it('should add extension to template', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/add-extension`)
                .send({
                extensionId: 'ms-python.python',
                version: '2024.1.0',
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.extensions).toHaveLength(1);
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .post('/api/templates/non-existent/add-extension')
                .send({
                extensionId: 'ext-id',
                version: '1.0.0',
            });
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
        it('should return 400 for missing fields', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/add-extension`)
                .send({ extensionId: 'ext-id' });
            expect(res.status).toBe(400);
        });
    });
    describe('PATCH /:templateId/settings', () => {
        it('should update template settings', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .patch(`/api/templates/${template.id}/settings`)
                .send({ fontSize: 16, tabSize: 4 });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.settings.fontSize).toBe(16);
            expect(res.body.template.settings.tabSize).toBe(4);
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .patch('/api/templates/non-existent/settings')
                .send({ fontSize: 16 });
            expect(res.status).toBe(404);
        });
    });
    describe('POST /:templateId/devcontainer', () => {
        it('should set devcontainer configuration', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/devcontainer`)
                .send({
                image: 'node:20-alpine',
                forwardPorts: [3000, 5173],
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.devcontainer).toBeDefined();
        });
    });
    describe('POST /:templateId/environment-schema', () => {
        it('should set environment schema', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/environment-schema`)
                .send({
                variables: [
                    {
                        name: 'PORT',
                        description: 'Server port',
                        required: true,
                        default: '3000',
                        type: 'number',
                    },
                ],
                secrets: [],
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.environmentSchema).toBeDefined();
        });
    });
    describe('POST /:templateId/git', () => {
        it('should set git repository', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/git`)
                .send({
                gitRepo: 'https://github.com/example/repo',
                branch: 'develop',
                path: '/backend',
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.gitRepo).toBe('https://github.com/example/repo');
        });
        it('should return 400 for missing gitRepo', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/git`)
                .send({ branch: 'develop' });
            expect(res.status).toBe(400);
        });
    });
    describe('POST /:templateId/tag', () => {
        it('should add tag to template', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/tag`)
                .send({ tag: 'python' });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.tags).toContain('python');
        });
        it('should return 400 for missing tag', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/tag`)
                .send({});
            expect(res.status).toBe(400);
        });
    });
    describe('DELETE /:templateId/tag/:tag', () => {
        it('should remove tag from template', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            service.addTag(template.id, 'python');
            const res = await request(app)
                .delete(`/api/templates/${template.id}/tag/python`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.tags).not.toContain('python');
        });
    });
    describe('GET /:templateId', () => {
        it('should retrieve template', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .get(`/api/templates/${template.id}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.id).toBe(template.id);
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .get('/api/templates/non-existent');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    describe('GET /list/all', () => {
        beforeEach(() => {
            service.createTemplate('Frontend', 'frontend', 'React', 'user1', true);
            service.createTemplate('Backend', 'backend', 'Node.js', 'user2', false);
            service.createTemplate('Full Stack', 'full-stack', 'Complete', 'user1', true);
        });
        it('should list all templates', async () => {
            const res = await request(app)
                .get('/api/templates/list/all');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.count).toBe(3);
        });
        it('should filter by category', async () => {
            const res = await request(app)
                .get('/api/templates/list/all?category=backend');
            expect(res.status).toBe(200);
            expect(res.body.count).toBe(1);
            expect(res.body.templates[0].category).toBe('backend');
        });
        it('should filter by author', async () => {
            const res = await request(app)
                .get('/api/templates/list/all?author=user1');
            expect(res.status).toBe(200);
            expect(res.body.count).toBe(2);
        });
        it('should filter by public only', async () => {
            const res = await request(app)
                .get('/api/templates/list/all?publicOnly=true');
            expect(res.status).toBe(200);
            expect(res.body.count).toBe(2);
            expect(res.body.templates.every((t) => t.public)).toBe(true);
        });
    });
    describe('GET /search', () => {
        beforeEach(() => {
            service.createTemplate('Python Backend', 'backend', 'FastAPI', 'user1');
            service.createTemplate('React Frontend', 'frontend', 'Next.js', 'user2');
        });
        it('should search by keyword', async () => {
            const res = await request(app)
                .get('/api/templates/search?q=Python');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.count).toBe(1);
        });
        it('should return 400 without query', async () => {
            const res = await request(app)
                .get('/api/templates/search');
            expect(res.status).toBe(400);
        });
    });
    describe('POST /:templateId/apply', () => {
        it('should apply template to workspace', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/apply`)
                .send({
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        }, 15000);
        it('should return 400 for missing fields', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/apply`)
                .send({ workspaceId: 'ws-123' });
            expect(res.status).toBe(400);
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .post('/api/templates/non-existent/apply')
                .send({
                workspaceId: 'ws-123',
                userId: 'user1',
            });
            expect(res.status).toBe(404);
        });
    });
    describe('GET /:workspaceId/progress', () => {
        it('should return 404 when no provisioning in progress', async () => {
            const res = await request(app)
                .get('/api/templates/ws-123/progress');
            expect(res.status).toBe(404);
        });
    });
    describe('PATCH /:templateId', () => {
        it('should update template', async () => {
            const template = service.createTemplate('Original', 'custom', 'Test', 'user1', false);
            const res = await request(app)
                .patch(`/api/templates/${template.id}`)
                .send({ name: 'Updated', public: true });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.template.name).toBe('Updated');
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .patch('/api/templates/non-existent')
                .send({ name: 'Updated' });
            expect(res.status).toBe(404);
        });
    });
    describe('DELETE /:templateId', () => {
        it('should delete template', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .delete(`/api/templates/${template.id}`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            // Verify deletion
            const retrieved = service.getTemplate(template.id);
            expect(retrieved).toBeUndefined();
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .delete('/api/templates/non-existent');
            expect(res.status).toBe(404);
        });
    });
    describe('POST /:templateId/clone', () => {
        it('should clone template', async () => {
            const original = service.createTemplate('Original', 'backend', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${original.id}/clone`)
                .send({
                newName: 'Cloned Template',
                author: 'user2',
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.template.name).toBe('Cloned Template');
            expect(res.body.template.author).toBe('user2');
            expect(res.body.template.id).not.toBe(original.id);
        });
        it('should return 400 for missing fields', async () => {
            const template = service.createTemplate('Test', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/clone`)
                .send({ newName: 'Cloned' });
            expect(res.status).toBe(400);
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .post('/api/templates/non-existent/clone')
                .send({
                newName: 'Cloned',
                author: 'user1',
            });
            expect(res.status).toBe(404);
        });
    });
    describe('GET /stats/all', () => {
        beforeEach(() => {
            service.createTemplate('Template 1', 'backend', 'Test', 'user1');
            service.createTemplate('Template 2', 'frontend', 'Test', 'user2');
        });
        it('should return statistics', async () => {
            const res = await request(app)
                .get('/api/templates/stats/all');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.stats).toMatchObject({
                totalTemplates: 2,
                totalProvisioned: 0,
                categoryCounts: expect.any(Object),
            });
        });
    });
    describe('POST /:templateId/validate', () => {
        it('should validate incomplete template', async () => {
            const template = service.createTemplate('No Extensions', 'custom', 'Test', 'user1');
            const res = await request(app)
                .post(`/api/templates/${template.id}/validate`);
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.valid).toBe(false);
            expect(res.body.issues).toContain('At least one extension should be pinned');
        });
        it('should validate complete template', async () => {
            const template = service.createTemplate('Complete', 'backend', 'Test', 'user1');
            service.addPinnedExtension(template.id, 'ext-1', '1.0.0');
            service.setGitRepository(template.id, 'https://github.com/example/repo');
            const res = await request(app)
                .post(`/api/templates/${template.id}/validate`);
            expect(res.status).toBe(200);
            expect(res.body.valid).toBe(true);
            expect(res.body.issues).toHaveLength(0);
        });
    });
    describe('GET /:templateId/export', () => {
        it('should export template as JSON', async () => {
            const template = service.createTemplate('Export Test', 'backend', 'Test', 'user1');
            const res = await request(app)
                .get(`/api/templates/${template.id}/export`);
            expect(res.status).toBe(200);
            expect(res.headers['content-type']).toContain('application/json');
            expect(() => JSON.parse(res.text)).not.toThrow();
        });
        it('should return 404 for non-existent template', async () => {
            const res = await request(app)
                .get('/api/templates/non-existent/export');
            expect(res.status).toBe(404);
        });
    });
    describe('POST /import', () => {
        it('should import template from JSON', async () => {
            const original = service.createTemplate('Import Test', 'backend', 'Test', 'user1');
            const json = service.exportTemplate(original.id);
            service.deleteTemplate(original.id); // Clear it
            const res = await request(app)
                .post('/api/templates/import')
                .send({ json });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.template.name).toBe('Import Test');
        });
        it('should return 400 for missing json', async () => {
            const res = await request(app)
                .post('/api/templates/import')
                .send({});
            expect(res.status).toBe(400);
        });
        it('should return 400 for invalid JSON', async () => {
            const res = await request(app)
                .post('/api/templates/import')
                .send({ json: '{ invalid }' });
            expect(res.status).toBe(400);
        });
    });
});
//# sourceMappingURL=workspace-templates.test.js.map