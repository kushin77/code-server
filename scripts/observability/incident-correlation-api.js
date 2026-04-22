#!/usr/bin/env node
/**
 * Incident Correlation API
 * REST API for incident correlation and SLO tracking
 */

const express = require('express');
const IncidentCorrelationEngine = require('./incident-correlation-engine');

const app = express();
const PORT = process.env.PORT || 9092;

// Initialize correlation engine
const engine = new IncidentCorrelationEngine({
    correlationWindowMs: 300000, // 5 minutes
    minRelevanceScore: 0.5,
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'incident-correlation-api' });
});

// Record SLO breach
app.post('/slo-breaches', (req, res) => {
    try {
        const breach = engine.recordSLOBreach(req.body);
        res.status(201).json(breach);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record deployment
app.post('/deployments', (req, res) => {
    try {
        const deployment = engine.recordDeployment(req.body);
        res.status(201).json(deployment);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record config change
app.post('/config-changes', (req, res) => {
    try {
        const change = engine.recordConfigChange(req.body);
        res.status(201).json(change);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record restart
app.post('/restarts', (req, res) => {
    try {
        const restart = engine.recordRestart(req.body);
        res.status(201).json(restart);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record error
app.post('/errors', (req, res) => {
    try {
        const error = engine.recordError(req.body);
        res.status(201).json(error);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get incident summary
app.get('/incidents/summary', (req, res) => {
    const timeWindow = parseInt(req.query.timeWindow) || 3600000; // 1 hour default
    const summary = engine.getIncidentSummary(timeWindow);
    res.json(summary);
});

// Get correlations
app.get('/correlations', (req, res) => {
    res.json({
        total: engine.correlations.length,
        correlations: engine.correlations.map(c => ({
            slo: c.sloEvent.slo,
            service: c.sloEvent.service,
            severity: c.sloEvent.severity,
            correlatedEventCount: c.correlatedEvents.length,
            timeline: c.timeline,
            rootCause: c.rootCauseHypothesis,
            recommendations: c.recommendedActions,
        })),
    });
});

// Get specific correlation
app.get('/correlations/:id', (req, res) => {
    const { id } = req.params;
    const correlation = engine.correlations[parseInt(id)];
    
    if (!correlation) {
        return res.status(404).json({ error: 'Correlation not found' });
    }
    
    res.json({
        slo: correlation.sloEvent,
        timeline: correlation.timeline,
        correlatedEvents: correlation.correlatedEvents,
        rootCause: correlation.rootCauseHypothesis,
        recommendations: correlation.recommendedActions,
    });
});

// Get events by service
app.get('/services/:service/events', (req, res) => {
    const { service } = req.params;
    
    const events = {
        sloBreaches: engine.events.sloBreaches.filter(e => e.service === service),
        deployments: engine.events.deployments.filter(e => e.service === service),
        configChanges: engine.events.configChanges.filter(e => e.service === service),
        restarts: engine.events.restarts.filter(e => e.service === service),
    };
    
    res.json({ service, events });
});

// Listen
app.listen(PORT, () => {
    console.log(`[Incident Correlation API] Listening on port ${PORT}`);
    console.log(`[Incident Correlation API] POST /slo-breaches - Record SLO breach`);
    console.log(`[Incident Correlation API] POST /deployments - Record deployment`);
    console.log(`[Incident Correlation API] GET /correlations - Get all correlations`);
    console.log(`[Incident Correlation API] GET /incidents/summary - Get incident summary`);
});
