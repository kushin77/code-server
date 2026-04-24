#!/usr/bin/env node
/**
 * @file        scripts/integrations/datadog-immutable-api.js
 * @module      integrations/datadog
 * @description REST API for DataDog metrics integration
 */

const express = require('express');
const DataDogIntegrationService = require('./datadog-immutable-service');

const app = express();
const PORT = process.env.PORT || 9109;

// Initialize service
const datadogService = new DataDogIntegrationService({
    apiKey: process.env.DATADOG_API_KEY,
    appKey: process.env.DATADOG_APP_KEY,
    site: process.env.DATADOG_SITE,
});

// Event listeners
datadogService.on('metric-recorded', (context) => {
    console.log(`[DataDog] Metric: ${context.metricName} = ${context.value}`);
});

datadogService.on('metrics-submitted', (context) => {
    console.log(`[DataDog] Submitted: ${context.submissionId} (${context.batchSize} metrics)`);
});

datadogService.on('submission-success', (context) => {
    console.log(`[DataDog] Success: ${context.submissionId} → Batch ${context.batchId}`);
});

datadogService.on('submission-failure', (context) => {
    console.log(`[DataDog] Failed: ${context.submissionId} - ${context.errorCode}`);
});

datadogService.on('dashboard-created', (context) => {
    console.log(`[DataDog] Dashboard: ${context.title} (${context.widgetCount} widgets)`);
});

datadogService.on('dashboard-published', (context) => {
    console.log(`[DataDog] Published: ${context.datadogDashboardId}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'datadog-integration' });
});

// Record metric observation
app.post('/metrics', (req, res) => {
    try {
        const metricId = datadogService.recordMetricObservation(req.body);
        
        const metric = datadogService.getMetric(metricId);
        
        res.status(201).json({
            status: 'recorded',
            metricId,
            metricName: metric.metricName,
            value: metric.value,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Submit metrics (idempotent)
app.post('/metrics/submit', (req, res) => {
    try {
        const submissionToken = req.headers['x-submission-token'] || 
            `sub-${Date.now()}`;
        
        const metricIds = req.body.metricIds || [];
        const submissionId = datadogService.submitMetrics(metricIds, submissionToken);
        
        const submission = datadogService.getSubmission(submissionId);
        
        res.json({
            status: 'submitted',
            submissionId,
            batchSize: submission.batchSize,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record submission success
app.post('/submissions/:submissionId/success', (req, res) => {
    try {
        datadogService.recordSubmissionSuccess(req.params.submissionId, req.body);
        
        const submission = datadogService.getSubmission(req.params.submissionId);
        
        res.json({
            status: 'accepted',
            submissionId: req.params.submissionId,
            datadogBatchId: submission.datadogBatchId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record submission failure
app.post('/submissions/:submissionId/failure', (req, res) => {
    try {
        datadogService.recordSubmissionFailure(req.params.submissionId, req.body);
        
        res.json({
            status: 'failure_recorded',
            submissionId: req.params.submissionId,
            errorCode: req.body.code,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get metric
app.get('/metrics/:metricId', (req, res) => {
    try {
        const metric = datadogService.getMetric(req.params.metricId);
        
        if (!metric) {
            return res.status(404).json({ error: 'Metric not found' });
        }
        
        res.json({
            metricId: metric.metricId,
            metricName: metric.metricName,
            value: metric.value,
            unit: metric.unit,
            host: metric.host,
            service: metric.service,
            timestamp: metric.timestamp,
            submitted: metric.submitted,
            version: metric.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query metrics
app.get('/metrics', (req, res) => {
    try {
        const filters = {
            metricName: req.query.metricName,
            host: req.query.host,
            service: req.query.service,
            submitted: req.query.submitted ? req.query.submitted === 'true' : undefined,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const metrics = datadogService.queryMetrics(filters);
        
        res.json({
            total: metrics.length,
            metrics: metrics.map(m => ({
                metricId: m.metricId,
                metricName: m.metricName,
                value: m.value,
                host: m.host,
                service: m.service,
                timestamp: m.timestamp,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get submission
app.get('/submissions/:submissionId', (req, res) => {
    try {
        const submission = datadogService.getSubmission(req.params.submissionId);
        
        if (!submission) {
            return res.status(404).json({ error: 'Submission not found' });
        }
        
        res.json({
            submissionId: submission.submissionId,
            status: submission.status,
            batchSize: submission.batchSize,
            submittedAt: submission.submittedAt,
            datadogBatchId: submission.datadogBatchId,
            version: submission.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create dashboard
app.post('/dashboards', (req, res) => {
    try {
        const dashboardId = datadogService.createDashboard(req.body);
        
        const dashboard = datadogService.dashboards.get(dashboardId);
        
        res.status(201).json({
            status: 'created',
            dashboardId,
            title: dashboard.title,
            widgetCount: dashboard.widgets.length,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Publish dashboard
app.post('/dashboards/:dashboardId/publish', (req, res) => {
    try {
        const datadogDashboardId = req.body.datadogDashboardId;
        datadogService.publishDashboard(req.params.dashboardId, datadogDashboardId);
        
        res.json({
            status: 'published',
            dashboardId: req.params.dashboardId,
            datadogDashboardId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = datadogService.getMetricStatistics();
        
        res.json({
            totalMetrics: stats.totalMetrics,
            submittedMetrics: stats.submittedMetrics,
            pendingMetrics: stats.pendingMetrics,
            totalSubmissions: stats.totalSubmissions,
            successfulSubmissions: stats.successfulSubmissions,
            failedSubmissions: stats.failedSubmissions,
            successRatePercent: stats.successRate,
            totalDashboards: stats.totalDashboards,
            publishedDashboards: stats.publishedDashboards,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[DataDog Integration API] Listening on port ${PORT}`);
    console.log(`[DataDog Integration API] POST /metrics - Record metric observation`);
    console.log(`[DataDog Integration API] GET /metrics - Query metrics`);
    console.log(`[DataDog Integration API] GET /metrics/:id - Get metric`);
    console.log(`[DataDog Integration API] POST /metrics/submit - Submit metrics (idempotent)`);
    console.log(`[DataDog Integration API] GET /submissions/:id - Get submission`);
    console.log(`[DataDog Integration API] POST /submissions/:id/success - Record success`);
    console.log(`[DataDog Integration API] POST /submissions/:id/failure - Record failure`);
    console.log(`[DataDog Integration API] POST /dashboards - Create dashboard`);
    console.log(`[DataDog Integration API] POST /dashboards/:id/publish - Publish dashboard`);
    console.log(`[DataDog Integration API] GET /statistics - Get statistics`);
});
