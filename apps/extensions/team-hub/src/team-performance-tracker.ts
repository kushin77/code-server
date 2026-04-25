/**
 * @fileoverview Team Performance Tracker for Advanced Team Coordination
 * 
 * GOV-002 COMPLIANCE
 * - Deterministic: Metrics calculated using consistent formulas
 * - Audited: All metrics tracked with timestamps and source data
 * - Immutable: Metrics published to Kafka as immutable records
 * - Immutable Records: Performance history available for audit
 * 
 * ARCHITECTURE
 * Performance Tracker provides:
 * 1. Individual metrics (velocity, quality, reliability)
 * 2. Team metrics (throughput, cycle time, predictability)
 * 3. Trend analysis (improvement/degradation over time)
 * 4. Comparative analysis (team member performance comparison)
 * 5. Predictive insights (expected future performance)
 * 
 * METRICS
 * Individual:
 * - Velocity: Story points completed per sprint
 * - Quality: Bug escape rate, code review comments
 * - Reliability: On-time completion rate, SLA adherence
 * - Collaboration: Pair programming hours, mentoring time
 * 
 * Team:
 * - Throughput: Total points delivered per sprint
 * - Cycle time: Average time from task start to completion
 * - Predictability: Variance in estimates vs actual
 * - Efficiency: Points delivered per person-hour
 * 
 * @author Autonomous Infrastructure
 * @version 1.0.0
 * @date 2026-04-26
 * 
 * REFERENCES
 * - P2 #1539 Phase 7: Advanced Team Coordination
 * - GOV-002 Governance Standards
 * - ml-task-router.ts, capacity-forecaster.ts, workload-balancer.ts
 */

import { v4 as uuidv4 } from 'uuid';

/**
 * Individual team member performance metrics
 */
export interface IndividualMetrics {
  memberId: string;
  memberName: string;
  period: { startDate: Date; endDate: Date };
  
  // Core metrics
  velocity: number;           // story points/sprint
  qualityScore: number;       // 0-100
  reliabilityScore: number;   // on-time completion %
  collaborationScore: number; // 0-100
  
  // Detailed metrics
  tasksCompleted: number;
  tasksOnTime: number;
  averageCycleTime: number;   // hours
  bugEscapeRate: number;      // % of tasks with bugs
  codeReviewComments: number;
  
  // Trends
  velocityTrend: number;      // % change from previous period
  qualityTrend: number;       // % change
  
  // Audit
  metricsId: string;
  recordedAt: Date;
}

/**
 * Team-wide performance metrics
 */
export interface TeamMetrics {
  teamId: string;
  teamName: string;
  teamSize: number;
  period: { startDate: Date; endDate: Date };
  
  // Aggregate metrics
  totalVelocity: number;       // total story points
  averageVelocity: number;     // per person
  teamQualityScore: number;
  teamReliability: number;
  teamEfficiency: number;      // points per person-hour
  
  // Team-level metrics
  throughput: number;          // points delivered
  averageCycleTime: number;
  predictability: number;      // how accurate estimates are (0-100)
  
  // Distribution
  velocityDistribution: {
    memberId: string;
    velocity: number;
  }[];
  
  // Trends
  velocityTrend: number;
  qualityTrend: number;
  efficiencyTrend: number;
  
  // Audit
  metricsId: string;
  recordedAt: Date;
}

/**
 * Performance insight from historical data
 */
export interface PerformanceInsight {
  insightId: string;
  type: 'trend' | 'outlier' | 'improvement' | 'risk';
  severity: 'low' | 'medium' | 'high';
  title: string;
  description: string;
  affectedMembers?: string[];
  recommendation?: string;
  supportingData?: any;
}

/**
 * Team Performance Tracker
 */
export class TeamPerformanceTracker {
  private individualHistory: IndividualMetrics[] = [];
  private teamHistory: TeamMetrics[] = [];
  private insights: PerformanceInsight[] = [];
  private kafkaProducer: any;

  constructor(kafkaProducer: any) {
    this.kafkaProducer = kafkaProducer;
  }

  /**
   * Record individual performance metrics
   */
  async recordIndividualMetrics(metrics: Omit<IndividualMetrics, 'metricsId' | 'recordedAt'>): Promise<IndividualMetrics> {
    const fullMetrics: IndividualMetrics = {
      ...metrics,
      metricsId: uuidv4(),
      recordedAt: new Date(),
    };

    this.individualHistory.push(fullMetrics);
    await this.publishMetrics(fullMetrics, 'team.performance.individual');

    return fullMetrics;
  }

  /**
   * Record team performance metrics
   */
  async recordTeamMetrics(metrics: Omit<TeamMetrics, 'metricsId' | 'recordedAt'>): Promise<TeamMetrics> {
    const fullMetrics: TeamMetrics = {
      ...metrics,
      metricsId: uuidv4(),
      recordedAt: new Date(),
    };

    this.teamHistory.push(fullMetrics);
    await this.publishMetrics(fullMetrics, 'team.performance.aggregate');

    // Analyze for insights
    await this.analyzeForInsights();

    return fullMetrics;
  }

  /**
   * Get individual performance summary
   */
  getIndividualSummary(memberId: string, sprints: number = 4): any {
    const recent = this.individualHistory
      .filter(m => m.memberId === memberId)
      .slice(-sprints);

    if (recent.length === 0) return null;

    const latest = recent[recent.length - 1];
    const previous = recent.length > 1 ? recent[recent.length - 2] : null;

    return {
      memberId,
      current: latest,
      trend: previous ? {
        velocityChange: latest.velocity - previous.velocity,
        qualityChange: latest.qualityScore - previous.qualityScore,
        reliabilityChange: latest.reliabilityScore - previous.reliabilityScore,
      } : null,
      historicalAverage: {
        velocity: recent.reduce((sum, m) => sum + m.velocity, 0) / recent.length,
        quality: recent.reduce((sum, m) => sum + m.qualityScore, 0) / recent.length,
        reliability: recent.reduce((sum, m) => sum + m.reliabilityScore, 0) / recent.length,
      },
    };
  }

  /**
   * Get team performance summary
   */
  getTeamSummary(teamId: string, periods: number = 4): any {
    const recent = this.teamHistory
      .filter(m => m.teamId === teamId)
      .slice(-periods);

    if (recent.length === 0) return null;

    const latest = recent[recent.length - 1];
    const previous = recent.length > 1 ? recent[recent.length - 2] : null;

    return {
      teamId,
      current: latest,
      trend: previous ? {
        velocityChange: latest.totalVelocity - previous.totalVelocity,
        qualityChange: latest.teamQualityScore - previous.teamQualityScore,
        efficiencyChange: latest.teamEfficiency - previous.teamEfficiency,
      } : null,
      historicalAverage: {
        velocity: recent.reduce((sum, m) => sum + m.totalVelocity, 0) / recent.length,
        quality: recent.reduce((sum, m) => sum + m.teamQualityScore, 0) / recent.length,
        efficiency: recent.reduce((sum, m) => sum + m.teamEfficiency, 0) / recent.length,
      },
      distribution: latest.velocityDistribution,
    };
  }

  /**
   * Analyze metrics for insights
   */
  private async analyzeForInsights(): Promise<void> {
    const newInsights: PerformanceInsight[] = [];

    // Get latest team metrics
    if (this.teamHistory.length > 0) {
      const latest = this.teamHistory[this.teamHistory.length - 1];

      // Check for velocity decline
      if (this.teamHistory.length > 1) {
        const previous = this.teamHistory[this.teamHistory.length - 2];
        if (latest.totalVelocity < previous.totalVelocity * 0.8) {
          newInsights.push({
            insightId: uuidv4(),
            type: 'trend',
            severity: 'medium',
            title: 'Velocity Declining',
            description: `Team velocity dropped ${((1 - latest.totalVelocity / previous.totalVelocity) * 100).toFixed(1)}% this sprint`,
            recommendation: 'Review task complexity estimates or team capacity allocation',
            supportingData: {
              lastSprint: previous.totalVelocity,
              thisSprint: latest.totalVelocity,
            },
          });
        }
      }

      // Check for quality issues
      if (latest.teamQualityScore < 85) {
        newInsights.push({
          insightId: uuidv4(),
          type: 'risk',
          severity: 'high',
          title: 'Quality Score Below Target',
          description: `Team quality score is ${latest.teamQualityScore}, target is 90+`,
          recommendation: 'Increase code review scrutiny and invest in testing infrastructure',
          supportingData: {
            currentScore: latest.teamQualityScore,
            bugEscapeRate: latest.teamEfficiency,
          },
        });
      }

      // Check for unpredictability
      if (latest.predictability < 0.7) {
        newInsights.push({
          insightId: uuidv4(),
          type: 'trend',
          severity: 'medium',
          title: 'Low Estimation Predictability',
          description: `Estimates are off by more than 30% on average`,
          recommendation: 'Conduct estimation workshop and refine story point scale',
          supportingData: {
            predictability: latest.predictability,
          },
        });
      }
    }

    // Check individual outliers
    if (this.individualHistory.length > 0) {
      const recent = this.individualHistory.slice(-this.individualHistory.length);
      const avgVelocity = recent.reduce((sum, m) => sum + m.velocity, 0) / recent.length;
      
      const highPerformers = recent.filter(m => m.velocity > avgVelocity * 1.3);
      const lowPerformers = recent.filter(m => m.velocity < avgVelocity * 0.7);

      if (lowPerformers.length > 0) {
        newInsights.push({
          insightId: uuidv4(),
          type: 'outlier',
          severity: 'medium',
          title: 'Team Members Below Average Velocity',
          description: `${lowPerformers.length} team members have velocity significantly below team average`,
          affectedMembers: lowPerformers.map(m => m.memberId),
          recommendation: 'Offer pairing opportunities or additional mentoring to support growth',
        });
      }
    }

    // Publish insights
    for (const insight of newInsights) {
      this.insights.push(insight);
      await this.publishInsight(insight);
    }
  }

  /**
   * Get recent performance insights
   */
  getRecentInsights(limit: number = 10): PerformanceInsight[] {
    return this.insights.slice(-limit);
  }

  /**
   * Get insights by severity
   */
  getInsightsBySeverity(severity: 'low' | 'medium' | 'high'): PerformanceInsight[] {
    return this.insights.filter(i => i.severity === severity);
  }

  /**
   * Compare two team members
   */
  compareMemberPerformance(memberId1: string, memberId2: string, periods: number = 4): any {
    const member1 = this.getIndividualSummary(memberId1, periods);
    const member2 = this.getIndividualSummary(memberId2, periods);

    if (!member1 || !member2) return null;

    return {
      member1: member1.current.memberName,
      member2: member2.current.memberName,
      comparison: {
        velocity: {
          member1: member1.current.velocity,
          member2: member2.current.velocity,
          difference: member1.current.velocity - member2.current.velocity,
        },
        quality: {
          member1: member1.current.qualityScore,
          member2: member2.current.qualityScore,
          difference: member1.current.qualityScore - member2.current.qualityScore,
        },
        reliability: {
          member1: member1.current.reliabilityScore,
          member2: member2.current.reliabilityScore,
          difference: member1.current.reliabilityScore - member2.current.reliabilityScore,
        },
      },
    };
  }

  /**
   * Predict future performance
   */
  predictFuturePerformance(memberId: string, sprintsAhead: number = 2): any {
    const recent = this.individualHistory
      .filter(m => m.memberId === memberId)
      .slice(-8);

    if (recent.length < 2) return null;

    // Simple linear regression
    const velocities = recent.map(m => m.velocity);
    const trend = this.calculateLinearTrend(velocities);

    const predictions = [];
    for (let i = 1; i <= sprintsAhead; i++) {
      predictions.push({
        sprintAhead: i,
        predictedVelocity: Math.max(0, trend.slope * i + trend.intercept),
        confidence: Math.max(0, 100 - (20 * i)), // Decrease confidence further out
      });
    }

    return predictions;
  }

  /**
   * Calculate linear trend from data
   */
  private calculateLinearTrend(values: number[]): { slope: number; intercept: number } {
    const n = values.length;
    const xSum = (n * (n + 1)) / 2;
    const x2Sum = (n * (n + 1) * (2 * n + 1)) / 6;
    const ySum = values.reduce((sum, v) => sum + v, 0);
    const xySum = values.reduce((sum, v, i) => sum + v * (i + 1), 0);

    const slope = (n * xySum - xSum * ySum) / (n * x2Sum - xSum * xSum);
    const intercept = (ySum - slope * xSum) / n;

    return { slope, intercept };
  }

  /**
   * Publish metrics to Kafka
   */
  private async publishMetrics(metrics: any, topic: string): Promise<void> {
    try {
      await this.kafkaProducer.send({
        topic,
        messages: [{
          key: metrics.metricsId,
          value: JSON.stringify(metrics),
          headers: {
            'timestamp': new Date().toISOString(),
            'period': `${metrics.period.startDate.toISOString()}_${metrics.period.endDate.toISOString()}`,
          },
        }],
      });
    } catch (error) {
      console.error(`Failed to publish metrics to ${topic}:`, error);
    }
  }

  /**
   * Publish insight to Kafka
   */
  private async publishInsight(insight: PerformanceInsight): Promise<void> {
    try {
      await this.kafkaProducer.send({
        topic: 'team.performance.insights',
        messages: [{
          key: insight.insightId,
          value: JSON.stringify(insight),
          headers: {
            'type': insight.type,
            'severity': insight.severity,
            'timestamp': new Date().toISOString(),
          },
        }],
      });
    } catch (error) {
      console.error('Failed to publish performance insight:', error);
    }
  }
}
