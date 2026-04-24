#!/usr/bin/env node
/**
 * @file        scripts/integrations/newrelic-immutable-api.js
 * @module      integrations/newrelic
 * @description REST API for New Relic APM integration
 */

const express = require('express');
const NewRelicIntegrationService = require('./newrelic-immutable-service');

const app = express();
const PORT = process.env.PORT || 9110;

// Initialize service
const nrService = new NewRelicIntegrationService({
    licenseKey: process.env.NEW_RELIC_LICENSE_KEY,
    accountId: process.env.NEW_RELIC_ACCOUNT_ID,
    appName: process.env.NEW_RELIC_APP_NAME,
});

// Event listeners
nrService.on('transaction-recorded', (context) => {
    console.log(`[New Relic] Transaction: ${context.name} - ${context.durationMs}ms`);
});

nrService.on('batch-submitted', (context) => {
    console.log(`[New Relic] Batch: ${context.batchId} (${context.batchSize} txns)`);
});

nrService.on('batch-success', (context) => {
    console.log(`[New Relic] Success: ${context.batchId} → ${context.nrBatchId}`);
});

nrService.on('batch-failure', (context) => {
    console.log(`[New Relic] Failed: ${context.batchId} - ${context.errorCode}`);
});

nrService.on('alert-created', (context) => {
    console.log(`[New Relic] Alert: ${context.name} on ${context.metric}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'newrelic-integration' });
});

// Record transaction
app.post('/transactions', (req, res) => {
    try {
        const transactionId = nrService.recordTransaction(req.body);
        
        const txn = nrService.getTransaction(transactionId);
        
        res.status(201).json({
            status: 'recorded',
            transactionId,
            name: txn.name,
            durationMs: txn.durationMs,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get transaction
app.get('/transactions/:transactionId', (req, res) => {
    try {
        const txn = nrService.getTransaction(req.params.transactionId);
        
        if (!txn) {
            return res.status(404).json({ error: 'Transaction not found' });
        }
        
        res.json({
            transactionId: txn.transactionId,
            name: txn.name,
            type: txn.type,
            method: txn.method,
            url: txn.url,
            durationMs: txn.durationMs,
            responseCode: txn.responseCode,
            spanCount: txn.spans.length,
            submitted: txn.submitted,
            version: txn.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query transactions
app.get('/transactions', (req, res) => {
    try {
        const filters = {
            name: req.query.name,
            method: req.query.method,
            submitted: req.query.submitted ? req.query.submitted === 'true' : undefined,
            minDurationMs: req.query.minDurationMs ? parseInt(req.query.minDurationMs) : undefined,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const txns = nrService.queryTransactions(filters);
        
        res.json({
            total: txns.length,
            transactions: txns.map(t => ({
                transactionId: t.transactionId,
                name: t.name,
                method: t.method,
                durationMs: t.durationMs,
                submitted: t.submitted,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Submit transaction batch (idempotent)
app.post('/transactions/submit', (req, res) => {
    try {
        const batchToken = req.headers['x-batch-token'] || 
            `batch-${Date.now()}`;
        
        const transactionIds = req.body.transactionIds || [];
        const batchId = nrService.submitTransactionBatch(transactionIds, batchToken);
        
        const batch = nrService.getBatch(batchId);
        
        res.json({
            status: 'submitted',
            batchId,
            batchSize: batch.batchSize,
            totalDurationMs: batch.totalDurationMs,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record batch success
app.post('/batches/:batchId/success', (req, res) => {
    try {
        nrService.recordBatchSuccess(req.params.batchId, req.body);
        
        const batch = nrService.getBatch(req.params.batchId);
        
        res.json({
            status: 'accepted',
            batchId: req.params.batchId,
            nrBatchId: batch.nrBatchId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record batch failure
app.post('/batches/:batchId/failure', (req, res) => {
    try {
        nrService.recordBatchFailure(req.params.batchId, req.body);
        
        res.json({
            status: 'failure_recorded',
            batchId: req.params.batchId,
            errorCode: req.body.code,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get batch
app.get('/batches/:batchId', (req, res) => {
    try {
        const batch = nrService.getBatch(req.params.batchId);
        
        if (!batch) {
            return res.status(404).json({ error: 'Batch not found' });
        }
        
        res.json({
            batchId: batch.batchId,
            status: batch.status,
            batchSize: batch.batchSize,
            totalDurationMs: batch.totalDurationMs,
            avgDurationMs: batch.avgDurationMs,
            submittedAt: batch.submittedAt,
            nrBatchId: batch.nrBatchId,
            version: batch.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create alert condition
app.post('/alerts', (req, res) => {
    try {
        const alertId = nrService.createAlertCondition(req.body);
        
        const alert = nrService.alerts.get(alertId);
        
        res.status(201).json({
            status: 'created',
            alertId,
            name: alert.name,
            metric: alert.metric,
            threshold: alert.threshold,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = nrService.getAPMStatistics();
        
        res.json({
            totalTransactions: stats.totalTransactions,
            submittedTransactions: stats.submittedTransactions,
            pendingTransactions: stats.pendingTransactions,
            averageDurationMs: stats.averageDurationMs,
            maxDurationMs: stats.maxDurationMs,
            minDurationMs: stats.minDurationMs,
            totalBatches: stats.totalBatches,
            successfulBatches: stats.successfulBatches,
            failedBatches: stats.failedBatches,
            successRatePercent: stats.successRate,
            totalAlerts: stats.totalAlerts,
            enabledAlerts: stats.enabledAlerts,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[New Relic Integration API] Listening on port ${PORT}`);
    console.log(`[New Relic Integration API] POST /transactions - Record transaction`);
    console.log(`[New Relic Integration API] GET /transactions/:id - Get transaction`);
    console.log(`[New Relic Integration API] GET /transactions - Query transactions`);
    console.log(`[New Relic Integration API] POST /transactions/submit - Submit batch (idempotent)`);
    console.log(`[New Relic Integration API] GET /batches/:id - Get batch`);
    console.log(`[New Relic Integration API] POST /batches/:id/success - Record success`);
    console.log(`[New Relic Integration API] POST /batches/:id/failure - Record failure`);
    console.log(`[New Relic Integration API] POST /alerts - Create alert`);
    console.log(`[New Relic Integration API] GET /statistics - Get APM statistics`);
});
