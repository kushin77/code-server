#!/usr/bin/env node
/**
 * @file        scripts/integrations/cicd-status-api.js
 * @module      integrations/cicd
 * @description REST API for CI/CD pipeline status with immutable snapshots
 */

const express = require('express');
const CICDStatusService = require('./cicd-status-service');

const app = express();
const PORT = process.env.PORT || 9095;

// Initialize service
const cicdService = new CICDStatusService({
    gitHubToken: process.env.GITHUB_TOKEN,
    owner: process.env.GITHUB_OWNER || 'kushin77',
    repo: process.env.GITHUB_REPO || 'code-server',
});

// Event listeners
cicdService.on('run-registered', (run) => {
    console.log(`[CI/CD] Workflow started: ${run.name} (#${run.id})`);
});

cicdService.on('job-updated', (job) => {
    console.log(`[CI/CD] Job ${job.name}: ${job.status} → ${job.conclusion || 'pending'}`);
});

cicdService.on('job-rerun-requested', (result) => {
    console.log(`[CI/CD] Job re-run requested: ${result.jobId}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'cicd-status' });
});

// Register workflow run
app.post('/runs', (req, res) => {
    try {
        const run = cicdService.registerWorkflowRun(req.body);
        res.status(201).json(run);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Update job status
app.put('/jobs/:jobId', (req, res) => {
    try {
        const updateToken = req.headers['x-idempotency-key'];
        const job = cicdService.updateJobStatus(req.body, updateToken);
        res.json(job);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Append logs
app.post('/jobs/:jobId/logs', (req, res) => {
    try {
        const { lines } = req.body;
        const logs = cicdService.appendLogs(req.params.jobId, lines);
        res.json({
            jobId: req.params.jobId,
            lineCount: logs.length,
            lastLine: logs.length,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get job logs
app.get('/jobs/:jobId/logs', (req, res) => {
    try {
        const fromLine = parseInt(req.query.from) || 0;
        const toLine = parseInt(req.query.to) || null;
        
        const logs = cicdService.getJobLogs(req.params.jobId, fromLine, toLine);
        
        if (!logs) {
            return res.status(404).json({ error: 'Job not found' });
        }
        
        res.json(logs);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get pipeline status
app.get('/runs/:runId/status', (req, res) => {
    try {
        const status = cicdService.getPipelineStatus(req.params.runId);
        
        if (!status) {
            return res.status(404).json({ error: 'Run not found' });
        }
        
        res.json(status);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get pipeline DAG
app.get('/runs/:runId/dag', (req, res) => {
    try {
        const dag = cicdService.buildPipelineDAG(req.params.runId);
        
        if (!dag) {
            return res.status(404).json({ error: 'Run not found' });
        }
        
        res.json(dag);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get job details
app.get('/jobs/:jobId', (req, res) => {
    try {
        const details = cicdService.getJobDetails(req.params.jobId);
        
        if (!details) {
            return res.status(404).json({ error: 'Job not found' });
        }
        
        res.json(details);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Request job re-run (idempotent)
app.post('/jobs/:jobId/rerun', (req, res) => {
    try {
        const rerunToken = req.headers['x-idempotency-key'] || `${Date.now()}`;
        const result = cicdService.rerunJob(req.params.jobId, rerunToken);
        
        res.json(result);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[CI/CD Status API] Listening on port ${PORT}`);
    console.log(`[CI/CD Status API] POST /runs - Register workflow run`);
    console.log(`[CI/CD Status API] GET /runs/:runId/status - Get pipeline status`);
    console.log(`[CI/CD Status API] GET /runs/:runId/dag - Get DAG visualization`);
    console.log(`[CI/CD Status API] GET /jobs/:jobId - Get job details`);
    console.log(`[CI/CD Status API] GET /jobs/:jobId/logs - Get job logs`);
    console.log(`[CI/CD Status API] POST /jobs/:jobId/rerun - Request job re-run`);
});
