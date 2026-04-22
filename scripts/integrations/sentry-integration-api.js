#!/usr/bin/env node
/**
 * @file        scripts/integrations/sentry-integration-api.js
 * @module      integrations/sentry
 * @description REST API server for Sentry integration with error browsing and AI-powered fixes
 */

const express = require('express');
const SentryIntegrationService = require('./sentry-integration-service');
const SentryErrorAnalyzer = require('./sentry-error-analyzer');

const app = express();
const PORT = process.env.SENTRY_API_PORT || 9095;

// Middleware
app.use(express.json());

// Initialize services
const sentryService = new SentryIntegrationService({
    authToken: process.env.SENTRY_AUTH_TOKEN,
    orgSlug: process.env.SENTRY_ORG_SLUG,
    projectSlugs: process.env.SENTRY_PROJECT_SLUG || 'code-server'
});

const analyzer = new SentryErrorAnalyzer({
    copilotToken: process.env.GITHUB_TOKEN,
    cache: true
});

// Event listeners for logging
sentryService.on('errors-fetched', (data) => {
    console.log(`[Sentry API] ✅ Fetched ${data.count} errors from ${data.projects.join(', ')}`);
});

sentryService.on('cache-hit', (data) => {
    console.log(`[Sentry API] 💾 Cache hit: ${data.cacheKey}`);
});

sentryService.on('error-resolved', (data) => {
    console.log(`[Sentry API] ✓ Error #${data.groupId} resolved as ${data.status}`);
});

analyzer.on('fix-generated', (data) => {
    console.log(`[Sentry API] 🔧 Fix suggestion generated for error ${data.errorId} (confidence: ${data.confidence})`);
});

sentryService.on('error', (data) => {
    console.error(`[Sentry API] ❌ Error: ${data.message}`, data.error);
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'sentry-integration-api', version: '1.0.0' });
});

/**
 * GET /api/sentry/errors
 * Fetch errors from Sentry with optional filtering
 * Query params: limit, offset, projects, environment, minLevel
 */
app.get('/api/sentry/errors', async (req, res) => {
    try {
        const { limit = 50, offset = 0, projects, environment = 'production', minLevel = 'error' } = req.query;
        
        const errors = await sentryService.fetchErrors({
            limit: parseInt(limit),
            offset: parseInt(offset),
            projects: projects ? projects.split(',') : undefined,
            environment,
            minLevel
        });
        
        res.json({
            success: true,
            errors: errors.map(e => ({
                id: e.id,
                title: e.title,
                level: e.level,
                culprit: e.culprit,
                timestamp: e.timestamp,
                count: e.count,
                stackTrace: e.stackTrace.slice(0, 3) // Top 3 frames only
            })),
            total: errors.length,
            hasMore: errors.length === parseInt(limit)
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message,
            details: error.response?.data
        });
    }
});

/**
 * GET /api/sentry/errors/:eventId
 * Fetch detailed error information
 */
app.get('/api/sentry/errors/:eventId', async (req, res) => {
    try {
        const { eventId } = req.params;
        const { project = 'code-server' } = req.query;
        
        const details = await sentryService.getErrorDetails(project, eventId);
        
        res.json({
            success: true,
            error: details
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * POST /api/sentry/ai-fix
 * Generate AI-powered fix suggestion for an error
 */
app.post('/api/sentry/ai-fix', async (req, res) => {
    try {
        const { errorId, projectSlug = 'code-server', stackTrace, errorMessage, errorType } = req.body;
        
        // Prepare context for AI analysis
        const aiContext = await sentryService.prepareAIContext(
            { id: errorId, title: errorMessage, type: errorType },
            stackTrace || []
        );
        
        // Generate fix suggestion
        const suggestion = await analyzer.generateFixSuggestion(aiContext);
        
        res.json({
            success: true,
            suggestion: {
                errorId,
                fix: suggestion.fix,
                explanation: suggestion.explanation,
                confidence: suggestion.confidence,
                codeSnippet: suggestion.codeSnippet,
                testCase: suggestion.testCase,
                relatedDocs: suggestion.relatedDocs
            }
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * PUT /api/sentry/errors/:groupId/resolve
 * Resolve an error in Sentry
 */
app.put('/api/sentry/errors/:groupId/resolve', async (req, res) => {
    try {
        const { groupId } = req.params;
        const { resolution = 'fixed', projectSlug = 'code-server' } = req.body;
        
        const result = await sentryService.resolveError(projectSlug, groupId, resolution);
        
        res.json({
            success: true,
            result
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * POST /api/sentry/cache/clear
 * Clear the Sentry error cache
 */
app.post('/api/sentry/cache/clear', (req, res) => {
    sentryService.clearCache();
    analyzer.clearCache();
    
    res.json({
        success: true,
        message: 'Cache cleared'
    });
});

/**
 * GET /api/sentry/projects
 * List available Sentry projects
 */
app.get('/api/sentry/projects', (req, res) => {
    res.json({
        success: true,
        projects: sentryService.projectSlugs,
        organization: sentryService.orgSlug
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('[Sentry API] Unhandled error:', err);
    res.status(500).json({
        success: false,
        error: 'Internal server error',
        message: err.message
    });
});

// Start server
const server = app.listen(PORT, () => {
    console.log(`[Sentry API] 🚀 Server running on port ${PORT}`);
    console.log(`[Sentry API] Organization: ${sentryService.orgSlug}`);
    console.log(`[Sentry API] Projects: ${sentryService.projectSlugs.join(', ')}`);
    console.log(`[Sentry API] Health check: http://localhost:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('[Sentry API] SIGTERM received, shutting down gracefully...');
    server.close(() => {
        console.log('[Sentry API] Server closed');
        process.exit(0);
    });
});

module.exports = { app, server, sentryService, analyzer };
