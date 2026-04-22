#!/usr/bin/env node
/**
 * @file        scripts/integrations/pagerduty-integration-api.js
 * @module      integrations/pagerduty
 * @description REST API for incident handling with immutable snapshots
 *
 * IaC Principles:
 * - Immutable: Incident payloads stored as-received
 * - Idempotent: Webhook endpoint safe for retry (deduplication via incident ID + timestamp)
 * - Versioned: All state changes tracked with timestamps
 */

/**
 * PagerDuty Integration API
 * REST API for incident handling and workspace context generation
 */

const express = require('express');
const PagerDutyIntegrationService = require('./pagerduty-integration-service');

const app = express();
const PORT = process.env.PORT || 9094;

// Initialize service
const pagerdutyService = new PagerDutyIntegrationService({
    webhookSecret: process.env.PAGERDUTY_WEBHOOK_SECRET || 'default-secret',
    onCallSchedules: {
        'api-gateway': 'api-team-primary',
        'workspace-service': 'workspace-team-primary',
        'auth-service': 'security-team-primary',
        'websocket-gateway': 'infra-team-primary',
        'database': 'dba-team-primary',
        'redis': 'cache-team-primary',
    },
});

// Event listeners
pagerdutyService.on('incident-triggered', (context) => {
    console.log(`[PagerDuty] 🚨 Incident triggered: #${context.incident.id} - ${context.incident.title}`);
    console.log(`[PagerDuty] Service: ${context.incident.serviceName}`);
    console.log(`[PagerDuty] Opening ${context.relevantFiles.serviceFiles.length} relevant files`);
});

pagerdutyService.on('incident-acknowledged', (incident) => {
    console.log(`[PagerDuty] ✅ Incident acknowledged: #${incident.id} by ${incident.acknowledgedBy}`);
});

pagerdutyService.on('incident-resolved', (incident) => {
    console.log(`[PagerDuty] ✓ Incident resolved: #${incident.id}`);
});

pagerdutyService.on('incident-escalated', (context) => {
    console.log(`[PagerDuty] 📈 Incident escalated: #${context.incident.id} (level ${context.escalationLevel})`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'pagerduty-integration' });
});

// PagerDuty webhook endpoint
app.post('/webhooks/pagerduty', (req, res) => {
    try {
        // Validate signature (optional, can be disabled)
        // const signature = req.headers['x-pagerduty-signature'];
        // if (!pagerdutyService.validateWebhookSignature(req.body, signature)) {
        //     return res.status(401).json({ error: 'Invalid signature' });
        // }
        
        // Handle event
        const result = pagerdutyService.handleIncidentWebhook(req.body);
        
        if (!result) {
            return res.status(400).json({ error: 'Unknown event type' });
        }
        
        res.json({
            status: 'received',
            incident: result.incident?.id,
            action: result.action,
            filesOpened: result.relevantFiles?.serviceFiles?.length || 0,
        });
    } catch (err) {
        console.error('[PagerDuty] Webhook error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get workspace context for incident
app.get('/incidents/:incidentId/workspace-context', (req, res) => {
    const { incidentId } = req.params;
    
    const context = pagerdutyService.generateWorkspaceContext(incidentId);
    if (!context) {
        return res.status(404).json({ error: 'Incident not found' });
    }
    
    res.json(context);
});

// Get incident status
app.get('/incidents/:incidentId', (req, res) => {
    const { incidentId } = req.params;
    
    const incident = pagerdutyService.getIncidentStatus(incidentId);
    if (!incident) {
        return res.status(404).json({ error: 'Incident not found' });
    }
    
    res.json(incident);
});

// Get active incidents
app.get('/incidents', (req, res) => {
    const active = pagerdutyService.getActiveIncidents();
    res.json({
        total: active.length,
        incidents: active,
    });
});

// Get incident history
app.get('/incidents/history', (req, res) => {
    const limit = parseInt(req.query.limit) || 50;
    const history = pagerdutyService.getIncidentHistory(limit);
    
    res.json({
        total: history.length,
        incidents: history,
    });
});

// Manual incident simulation (for testing)
app.post('/test/incident', (req, res) => {
    try {
        const simulatedEvent = {
            type: 'incident.triggered',
            data: {
                incident: {
                    incident_number: `test-${Date.now()}`,
                    title: req.body.title || 'Test incident',
                    description: req.body.description || 'Test incident description',
                    urgency: req.body.severity || 'high',
                    service: {
                        id: 'test-service',
                        summary: req.body.service || 'Test Service',
                    },
                    created_at: new Date().toISOString(),
                    assigned_via: 'webhook',
                },
            },
        };
        
        const result = pagerdutyService.handleIncidentWebhook(simulatedEvent);
        
        res.status(201).json({
            status: 'simulated',
            incident: result.incident,
            relevantFiles: result.relevantFiles,
            workspaceContext: pagerdutyService.generateWorkspaceContext(result.incident.id),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[PagerDuty Integration API] Listening on port ${PORT}`);
    console.log(`[PagerDuty Integration API] POST /webhooks/pagerduty - Webhook endpoint`);
    console.log(`[PagerDuty Integration API] GET /incidents - Get active incidents`);
    console.log(`[PagerDuty Integration API] GET /incidents/:id/workspace-context - Get workspace context`);
    console.log(`[PagerDuty Integration API] POST /test/incident - Test incident simulation`);
});
