#!/usr/bin/env node
// @file        apps/backend/src/services/workspace/workspace-templates-service.ts
// @module      workspace/templates
// @description Manages workspace templates for rapid provisioning with pinned extensions, settings, devcontainer config
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
const logger = getLogger('WorkspaceTemplatesService');
export class WorkspaceTemplatesService extends EventEmitter {
    constructor() {
        super();
        this.templates = new Map();
        this.provisioning = new Map();
    }
    static getInstance() {
        if (!WorkspaceTemplatesService.instance) {
            WorkspaceTemplatesService.instance = new WorkspaceTemplatesService();
        }
        return WorkspaceTemplatesService.instance;
    }
    reset() {
        this.templates.clear();
        this.provisioning.clear();
        this.removeAllListeners();
    }
    /**
     * Create a new workspace template
     */
    createTemplate(name, category, description, author, isPublic = false) {
        const id = `template-${Date.now()}-${Math.random().toString(36).substring(7)}`;
        const now = Date.now();
        const template = {
            id,
            name,
            description,
            category,
            author,
            public: isPublic,
            extensions: [],
            settings: {
                theme: 'One Dark+',
                fontSize: 13,
                fontFamily: 'Menlo, Monaco',
                autoSave: 'onFocusChange',
                autoSaveDelay: 1000,
                formatOnSave: true,
                tabSize: 2,
                insertSpaces: true,
                customSettings: {},
            },
            createdAt: now,
            updatedAt: now,
            provisionTime: 0,
            usageCount: 0,
            tags: [],
        };
        this.templates.set(id, template);
        logger.debug(`Template created: ${id}`);
        this.emit('templateCreated', { id, name, category, author });
        return template;
    }
    /**
     * Add pinned extension to template
     */
    addPinnedExtension(templateId, extensionId, version) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        // Check if extension already pinned
        const existing = template.extensions.find((e) => e.extensionId === extensionId);
        if (existing) {
            existing.version = version;
            existing.pinnedAt = Date.now();
        }
        else {
            template.extensions.push({
                extensionId,
                version,
                pinned: true,
                pinnedAt: Date.now(),
            });
        }
        template.updatedAt = Date.now();
        this.emit('extensionPinned', { templateId, extensionId, version });
        return true;
    }
    /**
     * Update template settings
     */
    updateSettings(templateId, settings) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        template.settings = { ...template.settings, ...settings };
        template.updatedAt = Date.now();
        this.emit('settingsUpdated', { templateId, settings });
        return true;
    }
    /**
     * Set devcontainer configuration
     */
    setDevContainerConfig(templateId, config) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        template.devcontainer = config;
        template.updatedAt = Date.now();
        this.emit('devcontainerConfigured', { templateId, config });
        return true;
    }
    /**
     * Set environment schema
     */
    setEnvironmentSchema(templateId, schema) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        template.environmentSchema = schema;
        template.updatedAt = Date.now();
        this.emit('schemaConfigured', { templateId, schema });
        return true;
    }
    /**
     * Set git repository configuration
     */
    setGitRepository(templateId, gitRepo, branch = 'main', path = '/') {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        template.gitRepo = gitRepo;
        template.gitBranch = branch;
        template.gitPath = path;
        template.updatedAt = Date.now();
        this.emit('gitConfigured', { templateId, gitRepo, branch, path });
        return true;
    }
    /**
     * Add tag to template
     */
    addTag(templateId, tag) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        if (!template.tags.includes(tag)) {
            template.tags.push(tag);
            template.updatedAt = Date.now();
            this.emit('tagAdded', { templateId, tag });
        }
        return true;
    }
    /**
     * Remove tag from template
     */
    removeTag(templateId, tag) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        const idx = template.tags.indexOf(tag);
        if (idx >= 0) {
            template.tags.splice(idx, 1);
            template.updatedAt = Date.now();
            this.emit('tagRemoved', { templateId, tag });
        }
        return true;
    }
    /**
     * Get template by ID
     */
    getTemplate(templateId) {
        return this.templates.get(templateId);
    }
    /**
     * List all templates with optional filtering
     */
    listTemplates(filter) {
        let results = Array.from(this.templates.values());
        if (filter?.publicOnly) {
            results = results.filter((t) => t.public);
        }
        if (filter?.category) {
            results = results.filter((t) => t.category === filter.category);
        }
        if (filter?.author) {
            results = results.filter((t) => t.author === filter.author);
        }
        if (filter?.tag) {
            results = results.filter((t) => t.tags.includes(filter.tag));
        }
        return results.sort((a, b) => b.usageCount - a.usageCount);
    }
    /**
     * Search templates by keyword
     */
    searchTemplates(keyword) {
        const lowerKeyword = keyword.toLowerCase();
        return Array.from(this.templates.values()).filter((template) => {
            return (template.name.toLowerCase().includes(lowerKeyword) ||
                template.description.toLowerCase().includes(lowerKeyword) ||
                template.tags.some((tag) => tag.toLowerCase().includes(lowerKeyword)));
        });
    }
    /**
     * Apply template to workspace (provision)
     */
    async applyTemplate(request) {
        const template = this.templates.get(request.templateId);
        if (!template) {
            logger.warn(`Template not found: ${request.templateId}`);
            return false;
        }
        const progressId = `${request.workspaceId}-${Date.now()}`;
        const startTime = Date.now();
        this.provisioning.set(progressId, {
            templateId: request.templateId,
            workspaceId: request.workspaceId,
            stage: 'initializing',
            progress: 0,
            message: 'Starting provisioning',
            startTime,
            elapsedTime: 0,
        });
        try {
            this.emit('provisioningStarted', {
                workspaceId: request.workspaceId,
                templateId: request.templateId,
            });
            // Stage 1: Clone git repo (if configured)
            if (template.gitRepo) {
                this.updateProgress(progressId, 'cloning', 20, 'Cloning git repository');
                await this.simulateDelay(3000); // Simulate clone
            }
            // Stage 2: Install extensions
            this.updateProgress(progressId, 'installing', 45, 'Installing pinned extensions');
            await this.simulateDelay(5000); // Simulate installation
            // Stage 3: Configure environment
            this.updateProgress(progressId, 'configuring', 75, 'Configuring environment');
            await this.simulateDelay(3000); // Simulate configuration
            // Stage 4: Apply settings and devcontainer
            this.updateProgress(progressId, 'configuring', 90, 'Applying settings');
            await this.simulateDelay(2000); // Simulate settings
            // Complete
            this.updateProgress(progressId, 'complete', 100, 'Provisioning complete');
            const elapsedTime = Date.now() - startTime;
            template.usageCount += 1;
            template.provisionTime = Math.max(template.provisionTime, elapsedTime);
            this.emit('provisioningComplete', {
                workspaceId: request.workspaceId,
                templateId: request.templateId,
                elapsedTime,
            });
            return true;
        }
        catch (error) {
            this.updateProgress(progressId, 'error', 0, `Error: ${String(error)}`);
            this.emit('provisioningError', {
                workspaceId: request.workspaceId,
                templateId: request.templateId,
                error,
            });
            return false;
        }
        finally {
            this.provisioning.delete(progressId);
        }
    }
    /**
     * Get current provisioning progress
     */
    getProgress(workspaceId) {
        // Find progress by workspaceId
        for (const progress of this.provisioning.values()) {
            if (progress.workspaceId === workspaceId) {
                return progress;
            }
        }
        return undefined;
    }
    /**
     * Update template (merge changes)
     */
    updateTemplate(templateId, updates) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        // Only allow updating specific fields
        const allowedFields = ['name', 'description', 'public', 'tags'];
        for (const key of allowedFields) {
            if (key in updates) {
                template[key] = updates[key];
            }
        }
        template.updatedAt = Date.now();
        this.emit('templateUpdated', { templateId, updates });
        return true;
    }
    /**
     * Delete template
     */
    deleteTemplate(templateId) {
        const template = this.templates.get(templateId);
        if (!template) {
            logger.warn(`Template not found: ${templateId}`);
            return false;
        }
        this.templates.delete(templateId);
        this.emit('templateDeleted', { templateId });
        return true;
    }
    /**
     * Clone/duplicate a template
     */
    cloneTemplate(sourceId, newName, author) {
        const source = this.templates.get(sourceId);
        if (!source) {
            logger.warn(`Source template not found: ${sourceId}`);
            return null;
        }
        const id = `template-${Date.now()}-${Math.random().toString(36).substring(7)}`;
        const now = Date.now();
        const clone = {
            ...source,
            id,
            name: newName,
            author,
            createdAt: now,
            updatedAt: now,
            usageCount: 0,
            extensions: [...source.extensions],
            tags: [...source.tags],
            settings: { ...source.settings, customSettings: { ...source.settings.customSettings } },
        };
        this.templates.set(id, clone);
        this.emit('templateCloned', { sourceId, newId: id, newName, author });
        return clone;
    }
    /**
     * Get provisioning statistics
     */
    getStatistics() {
        const templates = Array.from(this.templates.values());
        const categoryCounts = {};
        let totalProvisioned = 0;
        let totalTime = 0;
        for (const template of templates) {
            categoryCounts[template.category] = (categoryCounts[template.category] || 0) + 1;
            totalProvisioned += template.usageCount;
            totalTime += template.provisionTime;
        }
        const topCategories = Object.entries(categoryCounts)
            .map(([category, count]) => ({ category, count }))
            .sort((a, b) => b.count - a.count)
            .slice(0, 5);
        const mostUsedTemplate = templates.length > 0 ? templates.reduce((a, b) => (a.usageCount > b.usageCount ? a : b)) : null;
        return {
            totalTemplates: templates.length,
            categoryCounts,
            totalProvisioned,
            averageProvisionTime: templates.length > 0 ? totalTime / templates.length : 0,
            mostUsedTemplate,
            topCategories,
        };
    }
    /**
     * Validate template completeness
     */
    validateTemplate(templateId) {
        const template = this.templates.get(templateId);
        if (!template) {
            return { valid: false, issues: ['Template not found'] };
        }
        const issues = [];
        if (!template.name || template.name.trim().length === 0) {
            issues.push('Template name is required');
        }
        if (template.extensions.length === 0) {
            issues.push('At least one extension should be pinned');
        }
        if (!template.gitRepo && !template.devcontainer) {
            issues.push('Either git repository or devcontainer configuration is recommended');
        }
        if (template.public && template.author.length === 0) {
            issues.push('Public templates must have an author');
        }
        return { valid: issues.length === 0, issues };
    }
    /**
     * Export template as JSON
     */
    exportTemplate(templateId) {
        const template = this.templates.get(templateId);
        if (!template) {
            return null;
        }
        return JSON.stringify(template, null, 2);
    }
    /**
     * Import template from JSON
     */
    importTemplate(json) {
        try {
            const data = JSON.parse(json);
            const id = `template-${Date.now()}-${Math.random().toString(36).substring(7)}`;
            const template = {
                ...data,
                id,
                createdAt: Date.now(),
                updatedAt: Date.now(),
                usageCount: 0,
            };
            this.templates.set(id, template);
            this.emit('templateImported', { id, name: template.name });
            return template;
        }
        catch (error) {
            logger.error(`Failed to import template: ${error}`);
            return null;
        }
    }
    // Private helper methods
    updateProgress(progressId, stage, progress, message) {
        const current = this.provisioning.get(progressId);
        if (current) {
            current.stage = stage;
            current.progress = progress;
            current.message = message;
            current.elapsedTime = Date.now() - current.startTime;
            this.emit('provisioningProgress', { progressId, ...current });
        }
    }
    simulateDelay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
}
export default WorkspaceTemplatesService.getInstance();
//# sourceMappingURL=workspace-templates-service.js.map