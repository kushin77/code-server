#!/usr/bin/env node
/**
 * @file        scripts/observability/anomaly-detection-api.js
 * @module      observability/anomalies
 * @description REST API for anomaly detection service
 */

const express = require('express');
const AnomalyDetectionService = require('./anomaly-detection-service');

const app = express();
const PORT = process.env.PORT || 9101;

// Initialize service
const anomalyService = new AnomalyDetectionService({
    serviceName: process.env.SERVICE_NAME || 'code-server',
    baselineWindowDays: process.env.BASELINE_WINDOW_DAYS || 14,
});

// Event listeners
anomalyService.on('baseline-calculated', (context) => {
    console.log(`[Anomaly Detection] Baseline calculated: ${context.metricName} (μ=${context.mean.toFixed(2)}, σ=${context.stdDev.toFixed(2)})`);
});

anomalyService.on('anomaly-detected', (context) => {
    console.log(`[Anomaly Detection] Anomaly detected: ${context.anomalyId} - ${context.metricName} (${context.severity}, confidence=${(context.confidence * 100).toFixed(1)}%)`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'anomaly-detection' });
});

// Record metric
app.post('/metrics', (req, res) => {
    try {
        const { metricName, value, timestamp } = req.body;
        
        if (!metricName || value === undefined) {
            return res.status(400).json({ error: 'metricName and value are required' });
        }
        
        anomalyService.recordMetric(metricName, value, timestamp);
        
        res.status(201).json({
            status: 'recorded',
            metricName,
            value,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Calculate baseline
app.post('/baselines/:metricName', (req, res) => {
    try {
        const baseline = anomalyService.calculateBaseline(req.params.metricName);
        
        if (!baseline) {
            return res.status(400).json({ error: 'Insufficient metric data for baseline' });
        }
        
        res.status(201).json({
            status: 'calculated',
            metricName: baseline.metricName,
            mean: baseline.mean,
            stdDev: baseline.stdDev,
            thresholds: baseline.thresholds,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get baseline
app.get('/baselines/:metricName', (req, res) => {
    try {
        const baseline = anomalyService.getBaseline(req.params.metricName);
        
        if (!baseline) {
            return res.status(404).json({ error: 'Baseline not found' });
        }
        
        res.json({
            metricName: baseline.metricName,
            mean: baseline.mean,
            stdDev: baseline.stdDev,
            p50: baseline.p50,
            p95: baseline.p95,
            p99: baseline.p99,
            thresholds: baseline.thresholds,
            sampleCount: baseline.sampleCount,
            calculatedAt: baseline.calculatedAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get all baselines
app.get('/baselines', (req, res) => {
    try {
        const baselines = anomalyService.getAllBaselines();
        
        res.json({
            total: baselines.length,
            baselines: baselines.map(b => ({
                metricName: b.metricName,
                mean: b.mean,
                stdDev: b.stdDev,
                p99: b.p99,
                sampleCount: b.sampleCount,
                version: b.version,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Detect anomaly (idempotent)
app.post('/metrics/:metricName/detect', (req, res) => {
    try {
        const { value } = req.body;
        const scoreToken = req.headers['x-score-token'] || 
            `score-${req.params.metricName}-${Date.now()}`;
        
        if (value === undefined) {
            return res.status(400).json({ error: 'value is required' });
        }
        
        const anomalyId = anomalyService.detectAnomaly(
            req.params.metricName,
            value,
            scoreToken
        );
        
        const score = anomalyService.getAnomalyScore(anomalyId);
        
        res.status(201).json({
            status: 'detected',
            anomalyId,
            severity: score.severity,
            type: score.type,
            zScore: score.zScore.toFixed(2),
            confidence: (score.confidence * 100).toFixed(1) + '%',
            recommendation: score.recommendation,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get anomaly score
app.get('/anomalies/:anomalyId', (req, res) => {
    try {
        const score = anomalyService.getAnomalyScore(req.params.anomalyId);
        
        if (!score) {
            return res.status(404).json({ error: 'Anomaly not found' });
        }
        
        res.json({
            anomalyId: score.anomalyId,
            metricName: score.metricName,
            currentValue: score.currentValue,
            baselineMean: score.baselineMean,
            deviation: score.deviation,
            zScore: score.zScore.toFixed(2),
            percentile: (score.percentile * 100).toFixed(1) + '%',
            severity: score.severity,
            type: score.type,
            confidence: (score.confidence * 100).toFixed(1) + '%',
            recommendation: score.recommendation,
            timestamp: score.timestamp,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query anomalies
app.get('/anomalies', (req, res) => {
    try {
        const filters = {
            metricName: req.query.metricName,
            severity: req.query.severity,
            type: req.query.type,
            minConfidence: req.query.minConfidence ? parseFloat(req.query.minConfidence) : undefined,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const anomalies = anomalyService.queryAnomalies(filters);
        
        res.json({
            total: anomalies.length,
            filters,
            anomalies: anomalies.map(a => ({
                anomalyId: a.anomalyId,
                metricName: a.metricName,
                severity: a.severity,
                type: a.type,
                zScore: a.zScore.toFixed(2),
                confidence: (a.confidence * 100).toFixed(1) + '%',
                timestamp: a.timestamp,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get anomaly statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = anomalyService.getAnomalyStatistics();
        
        res.json({
            totalAnomalies: stats.totalAnomalies,
            bySeverity: stats.bySeverity,
            byType: stats.byType,
            averageConfidence: (stats.averageConfidence * 100).toFixed(1) + '%',
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Detect trend
app.post('/metrics/:metricName/detect-trend', (req, res) => {
    try {
        const { recentValues } = req.body;
        
        if (!recentValues || !Array.isArray(recentValues)) {
            return res.status(400).json({ error: 'recentValues array is required' });
        }
        
        const trend = anomalyService.detectTrend(req.params.metricName, recentValues);
        
        if (!trend) {
            return res.status(400).json({ error: 'Baseline or insufficient data' });
        }
        
        res.json({
            metricName: trend.metricName,
            trend: trend.trend,
            confidence: (trend.confidence * 100).toFixed(1) + '%',
            timestamp: trend.timestamp,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Anomaly Detection API] Listening on port ${PORT}`);
    console.log(`[Anomaly Detection API] POST /metrics - Record metric`);
    console.log(`[Anomaly Detection API] POST /baselines/:metricName - Calculate baseline`);
    console.log(`[Anomaly Detection API] GET /baselines/:metricName - Get baseline`);
    console.log(`[Anomaly Detection API] POST /metrics/:metricName/detect - Detect anomaly (idempotent)`);
    console.log(`[Anomaly Detection API] GET /anomalies - Query anomalies`);
    console.log(`[Anomaly Detection API] POST /metrics/:metricName/detect-trend - Detect trend`);
    console.log(`[Anomaly Detection API] GET /statistics - Get statistics`);
});
