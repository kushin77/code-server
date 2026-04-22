#!/usr/bin/env node
/**
 * @file        scripts/integrations/cicd-integration-api.js
 * @module      integrations/cicd
 * @description REST API for GitHub Actions workflow monitoring and control
 */

const express = require('express');
const CICDIntegrationService = require('./cicd-integration-service');

const app = express();
const PORT = process.env.CICD_API_PORT || 9096;

// Middleware
app.use(express.json());

// Initialize service
const cicdService = new CICDIntegrationService({
    githubToken: process.env.GITHUB_TOKEN,
    owner: process.env.GITHUB_ORG || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server'
});

// Event listeners
cicdService.on('workflows-fetched', (data) => {
    console.log(`[CI/CD API] ✅ Fetched ${data.count} workflows (${data.status})`);
});

cicdService.on('jobs-fetched', (data) => {
    console.log(`[CI/CD API] ✅ Fetched ${data.count} jobs for run ${data.runId}`);
});

cicdService.on('logs-fetched', (data) => {
    console.log(`[CI/CD API] ✅ Fetched ${data.lineCount} log lines for job ${data.jobId}`);
});

cicdService.on('workflow-triggered', (data) => {
    console.log(`[CI/CD API] 🚀 Workflow ${data.workflowId} triggered`);
});

cicdService.on('workflow-rerun', (data) => {
    console.log(`[CI/CD API] 🔄 Workflow run ${data.runId} re-run initiated`);
});

cicdService.on('poll-update', (data) => {
    console.log(`[CI/CD API] 📡 Poll update: ${data.runs.length} runs fetched`);
});

cicdService.on('error', (data) => {
    console.error(`[CI/CD API] ❌ Error: ${data.message}`, data.error);
});

// Start polling
cicdService.startPolling(30); // Poll every 30 seconds

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'cicd-integration-api', version: '1.0.0' });
});

/**
 * GET /api/cicd/workflows
 * Fetch workflow runs
 * Query params: status (all, completed, in_progress, queued), branch, limit
 */
app.get('/api/cicd/workflows', async (req, res) => {
    try {
        const { status = 'all', branch = 'main', limit = 20 } = req.query;
        
        const workflows = await cicdService.fetchWorkflowRuns({
            status,
            branch,
            limit: parseInt(limit)
        });
        
        res.json({
            success: true,
            workflows,
            total: workflows.length
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * GET /api/cicd/runs/:runId/jobs
 * Fetch jobs for a workflow run
 */
app.get('/api/cicd/runs/:runId/jobs', async (req, res) => {
    try {
        const { runId } = req.params;
        
        const jobs = await cicdService.fetchJobsForRun(runId);
        
        res.json({
            success: true,
            jobs,
            total: jobs.length
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * GET /api/cicd/jobs/:jobId/logs
 * Fetch logs for a job
 */
app.get('/api/cicd/jobs/:jobId/logs', async (req, res) => {
    try {
        const { jobId } = req.params;
        const { lines = 100 } = req.query;
        
        const logs = await cicdService.fetchJobLogs(null, jobId);
        
        res.json({
            success: true,
            logs: logs.slice(-parseInt(lines)),
            total: logs.length
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * POST /api/cicd/workflows/:workflowId/dispatch
 * Trigger a workflow
 */
app.post('/api/cicd/workflows/:workflowId/dispatch', async (req, res) => {
    try {
        const { workflowId } = req.params;
        const { inputs = {} } = req.body;
        
        const result = await cicdService.triggerWorkflow(workflowId, inputs);
        
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
 * POST /api/cicd/runs/:runId/rerun
 * Re-run a workflow
 */
app.post('/api/cicd/runs/:runId/rerun', async (req, res) => {
    try {
        const { runId } = req.params;
        
        const result = await cicdService.reRunWorkflow(runId);
        
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
 * GET /api/cicd/runs/:runId/dag
 * Get job DAG for a workflow run
 */
app.get('/api/cicd/runs/:runId/dag', async (req, res) => {
    try {
        const { runId } = req.params;
        
        const dag = await cicdService.buildJobDAG(runId);
        
        res.json({
            success: true,
            dag
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * GET /api/cicd/status
 * Get overall CI/CD status
 */
app.get('/api/cicd/status', async (req, res) => {
    try {
        const recentWorkflows = await cicdService.fetchWorkflowRuns({
            limit: 10
        });
        
        const statuses = {
            total: recentWorkflows.length,
            success: recentWorkflows.filter(w => w.conclusion === 'success').length,
            failure: recentWorkflows.filter(w => w.conclusion === 'failure').length,
            inProgress: recentWorkflows.filter(w => w.status === 'in_progress').length,
            queued: recentWorkflows.filter(w => w.status === 'queued').length
        };
        
        res.json({
            success: true,
            status: statuses,
            isPolling: cicdService.isPolling
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

/**
 * POST /api/cicd/cache/clear
 * Clear the cache
 */
app.post('/api/cicd/cache/clear', (req, res) => {
    cicdService.clearCache();
    
    res.json({
        success: true,
        message: 'Cache cleared'
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('[CI/CD API] Unhandled error:', err);
    res.status(500).json({
        success: false,
        error: 'Internal server error',
        message: err.message
    });
});

// Start server
const server = app.listen(PORT, () => {
    console.log(`[CI/CD API] 🚀 Server running on port ${PORT}`);
    console.log(`[CI/CD API] Repository: ${cicdService.owner}/${cicdService.repo}`);
    console.log(`[CI/CD API] Health check: http://localhost:${PORT}/health`);
    console.log(`[CI/CD API] Polling enabled (30s interval)`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('[CI/CD API] SIGTERM received, shutting down gracefully...');
    cicdService.stopPolling();
    server.close(() => {
        console.log('[CI/CD API] Server closed');
        process.exit(0);
    });
});

module.exports = { app, server, cicdService };
