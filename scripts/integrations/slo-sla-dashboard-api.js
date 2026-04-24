#!/usr/bin/env node
/**
 * @file        scripts/integrations/slo-sla-dashboard-api.js
 * @module      observability/slos
 * @description REST API for SLO/SLA dashboard
 */

const express = require('express');
const SLOSLADashboardService = require('./slo-sla-dashboard-service');

const app = express();
const PORT = process.env.PORT || 9098;

// Initialize service
const sloService = new SLOSLADashboardService({
    serviceName: process.env.SERVICE_NAME || 'code-server',
});

// Event listeners
sloService.on('budget-calculated', (context) => {
    console.log(`[SLO] ${context.sloId}: ${context.status} - ${context.remaining}% remaining`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'slo-sla-dashboard' });
});

// Get all SLOs
app.get('/slos', (req, res) => {
    try {
        const slos = sloService.getAllSLOs();
        
        res.json({
            total: slos.length,
            slos: slos.map(slo => ({
                id: slo.id,
                name: slo.name,
                description: slo.description,
                target: slo.target.percentage,
                unit: slo.target.unit,
                period: slo.errorBudget.period,
                version: slo.version,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get single SLO
app.get('/slos/:sloId', (req, res) => {
    try {
        const slo = sloService.getSLO(req.params.sloId);
        
        if (!slo) {
            return res.status(404).json({ error: 'SLO not found' });
        }
        
        res.json({
            id: slo.id,
            name: slo.name,
            description: slo.description,
            target: slo.target,
            errorBudget: slo.errorBudget,
            thresholds: slo.thresholds,
            alerts: slo.alerts,
            version: slo.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get error budget (idempotent)
app.get('/slos/:sloId/budget', (req, res) => {
    try {
        const sloId = req.params.sloId;
        const calcToken = req.headers['x-calc-token'] || 
            `calc-${Date.now()}-${Math.random()}`;
        
        const budget = sloService.calculateErrorBudget(sloId, calcToken);
        
        res.json({
            sloId: budget.sloId,
            sloName: budget.sloName,
            period: budget.period,
            actual: budget.actual,
            target: budget.target,
            budget: budget.budget,
            status: budget.status,
            burnRate: budget.burnRate,
            timestamp: budget.timestamp,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get budget history
app.get('/slos/:sloId/history', (req, res) => {
    try {
        const days = req.query.days ? parseInt(req.query.days) : 30;
        const history = sloService.getBudgetHistory(req.params.sloId, days);
        
        res.json({
            sloId: req.params.sloId,
            period: `${days}d`,
            history: history.map(h => ({
                date: h.date,
                consumed: parseFloat(h.consumed),
                remaining: parseFloat(h.remaining),
                incidentCount: h.incidentCount,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get burn rate (idempotent)
app.get('/slos/:sloId/burn-rate', (req, res) => {
    try {
        const sloId = req.params.sloId;
        const windowMinutes = req.query.window ? parseInt(req.query.window) : 5;
        const burnToken = req.headers['x-burn-token'] || 
            `burn-${Date.now()}-${Math.random()}`;
        
        const burnRate = sloService.calculateBurnRate(sloId, burnToken, windowMinutes);
        
        res.json({
            sloId: burnRate.sloId,
            sloName: burnRate.sloName,
            window: burnRate.window,
            errorRate: parseFloat(burnRate.errorRate),
            burnRate: parseFloat(burnRate.burnRate),
            forecast: burnRate.forecast,
            severity: burnRate.severity,
            timestamp: burnRate.timestamp,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get dashboard (immutable snapshot)
app.get('/dashboard', (req, res) => {
    try {
        const token = req.headers['x-dashboard-token'] || 
            `dash-${Date.now()}-${Math.random()}`;
        
        const dashboard = sloService.getDashboard(token);
        
        res.json({
            serviceName: dashboard.serviceName,
            timestamp: dashboard.timestamp,
            summary: dashboard.summary,
            budgets: dashboard.budgets.map(b => ({
                sloId: b.sloId,
                sloName: b.sloName,
                period: b.period,
                actual: b.actual,
                target: b.target,
                budget: b.budget,
                status: b.status,
                burnRate: b.burnRate,
            })),
            burnRates: dashboard.burnRates.map(br => ({
                sloId: br.sloId,
                sloName: br.sloName,
                errorRate: parseFloat(br.errorRate),
                burnRate: parseFloat(br.burnRate),
                forecast: br.forecast,
                severity: br.severity,
            })),
            alerts: dashboard.alerts.map(a => ({
                type: a.type,
                severity: a.severity,
                sloId: a.sloId,
                message: a.message,
                action: a.action,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[SLO/SLA Dashboard API] Listening on port ${PORT}`);
    console.log(`[SLO/SLA Dashboard API] GET /slos - List all SLOs`);
    console.log(`[SLO/SLA Dashboard API] GET /slos/:sloId - Get SLO details`);
    console.log(`[SLO/SLA Dashboard API] GET /slos/:sloId/budget - Get error budget`);
    console.log(`[SLO/SLA Dashboard API] GET /slos/:sloId/history - Get budget history`);
    console.log(`[SLO/SLA Dashboard API] GET /slos/:sloId/burn-rate - Get burn rate`);
    console.log(`[SLO/SLA Dashboard API] GET /dashboard - Get dashboard snapshot`);
});
