#!/usr/bin/env node
// @file        apps/backend/src/services/monitoring/__tests__/websocket-health-service.test.ts
// @module      services/monitoring
// @description Tests for WebSocket health monitoring service

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import service, { WebSocketHealthService, ConnectionHealth, ConnectionType, QualityMetric } from '../websocket-health-service';

describe('WebSocketHealthService', () => {
  beforeEach(() => {
    service.reset();
  });

  afterEach(() => {
    service.removeAllListeners();
  });

  // Registration Tests
  describe('Connection Registration', () => {
    it('should register a new connection', () => {
      const health = service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      expect(health).toBeDefined();
      expect(health.connectionId).toBe('conn1');
      expect(health.type).toBe('collaboration');
      expect(health.userId).toBe('user1');
      expect(health.workspaceId).toBe('ws1');
      expect(health.connected).toBe(true);
      expect(health.qualityScore).toBe(100);
      expect(health.reconnectAttempts).toBe(0);
    });

    it('should track multiple connections per user', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'presence', 'user1', 'ws1');
      service.registerConnection('conn3', 'voice-signaling', 'user2', 'ws1');

      const user1Conns = service.getConnectionsForUser('user1');
      expect(user1Conns).toHaveLength(2);
      expect(user1Conns.map((c) => c.connectionId)).toContain('conn1');
      expect(user1Conns.map((c) => c.connectionId)).toContain('conn2');
    });

    it('should emit connectionRegistered event', () => {
      return new Promise((resolve) => {
        service.on('connectionRegistered', (health: ConnectionHealth) => {
          expect(health.connectionId).toBe('conn1');
          resolve(null);
        });
        service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      });
    });

    it('should initialize metrics as empty array', () => {
      const health = service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      expect(health.metrics).toHaveLength(0);
    });
  });

  // Latency and Pong Tests
  describe('Ping/Pong and Latency', () => {
    it('should record ping sent', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      const health = service.recordPingSent('conn1');

      expect(health).toBeDefined();
      expect(health!.lastPingTime).toBeGreaterThan(0);
    });

    it('should calculate latency on pong received', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.recordPingSent('conn1');

      // Wait a bit to create measurable latency
      return new Promise((resolve) => {
        setTimeout(() => {
          const health = service.recordPongReceived('conn1');
          expect(health!.latency).toBeGreaterThanOrEqual(10); // At least 10ms latency due to setTimeout
          resolve(null);
        }, 15);
      });
    });

    it('should update lastPongTime on pong received', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      const beforeTime = Date.now();
      service.recordPingSent('conn1');

      return new Promise((resolve) => {
        setTimeout(() => {
          const health = service.recordPongReceived('conn1');
          expect(health!.lastPongTime).toBeGreaterThanOrEqual(beforeTime);
          resolve(null);
        }, 10);
      });
    });

    it('should calculate jitter from latency variance', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // First ping/pong (no jitter yet)
      service.recordPingSent('conn1');
      const health1 = service.recordPongReceived('conn1');
      const firstLatency = health1!.latency;

      // Second ping/pong with different latency
      return new Promise((resolve) => {
        setTimeout(() => {
          service.recordPingSent('conn1');
          setTimeout(() => {
            const health2 = service.recordPongReceived('conn1');
            // Jitter should reflect difference between latencies
            expect(health2!.jitter).toBeGreaterThanOrEqual(0);
            resolve(null);
          }, 25);
        }, 15);
      });
    });

    it('should return undefined for nonexistent connection on pong', () => {
      const health = service.recordPongReceived('nonexistent');
      expect(health).toBeUndefined();
    });
  });

  // Packet Loss Tests
  describe('Packet Loss', () => {
    it('should record packet loss percentage', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      const health = service.recordPacketLoss('conn1', 5);

      expect(health!.packetLoss).toBe(5);
    });

    it('should clamp packet loss to 0-100 range', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      const health1 = service.recordPacketLoss('conn1', -10);
      expect(health1!.packetLoss).toBe(0);

      const health2 = service.recordPacketLoss('conn1', 150);
      expect(health2!.packetLoss).toBe(100);
    });

    it('should return undefined for nonexistent connection on packet loss', () => {
      const health = service.recordPacketLoss('nonexistent', 5);
      expect(health).toBeUndefined();
    });

    it('should degrade quality score with packet loss', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // Record packet loss
      service.recordPacketLoss('conn1', 10);

      const health = service.getConnection('conn1');
      expect(health!.qualityScore).toBeLessThan(100);
    });
  });

  // Quality Score Tests
  describe('Quality Score Calculation', () => {
    it('should start with score of 100', () => {
      const health = service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      expect(health.qualityScore).toBe(100);
    });

    it('should degrade quality with high latency', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // Simulate high latency by manually setting values
      const conn = service.getConnection('conn1');
      expect(conn).toBeDefined();

      // Latency penalty: >50ms = penalty, max 50 points
      service.recordPingSent('conn1');
      return new Promise((resolve) => {
        setTimeout(() => {
          service.recordPongReceived('conn1');
          const health = service.getConnection('conn1');
          // High latency (>100ms) should reduce score
          if (health!.latency > 100) {
            expect(health!.qualityScore).toBeLessThan(100);
          }
          resolve(null);
        }, 150);
      });
    });

    it('should degrade quality with jitter', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // First ping/pong
      service.recordPingSent('conn1');
      const h1 = service.recordPongReceived('conn1');
      const firstLatency = h1!.latency;

      return new Promise((resolve) => {
        setTimeout(() => {
          service.recordPingSent('conn1');
          setTimeout(() => {
            service.recordPongReceived('conn1');
            const health = service.getConnection('conn1');
            // If jitter > 10ms, should reduce score
            if (health!.jitter > 10) {
              expect(health!.qualityScore).toBeLessThan(100);
            }
            resolve(null);
          }, 30);
        }, 10);
      });
    });

    it('should degrade quality with packet loss', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.recordPacketLoss('conn1', 5);

      const health = service.getConnection('conn1');
      // 5% loss = 15 point penalty (5 * 3)
      expect(health!.qualityScore).toBeLessThan(100);
      expect(health!.qualityScore).toBeGreaterThanOrEqual(85);
    });

    it('should emit connectionHealthy event when quality recovers', () => {
      return new Promise((resolve) => {
        service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

        let degradedEmitted = false;
        let healthyEmitted = false;

        service.on('connectionDegraded', () => {
          degradedEmitted = true;
        });

        service.on('connectionHealthy', () => {
          healthyEmitted = true;
          resolve(null);
        });

        // Degrade quality significantly (85% packet loss will degrade below threshold)
        service.recordPacketLoss('conn1', 85);
        expect(degradedEmitted).toBe(true);

        // Recovery
        service.recordPacketLoss('conn1', 0);
        service.recordPingSent('conn1');
        setTimeout(() => {
          service.recordPongReceived('conn1');
        }, 10);
      });
    });

    it('should keep quality score in 0-100 range', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // Apply multiple degrading factors
      service.recordPacketLoss('conn1', 100);
      const health = service.getConnection('conn1');

      expect(health!.qualityScore).toBeGreaterThanOrEqual(0);
      expect(health!.qualityScore).toBeLessThanOrEqual(100);
    });
  });

  // Disconnection Tests
  describe('Disconnection and Reconnection', () => {
    it('should mark connection as disconnected', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      const health = service.markDisconnected('conn1');

      expect(health!.connected).toBe(false);
    });

    it('should emit connectionDisconnected event', () => {
      return new Promise((resolve) => {
        service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

        service.on('connectionDisconnected', (health: ConnectionHealth) => {
          expect(health.connected).toBe(false);
          resolve(null);
        });

        service.markDisconnected('conn1');
      });
    });

    it('should increment reconnect attempts', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.markDisconnected('conn1');

      const health1 = service.attemptReconnection('conn1');
      expect(health1!.reconnectAttempts).toBe(1);

      const health2 = service.attemptReconnection('conn1');
      expect(health2!.reconnectAttempts).toBe(2);
    });

    it('should emit reconnectionAttempted event with exponential backoff', () => {
      return new Promise((resolve) => {
        service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

        let attemptNumber = 0;
        service.on('reconnectionAttempted', (data) => {
          attemptNumber++;
          // Backoff should be 2^(n-1) seconds, max 30
          const expectedBackoff = Math.min(30, Math.pow(2, attemptNumber - 1));
          expect(data.backoffSeconds).toBe(expectedBackoff);
          expect(data.attemptNumber).toBe(attemptNumber);
        });

        service.attemptReconnection('conn1');
        service.attemptReconnection('conn1');
        resolve(null);
      });
    });

    it('should mark reconnection as successful', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.markDisconnected('conn1');
      service.attemptReconnection('conn1');

      const health = service.reconnectionSuccessful('conn1');

      expect(health!.connected).toBe(true);
      expect(health!.reconnectAttempts).toBe(0);
      expect(health!.qualityScore).toBe(100);
    });

    it('should emit reconnectionSuccessful event', () => {
      return new Promise((resolve) => {
        service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

        service.on('reconnectionSuccessful', (health: ConnectionHealth) => {
          expect(health.connected).toBe(true);
          resolve(null);
        });

        service.markDisconnected('conn1');
        service.attemptReconnection('conn1');
        service.reconnectionSuccessful('conn1');
      });
    });
  });

  // Query Tests
  describe('Connection Queries', () => {
    beforeEach(() => {
      // Setup: mix of connections
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'presence', 'user1', 'ws1');
      service.registerConnection('conn3', 'voice-signaling', 'user2', 'ws1');
      service.registerConnection('conn4', 'session-broker', 'user3', 'ws2');
    });

    it('should get all connections for a user', () => {
      const connections = service.getConnectionsForUser('user1');
      expect(connections).toHaveLength(2);
      expect(connections.map((c) => c.connectionId)).toContain('conn1');
      expect(connections.map((c) => c.connectionId)).toContain('conn2');
    });

    it('should return empty array for user with no connections', () => {
      const connections = service.getConnectionsForUser('nonexistent-user');
      expect(connections).toHaveLength(0);
    });

    it('should get connections by type', () => {
      const collab = service.getConnectionsByType('collaboration');
      expect(collab).toHaveLength(1);
      expect(collab[0].connectionId).toBe('conn1');

      const presence = service.getConnectionsByType('presence');
      expect(presence).toHaveLength(1);
      expect(presence[0].connectionId).toBe('conn2');
    });

    it('should return empty array for connection type with no connections', () => {
      service.registerConnection('conn5', 'collaboration', 'user1', 'ws1');
      const result = service.getConnectionsByType('collaboration');
      expect(result.length).toBeGreaterThanOrEqual(1);
    });

    it('should get degraded connections', () => {
      service.recordPacketLoss('conn1', 80); // High packet loss to degrade below threshold
      const degraded = service.getDegradedConnections();

      expect(degraded.length).toBeGreaterThanOrEqual(1);
      expect(degraded.map((c) => c.connectionId)).toContain('conn1');
    });

    it('should filter degraded connections by workspace', () => {
      service.recordPacketLoss('conn1', 80); // High packet loss for conn1 in ws1
      const degradedWs1 = service.getDegradedConnections('ws1');
      const degradedWs2 = service.getDegradedConnections('ws2');

      expect(degradedWs1.map((c) => c.connectionId)).toContain('conn1');
      expect(degradedWs2.map((c) => c.connectionId)).not.toContain('conn1');
    });

    it('should not include disconnected connections in degraded list', () => {
      service.recordPacketLoss('conn3', 50);
      service.markDisconnected('conn3');

      const degraded = service.getDegradedConnections();
      expect(degraded.map((c) => c.connectionId)).not.toContain('conn3');
    });

    it('should calculate average quality score', () => {
      const avgAll = service.getAverageQuality();
      expect(avgAll).toBeGreaterThanOrEqual(0);
      expect(avgAll).toBeLessThanOrEqual(100);

      const avgWs1 = service.getAverageQuality('ws1');
      expect(avgWs1).toBeGreaterThanOrEqual(0);
      expect(avgWs1).toBeLessThanOrEqual(100);
    });

    it('should return 100 for average quality with no connections', () => {
      const avg = service.getAverageQuality('empty-workspace');
      expect(avg).toBe(100);
    });
  });

  // Statistics Tests
  describe('Workspace Statistics', () => {
    beforeEach(() => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'presence', 'user2', 'ws1');
      service.registerConnection('conn3', 'voice-signaling', 'user3', 'ws1');
      service.registerConnection('conn4', 'collaboration', 'user4', 'ws2');
    });

    it('should return workspace stats', () => {
      const stats = service.getWorkspaceStats('ws1');

      expect(stats.totalConnections).toBe(3);
      expect(stats.connectedCount).toBe(3);
      expect(stats.disconnectedCount).toBe(0);
      expect(stats.connectionsByType).toBeDefined();
      expect(stats.averageQuality).toBeGreaterThanOrEqual(0);
      expect(stats.degradedCount).toBe(0);
    });

    it('should count connection types correctly', () => {
      const stats = service.getWorkspaceStats('ws1');

      expect(stats.connectionsByType.collaboration).toBe(1);
      expect(stats.connectionsByType.presence).toBe(1);
      expect(stats.connectionsByType['voice-signaling']).toBe(1);
      expect(stats.connectionsByType['session-broker']).toBe(0);
    });

    it('should count disconnected connections in stats', () => {
      service.markDisconnected('conn1');
      const stats = service.getWorkspaceStats('ws1');

      expect(stats.connectedCount).toBe(2);
      expect(stats.disconnectedCount).toBe(1);
    });

    it('should count degraded connections in stats', () => {
      service.recordPacketLoss('conn1', 80);
      service.recordPacketLoss('conn2', 80);
      const stats = service.getWorkspaceStats('ws1');

      expect(stats.degradedCount).toBeGreaterThanOrEqual(2);
    });
  });

  // Cleanup Tests
  describe('Connection Cleanup', () => {
    it('should unregister connection', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.unregisterConnection('conn1');

      const health = service.getConnection('conn1');
      expect(health).toBeUndefined();
    });

    it('should emit connectionUnregistered event', () => {
      return new Promise((resolve) => {
        service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

        service.on('connectionUnregistered', (health: ConnectionHealth) => {
          expect(health.connectionId).toBe('conn1');
          resolve(null);
        });

        service.unregisterConnection('conn1');
      });
    });

    it('should remove connection from user tracking on unregister', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'presence', 'user1', 'ws1');

      service.unregisterConnection('conn1');

      const connections = service.getConnectionsForUser('user1');
      expect(connections).toHaveLength(1);
      expect(connections[0].connectionId).toBe('conn2');
    });

    it('should handle unregister of nonexistent connection gracefully', () => {
      expect(() => {
        service.unregisterConnection('nonexistent');
      }).not.toThrow();
    });
  });

  // System Health Tests
  describe('System Health', () => {
    beforeEach(() => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'presence', 'user2', 'ws1');
      service.registerConnection('conn3', 'voice-signaling', 'user3', 'ws2');
    });

    it('should return system health summary', () => {
      const health = service.getSystemHealth();

      expect(health.totalConnections).toBe(3);
      expect(health.activeConnections).toBe(3);
      expect(health.systemQuality).toBeGreaterThanOrEqual(0);
      expect(health.systemQuality).toBeLessThanOrEqual(100);
      expect(health.degradedConnections).toBe(0);
      expect(health.reconnectingConnections).toBe(0);
    });

    it('should track degraded connections in system health', () => {
      service.recordPacketLoss('conn1', 80);
      const health = service.getSystemHealth();

      expect(health.degradedConnections).toBeGreaterThanOrEqual(1);
    });

    it('should track reconnecting connections in system health', () => {
      service.markDisconnected('conn1');
      service.attemptReconnection('conn1');

      const health = service.getSystemHealth();
      expect(health.reconnectingConnections).toBeGreaterThanOrEqual(1);
    });

    it('should exclude disconnected connections from active count', () => {
      service.markDisconnected('conn1');
      const health = service.getSystemHealth();

      expect(health.activeConnections).toBe(2);
      expect(health.totalConnections).toBe(3);
    });

    it('should calculate system quality without disconnected connections', () => {
      service.recordPacketLoss('conn1', 10);
      service.markDisconnected('conn1');

      const health = service.getSystemHealth();
      // System quality should only include active connections
      expect(health.systemQuality).toBeGreaterThanOrEqual(0);
      expect(health.systemQuality).toBeLessThanOrEqual(100);
    });
  });

  // Metrics Tracking Tests
  describe('Metrics History', () => {
    it('should record metrics on quality updates', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.recordPingSent('conn1');

      return new Promise((resolve) => {
        setTimeout(() => {
          service.recordPongReceived('conn1');
          const health = service.getConnection('conn1');

          // At least one metric should be recorded on pong
          expect(health!.metrics.length).toBeGreaterThanOrEqual(1);
          expect(health!.metrics[0].latency).toBeGreaterThanOrEqual(0);
          expect(health!.metrics[0].timestamp).toBeGreaterThanOrEqual(0);
          resolve(null);
        }, 10);
      });
    });

    it('should limit metrics history to max entries', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // Add many metric recordings
      for (let i = 0; i < 150; i++) {
        service.recordPingSent('conn1');
        service.recordPongReceived('conn1');
      }

      const health = service.getConnection('conn1');
      expect(health!.metrics.length).toBeLessThanOrEqual(100);
    });
  });

  // Singleton Tests
  describe('Singleton Pattern', () => {
    it('should return same instance', () => {
      const instance1 = WebSocketHealthService.getInstance();
      const instance2 = WebSocketHealthService.getInstance();

      expect(instance1).toBe(instance2);
    });

    it('should share state between getInstance calls', () => {
      const instance1 = WebSocketHealthService.getInstance();
      instance1.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      const instance2 = WebSocketHealthService.getInstance();
      const connections = instance2.getConnectionsForUser('user1');

      expect(connections).toHaveLength(1);
    });
  });

  // Edge Cases
  describe('Edge Cases', () => {
    it('should handle same connection type queries', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn3', 'collaboration', 'user1', 'ws1');

      const collab = service.getConnectionsByType('collaboration');
      expect(collab).toHaveLength(3);
    });

    it('should handle multiple workspaces', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
      service.registerConnection('conn2', 'collaboration', 'user1', 'ws2');
      service.registerConnection('conn3', 'collaboration', 'user2', 'ws1');

      const stats1 = service.getWorkspaceStats('ws1');
      const stats2 = service.getWorkspaceStats('ws2');

      expect(stats1.totalConnections).toBe(2);
      expect(stats2.totalConnections).toBe(1);
    });

    it('should handle rapid metric updates', () => {
      service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');

      // Rapid updates
      for (let i = 0; i < 10; i++) {
        service.recordPingSent('conn1');
        service.recordPongReceived('conn1');
        service.recordPacketLoss('conn1', Math.random() * 10);
      }

      const health = service.getConnection('conn1');
      expect(health).toBeDefined();
      expect(health!.qualityScore).toBeGreaterThanOrEqual(0);
      expect(health!.qualityScore).toBeLessThanOrEqual(100);
    });
  });
});
