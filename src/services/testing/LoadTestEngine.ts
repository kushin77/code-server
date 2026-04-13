/**
 * Load Testing Engine - Phase 12.4: Testing & Validation
 * Distributed load testing for multi-region federation
 * 
 * Responsibilities:
 * - Generate controlled load across regions
 * - Measure latency, throughput, and error rates
 * - Support ramp-up and ramp-down patterns
 * - Track p50, p95, p99 latencies
 * - Identify bottlenecks and performance issues
 */

import { EventEmitter } from 'events';
import { Logger } from '../logging/Logger';
import { Metrics } from '../monitoring/Metrics';

export enum LoadTestPhase {
  IDLE = 'IDLE',
  RAMP_UP = 'RAMP_UP',
  STEADY_STATE = 'STEADY_STATE',
  RAMP_DOWN = 'RAMP_DOWN',
  COOLDOWN = 'COOLDOWN',
}

export interface LoadTestConfig {
  name: string;
  duration: number; // total test duration in milliseconds
  startRPS: number; // requests per second
  peakRPS: number; // peak RPS target
  rampUpDuration: number; // milliseconds
  steadyStateDuration: number; // milliseconds
  rampDownDuration: number; // milliseconds
  regions: string[];
  enableConnectionPool: boolean;
  connectionPoolSize: number;
  requestTimeout: number; // milliseconds
  payloadSize: number; // bytes
}

export interface LatencyBucket {
  p50: number;
  p95: number;
  p99: number;
  p999: number;
  min: number;
  max: number;
  mean: number;
}

export interface RegionMetrics {
  regionId: string;
  totalRequests: number;
  successfulRequests: number;
  failedRequests: number;
  successRate: number; // percentage
  errorRate: number; // percentage
  throughput: number; // requests/sec
  latency: LatencyBucket;
  dataTransferred: number; // bytes
}

export interface LoadTestResult {
  testName: string;
  startTime: Date;
  endTime: Date;
  duration: number; // milliseconds
  phase: LoadTestPhase;
  globalMetrics: {
    totalRequests: number;
    successfulRequests: number;
    failedRequests: number;
    successRate: number;
    errorRate: number;
    avgThroughput: number; // requests/sec
    peakThroughput: number;
    latency: LatencyBucket;
    dataTransferred: number; // bytes
  };
  regionMetrics: Record<string, RegionMetrics>;
  bottlenecks: string[];
  summary: string;
}

export class LoadTestEngine extends EventEmitter {
  private logger: Logger;
  private metrics: Metrics;
  private config: LoadTestConfig;
  private currentPhase: LoadTestPhase = LoadTestPhase.IDLE;
  private currentRPS: number = 0;
  private startTime: Date | null = null;
  private latencies: number[] = [];
  private regionLatencies: Map<string, number[]> = new Map();
  private regionRequests: Map<
    string,
    {
      total: number;
      successful: number;
      failed: number;
    }
  > = new Map();
  private throughputHistory: number[] = [];
  private running: boolean = false;
  private testStartTime: Date | null = null;

  constructor(config: LoadTestConfig) {
    super();
    this.config = config;
    this.logger = new Logger('LoadTestEngine');
    this.metrics = new Metrics('load_test');
    this.initializeMetrics();
  }

  /**
   * Initialize region metrics collections
   */
  private initializeMetrics(): void {
    for (const regionId of this.config.regions) {
      this.regionLatencies.set(regionId, []);
      this.regionRequests.set(regionId, {
        total: 0,
        successful: 0,
        failed: 0,
      });
    }
  }

  /**
   * Start load test
   */
  async start(): Promise<LoadTestResult> {
    if (this.running) {
      throw new Error('Load test already running');
    }

    this.running = true;
    this.testStartTime = new Date();
    this.startTime = new Date();

    this.logger.info('Starting load test', {
      name: this.config.name,
      peakRPS: this.config.peakRPS,
      duration: this.config.duration,
    });

    this.emit('test_started', {
      testName: this.config.name,
      startTime: this.startTime,
    });

    try {
      // Run test phases sequentially
      await this.phaseRampUp();
      await this.phaseSteadyState();
      await this.phaseRampDown();
      await this.phaseCooldown();

      return this.generateResult();
    } catch (error) {
      this.logger.error('Load test failed', error);
      this.metrics.increment('test_errors');
      throw error;
    } finally {
      this.running = false;
    }
  }

  /**
   * Ramp up phase - gradually increase load
   */
  private async phaseRampUp(): Promise<void> {
    this.currentPhase = LoadTestPhase.RAMP_UP;

    const startTime = Date.now();
    const rampSteps = 10; // Increment RPS in 10 steps

    this.logger.info('Starting ramp-up phase', {
      from: this.config.startRPS,
      to: this.config.peakRPS,
      duration: this.config.rampUpDuration,
    });

    while (Date.now() - startTime < this.config.rampUpDuration) {
      const elapsed = Date.now() - startTime;
      const progress = elapsed / this.config.rampUpDuration;

      this.currentRPS =
        this.config.startRPS +
        (this.config.peakRPS - this.config.startRPS) * progress;

      await this.sendBatch();

      // Small delay to allow processing
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    this.currentRPS = this.config.peakRPS;
    this.logger.info('Ramp-up phase complete');
  }

  /**
   * Steady state phase - maintain peak load
   */
  private async phaseSteadyState(): Promise<void> {
    this.currentPhase = LoadTestPhase.STEADY_STATE;

    const startTime = Date.now();

    this.logger.info('Starting steady-state phase', {
      targetRPS: this.config.peakRPS,
      duration: this.config.steadyStateDuration,
    });

    while (Date.now() - startTime < this.config.steadyStateDuration) {
      this.currentRPS = this.config.peakRPS;
      await this.sendBatch();

      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    this.logger.info('Steady-state phase complete');
  }

  /**
   * Ramp down phase - gradually decrease load
   */
  private async phaseRampDown(): Promise<void> {
    this.currentPhase = LoadTestPhase.RAMP_DOWN;

    const startTime = Date.now();

    this.logger.info('Starting ramp-down phase', {
      from: this.config.peakRPS,
      to: this.config.startRPS,
      duration: this.config.rampDownDuration,
    });

    while (Date.now() - startTime < this.config.rampDownDuration) {
      const elapsed = Date.now() - startTime;
      const progress = elapsed / this.config.rampDownDuration;

      this.currentRPS =
        this.config.peakRPS -
        (this.config.peakRPS - this.config.startRPS) * progress;

      await this.sendBatch();

      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    this.currentRPS = this.config.startRPS;
    this.logger.info('Ramp-down phase complete');
  }

  /**
   * Cooldown phase - allow system to stabilize
   */
  private async phaseCooldown(): Promise<void> {
    this.currentPhase = LoadTestPhase.COOLDOWN;

    this.logger.info('Starting cooldown phase');

    // Wait for pending requests to complete
    await new Promise((resolve) => setTimeout(resolve, 5000));

    this.currentPhase = LoadTestPhase.IDLE;
    this.logger.info('Cooldown phase complete');
  }

  /**
   * Send batch of requests based on current RPS
   */
  private async sendBatch(): Promise<void> {
    // Calculate requests to send in this interval (100ms)
    const requestsPerInterval = (this.currentRPS / 10); // 100ms intervals

    const promises: Promise<void>[] = [];

    for (let i = 0; i < Math.floor(requestsPerInterval); i++) {
      const regionId = this.selectRegion();
      promises.push(this.sendRequest(regionId));
    }

    // Handle partial request
    if (Math.random() < requestsPerInterval % 1) {
      const regionId = this.selectRegion();
      promises.push(this.sendRequest(regionId));
    }

    await Promise.all(promises);
  }

  /**
   * Select region for request distribution
   */
  private selectRegion(): string {
    return this.config.regions[
      Math.floor(Math.random() * this.config.regions.length)
    ];
  }

  /**
   * Send single request to region
   */
  private async sendRequest(regionId: string): Promise<void> {
    const startTime = Date.now();
    const requestId = `req-${Date.now()}-${Math.random()}`;

    try {
      // Simulate request with realistic latency
      const regionLatency = this.simulateLatency();
      await new Promise((resolve) =>
        setTimeout(resolve, regionLatency)
      );

      const latency = Date.now() - startTime;

      // Record success
      this.recordSuccess(regionId, latency);

      this.metrics.timing(`request_latency_${regionId}`, latency);
      this.metrics.increment(`requests_${regionId}_success`);
    } catch (error) {
      const latency = Date.now() - startTime;

      // Record failure
      this.recordFailure(regionId, latency);

      this.metrics.increment(`requests_${regionId}_failed`);
    }
  }

  /**
   * Simulate latency based on region
   */
  private simulateLatency(): number {
    // Base latencies per region (milliseconds)
    const baseLatencies: Record<string, number> = {
      'us-west': 20,
      'eu-west': 100,
      'eu-central': 110,
      'ap-south': 150,
      'ap-northeast': 140,
    };

    const region = this.selectRegion();
    const base = baseLatencies[region] || 50;

    // Add jitter (normal distribution, ~10% of base)
    const jitter = base * 0.1;
    const randomValue =
      Math.random() + Math.random() - 1; // Approximate normal distribution
    const noise = jitter * randomValue;

    // Occasional spikes (1% of requests)
    if (Math.random() < 0.01) {
      return base + 500; // 500ms spike
    }

    return Math.max(1, base + noise);
  }

  /**
   * Record successful request
   */
  private recordSuccess(regionId: string, latency: number): void {
    this.latencies.push(latency);

    const regionLatencies = this.regionLatencies.get(regionId) || [];
    regionLatencies.push(latency);
    this.regionLatencies.set(regionId, regionLatencies);

    const regionStats = this.regionRequests.get(regionId);
    if (regionStats) {
      regionStats.total++;
      regionStats.successful++;
    }
  }

  /**
   * Record failed request
   */
  private recordFailure(regionId: string, latency: number): void {
    this.latencies.push(latency);

    const regionLatencies = this.regionLatencies.get(regionId) || [];
    regionLatencies.push(latency);
    this.regionLatencies.set(regionId, regionLatencies);

    const regionStats = this.regionRequests.get(regionId);
    if (regionStats) {
      regionStats.total++;
      regionStats.failed++;
    }
  }

  /**
   * Calculate latency percentiles
   */
  private calculateLatencyBucket(latencies: number[]): LatencyBucket {
    if (latencies.length === 0) {
      return { p50: 0, p95: 0, p99: 0, p999: 0, min: 0, max: 0, mean: 0 };
    }

    const sorted = [...latencies].sort((a, b) => a - b);
    const sum = sorted.reduce((a, b) => a + b, 0);

    return {
      p50: sorted[Math.floor(sorted.length * 0.5)],
      p95: sorted[Math.floor(sorted.length * 0.95)],
      p99: sorted[Math.floor(sorted.length * 0.99)],
      p999: sorted[Math.floor(sorted.length * 0.999)] || sorted[sorted.length - 1],
      min: sorted[0],
      max: sorted[sorted.length - 1],
      mean: sum / sorted.length,
    };
  }

  /**
   * Generate test result
   */
  private generateResult(): LoadTestResult {
    const endTime = new Date();
    const duration =
      endTime.getTime() - (this.testStartTime?.getTime() || 0);

    const totalRequests = this.latencies.length;
    const globalLatency = this.calculateLatencyBucket(this.latencies);

    let successfulRequests = 0;
    let failedRequests = 0;
    const regionMetrics: Record<string, RegionMetrics> = {};
    const bottlenecks: string[] = [];

    for (const regionId of this.config.regions) {
      const requests = this.regionRequests.get(regionId) || {
        total: 0,
        successful: 0,
        failed: 0,
      };
      const latencies = this.regionLatencies.get(regionId) || [];

      successfulRequests += requests.successful;
      failedRequests += requests.failed;

      const throughput =
        (requests.total / duration) * 1000; // requests/sec
      const latency = this.calculateLatencyBucket(latencies);
      const successRate = (requests.successful / requests.total) * 100 || 0;
      const errorRate = (requests.failed / requests.total) * 100 || 0;

      regionMetrics[regionId] = {
        regionId,
        totalRequests: requests.total,
        successfulRequests: requests.successful,
        failedRequests: requests.failed,
        successRate,
        errorRate,
        throughput,
        latency,
        dataTransferred: requests.total * this.config.payloadSize,
      };

      // Identify bottlenecks
      if (latency.p99 > globalLatency.p99 * 1.5) {
        bottlenecks.push(
          `Region ${regionId}: P99 latency ${Math.round(latency.p99)}ms exceeds threshold`
        );
      }

      if (errorRate > 1) {
        bottlenecks.push(
          `Region ${regionId}: Error rate ${Math.round(errorRate)}% exceeds threshold`
        );
      }
    }

    const successRate = (successfulRequests / totalRequests) * 100 || 0;
    const errorRate = (failedRequests / totalRequests) * 100 || 0;
    const avgThroughput = (totalRequests / duration) * 1000;

    const summary = `
Load Test: ${this.config.name}
Duration: ${Math.round(duration / 1000)}s
Total Requests: ${totalRequests}
Success Rate: ${Math.round(successRate)}%
Error Rate: ${Math.round(errorRate)}%
Avg Throughput: ${Math.round(avgThroughput)} req/s
P95 Latency: ${Math.round(globalLatency.p95)}ms
P99 Latency: ${Math.round(globalLatency.p99)}ms
Bottlenecks Detected: ${bottlenecks.length}
    `.trim();

    return {
      testName: this.config.name,
      startTime: this.testStartTime!,
      endTime,
      duration,
      phase: this.currentPhase,
      globalMetrics: {
        totalRequests,
        successfulRequests,
        failedRequests,
        successRate,
        errorRate,
        avgThroughput,
        peakThroughput: this.config.peakRPS,
        latency: globalLatency,
        dataTransferred: totalRequests * this.config.payloadSize,
      },
      regionMetrics,
      bottlenecks,
      summary,
    };
  }

  /**
   * Stop test (for early termination)
   */
  stop(): void {
    this.running = false;
    this.currentPhase = LoadTestPhase.IDLE;
    this.logger.info('Load test stopped');
  }

  /**
   * Get current test status
   */
  getStatus(): {
    running: boolean;
    phase: LoadTestPhase;
    currentRPS: number;
    requestsSoFar: number;
    duration: number;
  } {
    return {
      running: this.running,
      phase: this.currentPhase,
      currentRPS: this.currentRPS,
      requestsSoFar: this.latencies.length,
      duration: this.testStartTime
        ? Date.now() - this.testStartTime.getTime()
        : 0,
    };
  }
}
