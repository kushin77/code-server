/**
 * Core anomaly detection engine using z-score statistical method.
 * Lightweight, interpretable, and production-ready.
 */
export const DEFAULT_ANOMALY_CONFIG = {
    anomalyScoreThreshold: 0.7,
    zScoreThreshold: 2.5,
    retrainingIntervalMs: 7 * 24 * 60 * 60 * 1000,
    minSamplesForProfile: 14,
    maxAlertsPerUserPerDay: 10,
    gracePeriodMs: 14 * 24 * 60 * 60 * 1000,
    enableLoginTimeAnalysis: true,
    enableFileAccessAnalysis: true,
    enableSessionDurationAnalysis: true,
    enableDataTransferAnalysis: true,
    enablePrometheusAlerts: true,
    enableMatrixNotifications: true,
};
export class AnomalyDetectionEngine {
    constructor(config = {}) {
        this.config = { ...DEFAULT_ANOMALY_CONFIG, ...config };
    }
    calculateZScore(value, stats) {
        if (stats.stdDev === 0) {
            return value === stats.mean ? 0 : Math.abs(value - stats.mean);
        }
        return Math.abs((value - stats.mean) / stats.stdDev);
    }
    calculateDimensionStatistics(values, dimension) {
        if (values.length === 0)
            throw new Error(`No values for dimension: ${dimension}`);
        const sorted = [...values].sort((a, b) => a - b);
        const mean = values.reduce((a, b) => a + b, 0) / values.length;
        const variance = values.reduce((a, b) => a + (b - mean) ** 2, 0) / values.length;
        const stdDev = Math.sqrt(variance);
        const percentile = (p) => {
            const idx = Math.ceil((p / 100) * sorted.length) - 1;
            return sorted[Math.max(0, Math.min(idx, sorted.length - 1))];
        };
        return {
            dimension,
            mean,
            stdDev,
            min: sorted[0],
            max: sorted[sorted.length - 1],
            p25: percentile(25),
            p50: percentile(50),
            p75: percentile(75),
            p95: percentile(95),
            sampleCount: values.length,
        };
    }
    scoreSession(event, profile) {
        const dimensionScores = {};
        const topAnomalies = [];
        // Login time analysis
        if (this.config.enableLoginTimeAnalysis && profile.loginTimes.stdDev) {
            const stats = {
                dimension: 'loginTime',
                mean: profile.loginTimes.mean || 9,
                stdDev: profile.loginTimes.stdDev || 4,
                min: 0, max: 23, p25: 0, p50: 9, p75: 0, p95: 0,
                sampleCount: profile.sampleCount,
            };
            const zScore = this.calculateZScore(event.loginHour, stats);
            const normalized = Math.min(1, zScore / this.config.zScoreThreshold);
            dimensionScores['loginTime'] = normalized;
            if (normalized > 0.3) {
                topAnomalies.push({
                    dimension: 'loginTime',
                    score: normalized,
                    description: `Login at unusual hour (${event.loginHour}:00, typically ${Math.round(stats.mean)}:00)`,
                });
            }
        }
        // Session duration analysis
        if (this.config.enableSessionDurationAnalysis) {
            const stats = {
                dimension: 'sessionDuration',
                mean: profile.sessionDuration.mean,
                stdDev: profile.sessionDuration.stdDev,
                min: 0,
                max: profile.sessionDuration.p95 * 2,
                p25: 0, p50: profile.sessionDuration.mean, p75: 0,
                p95: profile.sessionDuration.p95,
                sampleCount: profile.sampleCount,
            };
            const zScore = this.calculateZScore(event.sessionDurationSeconds, stats);
            const normalized = Math.min(1, zScore / this.config.zScoreThreshold);
            dimensionScores['sessionDuration'] = normalized;
            if (normalized > 0.3) {
                topAnomalies.push({
                    dimension: 'sessionDuration',
                    score: normalized,
                    description: `Unusual duration (${event.sessionDurationSeconds}s, typically ${Math.round(stats.mean)}s)`,
                });
            }
        }
        // File access analysis
        if (this.config.enableFileAccessAnalysis && profile.fileAccessPatterns.mean_files_accessed) {
            const stats = {
                dimension: 'fileAccess',
                mean: profile.fileAccessPatterns.mean_files_accessed,
                stdDev: profile.fileAccessPatterns.stdDev_files_accessed || 5,
                min: 0, max: 1000, p25: 0, p50: profile.fileAccessPatterns.mean_files_accessed,
                p75: 0, p95: 0,
                sampleCount: profile.sampleCount,
            };
            const zScore = this.calculateZScore(event.filesAccessed, stats);
            const normalized = Math.min(1, zScore / this.config.zScoreThreshold);
            dimensionScores['fileAccess'] = normalized;
            if (normalized > 0.4) {
                topAnomalies.push({
                    dimension: 'fileAccess',
                    score: normalized,
                    description: `Unusual file volume (${event.filesAccessed} files, typically ${Math.round(stats.mean)})`,
                });
            }
        }
        // Data transfer analysis
        if (this.config.enableDataTransferAnalysis && profile.dataTransfer.mean_bytes) {
            const stats = {
                dimension: 'dataTransfer',
                mean: profile.dataTransfer.mean_bytes,
                stdDev: profile.dataTransfer.stdDev_bytes || profile.dataTransfer.mean_bytes * 0.5,
                min: 0,
                max: profile.dataTransfer.p95_bytes || profile.dataTransfer.mean_bytes * 3,
                p25: 0, p50: profile.dataTransfer.mean_bytes, p75: 0,
                p95: profile.dataTransfer.p95_bytes || 0,
                sampleCount: profile.sampleCount,
            };
            const zScore = this.calculateZScore(event.bytesTransferred, stats);
            const normalized = Math.min(1, zScore / this.config.zScoreThreshold);
            dimensionScores['dataTransfer'] = normalized;
            if (normalized > 0.4) {
                topAnomalies.push({
                    dimension: 'dataTransfer',
                    score: normalized,
                    description: `Unusual data volume (${(event.bytesTransferred / 1024 / 1024).toFixed(2)} MB)`,
                });
            }
        }
        topAnomalies.sort((a, b) => b.score - a.score);
        const scores = Object.values(dimensionScores);
        const overallScore = scores.length > 0 ? scores.reduce((a, b) => a + b) / scores.length : 0;
        return {
            sessionId: event.sessionId,
            userId: event.userId,
            timestamp: event.timestamp,
            overallScore: Math.min(1, overallScore),
            dimensionScores: {
                loginTime: dimensionScores['loginTime'] || 0,
                fileAccess: dimensionScores['fileAccess'] || 0,
                sessionDuration: dimensionScores['sessionDuration'] || 0,
                dataTransfer: dimensionScores['dataTransfer'] || 0,
            },
            topAnomalies,
            method: 'z-score',
            confidence: Math.min(0.99, 0.5 + profile.sampleCount / 100),
        };
    }
    buildProfile(userId, events) {
        if (events.length < this.config.minSamplesForProfile) {
            throw new Error(`Insufficient samples (${events.length} < ${this.config.minSamplesForProfile})`);
        }
        const loginHours = events.map((e) => e.loginHour);
        const sessionDurations = events.map((e) => e.sessionDurationSeconds);
        const filesAccessed = events.map((e) => e.filesAccessed);
        const bytesTransferred = events.map((e) => e.bytesTransferred);
        const loginStats = this.calculateDimensionStatistics(loginHours, 'loginTime');
        const durationStats = this.calculateDimensionStatistics(sessionDurations, 'sessionDuration');
        const filesStats = this.calculateDimensionStatistics(filesAccessed, 'filesAccessed');
        const bytesStats = this.calculateDimensionStatistics(bytesTransferred, 'bytesTransferred');
        const extensions = {};
        const directories = {};
        for (const event of events) {
            for (const ext of event.fileExtensions) {
                extensions[ext] = (extensions[ext] || 0) + 1;
            }
            for (const dir of event.directoriesAccessed) {
                directories[dir] = (directories[dir] || 0) + 1;
            }
        }
        return {
            userId,
            profileId: `profile-${userId}-${Date.now()}`,
            createdAt: Date.now(),
            updatedAt: Date.now(),
            sampleCount: events.length,
            loginTimes: {
                hours: loginHours,
                mean: loginStats.mean,
                stdDev: loginStats.stdDev,
            },
            fileAccessPatterns: {
                extensions,
                directories,
                mean_files_accessed: filesStats.mean,
                stdDev_files_accessed: filesStats.stdDev,
            },
            sessionDuration: {
                mean: durationStats.mean,
                stdDev: durationStats.stdDev,
                p95: durationStats.p95,
            },
            dataTransfer: {
                mean_bytes: bytesStats.mean,
                stdDev_bytes: bytesStats.stdDev,
                p95_bytes: bytesStats.p95,
            },
            trainingData: {
                startDate: Math.min(...events.map((e) => e.timestamp)),
                endDate: Math.max(...events.map((e) => e.timestamp)),
                sessionCount: events.length,
            },
        };
    }
}
//# sourceMappingURL=engine.js.map