#!/usr/bin/env node
/**
 * @file        scripts/integrations/prometheus-immutable-api.js
 * @module      integrations/prometheus
 * @description REST API for Prometheus metrics integration
 */

const express = require('express');
const PrometheusIntegrationService = require('./prometheus-immutable-service');

const app = express();
const PORT = process.env.PORT || 9112;

// Initialize service
const prometheusService = new PrometheusIntegrationService({
    baseUrl: process.env.PROMETHEUS_URL,
});

// Event listeners
prometheusService.on('scrape-config-created', (context) => {
    console.log(`[Prometheus] Config: ${context.jobName} @ ${context.interval}`);
});

prometheusService.on('target-registered', (context) => {
    console.log(`[Prometheus] Target: ${context.jobName} → ${context.address}`);
});

prometheusService.on('scrape-result', (context) => {
    console.log(`[Prometheus] Scrape: ${context.targetId} - ${context.status} (${context.durationMs}ms)`);
});

prometheusService.on('recording-rule-created', (context) => {
    console.log(`[Prometheus] Recording: ${context.recordName} = ${context.expr}`);
});

prometheusService.on('alert-rule-created', (context) => {
    console.log(`[Prometheus] Alert: ${context.name}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'prometheus-integration' });
});

// Create scrape config
app.post('/scrape-configs', (req, res) => {
    try {
        const configId = prometheusService.createScrapeConfig(req.body);
        
        const config = prometheusService.scrapeConfigs.get(configId);
        
        res.status(201).json({
            status: 'created',
            configId,
            jobName: config.jobName,
            interval: config.scrapeInterval,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Register target (idempotent)
app.post('/targets/register', (req, res) => {
    try {
        const registrationToken = req.headers['x-registration-token'] || 
            `reg-${req.body.jobName}-${Date.now()}`;
        
        const targetId = prometheusService.registerTarget(req.body, registrationToken);
        
        const target = prometheusService.getTarget(targetId);
        
        res.status(201).json({
            status: 'registered',
            targetId,
            jobName: target.jobName,
            address: `${target.scheme}://${target.host}:${target.port}`,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get target
app.get('/targets/:targetId', (req, res) => {
    try {
        const target = prometheusService.getTarget(req.params.targetId);
        
        if (!target) {
            return res.status(404).json({ error: 'Target not found' });
        }
        
        res.json({
            targetId: target.targetId,
            jobName: target.jobName,
            host: target.host,
            port: target.port,
            scheme: target.scheme,
            status: target.status,
            lastScrapeAt: target.lastScrapeAt,
            scrapeCount: target.scrapeCount,
            version: target.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query targets
app.get('/targets', (req, res) => {
    try {
        const filters = {
            jobName: req.query.jobName,
            status: req.query.status,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const targets = prometheusService.queryTargets(filters);
        
        res.json({
            total: targets.length,
            targets: targets.map(t => ({
                targetId: t.targetId,
                jobName: t.jobName,
                address: `${t.scheme}://${t.host}:${t.port}`,
                status: t.status,
                scrapeCount: t.scrapeCount,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record scrape result
app.post('/targets/:targetId/scrape', (req, res) => {
    try {
        prometheusService.recordScrapeResult(req.params.targetId, req.body);
        
        const target = prometheusService.getTarget(req.params.targetId);
        
        res.json({
            status: 'recorded',
            targetId: req.params.targetId,
            targetStatus: target.status,
            scrapeCount: target.scrapeCount,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create recording rule
app.post('/recording-rules', (req, res) => {
    try {
        const ruleId = prometheusService.createRecordingRule(req.body);
        
        const rule = prometheusService.recordingRules.get(ruleId);
        
        res.status(201).json({
            status: 'created',
            ruleId,
            recordName: rule.recordName,
            expr: rule.expr,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create alert rule
app.post('/alert-rules', (req, res) => {
    try {
        const alertId = prometheusService.createAlertRule(req.body);
        
        const alert = prometheusService.alertRules.get(alertId);
        
        res.status(201).json({
            status: 'created',
            alertId,
            name: alert.name,
            expr: alert.expr,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = prometheusService.getStatistics();
        
        res.json({
            totalConfigs: stats.totalConfigs,
            enabledConfigs: stats.enabledConfigs,
            totalTargets: stats.totalTargets,
            activeTargets: stats.activeTargets,
            inactiveTargets: stats.inactiveTargets,
            unknownTargets: stats.unknownTargets,
            totalRecordingRules: stats.totalRecordingRules,
            enabledRecordingRules: stats.enabledRecordingRules,
            totalAlertRules: stats.totalAlertRules,
            enabledAlertRules: stats.enabledAlertRules,
            avgScrapeDurationMs: stats.avgScrapeIntervalMs,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Prometheus Integration API] Listening on port ${PORT}`);
    console.log(`[Prometheus Integration API] POST /scrape-configs - Create scrape config`);
    console.log(`[Prometheus Integration API] POST /targets/register - Register target (idempotent)`);
    console.log(`[Prometheus Integration API] GET /targets/:id - Get target`);
    console.log(`[Prometheus Integration API] GET /targets - Query targets`);
    console.log(`[Prometheus Integration API] POST /targets/:id/scrape - Record scrape result`);
    console.log(`[Prometheus Integration API] POST /recording-rules - Create recording rule`);
    console.log(`[Prometheus Integration API] POST /alert-rules - Create alert rule`);
    console.log(`[Prometheus Integration API] GET /statistics - Get statistics`);
});
