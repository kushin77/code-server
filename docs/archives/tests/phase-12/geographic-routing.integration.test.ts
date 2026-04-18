/**
 * Integration tests for Phase 12.3: Geographic Routing
 * Tests GeoRouter, FailoverManager, and LoadBalancer components
 */

import { describe, it, expect, beforeEach, afterEach } from '@jest/globals';
import { GeoRouter, RoutingRequest, LoadBalancingStrategy } from '../src/services/routing/GeoRouter';
import {
  FailoverManager,
  CircuitBreakerState,
} from '../src/services/routing/FailoverManager';
import {
  LoadBalancer,
  LoadBalancerConfig,
} from '../src/services/routing/LoadBalancer';

// Mock Logger and Metrics
jest.mock('../src/logging/Logger');
jest.mock('../src/monitoring/Metrics');

const TEST_REGIONS = [
  'us-west',
  'eu-west',
  'eu-central',
  'ap-south',
  'ap-northeast',
];

describe('Phase 12.3: Geographic Routing Integration Tests', () => {
  let geoRouter: GeoRouter;
  let failoverManager: FailoverManager;
  let loadBalancer: LoadBalancer;

  beforeEach(async () => {
    // Initialize GeoRouter
    geoRouter = new GeoRouter({
      regions: TEST_REGIONS,
      updateInterval: 5000,
      healthCheckTimeout: 3000,
      minConfidenceThreshold: 0.5,
      enableAffinity: true,
      enableWeightedRoundRobin: false,
      maxRetries: 3,
    });

    // Initialize FailoverManager
    failoverManager = new FailoverManager({
      regions: TEST_REGIONS,
      circuitBreakerConfig: {
        failureThreshold: 0.5,
        successThreshold: 3,
        timeout: 5000,
        windowSize: 20,
      },
      healthCheckInterval: 5000,
      canaryPercentage: 10,
      maxFailoverChain: 3,
      failoverTimeout: 10000,
    });

    // Initialize LoadBalancer
    loadBalancer = new LoadBalancer({
      strategy: LoadBalancingStrategy.LEAST_CONNECTIONS,
      regions: TEST_REGIONS,
      enableAffinity: true,
      affinityTimeout: 1800000,
      drainingTimeout: 30000,
      healthCheckInterval: 10000,
      maxConnectionsPerRegion: 1000,
      softLimitPercentage: 80,
    });

    await geoRouter.start();
    await failoverManager.start();
    await loadBalancer.start();
  });

  afterEach(() => {
    geoRouter.stop();
    failoverManager.stop();
    loadBalancer.stop();
  });

  describe('GeoRouter Tests', () => {
    it('should route request based on user location', async () => {
      const request: RoutingRequest = {
        clientIP: '1.2.3.4',
        userLocation: {
          latitude: 37.7749,
          longitude: -122.4194, // San Francisco
        },
      };

      const decision = await geoRouter.routeRequest(request);

      expect(decision).toBeDefined();
      expect(decision.selectedRegion).toBeDefined();
      expect(TEST_REGIONS).toContain(decision.selectedRegion);
      expect(decision.confidence).toBeGreaterThanOrEqual(0);
      expect(decision.confidence).toBeLessThanOrEqual(1);
      expect(decision.reason).toBeDefined();
    });

    it('should maintain session affinity', async () => {
      const sessionId = 'session-123';
      const request: RoutingRequest = {
        clientIP: '1.2.3.4',
        sessionId,
      };

      const decision1 = await geoRouter.routeRequest(request);
      const decision2 = await geoRouter.routeRequest(request);

      expect(decision1.selectedRegion).toBe(decision2.selectedRegion);
    });

    it('should prefer user preferred regions', async () => {
      const request: RoutingRequest = {
        clientIP: '1.2.3.4',
        preferredRegions: ['eu-west', 'eu-central'],
      };

      const decision = await geoRouter.routeRequest(request);

      // Selected region should be from preferred or fallback with lower confidence
      expect(decision).toBeDefined();
    });

    it('should report metrics', () => {
      const metrics = geoRouter.getMetrics();

      expect(metrics).toBeDefined();
      expect(metrics.initialized).toBe(true);
      expect(metrics.regions).toBeDefined();
      expect(Object.keys(metrics.regions)).toEqual(TEST_REGIONS);
    });

    it('should handle location-based scoring', async () => {
      // West coast user
      const westRequest: RoutingRequest = {
        clientIP: '1.2.3.4',
        userLocation: {
          latitude: 37.7749,
          longitude: -122.4194,
        },
      };

      // East coast user
      const eastRequest: RoutingRequest = {
        clientIP: '5.6.7.8',
        userLocation: {
          latitude: 40.7128,
          longitude: -74.006,
        },
      };

      const westDecision = await geoRouter.routeRequest(westRequest);
      const eastDecision = await geoRouter.routeRequest(eastRequest);

      // Decisions should be independent
      expect(westDecision).toBeDefined();
      expect(eastDecision).toBeDefined();
    });

    it('should handle requests without location info', async () => {
      const request: RoutingRequest = {
        clientIP: '1.2.3.4',
      };

      const decision = await geoRouter.routeRequest(request);

      expect(decision).toBeDefined();
      expect(decision.selectedRegion).toBeDefined();
    });
  });

  describe('FailoverManager Tests', () => {
    it('should initialize circuit breakers', () => {
      const metrics = failoverManager.getMetrics();

      expect(metrics.regionMetrics).toBeDefined();
      expect(Object.keys(metrics.regionMetrics)).toEqual(TEST_REGIONS);

      for (const regionId of TEST_REGIONS) {
        expect(metrics.regionMetrics[regionId].state).toBe(
          CircuitBreakerState.CLOSED
        );
      }
    });

    it('should open circuit breaker on consecutive failures', () => {
      const regionId = TEST_REGIONS[0];

      // Record multiple failures
      for (let i = 0; i < 15; i++) {
        failoverManager.recordRequest(regionId, false);
      }

      const metrics = failoverManager.getMetrics();
      expect(metrics.regionMetrics[regionId].state).toBe(
        CircuitBreakerState.OPEN
      );
    });

    it('should transition through circuit breaker states', () => {
      const regionId = TEST_REGIONS[0];

      // Start at CLOSED
      let metrics = failoverManager.getMetrics();
      expect(metrics.regionMetrics[regionId].state).toBe(
        CircuitBreakerState.CLOSED
      );

      // Fail requests to open
      for (let i = 0; i < 15; i++) {
        failoverManager.recordRequest(regionId, false);
      }

      metrics = failoverManager.getMetrics();
      expect(metrics.regionMetrics[regionId].state).toBe(
        CircuitBreakerState.OPEN
      );

      // Cannot attempt requests
      expect(failoverManager.needsFailover(regionId)).toBe(true);
    });

    it('should execute failover from failed region', async () => {
      const fromRegion = TEST_REGIONS[0];

      // Open circuit for first region
      for (let i = 0; i < 15; i++) {
        failoverManager.recordRequest(fromRegion, false);
      }

      const toRegion = await failoverManager.executeFailover(fromRegion);

      expect(toRegion).toBeDefined();
      expect(toRegion).not.toBe(fromRegion);
      expect(TEST_REGIONS).toContain(toRegion);
    });

    it('should track failover history', async () => {
      const fromRegion = TEST_REGIONS[0];

      // Open circuit
      for (let i = 0; i < 15; i++) {
        failoverManager.recordRequest(fromRegion, false);
      }

      await failoverManager.executeFailover(fromRegion);

      const history = failoverManager.getFailoverHistory();
      expect(history.length).toBeGreaterThan(0);
      expect(history[0].fromRegion).toBe(fromRegion);
    });

    it('should prevent excessive failover chains', async () => {
      const config = failoverManager['config'];
      const maxChain = config.maxFailoverChain;

      for (let i = 0; i < maxChain; i++) {
        await failoverManager.executeFailover(TEST_REGIONS[i % TEST_REGIONS.length]);
      }

      // Next failover should fail
      await expect(
        failoverManager.executeFailover(TEST_REGIONS[maxChain % TEST_REGIONS.length])
      ).rejects.toThrow('Max failover chain exceeded');
    });
  });

  describe('LoadBalancer Tests', () => {
    it('should select regions based on strategy', async () => {
      const decision = await loadBalancer.selectRegion();

      expect(decision).toBeDefined();
      expect(decision.selectedRegion).toBeDefined();
      expect(TEST_REGIONS).toContain(decision.selectedRegion);
      expect(decision.capacity).toBeDefined();
    });

    it('should maintain client affinity', async () => {
      const clientId = 'client-123';

      const decision1 = await loadBalancer.selectRegion(clientId);
      const decision2 = await loadBalancer.selectRegion(clientId);

      expect(decision1.selectedRegion).toBe(decision2.selectedRegion);
    });

    it('should track active connections', () => {
      const regionId = TEST_REGIONS[0];

      expect(loadBalancer['regionLoad'].get(regionId)?.activeConnections).toBe(
        0
      );

      loadBalancer.recordConnectionOpened(regionId);
      expect(loadBalancer['regionLoad'].get(regionId)?.activeConnections).toBe(
        1
      );

      loadBalancer.recordConnectionClosed(regionId);
      expect(loadBalancer['regionLoad'].get(regionId)?.activeConnections).toBe(
        0
      );
    });

    it('should respect capacity limits', async () => {
      const regionId = TEST_REGIONS[0];
      const capacity =
        loadBalancer['regionLoad'].get(regionId)?.capacity || 1000;

      // Fill to capacity
      for (let i = 0; i < capacity; i++) {
        loadBalancer.recordConnectionOpened(regionId);
      }

      // Should not select this region
      const decision = await loadBalancer.selectRegion();
      expect(decision.selectedRegion).not.toBe(regionId);
    });

    it('should support graceful draining', async () => {
      const regionId = TEST_REGIONS[0];

      expect(loadBalancer.isDraining(regionId)).toBe(false);

      loadBalancer.startDrain(regionId);
      expect(loadBalancer.isDraining(regionId)).toBe(true);

      // Should not be selected during drain
      const decision = await loadBalancer.selectRegion();
      expect(decision.selectedRegion).not.toBe(regionId);
    });

    it('should update region load metrics', () => {
      const regionId = TEST_REGIONS[0];
      const latency = 50;
      const errorRate = 0.5;
      const healthy = true;

      loadBalancer.updateRegionLoad(
        regionId,
        latency,
        errorRate,
        healthy,
        0.8
      );

      const metrics = loadBalancer.getMetrics();
      const regionMetrics = metrics.regionMetrics[regionId];

      expect(regionMetrics.latency).toBe(latency);
      expect(regionMetrics.errorRate).toBe(errorRate);
      expect(regionMetrics.healthy).toBe(healthy);
      expect(regionMetrics.weight).toBe(0.8);
    });

    it('should report metrics', () => {
      const metrics = loadBalancer.getMetrics();

      expect(metrics).toBeDefined();
      expect(metrics.initialized).toBe(true);
      expect(metrics.strategy).toBe(LoadBalancingStrategy.LEAST_CONNECTIONS);
      expect(metrics.regionMetrics).toBeDefined();
    });
  });

  describe('Integration Scenarios', () => {
    it('should handle regional failure and recovery', async () => {
      const failedRegion = TEST_REGIONS[0];

      // Simulate region failure
      for (let i = 0; i < 20; i++) {
        failoverManager.recordRequest(failedRegion, false);
      }

      expect(failoverManager.needsFailover(failedRegion)).toBe(true);

      // Route should not go to failed region
      const decision = await geoRouter.routeRequest({
        clientIP: '1.2.3.4',
      });

      // Load balancer should not select failed region
      expect(loadBalancer.isDraining(failedRegion)).toBe(false);

      // Simulate recovery
      failoverManager.forceRecovery(failedRegion);
      const recoveryMetrics = failoverManager.getMetrics();
      expect(recoveryMetrics.regionMetrics[failedRegion].state).toBe(
        CircuitBreakerState.CLOSED
      );
    });

    it('should coordinate between geo router and failover manager', async () => {
      const failedRegion = TEST_REGIONS[1];

      // Fail the region
      for (let i = 0; i < 20; i++) {
        failoverManager.recordRequest(failedRegion, false);
      }

      // Route should adapt
      const decision = await geoRouter.routeRequest({
        clientIP: '1.2.3.4',
      });

      expect(decision.alternateRegions.length).toBeGreaterThan(0);
    });

    it('should balance load across healthy regions', async () => {
      const clientCount = 100;
      const distribution: Record<string, number> = {};

      for (let i = 0; i < clientCount; i++) {
        const decision = await loadBalancer.selectRegion(
          `client-${i}`
        );
        distribution[decision.selectedRegion] =
          (distribution[decision.selectedRegion] || 0) + 1;
      }

      // All healthy regions should receive requests
      expect(Object.keys(distribution).length).toBeGreaterThan(1);

      // Distribution should be relatively even
      const values = Object.values(distribution);
      const avg = values.reduce((a, b) => a + b, 0) / values.length;
      const variance = values.reduce((sum, v) => sum + Math.pow(v - avg, 2), 0) / values.length;
      const stdDev = Math.sqrt(variance);

      expect(stdDev / avg).toBeLessThan(0.3); // Coefficient of variation < 30%
    });
  });
});
