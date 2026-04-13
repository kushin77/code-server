/**
 * Phase 15: Canary Deployment Engine
 * Gradual rollout with automatic validation
 */

import { SystemMetrics } from './DeploymentOrchestrator';

export interface CanaryDeployment {
  deploymentId: string;
  currentVersion: string;
  newVersion: string;
  canaryPercentage: number;
  startTime: Date;
  status: 'in-progress' | 'paused' | 'promoted' | 'rolled-back';
  metrics: CanaryMetrics;
}

export interface CanaryMetrics {
  canaryP99Latency: number;
  baselineP99Latency: number;
  canaryErrorRate: number;
  baselineErrorRate: number;
  canaryThroughput: number;
  baselineThroughput: number;
  healthScore: number;
}

export interface HealthEvaluation {
  healthy: boolean;
  healthScore: number;
  violations: string[];
  recommendations: string[];
}

export interface MetricsComparison {
  latencyDelta: number;
  errorRateDelta: number;
  throughputDelta: number;
  overallHealthDelta: number;
  isHealthy: boolean;
}

export interface PromotionResult {
  success: boolean;
  newVersion: string;
  promotionTime: Date;
  trafficPercentage: number;
  duration: number;
}

export interface CanaryStatus {
  deploymentId: string;
  canaryPercentage: number;
  healthScore: number;
  status: 'in-progress' | 'paused' | 'promoted' | 'rolled-back';
  nextProgressionTime?: Date;
}

export interface CanaryReport {
  deploymentId: string;
  currentVersion: string;
  newVersion: string;
  startTime: Date;
  endTime: Date;
  duration: number;
  finalCanaryPercentage: number;
  healthScore: number;
  metricsComparison: MetricsComparison;
  observations: string[];
  recommendations: string[];
}

export class CanaryDeploymentEngine {
  private canaryDeployments: Map<string, CanaryDeployment> = new Map();
  private metricsHistory: Map<string, CanaryMetrics[]> = new Map();
  private healthThresholds = {
    minHealthScore: 75,
    maxLatencyIncrease: 10,  // percentage
    maxErrorRateIncrease: 5,  // percentage
  };

  async startCanaryDeployment(
    currentVersion: string,
    newVersion: string,
    canaryPercentage: number
  ): Promise<CanaryDeployment> {
    const deploymentId = this.generateDeploymentId();
    const deployment: CanaryDeployment = {
      deploymentId,
      currentVersion,
      newVersion,
      canaryPercentage,
      startTime: new Date(),
      status: 'in-progress',
      metrics: await this.initializeCanaryMetrics(),
    };

    this.canaryDeployments.set(deploymentId, deployment);
    this.metricsHistory.set(deploymentId, [deployment.metrics]);

    return deployment;
  }

  async increaseCanaryTraffic(deploymentId: string, newPercentage: number): Promise<void> {
    const deployment = this.canaryDeployments.get(deploymentId);
    if (deployment) {
      deployment.canaryPercentage = newPercentage;
      deployment.metrics = await this.collectCanaryMetrics(deploymentId);
      
      const history = this.metricsHistory.get(deploymentId) || [];
      history.push(deployment.metrics);
      this.metricsHistory.set(deploymentId, history);
    }
  }

  async completeCanaryPromotion(deploymentId: string): Promise<PromotionResult> {
    const deployment = this.canaryDeployments.get(deploymentId);
    if (!deployment) {
      throw new Error(`Canary deployment ${deploymentId} not found`);
    }

    deployment.status = 'promoted';
    const duration = (Date.now() - deployment.startTime.getTime()) / 1000;

    return {
      success: true,
      newVersion: deployment.newVersion,
      promotionTime: new Date(),
      trafficPercentage: 100,
      duration,
    };
  }

  async evaluateCanaryHealth(deploymentId: string): Promise<HealthEvaluation> {
    const deployment = this.canaryDeployments.get(deploymentId);
    if (!deployment) {
      throw new Error(`Canary deployment ${deploymentId} not found`);
    }

    const violations: string[] = [];
    const healthScore = this.calculateHealthScore(deployment.metrics);

    if (healthScore < this.healthThresholds.minHealthScore) {
      violations.push(`Health score ${healthScore} below minimum ${this.healthThresholds.minHealthScore}`);
    }

    const latencyIncrease = ((deployment.metrics.canaryP99Latency - deployment.metrics.baselineP99Latency) / deployment.metrics.baselineP99Latency) * 100;
    if (latencyIncrease > this.healthThresholds.maxLatencyIncrease) {
      violations.push(`Latency increased by ${latencyIncrease.toFixed(2)}%`);
    }

    const errorRateIncrease = ((deployment.metrics.canaryErrorRate - deployment.metrics.baselineErrorRate) / deployment.metrics.baselineErrorRate) * 100;
    if (errorRateIncrease > this.healthThresholds.maxErrorRateIncrease) {
      violations.push(`Error rate increased by ${errorRateIncrease.toFixed(2)}%`);
    }

    return {
      healthy: violations.length === 0,
      healthScore,
      violations,
      recommendations: this.generateHealthRecommendations(violations),
    };
  }

  async compareCanaryMetrics(
    baseline: CanaryMetrics,
    canary: CanaryMetrics
  ): Promise<MetricsComparison> {
    const latencyDelta = canary.canaryP99Latency - baseline.baselineP99Latency;
    const errorRateDelta = canary.canaryErrorRate - baseline.baselineErrorRate;
    const throughputDelta = canary.canaryThroughput - baseline.baselineThroughput;
    const overallHealthDelta = canary.healthScore - baseline.healthScore;

    return {
      latencyDelta,
      errorRateDelta,
      throughputDelta,
      overallHealthDelta,
      isHealthy: latencyDelta <= 10 && errorRateDelta <= 0.5,
    };
  }

  async tryAutoProgressCanary(deploymentId: string): Promise<boolean> {
    const evaluation = await this.evaluateCanaryHealth(deploymentId);
    if (evaluation.healthy) {
      const deployment = this.canaryDeployments.get(deploymentId);
      if (deployment && deployment.canaryPercentage < 100) {
        const nextPercentage = Math.min(100, deployment.canaryPercentage + 25);
        await this.increaseCanaryTraffic(deploymentId, nextPercentage);
        return true;
      }
    }
    return false;
  }

  async abortCanaryDeployment(deploymentId: string): Promise<{ success: boolean; reason: string }> {
    const deployment = this.canaryDeployments.get(deploymentId);
    if (deployment) {
      deployment.status = 'rolled-back';
      return {
        success: true,
        reason: 'Canary deployment aborted',
      };
    }
    return {
      success: false,
      reason: `Canary deployment ${deploymentId} not found`,
    };
  }

  getCanaryStatus(deploymentId: string): CanaryStatus {
    const deployment = this.canaryDeployments.get(deploymentId);
    if (!deployment) {
      throw new Error(`Canary deployment ${deploymentId} not found`);
    }

    return {
      deploymentId,
      canaryPercentage: deployment.canaryPercentage,
      healthScore: deployment.metrics.healthScore,
      status: deployment.status,
      nextProgressionTime: new Date(Date.now() + 300000),
    };
  }

  generateCanaryReport(deploymentId: string): CanaryReport {
    const deployment = this.canaryDeployments.get(deploymentId);
    if (!deployment) {
      throw new Error(`Canary deployment ${deploymentId} not found`);
    }

    const history = this.metricsHistory.get(deploymentId) || [];
    const duration = (Date.now() - deployment.startTime.getTime()) / 1000;

    const comparison: MetricsComparison = {
      latencyDelta: deployment.metrics.canaryP99Latency - deployment.metrics.baselineP99Latency,
      errorRateDelta: deployment.metrics.canaryErrorRate - deployment.metrics.baselineErrorRate,
      throughputDelta: deployment.metrics.canaryThroughput - deployment.metrics.baselineThroughput,
      overallHealthDelta: 0,
      isHealthy: true,
    };

    return {
      deploymentId,
      currentVersion: deployment.currentVersion,
      newVersion: deployment.newVersion,
      startTime: deployment.startTime,
      endTime: new Date(),
      duration,
      finalCanaryPercentage: deployment.canaryPercentage,
      healthScore: deployment.metrics.healthScore,
      metricsComparison: comparison,
      observations: [
        `Canary started with ${history[0].canaryP99Latency}ms latency`,
        `Final health score: ${deployment.metrics.healthScore}`,
        `Deployed version: ${deployment.newVersion}`,
      ],
      recommendations: [
        'Monitor production metrics for 24 hours',
        'Prepare rollback plan',
        'Update runbooks if needed',
      ],
    };
  }

  private async initializeCanaryMetrics(): Promise<CanaryMetrics> {
    return {
      canaryP99Latency: 85,
      baselineP99Latency: 80,
      canaryErrorRate: 0.5,
      baselineErrorRate: 0.4,
      canaryThroughput: 5000,
      baselineThroughput: 5100,
      healthScore: 85,
    };
  }

  private async collectCanaryMetrics(deploymentId: string): Promise<CanaryMetrics> {
    // Simulate metrics collection with slight variation
    const baseMetrics = await this.initializeCanaryMetrics();
    return {
      canaryP99Latency: baseMetrics.canaryP99Latency + (Math.random() - 0.5) * 10,
      baselineP99Latency: baseMetrics.baselineP99Latency,
      canaryErrorRate: baseMetrics.canaryErrorRate + (Math.random() - 0.5) * 0.1,
      baselineErrorRate: baseMetrics.baselineErrorRate,
      canaryThroughput: baseMetrics.canaryThroughput + (Math.random() - 0.5) * 200,
      baselineThroughput: baseMetrics.baselineThroughput,
      healthScore: 85 + Math.random() * 10,
    };
  }

  private calculateHealthScore(metrics: CanaryMetrics): number {
    let score = 100;
    const latencyPenalty = Math.max(0, ((metrics.canaryP99Latency - metrics.baselineP99Latency) / metrics.baselineP99Latency) * 100);
    const errorRatePenalty = Math.max(0, ((metrics.canaryErrorRate - metrics.baselineErrorRate) / metrics.baselineErrorRate) * 100);
    
    score -= latencyPenalty * 0.5;
    score -= errorRatePenalty * 0.5;
    
    return Math.max(0, Math.min(100, score));
  }

  private generateHealthRecommendations(violations: string[]): string[] {
    if (violations.length === 0) return ['Proceed with next canary stage'];
    
    if (violations.some(v => v.includes('Health score'))) {
      return ['Address performance issues before proceeding'];
    }
    if (violations.some(v => v.includes('Latency'))) {
      return ['Optimize query performance', 'Check for resource contention'];
    }
    if (violations.some(v => v.includes('Error rate'))) {
      return ['Debug error sources', 'Review recent code changes'];
    }
    
    return ['Investigate metric violations'];
  }

  private generateDeploymentId(): string {
    return `canary-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }
}
