/**
 * Workspace Templates Service
 * Git-managed templates with fast provisioning (<30s)
 */
import { EventEmitter } from 'events';
/**
 * Workspace Templates Service
 * Manage and provision workspace templates
 */
export class TemplateService extends EventEmitter {
    constructor(config) {
        super();
        this.isInitialized = false;
        this.templates = new Map();
        this.metadata = new Map(); // Per-user templates
        this.auditLog = new Map(); // Per-user audit trail
        this.stats = {
            totalTemplates: 0,
            templatesByType: {},
            templatesByVisibility: {},
            totalProvisioned: 0,
            provisionedByUser: {},
            provisionedByTemplate: {},
            averageProvisionTime: 0,
            provisionSuccessRate: 100,
            totalExtensions: 0,
            averageExtensionsPerTemplate: 0,
        };
        this.config = {
            enabled: true,
            auditLoggingEnabled: true,
            maxTemplatesPerUser: 50,
            maxFilesPerTemplate: 1000,
            maxExtensionsPerTemplate: 100,
            provisionTimeoutMs: 30000, // < 30s
            compressionEnabled: true,
            encryptionEnabled: false,
            maxAuditLogSize: 10000,
            storageBackend: 'memory',
            autoSync: false,
            ...config,
        };
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        this.emit('initialized');
    }
    /**
     * Shutdown service
     */
    async shutdown() {
        this.emit('shutdown');
    }
    /**
     * Create template
     */
    async createTemplate(userId, userEmail, template, ipAddress, userAgent) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const now = Date.now();
        const templateId = `tpl-${userId}-${now}-${Math.random().toString(36).slice(2, 9)}`;
        const fullTemplate = {
            ...template,
            id: templateId,
            createdAt: now,
            updatedAt: now,
        };
        this.templates.set(templateId, fullTemplate);
        // Update metadata
        const userMeta = this.metadata.get(userId) || [];
        const newMetadata = {
            templateId,
            name: template.name,
            version: template.version,
            author: template.author,
            createdAt: now,
            updatedAt: now,
            fileCount: template.files?.length || 0,
            extensionCount: template.extensions?.length || 0,
            visibility: template.visibility,
            tags: template.tags,
            downloads: 0,
            rating: 0,
        };
        userMeta.push(newMetadata);
        if (userMeta.length > this.config.maxTemplatesPerUser) {
            const oldest = userMeta.shift();
            this.templates.delete(oldest.templateId);
        }
        this.metadata.set(userId, userMeta);
        // Log audit
        const auditEntry = {
            id: `audit-${templateId}`,
            userId,
            userEmail,
            operation: 'created',
            status: 'success',
            templateId,
            ipAddress,
            userAgent,
            timestamp: now,
            details: {
                fileCount: template.files?.length,
                extensionCount: template.extensions?.length,
            },
        };
        await this.logAudit(userId, auditEntry);
        this.updateStats();
        this.emit('template-created', { templateId, userId });
        return fullTemplate;
    }
    /**
     * Get template
     */
    async getTemplate(templateId) {
        return this.templates.get(templateId);
    }
    /**
     * Provision template
     */
    async provisionTemplate(request, ipAddress, userAgent) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const startTime = Date.now();
        const template = this.templates.get(request.templateId);
        if (!template) {
            const auditEntry = {
                id: `audit-prov-${request.templateId}-${startTime}`,
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'provisioned',
                status: 'error',
                templateId: request.templateId,
                workspacePath: request.workspacePath,
                ipAddress,
                userAgent,
                timestamp: startTime,
            };
            await this.logAudit(request.userId, auditEntry);
            return {
                templateId: request.templateId,
                workspacePath: request.workspacePath,
                successful: false,
                startTime,
                endTime: Date.now(),
                duration: Date.now() - startTime,
                filesCreated: 0,
                extensionsInstalled: 0,
                envVarsSet: 0,
                errors: [{ file: 'template', reason: 'Template not found' }],
            };
        }
        // Simulate provisioning
        let filesCreated = 0;
        let extensionsInstalled = 0;
        let envVarsSet = 0;
        const errors = [];
        if (request.skipFiles === undefined || request.skipFiles.length === 0) {
            filesCreated = template.files?.length || 0;
        }
        else {
            filesCreated = (template.files?.length || 0) - request.skipFiles.length;
        }
        if (request.skipExtensions === undefined || request.skipExtensions.length === 0) {
            extensionsInstalled = template.extensions?.length || 0;
        }
        else {
            extensionsInstalled = (template.extensions?.length || 0) - request.skipExtensions.length;
        }
        envVarsSet = template.envSchema?.variables?.length || 0;
        const endTime = Date.now();
        const duration = endTime - startTime;
        // Verify provision time < 30s
        if (duration > this.config.provisionTimeoutMs) {
            errors.push({
                file: 'provision',
                reason: `Provision took ${duration}ms, exceeded timeout of ${this.config.provisionTimeoutMs}ms`,
            });
        }
        // Log audit
        const auditEntry = {
            id: `audit-prov-${request.templateId}-${startTime}`,
            userId: request.userId,
            userEmail: request.userEmail,
            operation: 'provisioned',
            status: errors.length === 0 ? 'success' : 'error',
            templateId: request.templateId,
            workspacePath: request.workspacePath,
            ipAddress,
            userAgent,
            timestamp: startTime,
            duration,
            details: {
                filesCreated,
                extensionsInstalled,
                envVarsSet,
            },
        };
        await this.logAudit(request.userId, auditEntry);
        this.updateStats();
        this.emit('template-provisioned', {
            templateId: request.templateId,
            duration,
            successful: errors.length === 0,
        });
        return {
            templateId: request.templateId,
            workspacePath: request.workspacePath,
            successful: errors.length === 0,
            startTime,
            endTime,
            duration,
            filesCreated,
            extensionsInstalled,
            envVarsSet,
            errors: errors.length > 0 ? errors : undefined,
        };
    }
    /**
     * Delete template
     */
    async deleteTemplate(userId, userEmail, templateId, ipAddress, userAgent) {
        const now = Date.now();
        this.templates.delete(templateId);
        // Update metadata
        const userMeta = this.metadata.get(userId);
        if (userMeta) {
            const idx = userMeta.findIndex((m) => m.templateId === templateId);
            if (idx >= 0) {
                userMeta.splice(idx, 1);
            }
        }
        // Log audit
        const auditEntry = {
            id: `audit-del-${templateId}-${now}`,
            userId,
            userEmail,
            operation: 'deleted',
            status: 'success',
            templateId,
            ipAddress,
            userAgent,
            timestamp: now,
        };
        await this.logAudit(userId, auditEntry);
        this.updateStats();
        this.emit('template-deleted', { templateId });
    }
    /**
     * List templates for user
     */
    async listTemplates(userId) {
        const userMeta = this.metadata.get(userId) || [];
        return userMeta.sort((a, b) => b.updatedAt - a.updatedAt);
    }
    /**
     * Query templates
     */
    async queryTemplates(query) {
        let results = [];
        if (query.userId) {
            results = this.metadata.get(query.userId) || [];
        }
        else {
            // Get all templates (optionally filtered by visibility)
            for (const userMeta of this.metadata.values()) {
                results.push(...userMeta);
            }
        }
        // Filter by visibility first (applies to both cases)
        if (query.visibility) {
            results = results.filter((m) => m.visibility === query.visibility);
        }
        // Filter by type
        if (query.templateType) {
            results = results.filter((m) => m.templateId.includes(query.templateType));
        }
        // Filter by tags
        if (query.tags && query.tags.length > 0) {
            results = results.filter((m) => query.tags.some((tag) => m.tags.includes(tag)));
        }
        // Sort by update time descending
        results.sort((a, b) => b.updatedAt - a.updatedAt);
        // Paginate
        const limit = query.limit || 20;
        const offset = query.offset || 0;
        return {
            templates: results.slice(offset, offset + limit),
            total: results.length,
            limit,
            offset,
        };
    }
    /**
     * Update template
     */
    async updateTemplate(userId, userEmail, templateId, updates, ipAddress, userAgent) {
        const template = this.templates.get(templateId);
        if (!template)
            throw new Error('Template not found');
        const updated = {
            ...template,
            ...updates,
            id: templateId,
            createdAt: template.createdAt,
            updatedAt: Date.now(),
        };
        this.templates.set(templateId, updated);
        // Update metadata
        const userMeta = this.metadata.get(userId);
        if (userMeta) {
            const meta = userMeta.find((m) => m.templateId === templateId);
            if (meta) {
                meta.updatedAt = Date.now();
                if (updates.name)
                    meta.name = updates.name;
                if (updates.version)
                    meta.version = updates.version;
            }
        }
        // Log audit
        const auditEntry = {
            id: `audit-upd-${templateId}-${Date.now()}`,
            userId,
            userEmail,
            operation: 'updated',
            status: 'success',
            templateId,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
        };
        await this.logAudit(userId, auditEntry);
        this.emit('template-updated', { templateId });
        return updated;
    }
    /**
     * Export template
     */
    async exportTemplate(userId, userEmail, templateId, ipAddress, userAgent) {
        const template = this.templates.get(templateId);
        if (!template)
            throw new Error('Template not found');
        const json = JSON.stringify(template, null, 2);
        // Log audit
        const auditEntry = {
            id: `audit-exp-${templateId}-${Date.now()}`,
            userId,
            userEmail,
            operation: 'exported',
            status: 'success',
            templateId,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
        };
        await this.logAudit(userId, auditEntry);
        this.emit('template-exported', { templateId });
        return json;
    }
    /**
     * Import template
     */
    async importTemplate(userId, userEmail, template, ipAddress, userAgent) {
        return this.createTemplate({ ...template, author: userId }, userId, userEmail, ipAddress, userAgent);
    }
    /**
     * Get audit log for user
     */
    async getAuditLog(userId, limit) {
        const log = this.auditLog.get(userId) || [];
        if (limit) {
            return log.slice(-limit);
        }
        return log;
    }
    /**
     * Get statistics
     */
    async getStatistics() {
        return { ...this.stats };
    }
    /**
     * Private: Log audit entry
     */
    async logAudit(userId, entry) {
        let log = this.auditLog.get(userId);
        if (!log) {
            log = [];
            this.auditLog.set(userId, log);
        }
        log.push(entry);
        // Keep only maxAuditLogSize entries
        if (log.length > this.config.maxAuditLogSize) {
            log.splice(0, log.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { userId, entry });
    }
    /**
     * Private: Update statistics
     */
    updateStats() {
        this.stats.totalTemplates = this.templates.size;
        // Calculate by type and visibility
        this.stats.templatesByType = {};
        this.stats.templatesByVisibility = {};
        let totalExts = 0;
        for (const template of this.templates.values()) {
            this.stats.templatesByType[template.templateType] =
                (this.stats.templatesByType[template.templateType] || 0) + 1;
            this.stats.templatesByVisibility[template.visibility] =
                (this.stats.templatesByVisibility[template.visibility] || 0) + 1;
            totalExts += template.extensions?.length || 0;
        }
        this.stats.totalExtensions = totalExts;
        this.stats.averageExtensionsPerTemplate =
            this.stats.totalTemplates > 0 ? totalExts / this.stats.totalTemplates : 0;
    }
    static getInstance(config) {
        if (!TemplateService.instance) {
            TemplateService.instance = new TemplateService(config);
        }
        return TemplateService.instance;
    }
}
//# sourceMappingURL=template-service.js.map