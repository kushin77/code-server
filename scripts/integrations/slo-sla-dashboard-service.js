#!/usr/bin/env node
/**
 * @file        scripts/integrations/slo-sla-dashboard-service.js
 * @module      observability/slos
 * @description SLO/SLA dashboard with immutable metrics and idempotent budget calculations
 *
 * IaC Principles:
 * - Immutable: SLO definitions and metric snapshots frozen
 * - Idempotent: Same metric window = same calculation
 * - Versioned: SLO version tracking for changes
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class SLOSLADashboardService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        
        // Immutable SLO definitions (frozen)
        this.slos = new Map(); // sloId → frozen SLO
        this.metrics = new Map(); // metricId → frozen metric snapshots
        
        // Idempotent calculations
        this.budgetCalculations = new Map(); // calcToken → budget snapshot
        this.burnRateCalcs = new Map(); // burnToken → burn rate
        
        // Initialize default SLOs
        this.initializeDefaultSLOs();
    }
    
    /**
     * Initialize default SLOs (immutable)
     */
    initializeDefaultSLOs() {
        const defaultSLOs = [
            {
                id: 'slo-sync-latency',
                name: 'Workspace Sync Latency',
                description: 'Sync operations complete within 100ms p99',
                
                // SLO target (immutable)
                target: {
                    metric: 'latency_p99_ms',
                    threshold: 100,
                    unit: 'milliseconds',
                    percentage: 99.5, // 99.5% of requests
                },
                
                // Error budget (immutable)
                errorBudget: {
                    period: '30d',
                    periodMs: 30 * 24 * 60 * 60 * 1000,
                    allowedErrors: 0.5, // 0.5% allowance
                    remainingPercentage: 0.5,
                },
                
                // Thresholds (immutable)
                thresholds: {
                    critical: 0.2, // Alert if <20% budget
                    warning: 0.5, // Warn if <50% budget
                },
                
                // Alert routing (immutable)
                alerts: {
                    slack: 'sre-alerts',
                    email: 'sre@kushnir.cloud',
                    pagerduty: true,
                },
                
                version: 1,
                createdAt: new Date().toISOString(),
            },
            {
                id: 'slo-presence-latency',
                name: 'Presence Updates Latency',
                description: 'Presence updates reach all peers within 500ms p99',
                
                target: {
                    metric: 'presence_latency_p99_ms',
                    threshold: 500,
                    unit: 'milliseconds',
                    percentage: 99.0,
                },
                
                errorBudget: {
                    period: '30d',
                    periodMs: 30 * 24 * 60 * 60 * 1000,
                    allowedErrors: 1.0,
                    remainingPercentage: 1.0,
                },
                
                thresholds: {
                    critical: 0.2,
                    warning: 0.5,
                },
                
                alerts: {
                    slack: 'sre-alerts',
                    email: 'sre@kushnir.cloud',
                    pagerduty: true,
                },
                
                version: 1,
                createdAt: new Date().toISOString(),
            },
            {
                id: 'slo-availability',
                name: 'Service Availability',
                description: 'Service responds to requests with 2xx/3xx 99.9% of time',
                
                target: {
                    metric: 'http_success_rate',
                    threshold: 99.9,
                    unit: 'percentage',
                    percentage: 99.9,
                },
                
                errorBudget: {
                    period: '30d',
                    periodMs: 30 * 24 * 60 * 60 * 1000,
                    allowedErrors: 0.1,
                    remainingPercentage: 0.1,
                },
                
                thresholds: {
                    critical: 0.1,
                    warning: 0.3,
                },
                
                alerts: {
                    slack: 'sre-critical',
                    email: 'sre@kushnir.cloud',
                    pagerduty: true,
                },
                
                version: 1,
                createdAt: new Date().toISOString(),
            },
        ];
        
        // Freeze and store
        defaultSLOs.forEach(slo => {
            Object.freeze(slo);
            this.slos.set(slo.id, slo);
        });
    }
    
    /**
     * Get SLO (immutable snapshot)
     */
    getSLO(sloId) {
        const slo = this.slos.get(sloId);
        return slo ? Object.freeze({ ...slo }) : null;
    }
    
    /**
     * Get all SLOs (immutable array)
     */
    getAllSLOs() {
        const slos = Array.from(this.slos.values());
        return Object.freeze(slos.map(slo => Object.freeze({ ...slo })));
    }
    
    /**
     * Calculate error budget (idempotent)
     */
    calculateErrorBudget(sloId, calcToken) {
        // Check if already calculated
        if (this.budgetCalculations.has(calcToken)) {
            return this.budgetCalculations.get(calcToken);
        }
        
        const slo = this.slos.get(sloId);
        if (!slo) throw new Error('SLO not found');
        
        // Simulate metric fetch
        const metricsData = {
            'slo-sync-latency': {
                p99: 85,
                successCount: 149500,
                totalCount: 150000,
            },
            'slo-presence-latency': {
                p99: 450,
                successCount: 148500,
                totalCount: 150000,
            },
            'slo-availability': {
                successRate: 99.92,
                successCount: 149880,
                totalCount: 150000,
            },
        };
        
        const metrics = metricsData[sloId];
        
        // Calculate budget (immutable snapshot)
        const now = new Date();
        const periodStart = new Date(now.getTime() - slo.errorBudget.periodMs);
        
        // Simulate error budget remaining
        const totalSeconds = slo.errorBudget.periodMs / 1000;
        const elapsedSeconds = (now.getTime() - periodStart.getTime()) / 1000;
        const elapsedPercentage = (elapsedSeconds / totalSeconds) * 100;
        
        // Error budget math: remaining = allowed - (elapsed - consumed)
        const errorPercentage = metrics.successRate ? (100 - metrics.successRate) : 0.5;
        const consumedPercentage = errorPercentage * (elapsedPercentage / 100);
        const remainingBudget = slo.errorBudget.allowedErrors - consumedPercentage;
        
        const budget = {
            sloId,
            sloName: slo.name,
            
            // Budget state (immutable)
            period: {
                start: periodStart.toISOString(),
                end: new Date(periodStart.getTime() + slo.errorBudget.periodMs).toISOString(),
                elapsedPercentage: Math.min(100, Math.round(elapsedPercentage)),
            },
            
            // Error rates (immutable)
            actual: {
                successRate: metrics.successRate || ((metrics.successCount / metrics.totalCount) * 100),
                errorRate: (100 - (metrics.successRate || ((metrics.successCount / metrics.totalCount) * 100))),
                requests: metrics.totalCount,
            },
            
            // Target (immutable)
            target: slo.target.percentage,
            
            // Budget consumption (immutable)
            budget: {
                allowed: slo.errorBudget.allowedErrors,
                consumed: Math.max(0, consumedPercentage),
                remaining: Math.max(0, remainingBudget),
                remainingPercentage: Math.max(0, (remainingBudget / slo.errorBudget.allowedErrors) * 100),
            },
            
            // Status (immutable)
            status: remainingBudget <= 0 ? 'violated' : 
                    remainingBudget < (slo.errorBudget.allowedErrors * slo.thresholds.critical) ? 'critical' :
                    remainingBudget < (slo.errorBudget.allowedErrors * slo.thresholds.warning) ? 'warning' :
                    'healthy',
            
            // Burn rate (immutable)
            burnRate: {
                current: consumedPercentage / (elapsedPercentage / 100) || 0,
                forecast30d: consumedPercentage / (elapsedPercentage / 100) * 100 || 0,
            },
            
            timestamp: now.toISOString(),
            version: slo.version,
        };
        
        // Freeze and cache
        Object.freeze(budget);
        this.budgetCalculations.set(calcToken, budget);
        
        this.emit('budget-calculated', {
            sloId,
            status: budget.status,
            remaining: budget.budget.remaining.toFixed(2),
        });
        
        return budget;
    }
    
    /**
     * Get budget history (immutable trend)
     */
    getBudgetHistory(sloId, days = 30) {
        const slo = this.slos.get(sloId);
        if (!slo) throw new Error('SLO not found');
        
        // Simulate historical data
        const history = [];
        const now = Date.now();
        
        for (let i = days - 1; i >= 0; i--) {
            const dayStart = now - (i * 24 * 60 * 60 * 1000);
            
            // Simulate realistic budget consumption
            const baseConsumption = 0.3;
            const noise = Math.sin(i / 7) * 0.2 + (Math.random() - 0.5) * 0.1;
            const consumption = Math.max(0, baseConsumption + noise);
            
            history.push({
                date: new Date(dayStart).toISOString().split('T')[0],
                consumed: consumption.toFixed(2),
                remaining: Math.max(0, (slo.errorBudget.allowedErrors - (consumption * i))).toFixed(2),
                incidentCount: Math.random() > 0.9 ? Math.floor(Math.random() * 3) : 0,
            });
        }
        
        return Object.freeze(history.map(h => Object.freeze(h)));
    }
    
    /**
     * Calculate burn rate (idempotent)
     */
    calculateBurnRate(sloId, burnToken, windowMinutes = 5) {
        // Check if already calculated
        if (this.burnRateCalcs.has(burnToken)) {
            return this.burnRateCalcs.get(burnToken);
        }
        
        const slo = this.slos.get(sloId);
        if (!slo) throw new Error('SLO not found');
        
        // Simulate window metrics
        const windowMs = windowMinutes * 60 * 1000;
        const errorCount = Math.floor(Math.random() * 10);
        const totalCount = 1000;
        const errorRate = (errorCount / totalCount) * 100;
        
        // Burn rate = (actual error rate) / (allowed error rate)
        const allowedErrorRate = (100 - slo.target.percentage);
        const burnRate = (errorRate / allowedErrorRate);
        
        // Time to exhaust budget
        const remainingErrorBudget = slo.errorBudget.allowedErrors;
        const daysToExhaust = remainingErrorBudget / (errorRate / 100 * 30);
        
        const calculation = {
            sloId,
            sloName: slo.name,
            
            // Window metrics (immutable)
            window: {
                minutes: windowMinutes,
                startTime: new Date(Date.now() - windowMs).toISOString(),
                endTime: new Date().toISOString(),
            },
            
            // Rates (immutable)
            errorRate: errorRate.toFixed(3),
            burnRate: Math.max(0, burnRate).toFixed(3),
            
            // Forecast (immutable)
            forecast: {
                daysToExhaust: Math.max(0, Math.round(daysToExhaust)),
                exhaustionDate: new Date(Date.now() + (daysToExhaust * 24 * 60 * 60 * 1000)).toISOString(),
            },
            
            // Severity (immutable)
            severity: burnRate > 10 ? 'critical' : 
                      burnRate > 5 ? 'high' :
                      burnRate > 1 ? 'medium' :
                      'low',
            
            timestamp: new Date().toISOString(),
            version: slo.version,
        };
        
        // Freeze and cache
        Object.freeze(calculation);
        this.burnRateCalcs.set(burnToken, calculation);
        
        return calculation;
    }
    
    /**
     * Get dashboard (immutable snapshot)
     */
    getDashboard(token) {
        const slos = this.getAllSLOs();
        const budgets = [];
        const burnRates = [];
        
        // Calculate budgets for all SLOs
        for (const slo of slos) {
            const calcToken = `budget-${slo.id}-${token}`;
            const budget = this.calculateErrorBudget(slo.id, calcToken);
            budgets.push(budget);
            
            const burnToken = `burn-${slo.id}-${token}`;
            const burnRate = this.calculateBurnRate(slo.id, burnToken);
            burnRates.push(burnRate);
        }
        
        const dashboard = {
            serviceName: this.serviceName,
            timestamp: new Date().toISOString(),
            
            // Summary (immutable)
            summary: {
                totalSLOs: slos.length,
                healthy: budgets.filter(b => b.status === 'healthy').length,
                warning: budgets.filter(b => b.status === 'warning').length,
                critical: budgets.filter(b => b.status === 'critical').length,
                violated: budgets.filter(b => b.status === 'violated').length,
            },
            
            // Budgets (immutable array)
            budgets: Object.freeze(budgets.map(b => Object.freeze(b))),
            
            // Burn rates (immutable array)
            burnRates: Object.freeze(burnRates.map(b => Object.freeze(b))),
            
            // Alerts (immutable)
            alerts: Object.freeze(this.generateAlerts(budgets, burnRates)),
        };
        
        return Object.freeze(dashboard);
    }
    
    /**
     * Generate alerts (immutable array)
     */
    generateAlerts(budgets, burnRates) {
        const alerts = [];
        
        // Budget alerts
        for (const budget of budgets) {
            if (budget.status === 'critical') {
                alerts.push({
                    type: 'budget-critical',
                    severity: 'critical',
                    sloId: budget.sloId,
                    message: `${budget.sloName}: Critical - Only ${budget.budget.remaining.toFixed(2)}% budget remaining`,
                    action: 'Review incident causes and prevent further errors',
                });
            } else if (budget.status === 'warning') {
                alerts.push({
                    type: 'budget-warning',
                    severity: 'warning',
                    sloId: budget.sloId,
                    message: `${budget.sloName}: Warning - ${budget.budget.remaining.toFixed(2)}% budget remaining`,
                    action: 'Monitor carefully and consider preventive measures',
                });
            }
        }
        
        // Burn rate alerts
        for (const burnRate of burnRates) {
            if (burnRate.severity === 'critical') {
                alerts.push({
                    type: 'burn-rate-high',
                    severity: 'critical',
                    sloId: burnRate.sloId,
                    message: `${burnRate.sloName}: High burn rate (${burnRate.burnRate}x) - budget exhausted in ${burnRate.forecast.daysToExhaust} days`,
                    action: 'Immediate action required to reduce error rate',
                });
            }
        }
        
        return Object.freeze(alerts.map(a => Object.freeze(a)));
    }
}

module.exports = SLOSLADashboardService;
