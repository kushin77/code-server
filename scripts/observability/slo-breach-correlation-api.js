#!/usr/bin/env node
/**
 * @file        scripts/observability/slo-breach-correlation-api.js
 * @module      observability/slo
 * @description REST API for SLO breach correlation
 */

const express = require('express');
const SLOBreachCorrelationService = require('./slo-breach-correlation-service');

const app = express();
const PORT = process.env.PORT || 9103;

// Initialize service
const correlationService = new SLOBreachCorrelationService({
    serviceName: process.env.SERVICE_NAME || 'code-server',
});

// Event listeners
correlationService.on('slo-breach-detected', (context) => {
    console.log(`[SLO Breach] Detected: ${context.sloName} - ${context.breachPct}% over threshold (${context.severity})`);
});

correlationService.on('deployment-recorded', (context) => {
    console.log(`[Deployment] Recorded: v${context.version} - ${context.services.join(', ')}`);
});

correlationService.on('config-change-recorded', (context) => {
    console.log(`[Config Change] ${context.service}/${context.configKey} - Impact: ${context.impactLevel}`);
});

correlationService.on('breach-deployment-correlated', (context) => {
    console.log(`[Correlation] Match found: ${context.matchId} - Confidence: ${(context.confidence * 100).toFixed(1)}%${context.likelyRootCause ? ' [ROOT CAUSE]' : ''}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'slo-breach-correlation' });
});

// Record SLO breach
app.post('/breaches', (req, res) => {
    try {
        const breachToken = req.headers['x-breach-token'] || `breach-${Date.now()}`;
        
        const breachId = correlationService.recordSLOBreach(req.body, breachToken);
        const breach = correlationService.getSLOBreach(breachId);
        
        res.status(201).json({
            status: 'recorded',
            breachId,
            sloName: breach.sloName,
            breachPct: breach.breachPct,
            severity: breach.severity,
            detectedAt: breach.detectedAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record deployment
app.post('/deployments', (req, res) => {
    try {
        const deployId = correlationService.recordDeployment(req.body);
        
        res.status(201).json({
            status: 'recorded',
            deployId,
            version: req.body.version,
            services: req.body.services,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record config change
app.post('/config-changes', (req, res) => {
    try {
        const changeId = correlationService.recordConfigChange(req.body);
        
        res.status(201).json({
            status: 'recorded',
            changeId,
            service: req.body.service,
            configKey: req.body.configKey,
            impactLevel: req.body.impactLevel,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Correlate breach with deployment (idempotent)
app.post('/breaches/:breachId/correlate-deployment/:deployId', (req, res) => {
    try {
        const correlationToken = req.headers['x-correlation-token'] || 
            `corr-${req.params.breachId}-${req.params.deployId}-${Date.now()}`;
        
        const matchId = correlationService.correlateBreachwithDeployment(
            req.params.breachId,
            req.params.deployId,
            correlationToken
        );
        
        const match = correlationService.getCorrelationMatch(matchId);
        
        res.status(201).json({
            status: 'correlated',
            matchId,
            breachId: req.params.breachId,
            deployId: req.params.deployId,
            confidence: match.confidence,
            likelyRootCause: match.likelyRootCause,
            reasons: match.reasons,
            recommendedAction: match.recommendedAction,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get SLO breach
app.get('/breaches/:breachId', (req, res) => {
    try {
        const breach = correlationService.getSLOBreach(req.params.breachId);
        
        if (!breach) {
            return res.status(404).json({ error: 'Breach not found' });
        }
        
        res.json({
            breachId: breach.breachId,
            sloName: breach.sloName,
            metric: breach.metric,
            threshold: breach.threshold,
            actualValue: breach.actualValue,
            breachPct: breach.breachPct,
            severity: breach.severity,
            status: breach.status,
            detectedAt: breach.detectedAt,
            duration: breach.duration,
            correlations: breach.correlations,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query correlation matches (idempotent)
app.get('/correlations', (req, res) => {
    try {
        const filters = {
            breachId: req.query.breachId,
            minConfidence: req.query.minConfidence ? parseFloat(req.query.minConfidence) : undefined,
            likelyRootCause: req.query.likelyRootCause === 'true',
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const matches = correlationService.queryCorrelationMatches(filters);
        
        res.json({
            total: matches.length,
            filters,
            correlations: matches.map(m => ({
                matchId: m.matchId,
                breachId: m.breachId,
                deployId: m.deployId,
                confidence: m.confidence,
                likelyRootCause: m.likelyRootCause,
                reasons: m.reasons,
                timeDeltaMin: m.timeDeltaMin,
                recommendedAction: m.recommendedAction,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get correlation match
app.get('/correlations/:matchId', (req, res) => {
    try {
        const match = correlationService.getCorrelationMatch(req.params.matchId);
        
        if (!match) {
            return res.status(404).json({ error: 'Correlation not found' });
        }
        
        res.json({
            matchId: match.matchId,
            breachId: match.breachId,
            deployId: match.deployId,
            confidence: match.confidence,
            likelyRootCause: match.likelyRootCause,
            reasons: match.reasons,
            timeDeltaMin: match.timeDeltaMin,
            sloName: match.sloName,
            metric: match.metric,
            breachPct: match.breachPct,
            deployVersion: match.deployVersion,
            deployedServices: match.deployedServices,
            recommendedAction: match.recommendedAction,
            detectedAt: match.detectedAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get correlation statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = correlationService.getCorrelationStatistics();
        
        res.json({
            totalMatches: stats.totalMatches,
            likelyRootCauses: stats.likelyRootCauses,
            averageConfidence: stats.averageConfidence.toFixed(3),
            byConfidenceLevel: stats.byConfidenceLevel,
            deploymentCorrelations: stats.deploymentCorrelations,
            totalBreaches: stats.totalBreaches,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[SLO Breach Correlation API] Listening on port ${PORT}`);
    console.log(`[SLO Breach Correlation API] POST /breaches - Record SLO breach`);
    console.log(`[SLO Breach Correlation API] POST /deployments - Record deployment`);
    console.log(`[SLO Breach Correlation API] POST /config-changes - Record config change`);
    console.log(`[SLO Breach Correlation API] POST /breaches/:id/correlate-deployment/:id - Correlate (idempotent)`);
    console.log(`[SLO Breach Correlation API] GET /breaches/:id - Get breach`);
    console.log(`[SLO Breach Correlation API] GET /correlations - Query matches`);
    console.log(`[SLO Breach Correlation API] GET /correlations/:id - Get match`);
    console.log(`[SLO Breach Correlation API] GET /statistics - Get statistics`);
});
