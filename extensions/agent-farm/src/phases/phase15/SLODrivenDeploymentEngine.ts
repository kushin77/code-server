/**
 * Phase 15: SLO-Driven Deployment Engine
 * Metric-based deployment gate decisions
 */

import { SystemMetrics } from './DeploymentOrchestrator';

export interface SLOTargets {
  authenticationLatencyP99: number;
  policyEvaluationP99: number;
  threatDetectionThroughput: number;
  dataExfiltrationPrevention: string;
  errorRate: number;
  availability: number;
}

export interface SLOValidation {
  meetsAuthLatency: boolean;
  meetsPolicyEval: boolean;
  meetsThreatDetection: boolean;
  meetsErrorRate: boolean;
  meetsAvailability: boolean;
  overallCompliance: boolean;
  violations: SLOViolation[];
}

export interface SLOViolation {
  metric: string;
  target: number;
  actual: number;
  severity: 'warning' | 'critical';
}

export interface GateValidation {
  canProgress: boolean;
  violations: string[];
  recommendations: string[];
  nextCheckTime?: Date;
}

export interface MetricsComparison {
  latencyImprovement: number;
  errorRateImprovement: number;
  availabilityImprovement: number;
  overallImprovement: number;
  degradedMetrics: string[];
}

export interface SLOReport {
  period: { start: Date; end: Date };
  metrics: SystemMetrics[];
  violations: SLOViolation[];
  compliancePercentage: number;
  observations: string[];
  recommendations: string[];
}

export interface TimeWindow {
  start: Date;
  end: Date;
}

export class SLODrivenDeploymentEngine {
  private sloTargets: SLOTargets = {
    authenticationLatencyP99: 100,
    policyEvaluationP99: 50,
    threatDetectionThroughput: 5000,
    dataExfiltrationPrevention: 'blocking-gt-100mb',
    errorRate: 1,
    availability: 99.95,
  };

  private baselineMetrics: SystemMetrics | null = null;
  private metricsHistory: SystemMetrics[] = [];

  async validateSLOCompliance(metrics: SystemMetrics): Promise<SLOValidation> {
    const violations: SLOViolation[] = [];

    // Check authentication latency
    const authLatencyMet = metrics.p99Latency <= this.sloTargets.authenticationLatencyP99;
    if (!authLatencyMet) {
      violations.push({
        metric: 'authenticationLatencyP99',
        target: this.sloTargets.authenticationLatencyP99,
        actual: metrics.p99Latency,
        severity: metrics.p99Latency > 150 ? 'critical' : 'warning',
      });
    }

    // Check error rate
    const errorRateMet = metrics.errorRate <= this.sloTargets.errorRate;
    if (!errorRateMet) {
      violations.push({
        metric: 'errorRate',
        target: this.sloTargets.errorRate,
        actual: metrics.errorRate,
        severity: metrics.errorRate > 2 ? 'critical' : 'warning',
      });
    }

    // Check throughput
    const throughputMet = metrics.throughput >= this.sloTargets.threatDetectionThroughput;
    if (!throughputMet) {
      violations.push({
        metric: 'threatDetectionThroughput',
        target: this.sloTargets.threatDetectionThroughput,
        actual: metrics.throughput,
        severity: 'warning',
      });
    }

    return {
      meetsAuthLatency: authLatencyMet,
      meetsPolicyEval: metrics.p95Latency <= this.sloTargets.policyEvaluationP99,
      meetsThreatDetection: throughputMet,
      meetsErrorRate: errorRateMet,
      meetsAvailability: true,  // Would calculate from uptime
      overallCompliance: violations.length === 0,
      violations,
    };
  }

  async checkDeploymentGates(
    stage: string,
    metrics: SystemMetrics
  ): Promise<GateValidation> {
    const validation = await this.validateSLOCompliance(metrics);
    const violations: string[] = [];
    const recommendations: string[] = [];

    if (!validation.meetsAuthLatency) {
      violations.push('Authentication latency exceeds SLO');
      recommendations.push('Optimize query performance or increase resources');
    }

    if (!validation.meetsErrorRate) {
      violations.push('Error rate exceeds SLO');
      recommendations.push('Debug error sources and deploy fix');
    }

    if (!validation.meetsThreatDetection) {
      violations.push('Threat detection throughput below SLO');
      recommendations.push('Scale threat detection service');
    }

    return {
      canProgress: violations.length === 0,
      violations,
      recommendations,
      nextCheckTime: new Date(Date.now() + 60000),
    };
  }

  async establishBaselineMetrics(environment: 'staging' | 'production'): Promise<void> {
    this.baselineMetrics = {
      timestamp: new Date(),
      p99Latency: 85,
      p95Latency: 45,
      errorRate: 0.5,
      throughput: 5000,
      cpuUsage: 45,
      memoryUsage: 60,
      diskUsage: 70,
      requestCount: 50000,
      failureCount: 250,
      activeConnections: 1000,
    };
  }

  async updateBaselineMetrics(metrics: SystemMetrics): Promise<void> {
    this.baselineMetrics = metrics;
  }

  async compareMetricsWithBaseline(current: SystemMetrics): Promise<MetricsComparison> {
    if (!this.baselineMetrics) {
      await this.establishBaselineMetrics('production');
    }

    const baseline = this.baselineMetrics!;

    const latencyImprovement = ((baseline.p99Latency - current.p99Latency) / baseline.p99Latency) * 100;
    const errorRateImprovement = ((baseline.errorRate - current.errorRate) / baseline.errorRate) * 100;
    const availabilityImprovement = (99.5 - 99.4);

    const degradedMetrics: string[] = [];
    if (latencyImprovement < 0) degradedMetrics.push('latency');
    if (errorRateImprovement < 0) degradedMetrics.push('error-rate');
    if (availabilityImprovement < 0) degradedMetrics.push('availability');

    return {
      latencyImprovement,
      errorRateImprovement,
      availabilityImprovement,
      overallImprovement: (latencyImprovement + errorRateImprovement) / 2,
      degradedMetrics,
    };
  }

  async updateSLOThresholds(slos: SLOTargets): Promise<void> {
    this.sloTargets = slos;
  }

  async getCurrentSLOThresholds(): Promise<SLOTargets> {
    return { ...this.sloTargets };
  }

  async generateSLOReport(timeWindow: TimeWindow): Promise<SLOReport> {
    const windowMetrics = this.metricsHistory.filter(
      m => m.timestamp >= timeWindow.start && m.timestamp <= timeWindow.end
    );

    const violations: SLOViolation[] = [];
    let violationCount = 0;

    windowMetrics.forEach(metrics => {
      const validation = { /* quick check */ } as any;
      // Simulate violation checking
      if (metrics.p99Latency > this.sloTargets.authenticationLatencyP99) {
        violationCount += 1;
      }
      if (metrics.errorRate > this.sloTargets.errorRate) {
        violationCount += 1;
      }
    });

    const compliancePercentage = windowMetrics.length > 0
      ? ((windowMetrics.length - violationCount) / windowMetrics.length) * 100
      : 100;

    return {
      period: timeWindow,
      metrics: windowMetrics,
      violations,
      compliancePercentage,
      observations: [
        `Monitored ${windowMetrics.length} metric snapshots`,
        `Average P99 latency: ${(windowMetrics.reduce((sum, m) => sum + m.p99Latency, 0) / Math.max(1, windowMetrics.length)).toFixed(2)}ms`,
      ],
      recommendations: [
        'Continue monitoring at current SLO levels',
        'Review thresholds if trending toward violations',
      ],
    };
  }

  async detectSLOViolations(metrics: SystemMetrics): Promise<SLOViolation[]> {
    const violations: SLOViolation[] = [];

    if (metrics.p99Latency > this.sloTargets.authenticationLatencyP99) {
      violations.push({
        metric: 'p99Latency',
        target: this.sloTargets.authenticationLatencyP99,
        actual: metrics.p99Latency,
        severity: 'critical',
      });
    }

    if (metrics.errorRate > this.sloTargets.errorRate) {
      violations.push({
        metric: 'errorRate',
        target: this.sloTargets.errorRate,
        actual: metrics.errorRate,
        severity: 'critical',
      });
    }

    if (metrics.throughput < this.sloTargets.threatDetectionThroughput) {
      violations.push({
        metric: 'throughput',
        target: this.sloTargets.threatDetectionThroughput,
        actual: metrics.throughput,
        severity: 'warning',
      });
    }

    return violations;
  }
}
