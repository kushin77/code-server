#!/usr/bin/env node
/**
 * @file        scripts/integrations/datadog-immutable-service.js
 * @module      integrations/datadog
 * @description DataDog metrics with immutable observations and idempotent submissions
 *
 * IaC Principles:
 * - Immutable: Metric observations frozen once recorded
 * - Immutable: Tags frozen, metadata frozen
 * - Idempotent: Same submissionToken = same submission
 * - Versioned: Metric versions for audit trails
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class DataDogIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.apiKey = options.apiKey || process.env.DATADOG_API_KEY || '';
        this.appKey = options.appKey || process.env.DATADOG_APP_KEY || '';
        this.site = options.site || process.env.DATADOG_SITE || 'datadoghq.com';
        
        // Immutable metric observations (frozen)
        this.metrics = new Map(); // metricId → frozen metric
        
        // Immutable submissions (frozen)
        this.submissions = new Map(); // submissionId → frozen submission
        
        // Token to submissionId mapping (idempotency)
        this.submissionTokens = new Map(); // token → submissionId
        
        // Immutable dashboards (frozen)
        this.dashboards = new Map(); // dashboardId → frozen dashboard
        
        // Submission history
        this.submissionHistory = [];
    }
    
    /**
     * Record metric observation (immutable)
     */
    recordMetricObservation(metricData) {
        const metricId = `metric-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const metric = {
            // Identifiers (immutable)
            metricId,
            metricName: metricData.metricName,
            
            // Value (immutable)
            value: metricData.value,
            unit: metricData.unit || 'none',  // seconds, bytes, percent, etc.
            
            // Timing (immutable)
            timestamp: new Date().toISOString(),
            timestampMs: now,
            
            // Context (immutable)
            host: metricData.host || 'unknown',
            environment: metricData.environment || 'production',
            region: metricData.region || 'us-east-1',
            service: metricData.service || 'default',
            
            // Tags (immutable)
            tags: Object.freeze(metricData.tags || []),
            
            // Metadata (immutable)
            metadata: Object.freeze(metricData.metadata || {}),
            
            // Status (mutable)
            submitted: false,
            submittedAt: null,
            submissionId: null,
            
            version: 1,
        };
        
        Object.freeze(metric);
        this.metrics.set(metricId, metric);
        
        this.emit('metric-recorded', {
            metricId,
            metricName: metric.metricName,
            value: metric.value,
            tags: metric.tags,
        });
        
        return metricId;
    }
    
    /**
     * Submit metrics (idempotent)
     */
    submitMetrics(metricIds, submissionToken) {
        // Idempotency check
        if (submissionToken && this.submissionTokens.has(submissionToken)) {
            return this.submissionTokens.get(submissionToken);
        }
        
        const submissionId = `sub-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Verify all metrics exist
        const metricsToSubmit = [];
        for (const metricId of metricIds) {
            const metric = this.metrics.get(metricId);
            if (!metric) throw new Error(`Metric ${metricId} not found`);
            metricsToSubmit.push(metric);
        }
        
        // Create immutable submission
        const submission = {
            // Identifiers (immutable)
            submissionId,
            
            // Metrics (immutable snapshots)
            metricIds: Object.freeze([...metricIds]),
            metricSnapshots: Object.freeze(
                metricsToSubmit.map(m => Object.freeze({
                    metricName: m.metricName,
                    value: m.value,
                    timestamp: m.timestampMs,
                    tags: m.tags,
                    host: m.host,
                }))
            ),
            
            // Submission info (immutable)
            submittedAt: new Date().toISOString(),
            submittedAtMs: now,
            batchSize: metricIds.length,
            
            // Status (mutable)
            status: 'submitted',
            datadogBatchId: null,
            errorCode: null,
            errorMessage: null,
            
            version: 1,
        };
        
        Object.freeze(submission);
        this.submissions.set(submissionId, submission);
        
        // Update metrics (create new versions)
        for (const metricId of metricIds) {
            const metric = this.metrics.get(metricId);
            const updated = {
                ...metric,
                submitted: true,
                submittedAt: submission.submittedAt,
                submissionId,
                version: metric.version + 1,
            };
            Object.freeze(updated);
            this.metrics.set(metricId, updated);
        }
        
        if (submissionToken) {
            this.submissionTokens.set(submissionToken, submissionId);
        }
        
        this.recordSubmissionHistory(submissionId, 'submitted');
        
        this.emit('metrics-submitted', {
            submissionId,
            batchSize: metricIds.length,
            status: 'submitted',
        });
        
        return submissionId;
    }
    
    /**
     * Record submission success
     */
    recordSubmissionSuccess(submissionId, successData) {
        const submission = this.submissions.get(submissionId);
        if (!submission) throw new Error(`Submission ${submissionId} not found`);
        
        const updated = {
            ...submission,
            status: 'accepted',
            datadogBatchId: successData.batchId,
            version: submission.version + 1,
        };
        
        Object.freeze(updated);
        this.submissions.set(submissionId, updated);
        
        this.emit('submission-success', {
            submissionId,
            batchId: successData.batchId,
            metricCount: submission.batchSize,
        });
    }
    
    /**
     * Record submission failure
     */
    recordSubmissionFailure(submissionId, failureData) {
        const submission = this.submissions.get(submissionId);
        if (!submission) throw new Error(`Submission ${submissionId} not found`);
        
        const updated = {
            ...submission,
            status: 'failed',
            errorCode: failureData.code,
            errorMessage: failureData.message,
            version: submission.version + 1,
        };
        
        Object.freeze(updated);
        this.submissions.set(submissionId, updated);
        
        this.emit('submission-failure', {
            submissionId,
            errorCode: failureData.code,
            metricCount: submission.batchSize,
        });
    }
    
    /**
     * Create dashboard (immutable)
     */
    createDashboard(dashboardData) {
        const dashboardId = `dash-${crypto.randomBytes(8).toString('hex')}`;
        
        const dashboard = {
            // Identifiers (immutable)
            dashboardId,
            title: dashboardData.title,
            
            // Content (immutable)
            description: dashboardData.description,
            tags: Object.freeze(dashboardData.tags || []),
            
            // Widgets (immutable)
            widgets: Object.freeze((dashboardData.widgets || []).map(w =>
                Object.freeze({
                    widgetId: w.widgetId || `widget-${crypto.randomBytes(4).toString('hex')}`,
                    title: w.title,
                    metricName: w.metricName,
                    type: w.type,  // timeseries, gauge, etc.
                    position: Object.freeze(w.position || {}),
                })
            )),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            published: false,
            datadogDashboardId: null,
            
            version: 1,
        };
        
        Object.freeze(dashboard);
        this.dashboards.set(dashboardId, dashboard);
        
        this.emit('dashboard-created', {
            dashboardId,
            title: dashboard.title,
            widgetCount: dashboard.widgets.length,
        });
        
        return dashboardId;
    }
    
    /**
     * Publish dashboard
     */
    publishDashboard(dashboardId, datadogDashboardId) {
        const dashboard = this.dashboards.get(dashboardId);
        if (!dashboard) throw new Error(`Dashboard ${dashboardId} not found`);
        
        const updated = {
            ...dashboard,
            published: true,
            datadogDashboardId,
            version: dashboard.version + 1,
        };
        
        Object.freeze(updated);
        this.dashboards.set(dashboardId, updated);
        
        this.emit('dashboard-published', {
            dashboardId,
            title: dashboard.title,
            datadogDashboardId,
        });
    }
    
    /**
     * Query metrics (immutable array)
     */
    queryMetrics(filters = {}) {
        let metrics = Array.from(this.metrics.values());
        
        if (filters.metricName) {
            metrics = metrics.filter(m => m.metricName === filters.metricName);
        }
        
        if (filters.host) {
            metrics = metrics.filter(m => m.host === filters.host);
        }
        
        if (filters.service) {
            metrics = metrics.filter(m => m.service === filters.service);
        }
        
        if (filters.submitted !== undefined) {
            metrics = metrics.filter(m => m.submitted === filters.submitted);
        }
        
        metrics.sort((a, b) => b.timestampMs - a.timestampMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            metrics.slice(0, limit).map(m => Object.freeze(m))
        );
    }
    
    /**
     * Get metric (immutable snapshot)
     */
    getMetric(metricId) {
        const metric = this.metrics.get(metricId);
        return metric ? Object.freeze({ ...metric }) : null;
    }
    
    /**
     * Get submission (immutable snapshot)
     */
    getSubmission(submissionId) {
        const submission = this.submissions.get(submissionId);
        return submission ? Object.freeze({ ...submission }) : null;
    }
    
    /**
     * Get statistics (immutable)
     */
    getMetricStatistics() {
        const allMetrics = Array.from(this.metrics.values());
        const allSubmissions = Array.from(this.submissions.values());
        
        const stats = {
            totalMetrics: allMetrics.length,
            submittedMetrics: allMetrics.filter(m => m.submitted).length,
            pendingMetrics: allMetrics.filter(m => !m.submitted).length,
            
            totalSubmissions: allSubmissions.length,
            successfulSubmissions: allSubmissions.filter(s => s.status === 'accepted').length,
            failedSubmissions: allSubmissions.filter(s => s.status === 'failed').length,
            
            successRate: allSubmissions.length > 0
                ? ((allSubmissions.filter(s => s.status === 'accepted').length / allSubmissions.length) * 100).toFixed(2)
                : 0,
            
            totalDashboards: this.dashboards.size,
            publishedDashboards: Array.from(this.dashboards.values()).filter(d => d.published).length,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Record submission history
     */
    recordSubmissionHistory(submissionId, action) {
        const submission = this.submissions.get(submissionId);
        
        const record = Object.freeze({
            timestamp: new Date().toISOString(),
            timestampMs: Date.now(),
            action,
            submissionId,
            status: submission.status,
            batchSize: submission.batchSize,
        });
        
        this.submissionHistory.push(record);
    }
}

module.exports = DataDogIntegrationService;
