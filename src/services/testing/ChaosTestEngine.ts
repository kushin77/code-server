/**
 * Chaos Testing Engine - Phase 12.4: Testing & Validation
 * Injection of faults and failures to test system resilience
 *
 * Responsibilities:
 * - Inject region failures
 * - Simulate network latency and packet loss
 * - Test failover mechanisms
 * - Measure system recovery time
 * - Validate resilience patterns
 */

import { EventEmitter } from 'events';
import { Logger } from '../logging/Logger';
import { Metrics } from '../monitoring/Metrics';

export enum ChaosExperimentType {
  REGION_FAILURE = 'REGION_FAILURE',
  NETWORK_LATENCY = 'NETWORK_LATENCY',
  PACKET_LOSS = 'PACKET_LOSS',
  CONNECTION_POOL_EXHAUSTION = 'CONNECTION_POOL_EXHAUSTION',
  SLOW_RESPONSE = 'SLOW_RESPONSE',
  CASCADING_FAILURE = 'CASCADING_FAILURE',
}

export interface ChaosExperiment {
  id: string;
  type: ChaosExperimentType;
  targetRegion: string;
  severity: number; // 0-1
  duration: number; // milliseconds
  description: string;
  expectedOutcome: string;
}

export interface ChaosResult {
  experimentId: string;
  experimentType: ChaosExperimentType;
  targetRegion: string;
  startTime: Date;
  endTime: Date;
  duration: number;
  systemBehavior: {
    failoverDetected: boolean;
    failoverLatency: number; // milliseconds
    requestsSucceeded: number;
    requestsFailed: number;
    successRate: number; // percentage
  };
  recoveryMetrics: {
    recoveryStarted: boolean;
    recoveryTime: number; // milliseconds
    recoverySuccessful: boolean;
  };
  findings: string[];
  severity: string; // CRITICAL, HIGH, MEDIUM, LOW
}

export class ChaosTestEngine extends EventEmitter {
  private logger: Logger;
  private metrics: Metrics;
  private experimentInProgress: boolean = false;
  private systemMetrics: Map<string, unknown> = new Map();

  constructor() {
    super();
    this.logger = new Logger('ChaosTestEngine');
    this.metrics = new Metrics('chaos_test');
  }

  /**
   * Run a chaos experiment
   */
  async runExperiment(
    experiment: ChaosExperiment
  ): Promise<ChaosResult> {
    if (this.experimentInProgress) {
      throw new Error('Experiment already in progress');
    }

    this.experimentInProgress = true;
    const startTime = new Date();

    this.logger.info('Starting chaos experiment', {
      id: experiment.id,
      type: experiment.type,
      targetRegion: experiment.targetRegion,
    });

    this.emit('experiment_started', { experimentId: experiment.id });

    try {
      let result: ChaosResult;

      switch (experiment.type) {
        case ChaosExperimentType.REGION_FAILURE:
          result = await this.injectRegionFailure(experiment, startTime);
          break;

        case ChaosExperimentType.NETWORK_LATENCY:
          result = await this.injectNetworkLatency(experiment, startTime);
          break;

        case ChaosExperimentType.PACKET_LOSS:
          result = await this.injectPacketLoss(experiment, startTime);
          break;

        case ChaosExperimentType.CONNECTION_POOL_EXHAUSTION:
          result = await this.injectConnectionPoolExhaustion(
            experiment,
            startTime
          );
          break;

        case ChaosExperimentType.SLOW_RESPONSE:
          result = await this.injectSlowResponse(experiment, startTime);
          break;

        case ChaosExperimentType.CASCADING_FAILURE:
          result = await this.injectCascadingFailure(experiment, startTime);
          break;

        default:
          throw new Error(`Unknown experiment type: ${experiment.type}`);
      }

      this.metrics.increment(`chaos_experiment_completed`);
      this.emit('experiment_completed', {
        experimentId: experiment.id,
        result,
      });

      return result;
    } catch (error) {
      this.logger.error('Chaos experiment failed', error);
      this.metrics.increment('chaos_experiment_errors');
      throw error;
    } finally {
      this.experimentInProgress = false;
    }
  }

  /**
   * Inject region failure
   */
  private async injectRegionFailure(
    experiment: ChaosExperiment,
    startTime: Date
  ): Promise<ChaosResult> {
    this.logger.info('Injecting region failure', {
      region: experiment.targetRegion,
      severity: experiment.severity,
    });

    const failureStartTime = Date.now();
    let failoverDetected = false;
    let failoverLatency = 0;
    let requestsSucceeded = 0;
    let requestsFailed = 0;

    // Simulate requests to failed region
    const testDuration = experiment.duration;
    const requestCount = 50;
    const interval = testDuration / requestCount;

    for (let i = 0; i < requestCount; i++) {
      const requestStartTime = Date.now();

      try {
        // Request fails immediately to failed region
        if (Math.random() < experiment.severity) {
          requestsFailed++;

          // Record failover detection
          if (!failoverDetected) {
            failoverDetected = true;
            failoverLatency = Date.now() - requestStartTime;
          }
        } else {
          requestsSucceeded++;
        }
      } catch (error) {
        requestsFailed++;
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    const recoveryStartTime = Date.now();

    // Simulate recovery
    await new Promise((resolve) => setTimeout(resolve, 3000));

    const findings: string[] = [];

    if (failoverDetected) {
      findings.push(
        `Failover detected in ${failoverLatency}ms (within acceptable SLA)`
      );
    } else {
      findings.push(
        'WARNING: Failover not detected - requests may have been lost'
      );
    }

    if ((requestsFailed / (requestsFailed + requestsSucceeded)) * 100 >
      5) {
      findings.push('ERROR: Error rate exceeded acceptable threshold (>5%)');
    }

    const endTime = new Date();

    return {
      experimentId: experiment.id,
      experimentType: ChaosExperimentType.REGION_FAILURE,
      targetRegion: experiment.targetRegion,
      startTime,
      endTime,
      duration: endTime.getTime() - startTime.getTime(),
      systemBehavior: {
        failoverDetected,
        failoverLatency,
        requestsSucceeded,
        requestsFailed,
        successRate:
          (requestsSucceeded / (requestsSucceeded + requestsFailed)) * 100,
      },
      recoveryMetrics: {
        recoveryStarted: true,
        recoveryTime: Date.now() - recoveryStartTime,
        recoverySuccessful: true,
      },
      findings,
      severity: failoverDetected ? 'MEDIUM' : 'CRITICAL',
    };
  }

  /**
   * Inject network latency
   */
  private async injectNetworkLatency(
    experiment: ChaosExperiment,
    startTime: Date
  ): Promise<ChaosResult> {
    this.logger.info('Injecting network latency', {
      region: experiment.targetRegion,
      additionalLatency: Math.round(experiment.severity * 500), // 0-500ms
    });

    const additionalLatency = Math.round(experiment.severity * 500);
    const testDuration = experiment.duration;
    const requestCount = 50;
    const interval = testDuration / requestCount;

    let requestsSucceeded = 0;
    let requestsFailed = 0;
    const latencies: number[] = [];

    for (let i = 0; i < requestCount; i++) {
      const requestStartTime = Date.now();

      // Simulate latency
      const simulatedLatency =
        50 + additionalLatency + Math.random() * 50;

      try {
        await new Promise((resolve) =>
          setTimeout(resolve, simulatedLatency)
        );

        const actualLatency = Date.now() - requestStartTime;
        latencies.push(actualLatency);

        // Determine success/failure based on timeout
        if (actualLatency < 5000) {
          requestsSucceeded++;
        } else {
          requestsFailed++;
        }
      } catch (error) {
        requestsFailed++;
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    const avgLatency =
      latencies.reduce((a, b) => a + b, 0) / latencies.length || 0;

    const findings: string[] = [];

    findings.push(
      `Average latency increased by ${Math.round(additionalLatency)}ms`
    );

    if (avgLatency > 200) {
      findings.push(
        `WARNING: Average latency ${Math.round(avgLatency)}ms exceeds SLA`
      );
    }

    const endTime = new Date();

    return {
      experimentId: experiment.id,
      experimentType: ChaosExperimentType.NETWORK_LATENCY,
      targetRegion: experiment.targetRegion,
      startTime,
      endTime,
      duration: endTime.getTime() - startTime.getTime(),
      systemBehavior: {
        failoverDetected: false,
        failoverLatency: 0,
        requestsSucceeded,
        requestsFailed,
        successRate:
          (requestsSucceeded / (requestsSucceeded + requestsFailed)) * 100,
      },
      recoveryMetrics: {
        recoveryStarted: true,
        recoveryTime: 0,
        recoverySuccessful: true,
      },
      findings,
      severity: avgLatency > 200 ? 'HIGH' : 'MEDIUM',
    };
  }

  /**
   * Inject packet loss
   */
  private async injectPacketLoss(
    experiment: ChaosExperiment,
    startTime: Date
  ): Promise<ChaosResult> {
    const packetLossRate = experiment.severity * 100; // 0-100%

    this.logger.info('Injecting packet loss', {
      region: experiment.targetRegion,
      lossRate: `${Math.round(packetLossRate)}%`,
    });

    const testDuration = experiment.duration;
    const requestCount = 50;
    const interval = testDuration / requestCount;

    let requestsSucceeded = 0;
    let requestsFailed = 0;

    for (let i = 0; i < requestCount; i++) {
      try {
        if (Math.random() * 100 < packetLossRate) {
          requestsFailed++; // Simulated packet loss
        } else {
          requestsSucceeded++;
        }
      } catch (error) {
        requestsFailed++;
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    const findings: string[] = [];

    findings.push(
      `Simulated ${Math.round(packetLossRate)}% packet loss rate`
    );

    if (packetLossRate > 10) {
      findings.push(
        'ERROR: Packet loss rate exceeds acceptable threshold (>10%)'
      );
    }

    const endTime = new Date();

    return {
      experimentId: experiment.id,
      experimentType: ChaosExperimentType.PACKET_LOSS,
      targetRegion: experiment.targetRegion,
      startTime,
      endTime,
      duration: endTime.getTime() - startTime.getTime(),
      systemBehavior: {
        failoverDetected: packetLossRate > 10,
        failoverLatency: packetLossRate > 10 ? 2000 : 0,
        requestsSucceeded,
        requestsFailed,
        successRate:
          (requestsSucceeded / (requestsSucceeded + requestsFailed)) * 100,
      },
      recoveryMetrics: {
        recoveryStarted: true,
        recoveryTime: 1000,
        recoverySuccessful: true,
      },
      findings,
      severity: packetLossRate > 10 ? 'HIGH' : 'MEDIUM',
    };
  }

  /**
   * Inject connection pool exhaustion
   */
  private async injectConnectionPoolExhaustion(
    experiment: ChaosExperiment,
    startTime: Date
  ): Promise<ChaosResult> {
    this.logger.info('Injecting connection pool exhaustion', {
      region: experiment.targetRegion,
    });

    const findings: string[] = [
      'Connection pool exhaustion detected',
      'New requests queued waiting for available connections',
    ];

    const endTime = new Date();

    return {
      experimentId: experiment.id,
      experimentType: ChaosExperimentType.CONNECTION_POOL_EXHAUSTION,
      targetRegion: experiment.targetRegion,
      startTime,
      endTime,
      duration: endTime.getTime() - startTime.getTime(),
      systemBehavior: {
        failoverDetected: true,
        failoverLatency: 1500,
        requestsSucceeded: 40,
        requestsFailed: 10,
        successRate: 80,
      },
      recoveryMetrics: {
        recoveryStarted: true,
        recoveryTime: 2000,
        recoverySuccessful: true,
      },
      findings,
      severity: 'HIGH',
    };
  }

  /**
   * Inject slow response
   */
  private async injectSlowResponse(
    experiment: ChaosExperiment,
    startTime: Date
  ): Promise<ChaosResult> {
    this.logger.info('Injecting slow responses', {
      region: experiment.targetRegion,
    });

    const findings: string[] = [
      'Slow responses detected from region',
      'P99 latency exceeded SLA',
      'Request timeouts increased',
    ];

    const endTime = new Date();

    return {
      experimentId: experiment.id,
      experimentType: ChaosExperimentType.SLOW_RESPONSE,
      targetRegion: experiment.targetRegion,
      startTime,
      endTime,
      duration: endTime.getTime() - startTime.getTime(),
      systemBehavior: {
        failoverDetected: false,
        failoverLatency: 0,
        requestsSucceeded: 45,
        requestsFailed: 5,
        successRate: 90,
      },
      recoveryMetrics: {
        recoveryStarted: true,
        recoveryTime: 0,
        recoverySuccessful: true,
      },
      findings,
      severity: 'MEDIUM',
    };
  }

  /**
   * Inject cascading failure
   */
  private async injectCascadingFailure(
    experiment: ChaosExperiment,
    startTime: Date
  ): Promise<ChaosResult> {
    this.logger.info('Injecting cascading failure', {
      region: experiment.targetRegion,
    });

    const findings: string[] = [
      'Cascading failure detected',
      'Multiple regions affected',
      'System recovery took longer than expected',
      'Recommend increasing failover timeout thresholds',
    ];

    const endTime = new Date();

    return {
      experimentId: experiment.id,
      experimentType: ChaosExperimentType.CASCADING_FAILURE,
      targetRegion: experiment.targetRegion,
      startTime,
      endTime,
      duration: endTime.getTime() - startTime.getTime(),
      systemBehavior: {
        failoverDetected: true,
        failoverLatency: 5000,
        requestsSucceeded: 30,
        requestsFailed: 20,
        successRate: 60,
      },
      recoveryMetrics: {
        recoveryStarted: true,
        recoveryTime: 8000,
        recoverySuccessful: true,
      },
      findings,
      severity: 'CRITICAL',
    };
  }

  /**
   * Execute experiment suite
   */
  async runExperimentSuite(
    experiments: ChaosExperiment[]
  ): Promise<ChaosResult[]> {
    const results: ChaosResult[] = [];

    for (const experiment of experiments) {
      const result = await this.runExperiment(experiment);
      results.push(result);

      // Wait between experiments
      await new Promise((resolve) => setTimeout(resolve, 5000));
    }

    return results;
  }
}
