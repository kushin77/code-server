#!/usr/bin/env node
// @file        apps/extensions/team-hub/src/__tests__/websocket-manager.test.ts
// @module      extensions/team-hub/websocket-manager-tests
// @description Tests for WebSocket manager real-time updates
// @owner       collab-9
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import WebSocket from 'ws';
import { WebSocketManager, WebSocketEvent } from '../websocket-manager';

// Mock WebSocket
vi.mock('ws');

describe('WebSocketManager', () => {
  let manager: WebSocketManager;
  let mockWs: any;

  beforeEach(() => {
    mockWs = {
      readyState: WebSocket.OPEN,
      send: vi.fn(),
      ping: vi.fn(),
      close: vi.fn(),
      on: vi.fn(),
      off: vi.fn(),
      once: vi.fn(),
    };

    // Mock WebSocket constructor
    (WebSocket as any).mockImplementation(() => mockWs);

    manager = new WebSocketManager({
      url: 'ws://localhost:3100/webhooks',
      reconnectIntervalMs: 100,
      maxReconnectAttempts: 3,
      heartbeatIntervalMs: 1000,
    });
  });

  afterEach(() => {
    manager.dispose();
    vi.clearAllMocks();
  });

  describe('Connection Management', () => {
    it('should connect to WebSocket server', async () => {
      const connectPromise = manager.connect();

      // Simulate open event
      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();

      await connectPromise;
      expect(manager.isConnected()).toBe(true);
    });

    it('should disconnect intentionally', (done) => {
      manager.connect().then(() => {
        manager.disconnect();

        // Simulate close event
        const closeHandler = mockWs.on.mock.calls.find((call) => call[0] === 'close')[1];
        closeHandler();

        expect(manager.isConnected()).toBe(false);
        done();
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });

    it('should handle connection errors', async () => {
      const errorPromise = manager.connect().catch(() => {});

      const errorHandler = mockWs.on.mock.calls.find((call) => call[0] === 'error')[1];
      errorHandler(new Error('Connection refused'));

      await expect(errorPromise).rejects.toThrow();
    });
  });

  describe('Message Handling', () => {
    it('should emit issue-created event', (done) => {
      manager.on('issue-created', (event) => {
        expect(event.type).toBe('issue-created');
        expect(event.issueNumber).toBe(123);
        expect(event.action).toBe('opened');
        done();
      });

      manager.connect().then(() => {
        const messageHandler = mockWs.on.mock.calls.find((call) => call[0] === 'message')[1];
        messageHandler(
          JSON.stringify({
            type: 'issue-created',
            issueNumber: 123,
            action: 'opened',
            timestamp: Date.now(),
          })
        );
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });

    it('should emit issue-updated event', (done) => {
      manager.on('issue-updated', (event) => {
        expect(event.type).toBe('issue-updated');
        expect(event.issueNumber).toBe(456);
        done();
      });

      manager.connect().then(() => {
        const messageHandler = mockWs.on.mock.calls.find((call) => call[0] === 'message')[1];
        messageHandler(
          JSON.stringify({
            type: 'issue-updated',
            issueNumber: 456,
            action: 'edited',
            data: { title: 'New title' },
            timestamp: Date.now(),
          })
        );
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });

    it('should deduplicate duplicate events', (done) => {
      let eventCount = 0;

      manager.on('issue-closed', () => {
        eventCount++;
        if (eventCount === 2) {
          expect(eventCount).toBe(1); // Should only fire once
          done();
        }
      });

      manager.connect().then(() => {
        const messageHandler = mockWs.on.mock.calls.find((call) => call[0] === 'message')[1];
        const eventData = JSON.stringify({
          type: 'issue-closed',
          issueNumber: 789,
          action: 'closed',
          timestamp: 1000,
        });

        // Send same event twice
        messageHandler(eventData);
        messageHandler(eventData);

        // Wait briefly for deduplication
        setTimeout(() => {
          expect(eventCount).toBe(1);
          done();
        }, 100);
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });

    it('should handle malformed JSON messages', (done) => {
      manager.on('error', () => {
        // Error event should be emitted
        done();
      });

      manager.connect().then(() => {
        const messageHandler = mockWs.on.mock.calls.find((call) => call[0] === 'message')[1];
        messageHandler('invalid json');
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });
  });

  describe('Event Listeners', () => {
    it('should allow subscribing to events', (done) => {
      const listener = vi.fn((event) => {
        expect(listener).toHaveBeenCalled();
        done();
      });

      manager.on('comment-added', listener);

      manager.connect().then(() => {
        const messageHandler = mockWs.on.mock.calls.find((call) => call[0] === 'message')[1];
        messageHandler(
          JSON.stringify({
            type: 'comment-added',
            issueNumber: 999,
            timestamp: Date.now(),
          })
        );
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });

    it('should allow unsubscribing from events', (done) => {
      const listener = vi.fn();

      manager.on('issue-reopened', listener);
      manager.off('issue-reopened', listener);

      manager.connect().then(() => {
        const messageHandler = mockWs.on.mock.calls.find((call) => call[0] === 'message')[1];
        messageHandler(
          JSON.stringify({
            type: 'issue-reopened',
            issueNumber: 555,
            timestamp: Date.now(),
          })
        );

        // Wait briefly to ensure listener is not called
        setTimeout(() => {
          expect(listener).not.toHaveBeenCalled();
          done();
        }, 100);
      });

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();
    });
  });

  describe('Message Sending', () => {
    it('should send messages when connected', async () => {
      await manager.connect();

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();

      manager.send({ type: 'subscribe', issue: 123 });

      expect(mockWs.send).toHaveBeenCalledWith(
        JSON.stringify({ type: 'subscribe', issue: 123 })
      );
    });

    it('should not send messages when disconnected', async () => {
      mockWs.readyState = WebSocket.CLOSED;

      manager.send({ type: 'subscribe', issue: 123 });

      expect(mockWs.send).not.toHaveBeenCalled();
    });
  });

  describe('Heartbeat', () => {
    it('should send heartbeat pings periodically', async () => {
      vi.useFakeTimers();

      await manager.connect();

      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();

      // Advance time past heartbeat interval
      vi.advanceTimersByTime(1100);

      expect(mockWs.ping).toHaveBeenCalled();

      vi.useRealTimers();
    });
  });

  describe('Connection Status', () => {
    it('should report connection status correctly', async () => {
      expect(manager.isConnected()).toBe(false);

      await manager.connect();
      const openHandler = mockWs.on.mock.calls.find((call) => call[0] === 'open')[1];
      openHandler();

      expect(manager.isConnected()).toBe(true);

      manager.disconnect();
      expect(manager.isConnected()).toBe(false);
    });
  });
});