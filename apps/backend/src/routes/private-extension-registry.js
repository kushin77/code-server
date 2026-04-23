// @file        apps/backend/src/routes/private-extension-registry.ts
// @module      collaboration/private-extension-registry
// @description REST API routes for the private extension registry service
// @owner       backend
// @status      active
import { Router } from 'express';
import { getAuditService } from '../services/audit/audit-service';
import { getLogger } from '../lib/logger';
const logger = getLogger('PrivateExtensionRegistryRoutes');
function emitValidationAudit(decision, actor) {
    getAuditService()?.emit({
        userId: actor,
        role: 'system',
        identityType: 'automation',
        method: 'GET',
        path: '/api/extensions/registry/validate',
        action: decision.allowed ? 'allow' : 'deny',
        resourceType: 'config',
        resource: decision.extensionId,
        fileAction: 'read',
        reason: decision.reason,
    });
}
function requireText(value, field) {
    if (typeof value !== 'string') {
        throw new Error(`Missing required query parameter: ${field}`);
    }
    const trimmed = value.trim();
    if (!trimmed) {
        throw new Error(`Missing required query parameter: ${field}`);
    }
    return trimmed;
}
export function initializePrivateExtensionRegistryRoutes(service) {
    const router = Router();
    router.get('/api/extensions/registry', (_request, response) => {
        try {
            response.json(service.getSnapshot());
        }
        catch (error) {
            logger.error('Failed to fetch private extension registry snapshot', { error });
            response.status(500).json({ error: 'Failed to fetch registry snapshot' });
        }
    });
    router.get('/api/extensions/registry/approved', (_request, response) => {
        try {
            response.json({ approved: service.listApprovedExtensions() });
        }
        catch (error) {
            logger.error('Failed to fetch approved extension manifest', { error });
            response.status(500).json({ error: 'Failed to fetch approved extensions' });
        }
    });
    router.get('/api/extensions/registry/blocked', (_request, response) => {
        try {
            response.json({ blocked: service.listBlockedExtensions() });
        }
        catch (error) {
            logger.error('Failed to fetch blocked extension manifest', { error });
            response.status(500).json({ error: 'Failed to fetch blocked extensions' });
        }
    });
    router.get('/api/extensions/registry/validate', (request, response) => {
        try {
            const actor = typeof request.query.actor === 'string' && request.query.actor.trim()
                ? request.query.actor.trim()
                : 'system';
            const extensionId = requireText(request.query.extensionId, 'extensionId');
            const requestedVersion = typeof request.query.version === 'string' ? request.query.version.trim() : undefined;
            const decision = service.validateExtension(extensionId, requestedVersion);
            emitValidationAudit(decision, actor);
            response.json({
                ...decision,
                actor,
            });
        }
        catch (error) {
            logger.error('Failed to validate private extension', { error, query: request.query });
            const message = error instanceof Error ? error.message : 'Failed to validate extension';
            response.status(400).json({ error: message });
        }
    });
    router.get('/api/extensions/registry/publish-check', (request, response) => {
        try {
            const actor = typeof request.query.actor === 'string' && request.query.actor.trim()
                ? request.query.actor.trim()
                : 'system';
            const extensionId = requireText(request.query.extensionId, 'extensionId');
            const version = requireText(request.query.version, 'version');
            const decision = service.canPublish(extensionId, version);
            emitValidationAudit(decision, actor);
            response.json({
                ...decision,
                actor,
            });
        }
        catch (error) {
            logger.error('Failed to run private extension publish check', { error, query: request.query });
            const message = error instanceof Error ? error.message : 'Failed to run publish check';
            response.status(400).json({ error: message });
        }
    });
    return router;
}
export { PrivateExtensionRegistryService } from '../services/private-extension-registry';
//# sourceMappingURL=private-extension-registry.js.map