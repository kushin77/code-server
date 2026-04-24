/**
 * Performance Validation Framework - Phase 12.4
 * Validates system meets SLA and performance targets
 *
 * Responsibilities:
 * - Define SLA requirements per region
 * - Validate performance metrics
 * - Generate compliance reports
 * - Flag violations and issues
 * - Track historical trends
 */
export class PerformanceValidator {
    constructor() {
        this.slaTargets = new Map();
    }
    /**
     * Register SLA targets for a region
     */
    registerRegionSLA(regionId, sla) {
        this.slaTargets.set(regionId, sla);
    }
    /**
     * Validate performance metrics
     */
    validatePerformance(regionId, metrics) {
        const sla = this.slaTargets.get(regionId);
        if (!sla) {
            return {
                regionId,
                compliant: true,
                violations: [],
                compliancePercent: 100,
                summary: 'No SLA targets defined',
            };
        }
        const violations = [];
        // Check each target
        for (const target of sla.targets) {
            let currentValue = 0;
            switch (target.metricType) {
                case 'latency':
                    currentValue = Math.max(metrics.latencyP95, metrics.latencyP99);
                    break;
                case 'availability':
                    currentValue = 100 - metrics.errorRate;
                    break;
                case 'throughput':
                    currentValue = metrics.throughput;
                    break;
                case 'errorRate':
                    currentValue = metrics.errorRate;
                    break;
            }
            // Check violation
            const isViolation = this.isViolation(target.metricType, currentValue, target.threshold);
            if (isViolation) {
                violations.push({
                    regionId,
                    metricType: target.metricType,
                    currentValue,
                    threshold: target.threshold,
                    violationPercent: ((currentValue - target.threshold) /
                        target.threshold) *
                        100,
                    severity: target.severity,
                    timestamp: new Date(),
                });
            }
        }
        const compliant = violations.length === 0;
        const compliancePercent = sla.targets.length > 0
            ? ((sla.targets.length - violations.length) /
                sla.targets.length) *
                100
            : 100;
        return {
            regionId,
            compliant,
            violations,
            compliancePercent,
            summary: compliant
                ? `Region ${regionId} is SLA compliant`
                : `Region ${regionId} has ${violations.length} SLA violations`,
        };
    }
    /**
     * Check if value violates threshold
     */
    isViolation(metricType, currentValue, threshold) {
        // Lower is better
        if (metricType === 'latency' || metricType === 'errorRate') {
            return currentValue > threshold;
        }
        // Higher is better
        if (metricType === 'availability' || metricType === 'throughput') {
            return currentValue < threshold;
        }
        return false;
    }
    /**
     * Generate performance report
     */
    generateReport(results) {
        const timestamp = new Date();
        const violations = [];
        const complianceScores = [];
        const recommendations = [];
        for (const compliance of Object.values(results)) {
            violations.push(...compliance.violations);
            complianceScores.push(compliance.compliancePercent);
        }
        const globalCompliance = complianceScores.length > 0
            ? complianceScores.reduce((a, b) => a + b, 0) /
                complianceScores.length
            : 100;
        // Generate recommendations
        for (const violation of violations) {
            if (violation.severity === 'CRITICAL') {
                recommendations.push(`CRITICAL: ${violation.regionId} ${violation.metricType} must be addressed immediately`);
            }
            else if (violation.severity === 'HIGH') {
                recommendations.push(`HIGH: ${violation.regionId} ${violation.metricType} needs attention`);
            }
        }
        if (recommendations.length === 0) {
            recommendations.push('✅ All regions meet SLA targets');
        }
        const summary = `
Global SLA Compliance: ${Math.round(globalCompliance)}%
Total Violations: ${violations.length}
Critical Issues: ${violations.filter((v) => v.severity === 'CRITICAL').length}
High Issues: ${violations.filter((v) => v.severity === 'HIGH').length}
    `.trim();
        return {
            timestamp,
            testDuration: Date.now(),
            regions: results,
            globalCompliance,
            summary,
            recommendations,
        };
    }
}
// Default SLA configuration for federation
export const DEFAULT_FEDERATION_SLA = {
    'us-west': {
        regionId: 'us-west',
        targets: [
            {
                name: 'Latency P95',
                metricType: 'latency',
                threshold: 50,
                window: 60000,
                severity: 'HIGH',
            },
            {
                name: 'Latency P99',
                metricType: 'latency',
                threshold: 100,
                window: 60000,
                severity: 'MEDIUM',
            },
            {
                name: 'Availability',
                metricType: 'availability',
                threshold: 99.9,
                window: 3600000,
                severity: 'CRITICAL',
            },
            {
                name: 'Error Rate',
                metricType: 'errorRate',
                threshold: 0.1,
                window: 60000,
                severity: 'HIGH',
            },
        ],
    },
    'eu-west': {
        regionId: 'eu-west',
        targets: [
            {
                name: 'Latency P95',
                metricType: 'latency',
                threshold: 100,
                window: 60000,
                severity: 'HIGH',
            },
            {
                name: 'Latency P99',
                metricType: 'latency',
                threshold: 150,
                window: 60000,
                severity: 'MEDIUM',
            },
            {
                name: 'Availability',
                metricType: 'availability',
                threshold: 99.95,
                window: 3600000,
                severity: 'CRITICAL',
            },
            {
                name: 'Error Rate',
                metricType: 'errorRate',
                threshold: 0.1,
                window: 60000,
                severity: 'HIGH',
            },
        ],
    },
};
//# sourceMappingURL=PerformanceValidator.js.map