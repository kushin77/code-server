#!/usr/bin/env node
/**
 * Access Pattern Anomaly Detection API
 * REST API for anomaly detection and alerting
 */

const express = require('express');
const { AccessPatternAnomalyDetector } = require('./access-pattern-anomaly-detector');

const app = express();
const PORT = process.env.PORT || 9093;

// Initialize detector
const detector = new AccessPatternAnomalyDetector({
    anomalyThreshold: 0.6,
    baselineWindowDays: 30,
});

// Event listeners
detector.on('model-trained', (info) => {
    console.log('[Anomaly Detector] Model trained:', info);
});

detector.on('anomaly-detected', (anomaly) => {
    console.log(`[Anomaly Detector] ALERT: User ${anomaly.userId} - Severity: ${anomaly.severity}`);
    console.log(`  Score: ${anomaly.anomalyScore.toFixed(3)}, Reason: ${anomaly.reason}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        service: 'access-pattern-anomaly-detection',
        modelTrained: detector.modelTrained,
    });
});

// Record access event
app.post('/access', (req, res) => {
    try {
        const access = detector.recordAccess(req.body);
        
        // Check for anomalies if model is trained
        let anomalyResult = null;
        if (detector.modelTrained) {
            anomalyResult = detector.checkAnomaly(access);
        }
        
        res.status(201).json({
            access,
            anomalyCheck: anomalyResult,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Train baseline model
app.post('/model/train', (req, res) => {
    try {
        detector.trainBaseline();
        res.json({
            status: 'success',
            message: 'Model training initiated',
            trained: detector.modelTrained,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Get anomaly report for user
app.get('/users/:userId/anomalies', (req, res) => {
    const { userId } = req.params;
    const timeWindow = parseInt(req.query.timeWindow) || 7; // days
    
    const report = detector.getAnomalyReport(userId, timeWindow);
    res.json(report);
});

// Get summary statistics
app.get('/summary', (req, res) => {
    const totalUsers = detector.users.size;
    const totalAnomalies = detector.anomalies.length;
    const recentAnomalies = detector.anomalies.filter(a => 
        (Date.now() - a.timestamp) <= 86400000 // Last 24 hours
    );
    
    const criticalCount = recentAnomalies.filter(a => a.severity === 'critical').length;
    const highCount = recentAnomalies.filter(a => a.severity === 'high').length;
    
    res.json({
        totalUsers,
        totalAnomalies,
        recentAnomalies: recentAnomalies.length,
        critical: criticalCount,
        high: highCount,
        modelStatus: {
            trained: detector.modelTrained,
            baselineWindowDays: detector.baselineWindowDays,
            anomalyThreshold: detector.anomalyThreshold,
        },
    });
});

// Get anomalies for all users
app.get('/anomalies', (req, res) => {
    const severity = req.query.severity; // Filter by 'critical', 'high', 'medium', 'low'
    const hours = parseInt(req.query.hours) || 24;
    
    const windowMs = hours * 60 * 60 * 1000;
    const filtered = detector.anomalies.filter(a => {
        const recentEnough = (Date.now() - a.timestamp) <= windowMs;
        const severityMatch = !severity || a.severity === severity;
        return recentEnough && severityMatch;
    });
    
    res.json({
        query: { severity, hours },
        total: filtered.length,
        anomalies: filtered
            .sort((a, b) => b.anomalyScore - a.anomalyScore)
            .map(a => ({
                userId: a.userId,
                timestamp: new Date(a.timestamp).toISOString(),
                type: a.type,
                score: a.anomalyScore.toFixed(3),
                severity: a.severity,
                reason: a.reason,
            })),
    });
});

// Webhook for continuous anomaly checking
app.post('/check', (req, res) => {
    try {
        const access = detector.recordAccess(req.body);
        const anomalyResult = detector.checkAnomaly(access);
        
        res.json({
            userId: access.userId,
            anomalous: anomalyResult.anomalous,
            score: anomalyResult.score.toFixed(3),
            severity: anomalyResult.severity,
            reason: anomalyResult.reason,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Access Pattern Anomaly Detection] Listening on port ${PORT}`);
    console.log(`[Access Pattern Anomaly Detection] POST /access - Record access event`);
    console.log(`[Access Pattern Anomaly Detection] POST /model/train - Train baseline model`);
    console.log(`[Access Pattern Anomaly Detection] GET /users/:userId/anomalies - Get user report`);
    console.log(`[Access Pattern Anomaly Detection] GET /anomalies - Get all recent anomalies`);
});
