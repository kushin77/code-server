#!/usr/bin/env node
// @file        apps/backend/src/routes/extension-registry.ts
// @module      routes
// @description Extension registry management REST API endpoints
import { Router } from 'express';
import { RegistryManagerService } from '../services/extension-registry/registry-manager';
import { getLogger } from '../lib/logger';
const router = Router();
const service = RegistryManagerService.getInstance();
const logger = getLogger('RegistryRoutes');
/**
 * POST /api/extension-registry/register
 * Register an extension in the private registry
 */
router.post('/register', (req, res) => {
    try {
        const { id, name, publisher, version, displayName, description, icon, repository } = req.body;
        if (!id || !publisher || !version) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: id, publisher, version',
            });
        }
        const ext = service.registerExtension(id, {
            id,
            name: name || id,
            publisher,
            version,
            displayName,
            description,
            icon,
            repository,
        });
        res.status(201).json({
            success: true,
            data: ext,
        });
    }
    catch (error) {
        logger.error('Failed to register extension', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to register extension',
        });
    }
});
/**
 * GET /api/extension-registry/extension/:id
 * Get extension metadata
 */
router.get('/extension/:id', (req, res) => {
    try {
        const { id } = req.params;
        const ext = service.getExtension(id);
        if (!ext) {
            return res.status(404).json({
                success: false,
                error: 'Extension not found',
            });
        }
        res.status(200).json({
            success: true,
            data: ext,
        });
    }
    catch (error) {
        logger.error('Failed to get extension', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to get extension',
        });
    }
});
/**
 * GET /api/extension-registry/extensions
 * Get all registered extensions
 */
router.get('/extensions', (req, res) => {
    try {
        const extensions = service.getAllExtensions();
        res.status(200).json({
            success: true,
            data: {
                extensions,
                total: extensions.length,
            },
        });
    }
    catch (error) {
        logger.error('Failed to get extensions', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to get extensions',
        });
    }
});
/**
 * POST /api/extension-registry/block
 * Block an extension
 */
router.post('/block', (req, res) => {
    try {
        const { id, reason, severity = 'medium', alternatives = [] } = req.body;
        if (!id || !reason) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: id, reason',
            });
        }
        const status = service.blockExtension(id, reason, severity, alternatives);
        res.status(201).json({
            success: true,
            data: status,
        });
    }
    catch (error) {
        logger.error('Failed to block extension', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to block extension',
        });
    }
});
/**
 * POST /api/extension-registry/unblock/:id
 * Unblock an extension
 */
router.post('/unblock/:id', (req, res) => {
    try {
        const { id } = req.params;
        service.unblockExtension(id);
        res.status(200).json({
            success: true,
            data: { id, message: 'Extension unblocked' },
        });
    }
    catch (error) {
        logger.error('Failed to unblock extension', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to unblock extension',
        });
    }
});
/**
 * GET /api/extension-registry/blocklist
 * Get blocklist
 */
router.get('/blocklist', (req, res) => {
    try {
        const blocklist = service.getBlocklist();
        res.status(200).json({
            success: true,
            data: {
                blocked: blocklist,
                total: blocklist.length,
            },
        });
    }
    catch (error) {
        logger.error('Failed to get blocklist', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to get blocklist',
        });
    }
});
/**
 * POST /api/extension-registry/pin-version
 * Set version pinning for an extension
 */
router.post('/pin-version', (req, res) => {
    try {
        const { extensionId, allowedVersions, workspaceId, reason } = req.body;
        if (!extensionId || !allowedVersions || !Array.isArray(allowedVersions)) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: extensionId, allowedVersions (array)',
            });
        }
        const pinning = service.setPinning(extensionId, allowedVersions, workspaceId, reason);
        res.status(201).json({
            success: true,
            data: pinning,
        });
    }
    catch (error) {
        logger.error('Failed to set version pinning', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to set version pinning',
        });
    }
});
/**
 * POST /api/extension-registry/validate-version
 * Validate if an extension version is allowed
 */
router.post('/validate-version', (req, res) => {
    try {
        const { extensionId, version, workspaceId } = req.body;
        if (!extensionId || !version) {
            return res.status(400).json({
                success: false,
                error: 'Missing required fields: extensionId, version',
            });
        }
        const validation = service.validateVersion(extensionId, version, workspaceId);
        res.status(200).json({
            success: true,
            data: validation,
        });
    }
    catch (error) {
        logger.error('Failed to validate version', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to validate version',
        });
    }
});
/**
 * POST /api/extension-registry/record-install/:id
 * Record extension installation
 */
router.post('/record-install/:id', (req, res) => {
    try {
        const { id } = req.params;
        service.recordInstallation(id);
        const stats = service.getInstallationStats(id);
        res.status(200).json({
            success: true,
            data: {
                extensionId: id,
                ...stats,
            },
        });
    }
    catch (error) {
        logger.error('Failed to record installation', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to record installation',
        });
    }
});
/**
 * GET /api/extension-registry/statistics
 * Get registry statistics
 */
router.get('/statistics', (req, res) => {
    try {
        const stats = service.getStatistics();
        res.status(200).json({
            success: true,
            data: stats,
        });
    }
    catch (error) {
        logger.error('Failed to get statistics', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to get statistics',
        });
    }
});
/**
 * POST /api/extension-registry/sync
 * Sync registry from Open VSIX backend
 */
router.post('/sync', (req, res) => {
    try {
        service.recordSync();
        const stats = service.getStatistics();
        res.status(200).json({
            success: true,
            data: {
                message: 'Registry synced',
                stats,
            },
        });
    }
    catch (error) {
        logger.error('Failed to sync registry', {
            error: error.message,
            stack: error.stack,
        });
        res.status(500).json({
            success: false,
            error: 'Failed to sync registry',
        });
    }
});
/**
 * GET /api/extension-registry/health
 * Health check endpoint
 */
router.get('/health', (req, res) => {
    res.status(200).json({
        success: true,
        data: {
            status: 'ok',
            service: 'extension-registry',
        },
    });
});
export default router;
//# sourceMappingURL=extension-registry.js.map