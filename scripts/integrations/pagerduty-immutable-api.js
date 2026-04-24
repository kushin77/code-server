#!/usr/bin/env node
/**
 * @file        scripts/integrations/pagerduty-immutable-api.js
 * @module      integrations/pagerduty
 * @description REST API for PagerDuty incident management
 */

const express = require('express');
const PagerDutyIntegrationService = require('./pagerduty-integration-service-immutable');

const app = express();
const PORT = process.env.PORT || 9105;

// Initialize service
const pagerdutyService = new PagerDutyIntegrationService({
    apiKey: process.env.PAGERDUTY_API_KEY,
    integrationKey: process.env.PAGERDUTY_INTEGRATION_KEY,
});

// Event listeners
pagerdutyService.on('alert-created', (context) => {
    console.log(`[PagerDuty] Alert: ${context.alertName} (${context.severity})`);
});

pagerdutyService.on('incident-created', (context) => {
    console.log(`[PagerDuty] Incident: ${context.incidentId} - ${context.title}`);
});

pagerdutyService.on('on-call-notified', (context) => {
    console.log(`[PagerDuty] Notified ${context.userId} at level ${context.escalationLevel}`);
});

pagerdutyService.on('incident-acknowledged', (context) => {
    console.log(`[PagerDuty] Acknowledged by ${context.acknowledgedBy}`);
});

pagerdutyService.on('incident-resolved', (context) => {
    console.log(`[PagerDuty] Resolved: ${context.incidentId} (${context.duration}ms)`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'pagerduty-integration' });
});

// Create alert
app.post('/alerts', (req, res) => {
    try {
        const alertToken = req.headers['x-alert-token'] || 
            `alert-${req.body.sourceId}-${Date.now()}`;
        
        const alertId = pagerdutyService.createAlert(req.body, alertToken);
        const alert = pagerdutyService.alerts.get(alertId);
        
        res.status(201).json({
            status: 'created',
            alertId,
            alertName: alert.alertName,
            severity: alert.severity,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create incident from alert
app.post('/alerts/:alertId/incident', (req, res) => {
    try {
        const incidentToken = req.headers['x-incident-token'] || 
            `incident-${req.params.alertId}-${Date.now()}`;
        
        const incidentId = pagerdutyService.createIncidentFromAlert(
            req.params.alertId,
            req.body,
            incidentToken
        );
        
        res.status(201).json({
            status: 'created',
            incidentId,
            alertId: req.params.alertId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Trigger on-call notification
app.post('/incidents/:incidentId/notify', (req, res) => {
    try {
        pagerdutyService.triggerOnCallNotification(req.params.incidentId, req.body);
        
        const incident = pagerdutyService.getIncident(req.params.incidentId);
        
        res.json({
            status: 'notified',
            incidentId: req.params.incidentId,
            assignedTo: incident.onCallUser?.name,
            escalationLevel: incident.escalationLevel,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Acknowledge incident
app.post('/incidents/:incidentId/acknowledge', (req, res) => {
    try {
        pagerdutyService.acknowledgeIncident(req.params.incidentId, req.body);
        
        res.json({
            status: 'acknowledged',
            incidentId: req.params.incidentId,
            acknowledgedBy: req.body.userId,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Resolve incident
app.post('/incidents/:incidentId/resolve', (req, res) => {
    try {
        pagerdutyService.resolveIncident(req.params.incidentId, req.body);
        
        const incident = pagerdutyService.getIncident(req.params.incidentId);
        
        res.json({
            status: 'resolved',
            incidentId: req.params.incidentId,
            resolvedBy: req.body.userId,
            duration: incident.resolvedAtMs - incident.createdAtMs,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get incident
app.get('/incidents/:incidentId', (req, res) => {
    try {
        const incident = pagerdutyService.getIncident(req.params.incidentId);
        
        if (!incident) {
            return res.status(404).json({ error: 'Incident not found' });
        }
        
        res.json({
            incidentId: incident.incidentId,
            alertId: incident.alertId,
            title: incident.title,
            severity: incident.severity,
            status: incident.status,
            service: incident.service,
            assignedTo: incident.onCallUser?.name,
            escalationLevel: incident.escalationLevel,
            createdAt: incident.createdAt,
            version: incident.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query incidents
app.get('/incidents', (req, res) => {
    try {
        const filters = {
            status: req.query.status,
            severity: req.query.severity,
            service: req.query.service,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const incidents = pagerdutyService.queryIncidents(filters);
        
        res.json({
            total: incidents.length,
            incidents: incidents.map(i => ({
                incidentId: i.incidentId,
                title: i.title,
                severity: i.severity,
                status: i.status,
                service: i.service,
                assignedTo: i.onCallUser?.name,
                createdAt: i.createdAt,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create escalation policy
app.post('/policies', (req, res) => {
    try {
        const policyId = pagerdutyService.createEscalationPolicy(req.body);
        
        const policy = pagerdutyService.escalationPolicies.get(policyId);
        
        res.status(201).json({
            status: 'created',
            policyId,
            name: policy.name,
            ruleCount: policy.escalationRules.length,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = pagerdutyService.getIncidentStatistics();
        
        res.json({
            totalIncidents: stats.totalIncidents,
            byStatus: stats.byStatus,
            bySeverity: stats.bySeverity,
            avgResolutionTimeMs: stats.avgResolutionTime,
            totalEscalations: stats.totalEscalations,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[PagerDuty Integration API] Listening on port ${PORT}`);
    console.log(`[PagerDuty Integration API] POST /alerts - Create alert`);
    console.log(`[PagerDuty Integration API] POST /alerts/:id/incident - Create incident`);
    console.log(`[PagerDuty Integration API] POST /incidents/:id/notify - Notify on-call`);
    console.log(`[PagerDuty Integration API] POST /incidents/:id/acknowledge - Acknowledge`);
    console.log(`[PagerDuty Integration API] POST /incidents/:id/resolve - Resolve`);
    console.log(`[PagerDuty Integration API] GET /incidents/:id - Get incident`);
    console.log(`[PagerDuty Integration API] GET /incidents - Query incidents`);
    console.log(`[PagerDuty Integration API] POST /policies - Create policy`);
    console.log(`[PagerDuty Integration API] GET /statistics - Get statistics`);
});
