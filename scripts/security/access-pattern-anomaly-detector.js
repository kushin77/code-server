#!/usr/bin/env node
/**
 * Access Pattern Anomaly Detector
 * Uses Isolation Forest ML to detect anomalous user access patterns
 * Baselines: login time, files accessed, session duration
 */

const EventEmitter = require('events');

/**
 * Simple Isolation Forest implementation for anomaly detection
 * Based on "Isolation Forest" paper (Liu et al., 2008)
 */
class IsolationForest extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.numTrees = options.numTrees || 100;
        this.sampleSize = options.sampleSize || 256;
        this.anomalyThreshold = options.anomalyThreshold || 0.6; // Anomaly score >= 0.6
        
        this.trees = [];
        this.trained = false;
    }
    
    /**
     * Train forest on baseline data
     */
    train(data) {
        this.trees = [];
        
        for (let i = 0; i < this.numTrees; i++) {
            // Sample random subset of data
            const sample = this.randomSample(data, this.sampleSize);
            // Build isolation tree on sample
            const tree = this.buildTree(sample, 0);
            this.trees.push(tree);
        }
        
        this.trained = true;
    }
    
    /**
     * Predict anomaly score for a data point
     * Returns score 0.0 (normal) to 1.0 (anomalous)
     */
    predict(point) {
        if (!this.trained) {
            throw new Error('Model not trained. Call train() first.');
        }
        
        // Get path length in each tree
        const pathLengths = this.trees.map(tree => this.getPathLength(point, tree, 0));
        
        // Calculate average path length
        const avgPathLength = pathLengths.reduce((a, b) => a + b, 0) / pathLengths.length;
        
        // Calculate anomaly score
        // c(n) is average path length for sample of size n
        const c = this.avgPathLength(this.sampleSize);
        const anomalyScore = Math.pow(2, -avgPathLength / c);
        
        return Math.min(1.0, Math.max(0.0, anomalyScore));
    }
    
    /**
     * Build isolation tree recursively
     */
    buildTree(data, depth, maxDepth = Math.log2(this.sampleSize)) {
        if (data.length <= 1 || depth >= maxDepth) {
            return {
                type: 'leaf',
                size: data.length,
            };
        }
        
        // Random feature selection
        const features = Object.keys(data[0]);
        const feature = features[Math.floor(Math.random() * features.length)];
        
        // Random split value
        const values = data.map(d => d[feature]).sort((a, b) => a - b);
        const minVal = values[0];
        const maxVal = values[values.length - 1];
        const splitValue = minVal + Math.random() * (maxVal - minVal);
        
        // Split data
        const left = data.filter(d => d[feature] < splitValue);
        const right = data.filter(d => d[feature] >= splitValue);
        
        // Handle edge case where split produces empty partition
        if (left.length === 0 || right.length === 0) {
            return {
                type: 'leaf',
                size: data.length,
            };
        }
        
        return {
            type: 'node',
            feature,
            splitValue,
            left: this.buildTree(left, depth + 1, maxDepth),
            right: this.buildTree(right, depth + 1, maxDepth),
        };
    }
    
    /**
     * Get path length to leaf node
     */
    getPathLength(point, tree, pathLength = 0) {
        if (tree.type === 'leaf') {
            return pathLength + this.avgPathLength(tree.size);
        }
        
        if (point[tree.feature] < tree.splitValue) {
            return this.getPathLength(point, tree.left, pathLength + 1);
        } else {
            return this.getPathLength(point, tree.right, pathLength + 1);
        }
    }
    
    /**
     * Calculate average path length for data sample
     */
    avgPathLength(n) {
        if (n <= 1) return 0;
        return 2 * (Math.log(n - 1) + 0.5772156649) - 2 * (n - 1) / n;
    }
    
    /**
     * Random sampling with replacement
     */
    randomSample(data, size) {
        const sample = [];
        for (let i = 0; i < size; i++) {
            sample.push(data[Math.floor(Math.random() * data.length)]);
        }
        return sample;
    }
}

/**
 * Access Pattern Anomaly Detector
 * Detects unusual user behavior patterns
 */
class AccessPatternAnomalyDetector extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.anomalyThreshold = options.anomalyThreshold || 0.6;
        this.baselineWindowDays = options.baselineWindowDays || 30;
        
        this.users = new Map(); // userId → user profile
        this.accessLogs = []; // All access events
        this.anomalies = []; // Detected anomalies
        
        // ML model
        this.forest = new IsolationForest({
            numTrees: 100,
            sampleSize: 256,
            anomalyThreshold: this.anomalyThreshold,
        });
        
        this.modelTrained = false;
    }
    
    /**
     * Add access event
     */
    recordAccess(event) {
        const access = {
            userId: event.userId,
            timestamp: event.timestamp || Date.now(),
            type: event.type,              // 'login', 'file-access', 'logout'
            duration: event.duration,      // session/event duration in ms
            filesAccessed: event.filesAccessed || 0,
            ipAddress: event.ipAddress,
            location: event.location,
            deviceId: event.deviceId,
        };
        
        this.accessLogs.push(access);
        
        // Update user profile
        if (!this.users.has(event.userId)) {
            this.users.set(event.userId, {
                userId: event.userId,
                accessCount: 0,
                firstSeen: access.timestamp,
                lastSeen: access.timestamp,
                loginTimes: [],
                sessionDurations: [],
                filesPerSession: [],
                ipAddresses: new Set(),
                locations: new Set(),
                deviceIds: new Set(),
            });
        }
        
        const user = this.users.get(event.userId);
        user.accessCount++;
        user.lastSeen = access.timestamp;
        
        if (event.type === 'login') {
            user.loginTimes.push(new Date(access.timestamp).getHours());
        }
        
        if (event.type === 'logout' && event.duration) {
            user.sessionDurations.push(event.duration);
        }
        
        if (event.filesAccessed) {
            user.filesPerSession.push(event.filesAccessed);
        }
        
        if (event.ipAddress) {
            user.ipAddresses.add(event.ipAddress);
        }
        
        if (event.location) {
            user.locations.add(event.location);
        }
        
        if (event.deviceId) {
            user.deviceIds.add(event.deviceId);
        }
        
        return access;
    }
    
    /**
     * Train baseline model on historical data
     */
    trainBaseline() {
        const now = Date.now();
        const windowMs = this.baselineWindowDays * 24 * 60 * 60 * 1000;
        
        // Get baseline data (older than window)
        const baselineEvents = this.accessLogs
            .filter(e => (now - e.timestamp) > windowMs)
            .map(e => this.extractFeatures(e));
        
        if (baselineEvents.length < 10) {
            console.warn('[AccessPatternAnomalyDetector] Insufficient baseline data');
            return;
        }
        
        try {
            this.forest.train(baselineEvents);
            this.modelTrained = true;
            this.emit('model-trained', {
                samplesUsed: baselineEvents.length,
                window: this.baselineWindowDays,
            });
        } catch (err) {
            this.emit('training-error', err);
        }
    }
    
    /**
     * Check access for anomalies
     */
    checkAnomaly(access) {
        if (!this.modelTrained) {
            return {
                anomalous: false,
                reason: 'Model not trained',
                score: 0,
            };
        }
        
        const features = this.extractFeatures(access);
        const score = this.forest.predict(features);
        const isAnomalous = score >= this.anomalyThreshold;
        
        if (isAnomalous) {
            const anomaly = {
                userId: access.userId,
                timestamp: access.timestamp,
                type: access.type,
                anomalyScore: score,
                features,
                severity: this.calculateSeverity(score),
                reason: this.generateReason(access),
            };
            
            this.anomalies.push(anomaly);
            this.emit('anomaly-detected', anomaly);
            
            return {
                anomalous: true,
                score,
                severity: anomaly.severity,
                reason: anomaly.reason,
            };
        }
        
        return {
            anomalous: false,
            score,
            reason: 'Normal pattern',
        };
    }
    
    /**
     * Extract features from access event
     */
    extractFeatures(access) {
        // Hour of day (0-23)
        const loginHour = new Date(access.timestamp).getHours();
        
        // Session duration in minutes
        const sessionMinutes = access.duration ? access.duration / 60000 : 0;
        
        // Files accessed count
        const fileCount = access.filesAccessed || 0;
        
        // Time since last access in hours
        const user = this.users.get(access.userId) || {};
        const timeSinceLastAccess = user.lastSeen 
            ? (access.timestamp - user.lastSeen) / 3600000 
            : 0;
        
        // Devices used (count)
        const deviceCount = user.deviceIds ? user.deviceIds.size : 1;
        
        // IP addresses used (count)
        const ipCount = user.ipAddresses ? user.ipAddresses.size : 1;
        
        // Locations (count)
        const locationCount = user.locations ? user.locations.size : 1;
        
        return {
            loginHour: Math.min(23, Math.max(0, loginHour)),
            sessionMinutes: Math.min(1440, sessionMinutes), // Cap at 24 hours
            fileCount: Math.min(10000, fileCount),
            timeSinceLastAccess: Math.min(720, timeSinceLastAccess), // Cap at 30 days
            deviceCount: Math.min(50, deviceCount),
            ipCount: Math.min(50, ipCount),
            locationCount: Math.min(50, locationCount),
        };
    }
    
    /**
     * Calculate severity level
     */
    calculateSeverity(score) {
        if (score >= 0.85) return 'critical';
        if (score >= 0.75) return 'high';
        if (score >= 0.65) return 'medium';
        return 'low';
    }
    
    /**
     * Generate reason for anomaly
     */
    generateReason(access) {
        const user = this.users.get(access.userId);
        if (!user) return 'Insufficient history';
        
        const reasons = [];
        
        // Check login hour deviation
        const expectedHours = this.calculateExpectedRange(user.loginTimes);
        const loginHour = new Date(access.timestamp).getHours();
        if (!expectedHours.includes(loginHour)) {
            reasons.push(`Unusual login hour: ${loginHour}h (expected ${expectedHours.join(',')}h)`);
        }
        
        // Check session duration
        if (user.sessionDurations.length > 0) {
            const avgDuration = user.sessionDurations.reduce((a, b) => a + b) / user.sessionDurations.length;
            const deviation = access.duration ? Math.abs(access.duration - avgDuration) / avgDuration : 0;
            if (deviation > 1.5) {
                reasons.push(`Unusual session duration: ${(access.duration / 60000).toFixed(1)}min (avg ${(avgDuration / 60000).toFixed(1)}min)`);
            }
        }
        
        // Check file access pattern
        if (user.filesPerSession.length > 0) {
            const avgFiles = user.filesPerSession.reduce((a, b) => a + b) / user.filesPerSession.length;
            if (access.filesAccessed && access.filesAccessed > avgFiles * 2) {
                reasons.push(`Excessive file access: ${access.filesAccessed} files (avg ${Math.round(avgFiles)})`);
            }
        }
        
        // Check device/location
        if (access.deviceId && !user.deviceIds.has(access.deviceId)) {
            reasons.push(`New device detected: ${access.deviceId}`);
        }
        
        if (access.location && !user.locations.has(access.location)) {
            reasons.push(`New location detected: ${access.location}`);
        }
        
        return reasons.length > 0 
            ? reasons.join('; ')
            : 'Pattern divergence from baseline';
    }
    
    /**
     * Calculate expected time range from historical data
     */
    calculateExpectedRange(hours) {
        if (hours.length === 0) return [0, 1, 2, 3, 4, 5, 23]; // Default night hours
        
        hours.sort();
        const mean = hours.reduce((a, b) => a + b) / hours.length;
        const stdDev = Math.sqrt(
            hours.reduce((sum, h) => sum + Math.pow(h - mean, 2), 0) / hours.length
        );
        
        // Expected range: mean ± stdDev
        const min = Math.max(0, Math.floor(mean - stdDev));
        const max = Math.min(23, Math.ceil(mean + stdDev));
        
        const range = [];
        for (let i = min; i <= max; i++) {
            range.push(i);
        }
        return range.length > 0 ? range : [Math.round(mean)];
    }
    
    /**
     * Get anomaly report
     */
    getAnomalyReport(userId, timeWindowDays = 7) {
        const now = Date.now();
        const windowMs = timeWindowDays * 24 * 60 * 60 * 1000;
        
        const userAnomalies = this.anomalies.filter(a =>
            a.userId === userId &&
            (now - a.timestamp) <= windowMs
        );
        
        const user = this.users.get(userId);
        
        return {
            userId,
            timeWindow: timeWindowDays,
            totalAnomalies: userAnomalies.length,
            criticalAnomalies: userAnomalies.filter(a => a.severity === 'critical').length,
            highAnomalies: userAnomalies.filter(a => a.severity === 'high').length,
            mediumAnomalies: userAnomalies.filter(a => a.severity === 'medium').length,
            anomalies: userAnomalies.map(a => ({
                timestamp: new Date(a.timestamp).toISOString(),
                type: a.type,
                score: a.anomalyScore.toFixed(3),
                severity: a.severity,
                reason: a.reason,
            })),
            baseline: {
                avgLoginHour: user ? Math.round(user.loginTimes.reduce((a, b) => a + b, 0) / user.loginTimes.length) : 'N/A',
                avgSessionDuration: user ? Math.round(user.sessionDurations.reduce((a, b) => a + b, 0) / user.sessionDurations.length / 60000) : 'N/A',
                avgFilesPerSession: user ? Math.round(user.filesPerSession.reduce((a, b) => a + b, 0) / user.filesPerSession.length) : 'N/A',
                knownDevices: user ? user.deviceIds.size : 0,
                knownLocations: user ? user.locations.size : 0,
            },
        };
    }
}

module.exports = { AccessPatternAnomalyDetector, IsolationForest };
