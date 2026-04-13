/**
 * SLO (Service Level Objective) Tracker
 * Monitors and tracks service metrics against defined SLOs/SLIs
 */

export interface SLI {
  name: string;
  description: string;
  type: 'availability' | 'latency' | 'error_rate' | 'throughput' | 'custom';
  unit: string;
  threshold: number; // target value
  window: number; // milliseconds
}

export interface SLO {
  name: string;
  description: string;
  service: string;
  slis: SLI[];
  targetPercentage: number; // e.g., 99.9 for 99.9%
  errorBudget: number; // milliseconds or events
  period: number; // measurement period in days
  reviewDate?: Date;
}

export interface MetricPoint {
  timestamp: number;
  value: number;
  labels?: Record<string, string>;
}

export interface SLIStatus {
  sli: SLI;
  currentValue: number;
  targetValue: number;
  percentage: number; // % of target met
  status: 'healthy' | 'warning' | 'critical';
  trend: 'improving' | 'stable' | 'degrading';
}

export interface SLOStatus {
  slo: SLO;
  sliStatuses: SLIStatus[];
  overallPercentage: number;
  errorBudgetRemaining: number;
  daysUntilBudgetExhausted: number;
  status: 'healthy' | 'warning' | 'critical';
}

export class SLOTracker {
  private slos: Map<string, SLO> = new Map();
  private metrics: Map<string, MetricPoint[]> = new Map();
  private history: Map<string, SLOStatus[]> = new Map();
  private readonly maxHistoryLength = 90; // 90 days

  constructor() {}

  /**
   * Register an SLO
   */
  registerSLO(slo: SLO): void {
    this.slos.set(slo.name, slo);
    this.metrics.set(`${slo.name}-metrics`, []);
    this.history.set(slo.name, []);
  }

  /**
   * Record a metric point
   */
  recordMetric(sloName: string, sliName: string, value: number, timestamp: number = Date.now()): void {
    const key = `${sloName}-${sliName}`;
    if (!this.metrics.has(key)) {
      this.metrics.set(key, []);
    }
    const points = this.metrics.get(key)!;
    points.push({ timestamp, value });

    // Keep only recent data (last 7 days)
    const sevenDaysAgo = timestamp - 7 * 24 * 60 * 60 * 1000;
    const filtered = points.filter((p) => p.timestamp > sevenDaysAgo);
    this.metrics.set(key, filtered);
  }

  /**
   * Calculate SLI status
   */
  calculateSLIStatus(slo: SLO, sli: SLI): SLIStatus {
    const key = `${slo.name}-${sli.name}`;
    const points = this.metrics.get(key) || [];

    if (points.length === 0) {
      return {
        sli,
        currentValue: 0,
        targetValue: sli.threshold,
        percentage: 0,
        status: 'critical',
        trend: 'stable',
      };
    }

    // Calculate average of recent points within the window
    const now = Date.now();
    const windowStart = now - sli.window;
    const windowPoints = points.filter((p) => p.timestamp >= windowStart);

    const avgValue = windowPoints.length > 0 ? windowPoints.reduce((sum, p) => sum + p.value, 0) / windowPoints.length : 0;

    // Determine if we're meeting the SLI
    const percentage = (avgValue / sli.threshold) * 100;
    let status: 'healthy' | 'warning' | 'critical';
    if (percentage >= 95) {
      status = 'healthy';
    } else if (percentage >= 80) {
      status = 'warning';
    } else {
      status = 'critical';
    }

    // Determine trend
    let trend: 'improving' | 'stable' | 'degrading' = 'stable';
    if (windowPoints.length >= 2) {
      const firstHalf = windowPoints.slice(0, Math.floor(windowPoints.length / 2));
      const secondHalf = windowPoints.slice(Math.floor(windowPoints.length / 2));
      const firstAvg = firstHalf.reduce((sum, p) => sum + p.value, 0) / firstHalf.length;
      const secondAvg = secondHalf.reduce((sum, p) => sum + p.value, 0) / secondHalf.length;
      if (secondAvg > firstAvg * 1.05) {
        trend = 'improving';
      } else if (secondAvg < firstAvg * 0.95) {
        trend = 'degrading';
      }
    }

    return {
      sli,
      currentValue: avgValue,
      targetValue: sli.threshold,
      percentage,
      status,
      trend,
    };
  }

  /**
   * Get SLO status
   */
  getSLOStatus(sloName: string): SLOStatus | undefined {
    const slo = this.slos.get(sloName);
    if (!slo) return undefined;

    // Calculate all SLI statuses
    const sliStatuses = slo.slis.map((sli) => this.calculateSLIStatus(slo, sli));

    // Overall percentage is the minimum of all SLIs
    const overallPercentage = sliStatuses.length > 0 ? Math.min(...sliStatuses.map((s) => s.percentage)) : 0;

    // Error budget tracking
    const targetPercentage = slo.targetPercentage;
    const allowedFailurePercentage = 100 - targetPercentage;
    const actualFailurePercentage = 100 - overallPercentage;
    const budgetUsedPercentage = (actualFailurePercentage / allowedFailurePercentage) * 100;
    const errorBudgetRemaining = Math.max(0, slo.errorBudget * (1 - budgetUsedPercentage / 100));

    // Calculate days until budget exhaustion
    const daysRemaining = slo.period - Math.ceil((budgetUsedPercentage / 100) * slo.period);
    const daysUntilBudgetExhausted = Math.max(0, daysRemaining);

    // Determine overall status
    let status: 'healthy' | 'warning' | 'critical';
    if (overallPercentage >= slo.targetPercentage) {
      status = 'healthy';
    } else if (overallPercentage >= slo.targetPercentage * 0.95) {
      status = 'warning';
    } else {
      status = 'critical';
    }

    const sloStatus: SLOStatus = {
      slo,
      sliStatuses,
      overallPercentage,
      errorBudgetRemaining,
      daysUntilBudgetExhausted,
      status,
    };

    // Store in history
    const hist = this.history.get(sloName) || [];
    hist.push(sloStatus);
    if (hist.length > this.maxHistoryLength) {
      hist.shift();
    }
    this.history.set(sloName, hist);

    return sloStatus;
  }

  /**
   * Get all SLO statuses
   */
  getAllSLOStatuses(): Map<string, SLOStatus> {
    const statuses = new Map<string, SLOStatus>();
    this.slos.forEach((_, sloName) => {
      const status = this.getSLOStatus(sloName);
      if (status) {
        statuses.set(sloName, status);
      }
    });
    return statuses;
  }

  /**
   * Get SLO history
   */
  getSLOHistory(sloName: string): SLOStatus[] {
    return this.history.get(sloName) || [];
  }

  /**
   * Get error budget summary
   */
  getErrorBudgetSummary(): {
    sloName: string;
    remaining: number;
    daysUntilExhausted: number;
    status: string;
  }[] {
    const summary: {
      sloName: string;
      remaining: number;
      daysUntilExhausted: number;
      status: string;
    }[] = [];

    this.slos.forEach((_, sloName) => {
      const status = this.getSLOStatus(sloName);
      if (status) {
        summary.push({
          sloName,
          remaining: status.errorBudgetRemaining,
          daysUntilExhausted: status.daysUntilBudgetExhausted,
          status: status.status,
        });
      }
    });

    return summary.sort((a, b) => a.daysUntilExhausted - b.daysUntilExhausted);
  }

  /**
   * Identify at-risk SLOs
   */
  getAtRiskSLOs(): SLOStatus[] {
    const atRisk: SLOStatus[] = [];
    this.slos.forEach((_, sloName) => {
      const status = this.getSLOStatus(sloName);
      if (status && (status.status === 'warning' || status.status === 'critical')) {
        atRisk.push(status);
      }
    });
    return atRisk;
  }

  /**
   * Get stats
   */
  getStats(): {
    totalSLOs: number;
    healthySLOs: number;
    warningSLOs: number;
    criticalSLOs: number;
    avgCompliancePercentage: number;
  } {
    const statuses = this.getAllSLOStatuses();
    let healthyCount = 0;
    let warningCount = 0;
    let criticalCount = 0;
    let totalPercentage = 0;

    statuses.forEach((status) => {
      if (status.status === 'healthy') {
        healthyCount++;
      } else if (status.status === 'warning') {
        warningCount++;
      } else {
        criticalCount++;
      }
      totalPercentage += status.overallPercentage;
    });

    return {
      totalSLOs: statuses.size,
      healthySLOs: healthyCount,
      warningSLOs: warningCount,
      criticalSLOs: criticalCount,
      avgCompliancePercentage: statuses.size > 0 ? totalPercentage / statuses.size : 0,
    };
  }
}

export default SLOTracker;
