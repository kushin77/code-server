#!/usr/bin/env node
/**
 * @file        scripts/integrations/newrelic-immutable-service.js
 * @module      integrations/newrelic
 * @description New Relic APM with immutable transactions and idempotent batching
 *
 * IaC Principles:
 * - Immutable: Transaction records frozen once created
 * - Immutable: Span data frozen with timing and attributes
 * - Idempotent: Same batchToken = same batch submission
 * - Versioned: Transaction versions for audit trails
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class NewRelicIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.licenseKey = options.licenseKey || process.env.NEW_RELIC_LICENSE_KEY || '';
        this.accountId = options.accountId || process.env.NEW_RELIC_ACCOUNT_ID || '';
        this.appName = options.appName || process.env.NEW_RELIC_APP_NAME || 'code-server';
        
        // Immutable transaction records (frozen)
        this.transactions = new Map(); // transactionId → frozen transaction
        
        // Immutable batches (frozen)
        this.batches = new Map(); // batchId → frozen batch
        
        // Token to batchId mapping (idempotency)
        this.batchTokens = new Map(); // token → batchId
        
        // Immutable alerts (frozen)
        this.alerts = new Map(); // alertId → frozen alert
        
        // Batch history
        this.batchHistory = [];
    }
    
    /**
     * Record transaction (immutable)
     */
    recordTransaction(transactionData) {
        const transactionId = `txn-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const transaction = {
            // Identifiers (immutable)
            transactionId,
            name: transactionData.name,
            
            // Timing (immutable)
            startedAt: new Date().toISOString(),
            startedAtMs: now,
            durationMs: transactionData.durationMs,
            
            // Classification (immutable)
            type: transactionData.type || 'Web',  // Web, Other
            method: transactionData.method,  // GET, POST, etc.
            url: transactionData.url,
            
            // Performance (immutable)
            responseCode: transactionData.responseCode,
            throughput: transactionData.throughput || 1,
            
            // Context (immutable)
            accountId: this.accountId,
            appName: this.appName,
            environment: transactionData.environment || 'production',
            
            // Attributes (immutable)
            attributes: Object.freeze(transactionData.attributes || {}),
            tags: Object.freeze(transactionData.tags || []),
            
            // Spans (immutable)
            spans: Object.freeze((transactionData.spans || []).map(span =>
                Object.freeze({
                    spanId: `span-${crypto.randomBytes(4).toString('hex')}`,
                    name: span.name,
                    durationMs: span.durationMs,
                    startedAtMs: now + (span.offsetMs || 0),
                    attributes: Object.freeze(span.attributes || {}),
                })
            )),
            
            // Status (mutable)
            submitted: false,
            submittedAt: null,
            batchId: null,
            
            version: 1,
        };
        
        Object.freeze(transaction);
        this.transactions.set(transactionId, transaction);
        
        this.emit('transaction-recorded', {
            transactionId,
            name: transaction.name,
            durationMs: transaction.durationMs,
            method: transaction.method,
        });
        
        return transactionId;
    }
    
    /**
     * Submit transaction batch (idempotent)
     */
    submitTransactionBatch(transactionIds, batchToken) {
        // Idempotency check
        if (batchToken && this.batchTokens.has(batchToken)) {
            return this.batchTokens.get(batchToken);
        }
        
        const batchId = `batch-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Verify all transactions exist
        const txnsToSubmit = [];
        let totalDurationMs = 0;
        
        for (const txnId of transactionIds) {
            const txn = this.transactions.get(txnId);
            if (!txn) throw new Error(`Transaction ${txnId} not found`);
            txnsToSubmit.push(txn);
            totalDurationMs += txn.durationMs;
        }
        
        // Create immutable batch
        const batch = {
            // Identifiers (immutable)
            batchId,
            licenseKey: this.licenseKey,
            accountId: this.accountId,
            
            // Transactions (immutable snapshots)
            transactionIds: Object.freeze([...transactionIds]),
            transactionSnapshots: Object.freeze(
                txnsToSubmit.map(t => Object.freeze({
                    name: t.name,
                    type: t.type,
                    durationMs: t.durationMs,
                    responseCode: t.responseCode,
                    spanCount: t.spans.length,
                }))
            ),
            
            // Batch info (immutable)
            submittedAt: new Date().toISOString(),
            submittedAtMs: now,
            batchSize: transactionIds.length,
            totalDurationMs,
            avgDurationMs: (totalDurationMs / transactionIds.length).toFixed(2),
            
            // Status (mutable)
            status: 'submitted',
            nrBatchId: null,
            errorCode: null,
            errorMessage: null,
            
            version: 1,
        };
        
        Object.freeze(batch);
        this.batches.set(batchId, batch);
        
        // Update transactions (create new versions)
        for (const txnId of transactionIds) {
            const txn = this.transactions.get(txnId);
            const updated = {
                ...txn,
                submitted: true,
                submittedAt: batch.submittedAt,
                batchId,
                version: txn.version + 1,
            };
            Object.freeze(updated);
            this.transactions.set(txnId, updated);
        }
        
        if (batchToken) {
            this.batchTokens.set(batchToken, batchId);
        }
        
        this.recordBatchHistory(batchId, 'submitted');
        
        this.emit('batch-submitted', {
            batchId,
            batchSize: transactionIds.length,
            totalDurationMs,
            status: 'submitted',
        });
        
        return batchId;
    }
    
    /**
     * Record batch success
     */
    recordBatchSuccess(batchId, successData) {
        const batch = this.batches.get(batchId);
        if (!batch) throw new Error(`Batch ${batchId} not found`);
        
        const updated = {
            ...batch,
            status: 'accepted',
            nrBatchId: successData.batchId,
            version: batch.version + 1,
        };
        
        Object.freeze(updated);
        this.batches.set(batchId, updated);
        
        this.emit('batch-success', {
            batchId,
            nrBatchId: successData.batchId,
            txnCount: batch.batchSize,
        });
    }
    
    /**
     * Record batch failure
     */
    recordBatchFailure(batchId, failureData) {
        const batch = this.batches.get(batchId);
        if (!batch) throw new Error(`Batch ${batchId} not found`);
        
        const updated = {
            ...batch,
            status: 'failed',
            errorCode: failureData.code,
            errorMessage: failureData.message,
            version: batch.version + 1,
        };
        
        Object.freeze(updated);
        this.batches.set(batchId, updated);
        
        this.emit('batch-failure', {
            batchId,
            errorCode: failureData.code,
            txnCount: batch.batchSize,
        });
    }
    
    /**
     * Create alert condition (immutable)
     */
    createAlertCondition(alertData) {
        const alertId = `alert-${crypto.randomBytes(8).toString('hex')}`;
        
        const alert = {
            // Identifiers (immutable)
            alertId,
            policyId: alertData.policyId,
            
            // Alert definition (immutable)
            name: alertData.name,
            description: alertData.description,
            metric: alertData.metric,  // apm.service.cpu, apm.service.memory, etc.
            
            // Threshold (immutable)
            condition: alertData.condition,  // above, below, equals
            threshold: alertData.threshold,
            duration: alertData.duration || 5,  // minutes
            
            // Configuration (immutable)
            enabled: true,
            criticalThreshold: alertData.criticalThreshold,
            warningThreshold: alertData.warningThreshold,
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            nrAlertId: null,
            
            version: 1,
        };
        
        Object.freeze(alert);
        this.alerts.set(alertId, alert);
        
        this.emit('alert-created', {
            alertId,
            name: alert.name,
            metric: alert.metric,
        });
        
        return alertId;
    }
    
    /**
     * Get transaction (immutable snapshot)
     */
    getTransaction(transactionId) {
        const txn = this.transactions.get(transactionId);
        return txn ? Object.freeze({ ...txn }) : null;
    }
    
    /**
     * Get batch (immutable snapshot)
     */
    getBatch(batchId) {
        const batch = this.batches.get(batchId);
        return batch ? Object.freeze({ ...batch }) : null;
    }
    
    /**
     * Query transactions (immutable array)
     */
    queryTransactions(filters = {}) {
        let txns = Array.from(this.transactions.values());
        
        if (filters.name) {
            txns = txns.filter(t => t.name === filters.name);
        }
        
        if (filters.method) {
            txns = txns.filter(t => t.method === filters.method);
        }
        
        if (filters.submitted !== undefined) {
            txns = txns.filter(t => t.submitted === filters.submitted);
        }
        
        if (filters.minDurationMs !== undefined) {
            txns = txns.filter(t => t.durationMs >= filters.minDurationMs);
        }
        
        txns.sort((a, b) => b.startedAtMs - a.startedAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            txns.slice(0, limit).map(t => Object.freeze(t))
        );
    }
    
    /**
     * Get APM statistics (immutable)
     */
    getAPMStatistics() {
        const allTxns = Array.from(this.transactions.values());
        const allBatches = Array.from(this.batches.values());
        
        const durationValues = allTxns.map(t => t.durationMs);
        const avgDuration = durationValues.length > 0
            ? (durationValues.reduce((a, b) => a + b, 0) / durationValues.length).toFixed(2)
            : 0;
        
        const stats = {
            totalTransactions: allTxns.length,
            submittedTransactions: allTxns.filter(t => t.submitted).length,
            pendingTransactions: allTxns.filter(t => !t.submitted).length,
            
            averageDurationMs: avgDuration,
            maxDurationMs: durationValues.length > 0 ? Math.max(...durationValues) : 0,
            minDurationMs: durationValues.length > 0 ? Math.min(...durationValues) : 0,
            
            totalBatches: allBatches.length,
            successfulBatches: allBatches.filter(b => b.status === 'accepted').length,
            failedBatches: allBatches.filter(b => b.status === 'failed').length,
            
            successRate: allBatches.length > 0
                ? ((allBatches.filter(b => b.status === 'accepted').length / allBatches.length) * 100).toFixed(2)
                : 0,
            
            totalAlerts: this.alerts.size,
            enabledAlerts: Array.from(this.alerts.values()).filter(a => a.enabled).length,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Record batch history
     */
    recordBatchHistory(batchId, action) {
        const batch = this.batches.get(batchId);
        
        const record = Object.freeze({
            timestamp: new Date().toISOString(),
            timestampMs: Date.now(),
            action,
            batchId,
            status: batch.status,
            batchSize: batch.batchSize,
            totalDurationMs: batch.totalDurationMs,
        });
        
        this.batchHistory.push(record);
    }
}

module.exports = NewRelicIntegrationService;
