#!/usr/bin/env node
// @file        apps/backend/src/routes/workspace-templates.ts
// @module      routes/workspace-templates
// @description HTTP routes for workspace template management and provisioning
import { Router } from 'express';
import service from '../services/workspace/workspace-templates-service';
import { getLogger } from '../lib/logger';
const logger = getLogger('WorkspaceTemplatesRoutes');
const router = Router();
/**
 * POST /create
 * Create a new workspace template
 */
router.post('/create', (req, res) => {
    try {
        const { name, category, description, author, isPublic } = req.body;
        if (!name || !category || !description || !author) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: name, category, description, author',
            });
        }
        const template = service.createTemplate(name, category, description, author, isPublic || false);
        logger.debug(`Template created: ${template.id}`);
        return res.status(201).json({
            success: true,
            template,
        });
    }
    catch (error) {
        logger.error(`Error creating template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * GET /list/all
 * List all templates with optional filtering
 */
router.get('/list/all', (req, res) => {
    try {
        const { category, author, tag, publicOnly } = req.query;
        const templates = service.listTemplates({
            category: category,
            author: author,
            tag: tag,
            publicOnly: publicOnly === 'true',
        });
        return res.json({ success: true, templates, count: templates.length });
    }
    catch (error) {
        logger.error(`Error listing templates: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * GET /search
 * Search templates by keyword
 */
router.get('/search', (req, res) => {
    try {
        const { q } = req.query;
        if (!q) {
            return res.status(400).json({
                success: false,
                error: 'Missing required query parameter: q',
            });
        }
        const templates = service.searchTemplates(q);
        return res.json({ success: true, templates, count: templates.length });
    }
    catch (error) {
        logger.error(`Error searching templates: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * GET /stats/all
 * Get statistics
 */
router.get('/stats/all', (req, res) => {
    try {
        const stats = service.getStatistics();
        return res.json({ success: true, stats });
    }
    catch (error) {
        logger.error(`Error fetching statistics: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /import
 * Import template from JSON
 */
router.post('/import', (req, res) => {
    try {
        const { json } = req.body;
        if (!json) {
            return res.status(400).json({
                success: false,
                error: 'Missing required field: json',
            });
        }
        const template = service.importTemplate(json);
        if (!template) {
            return res.status(400).json({
                success: false,
                error: 'Invalid JSON format',
            });
        }
        return res.status(201).json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error importing template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/add-extension
 * Add pinned extension to template
 */
router.post('/:templateId/add-extension', (req, res) => {
    try {
        const { templateId } = req.params;
        const { extensionId, version } = req.body;
        if (!extensionId || !version) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: extensionId, version',
            });
        }
        const success = service.addPinnedExtension(templateId, extensionId, version);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error adding extension: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * PATCH /:templateId/settings
 * Update template settings
 */
router.patch('/:templateId/settings', (req, res) => {
    try {
        const { templateId } = req.params;
        const settings = req.body;
        const success = service.updateSettings(templateId, settings);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error updating settings: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/devcontainer
 * Set devcontainer configuration
 */
router.post('/:templateId/devcontainer', (req, res) => {
    try {
        const { templateId } = req.params;
        const config = req.body;
        const success = service.setDevContainerConfig(templateId, config);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error setting devcontainer: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/environment-schema
 * Set environment schema
 */
router.post('/:templateId/environment-schema', (req, res) => {
    try {
        const { templateId } = req.params;
        const schema = req.body;
        const success = service.setEnvironmentSchema(templateId, schema);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error setting environment schema: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/git
 * Set git repository configuration
 */
router.post('/:templateId/git', (req, res) => {
    try {
        const { templateId } = req.params;
        const { gitRepo, branch, path } = req.body;
        if (!gitRepo) {
            return res.status(400).json({
                success: false,
                error: 'Missing required field: gitRepo',
            });
        }
        const success = service.setGitRepository(templateId, gitRepo, branch, path);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error setting git repository: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/tag
 * Add tag to template
 */
router.post('/:templateId/tag', (req, res) => {
    try {
        const { templateId } = req.params;
        const { tag } = req.body;
        if (!tag) {
            return res.status(400).json({
                success: false,
                error: 'Missing required field: tag',
            });
        }
        const success = service.addTag(templateId, tag);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error adding tag: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * DELETE /:templateId/tag/:tag
 * Remove tag from template
 */
router.delete('/:templateId/tag/:tag', (req, res) => {
    try {
        const { templateId, tag } = req.params;
        const success = service.removeTag(templateId, tag);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error removing tag: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * GET /:templateId
 * Get template by ID
 */
router.get('/:templateId', (req, res) => {
    try {
        const { templateId } = req.params;
        const template = service.getTemplate(templateId);
        if (!template) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error fetching template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/apply
 * Apply template to workspace (provision)
 */
router.post('/:templateId/apply', async (req, res) => {
    try {
        const { templateId } = req.params;
        const { workspaceId, userId, environmentVars, overrideSettings } = req.body;
        if (!workspaceId || !userId) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: workspaceId, userId',
            });
        }
        const success = await service.applyTemplate({
            templateId,
            workspaceId,
            userId,
            environmentVars,
            overrideSettings,
        });
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template, message: 'Template applied successfully' });
    }
    catch (error) {
        logger.error(`Error applying template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * GET /:workspaceId/progress
 * Get provisioning progress for workspace
 */
router.get('/:workspaceId/progress', (req, res) => {
    try {
        const { workspaceId } = req.params;
        const progress = service.getProgress(workspaceId);
        if (!progress) {
            return res.status(404).json({
                success: false,
                error: `No provisioning in progress for workspace: ${workspaceId}`,
            });
        }
        return res.json({ success: true, progress });
    }
    catch (error) {
        logger.error(`Error fetching progress: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * PATCH /:templateId
 * Update template
 */
router.patch('/:templateId', (req, res) => {
    try {
        const { templateId } = req.params;
        const updates = req.body;
        const success = service.updateTemplate(templateId, updates);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        const template = service.getTemplate(templateId);
        return res.json({ success: true, template });
    }
    catch (error) {
        logger.error(`Error updating template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * DELETE /:templateId
 * Delete template
 */
router.delete('/:templateId', (req, res) => {
    try {
        const { templateId } = req.params;
        const success = service.deleteTemplate(templateId);
        if (!success) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        return res.json({ success: true, message: 'Template deleted' });
    }
    catch (error) {
        logger.error(`Error deleting template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/clone
 * Clone template
 */
router.post('/:templateId/clone', (req, res) => {
    try {
        const { templateId } = req.params;
        const { newName, author } = req.body;
        if (!newName || !author) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: newName, author',
            });
        }
        const clone = service.cloneTemplate(templateId, newName, author);
        if (!clone) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        return res.status(201).json({ success: true, template: clone });
    }
    catch (error) {
        logger.error(`Error cloning template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * POST /:templateId/validate
 * Validate template
 */
router.post('/:templateId/validate', (req, res) => {
    try {
        const { templateId } = req.params;
        const result = service.validateTemplate(templateId);
        return res.json({ success: true, ...result });
    }
    catch (error) {
        logger.error(`Error validating template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
/**
 * GET /:templateId/export
 * Export template as JSON
 */
router.get('/:templateId/export', (req, res) => {
    try {
        const { templateId } = req.params;
        const json = service.exportTemplate(templateId);
        if (!json) {
            return res.status(404).json({
                success: false,
                error: `Template not found: ${templateId}`,
            });
        }
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Content-Disposition', `attachment; filename="template-${templateId}.json"`);
        return res.send(json);
    }
    catch (error) {
        logger.error(`Error exporting template: ${error}`);
        return res.status(500).json({ success: false, error: String(error) });
    }
});
export default router;
//# sourceMappingURL=workspace-templates.js.map