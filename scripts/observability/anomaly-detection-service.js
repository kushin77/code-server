#!/usr/bin/env node
/**
 * @file        scripts/observability/anomaly-detection-service.js
 * @module      observability/anomalies
 * @description Machine learning-based anomaly detection with immutable baselines
 *
 * IaC Principles:
 * - Immutable: Baselines frozen once calculated
 * - Immutable: Anomaly scores frozen once computed
 * - Idempotent: Same metric window = same anomaly score
 * - Versioned: Baseline versions for auditing
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class AnomalyDetectionService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        this.baselineWindowDays = options.baselineWindowDays || 14;
        
        // Immutable baselines (frozen)
        this.baselines = new Map(); // metricName → frozen baseline
        
        // Anomaly scores (frozen)
        this.anomalyScores = new Map(); // anomalyId → frozen score
        
        // Metric history for baseline calculation
        this.metricHistory = new Map(); // metricName → [values]
        
        // Token-based idempotency tracking
        this.scoreTokens = new Map(); // token → anomalyId
    }
    
    /**
     * Record metric (builds history for baseline)
     */
    recordMetric(metricName, value, timestamp = Date.now()) {
        const key = metricName;
        if (!this.metricHistory.has(key)) {
            this.metricHistory.set(key, []);
        }
        
        const history = this.metricHistory.get(key);
        history.push({ value, timestamp });
        
        // Keep rolling window (last 14 days)
        const cutoff = Date.now() - (this.baselineWindowDays * 24 * 60 * 60 * 1000);
        const filtered = history.filter(m => m.timestamp > cutoff);
        this.metricHistory.set(key, filtered);
    }
    
    /**
     * Calculate baseline (immutable)
     */
    calculateBaseline(metricName) {
        const history = this.metricHistory.get(metricName) || [];
        if (history.length === 0) return null;
        
        const values = history.map(m => m.value);
        values.sort((a, b) => a - b);
        
        const mean = values.reduce((a, b) => a + b, 0) / values.length;
        const variance = values.reduce((sum, v) => sum + Math.pow(v - mean, 2), 0) / values.length;
        const stdDev = Math.sqrt(variance);
        
        // Immutable baseline
        const baseline = {
            // Metadata (immutable)
            metricName,
            serviceName: this.serviceName,
            
            // Statistics (immutable)
            mean,
            stdDev,
            min: values[0],
            max: values[values.length - 1],
            p50: values[Math.floor(values.length * 0.5)],
            p95: values[Math.floor(values.length * 0.95)],
            p99: values[Math.floor(values.length * 0.99)],
            
            // Thresholds (immutable)
            thresholds: Object.freeze({
                anomalyUpper: mean + (3 * stdDev),  // 3-sigma
                anomalyLower: Math.max(0, mean - (3 * stdDev)),
                warningUpper: mean + (2 * stdDev),  // 2-sigma
                warningLower: Math.max(0, mean - (2 * stdDev)),
            }),
            
            // Sample info (immutable)
            sampleCount: history.length,
            baselineWindowDays: this.baselineWindowDays,
            
            // Metadata (immutable)
            calculatedAt: new Date().toISOString(),
            
            version: 1,
        };
        
        // Freeze baseline
        Object.freeze(baseline);
        this.baselines.set(metricName, baseline);
        
        this.emit('baseline-calculated', {
            metricName,
            mean: baseline.mean,
            stdDev: baseline.stdDev,
        });
        
        return baseline;
    }
    
    /**
     * Detect anomaly (idempotent)
     */
    detectAnomaly(metricName, currentValue, scoreToken) {
        // Check idempotency
        if (this.scoreTokens.has(scoreToken)) {
            return this.scoreTokens.get(scoreToken);
        }
        
        const baseline = this.baselines.get(metricName);
        if (!baseline) {
            throw new Error(`No baseline for metric ${metricName}`);
        }
        
        // Calculate z-score
        const zScore = (currentValue - baseline.mean) / baseline.stdDev;
        
        // Determine severity
        let severity = 'normal';
        if (Math.abs(zScore) > 3) {
            severity = 'critical';
        } else if (Math.abs(zScore) > 2) {
            severity = 'warning';
        }
        
        // Determine type
        let type = 'within_bounds';
        if (currentValue > baseline.thresholds.anomalyUpper) {
            type = 'spike';
        } else if (currentValue < baseline.thresholds.anomalyLower) {
            type = 'drop';
        }
        
        const anomalyId = `anomaly-${crypto.randomBytes(8).toString('hex')}`;
        
        // Create immutable anomaly score
        const anomalyScore = {
            // Identifiers (immutable)
            anomalyId,
            metricName,
            serviceName: this.serviceName,
            
            // Value (immutable)
            currentValue,
            baselineMean: baseline.mean,
            deviation: currentValue - baseline.mean,
            
            // Statistical analysis (immutable)
            zScore,
            percentile: this.calculatePercentile(zScore),
            
            // Classification (immutable)
            severity,  // normal, warning, critical
            type,      // within_bounds, spike, drop
            
            // Confidence (immutable)
            confidence: Math.min(Math.abs(zScore) / 4, 1.0),  // 0-1.0
            
            // Thresholds (immutable)
            thresholds: Object.freeze({
                anomalyUpper: baseline.thresholds.anomalyUpper,
                anomalyLower: baseline.thresholds.anomalyLower,
                warningUpper: baseline.thresholds.warningUpper,
                warningLower: baseline.thresholds.warningLower,
            }),
            
            // Timing (immutable)
            timestamp: new Date().toISOString(),
            
            // Recommendation (immutable)
            recommendation: this.generateRecommendation(severity, type),
            
            version: 1,
        };
        
        // Freeze anomaly score
        Object.freeze(anomalyScore);
        this.anomalyScores.set(anomalyId, anomalyScore);
        
        // Store token for idempotency
        this.scoreTokens.set(scoreToken, anomalyId);
        
        this.emit('anomaly-detected', {
            anomalyId,
            metricName,
            severity,
            confidence: anomalyScore.confidence,
        });
        
        return anomalyId;
    }
    
    /**
     * Calculate percentile from z-score
     */
    calculatePercentile(zScore) {
        // Approximation using error function
        const t = 1 / (1 + 0.2316419 * Math.abs(zScore));
        const d = 0.3989423 * Math.exp(-zScore * zScore / 2);
        const prob = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
        return zScore < 0 ? prob : 1 - prob;
    }
    
    /**
     * Generate recommendation based on severity
     */
    generateRecommendation(severity, type) {
        if (severity === 'critical') {
            if (type === 'spike') {
                return 'Investigate immediate cause of spike. Check deployment, traffic surge, or resource exhaustion.';
            } else if (type === 'drop') {
                return 'Investigate immediate cause of drop. Check service crash, circuit breaker, or timeout.';
            }
        } else if (severity === 'warning') {
            return 'Monitor metric closely. Consider alerting if trend continues.';
        }
        return 'Metric within normal range.';
    }
    
    /**
     * Detect trending anomaly
     */
    detectTrend(metricName, recentValues) {
        const baseline = this.baselines.get(metricName);
        if (!baseline || recentValues.length < 3) return null;
        
        // Check if trend is consistently above/below baseline
        const aboveCount = recentValues.filter(v => v > baseline.mean).length;
        const belowCount = recentValues.filter(v => v < baseline.mean).length;
        
        let trend = 'stable';
        let confidence = 0;
        
        if (aboveCount >= recentValues.length * 0.8) {
            trend = 'consistently_high';
            confidence = aboveCount / recentValues.length;
        } else if (belowCount >= recentValues.length * 0.8) {
            trend = 'consistently_low';
            confidence = belowCount / recentValues.length;
        }
        
        return Object.freeze({
            metricName,
            trend,
            confidence,
            recentValues: Object.freeze([...recentValues]),
            timestamp: new Date().toISOString(),
        });
    }
    
    /**
     * Get anomaly score (immutable snapshot)
     */
    getAnomalyScore(anomalyId) {
        const score = this.anomalyScores.get(anomalyId);
        return score ? Object.freeze({ ...score }) : null;
    }
    
    /**
     * Query anomalies (immutable array)
     */
    queryAnomalies(filters = {}) {
        const anomalies = Array.from(this.anomalyScores.values());
        
        let filtered = anomalies;
        
        // Filter by metric
        if (filters.metricName) {
            filtered = filtered.filter(a => a.metricName === filters.metricName);
        }
        
        // Filter by severity
        if (filters.severity) {
            filtered = filtered.filter(a => a.severity === filters.severity);
        }
        
        // Filter by type
        if (filters.type) {
            filtered = filtered.filter(a => a.type === filters.type);
        }
        
        // Filter by min confidence
        if (filters.minConfidence) {
            filtered = filtered.filter(a => a.confidence >= filters.minConfidence);
        }
        
        // Sort by confidence (descending)
        filtered.sort((a, b) => b.confidence - a.confidence);
        
        // Limit results
        const limit = filters.limit || 100;
        return Object.freeze(
            filtered.slice(0, limit).map(a => Object.freeze(a))
        );
    }
    
    /**
     * Get baseline (immutable snapshot)
     */
    getBaseline(metricName) {
        const baseline = this.baselines.get(metricName);
        return baseline ? Object.freeze({ ...baseline }) : null;
    }
    
    /**
     * Get all baselines (immutable array)
     */
    getAllBaselines() {
        return Object.freeze(
            Array.from(this.baselines.values())
                .map(b => Object.freeze(b))
        );
    }
    
    /**
     * Get anomaly statistics (immutable snapshot)
     */
    getAnomalyStatistics() {
        const allAnomalies = Array.from(this.anomalyScores.values());
        
        const stats = {
            totalAnomalies: allAnomalies.length,
            bySeverity: {
                critical: allAnomalies.filter(a => a.severity === 'critical').length,
                warning: allAnomalies.filter(a => a.severity === 'warning').length,
                normal: allAnomalies.filter(a => a.severity === 'normal').length,
            },
            byType: {
                spike: allAnomalies.filter(a => a.type === 'spike').length,
                drop: allAnomalies.filter(a => a.type === 'drop').length,
                within_bounds: allAnomalies.filter(a => a.type === 'within_bounds').length,
            },
            averageConfidence: allAnomalies.length > 0
                ? (allAnomalies.reduce((sum, a) => sum + a.confidence, 0) / allAnomalies.length)
                : 0,
        };
        
        return Object.freeze(stats);
    }
}

module.exports = AnomalyDetectionService;
