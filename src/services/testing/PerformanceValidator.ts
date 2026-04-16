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

export interface SLATarget {
  name: string;
  metricType: 'latency' | 'availability' | 'throughput' | 'errorRate';
  threshold: number;
  window: number; // milliseconds
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW';
}

export interface RegionSLA {
  regionId: string;
  targets: SLATarget[];
}

export interface SLAViolation {
  regionId: string;
  metricType: string;
  currentValue: number;
  threshold: number;
  violationPercent: number;
  severity: string;
  timestamp: Date;
}

export interface SLACompliance {
  regionId: string;
  compliant: boolean;
  violations: SLAViolation[];
  compliancePercent: number;
  summary: string;
}

export interface PerformanceValidationResult {
  timestamp: Date;
  testDuration: number;
  regions: Record<string, SLACompliance>;
  globalCompliance: number; // percentage
  summary: string;
  recommendations: string[];
}

export class PerformanceValidator {
  private slaTargets: Map<string, RegionSLA> = new Map();

  /**
   * Register SLA targets for a region
   */
  registerRegionSLA(regionId: string, sla: RegionSLA): void {
    this.slaTargets.set(regionId, sla);
  }

  /**
   * Validate performance metrics
   */
  validatePerformance(
    regionId: string,
    metrics: {
      latencyP95: number;
      latencyP99: number;
      availability: number; // 0-100
      throughput: number;
      errorRate: number; // 0-100
    }
  ): SLACompliance {
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

    const violations: SLAViolation[] = [];

    // Check each target
    for (const target of sla.targets) {
      let currentValue = 0;

      switch (target.metricType) {
        case 'latency':
          currentValue = Math.max(
            metrics.latencyP95,
            metrics.latencyP99
          );
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
      const isViolation = this.isViolation(
        target.metricType,
        currentValue,
        target.threshold
      );

      if (isViolation) {
        violations.push({
          regionId,
          metricType: target.metricType,
          currentValue,
          threshold: target.threshold,
          violationPercent:
            ((currentValue - target.threshold) /
              target.threshold) *
            100,
          severity: target.severity,
          timestamp: new Date(),
        });
      }
    }

    const compliant = violations.length === 0;
    const compliancePercent =
      sla.targets.length > 0
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
  private isViolation(
    metricType: string,
    currentValue: number,
    threshold: number
  ): boolean {
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
  generateReport(
    results: Record<string, SLACompliance>
  ): PerformanceValidationResult {
    const timestamp = new Date();
    const violations: SLAViolation[] = [];
    const complianceScores: number[] = [];
    const recommendations: string[] = [];

    for (const compliance of Object.values(results)) {
      violations.push(...compliance.violations);
      complianceScores.push(compliance.compliancePercent);
    }

    const globalCompliance =
      complianceScores.length > 0
        ? complianceScores.reduce((a, b) => a + b, 0) /
          complianceScores.length
        : 100;

    // Generate recommendations
    for (const violation of violations) {
      if (violation.severity === 'CRITICAL') {
        recommendations.push(
          `CRITICAL: ${violation.regionId} ${violation.metricType} must be addressed immediately`
        );
      } else if (violation.severity === 'HIGH') {
        recommendations.push(
          `HIGH: ${violation.regionId} ${violation.metricType} needs attention`
        );
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
export const DEFAULT_FEDERATION_SLA: Record<string, RegionSLA> = {
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
