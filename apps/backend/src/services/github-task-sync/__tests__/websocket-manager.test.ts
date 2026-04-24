#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/__tests__/websocket-manager.test.ts
// @module      github-task-sync/__tests__/websocket-manager
// @description Integration tests for the backend WebSocket manager.
// @owner       collab-9
// @status      active

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createServer, Server as HttpServer } from 'http';
import WebSocket from 'ws';
import WebSocketManager from '../websocket-manager';

async function createServerAndManager() {
  const httpServer = createServer();
  const manager = new WebSocketManager();

  manager.attach(httpServer);

  await new Promise<void>((resolve) => {
    httpServer.listen(0, '127.0.0.1', resolve);
  });

  const address = httpServer.address();
  if (!address || typeof address === 'string') {
    throw new Error('Failed to resolve test server port');
  }

  return {
    httpServer,
    manager,
    url: `ws://127.0.0.1:${address.port}/ws/task-sync`,
  };
}

async function connectAuthenticatedClient(url: string, userId = 'repo-1') {
  const socket = new WebSocket(url);

  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      socket.off('message', handleMessage);
      reject(new Error('Timed out waiting for auth pong'));
    }, 5000);

    const handleMessage = (data: WebSocket.RawData) => {
      try {
        const message = JSON.parse(data.toString()) as { type: string };
        if (message.type === 'pong') {
          clearTimeout(timeout);
          socket.off('message', handleMessage);
          resolve();
        }
      } catch (error) {
        clearTimeout(timeout);
        reject(error);
      }
    };

    socket.on('message', handleMessage);
    socket.once('open', () => {
      socket.send(
        JSON.stringify({
          type: 'auth',
          payload: {
            token: 'test-token',
            userId,
          },
          timestamp: Date.now(),
        })
      );
    });

    socket.once('error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });

  return socket;
}

async function waitFor(condition: () => boolean, timeoutMs = 2000): Promise<void> {
  const startedAt = Date.now();

  while (!condition()) {
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error('Timed out waiting for websocket state to settle');
    }

    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

describe('WebSocketManager', () => {
  let manager: WebSocketManager;
  let httpServer: HttpServer;
  let socket: WebSocket | undefined;
  let url: string;

  beforeEach(async () => {
    ({ httpServer, manager, url } = await createServerAndManager());
  });

  afterEach(() => {
    socket?.close();
    manager.close();
    httpServer.close();
  });

  it('attaches to the HTTP server and starts empty', () => {
    const stats = manager.getStats();

    expect(stats).toMatchObject({
      connectedClients: 0,
      totalSubscriptions: 0,
      queuedSessions: 0,
    });
    expect(Array.isArray(stats.sessions)).toBe(true);
  });

  it('authenticates clients and tracks an active session', async () => {
    manager.setAuthValidator(async (token, userId) => token === 'test-token' && userId === 'repo-1');

    socket = await connectAuthenticatedClient(url, 'repo-1');

    await waitFor(() => manager.getStats().connectedClients === 1);

    const stats = manager.getStats();
    expect(stats.connectedClients).toBe(1);
    expect(stats.totalSubscriptions).toBe(0);
    expect(stats.sessions[0]).toMatchObject({
      userId: 'repo-1',
      subscriptionCount: 0,
    });
  });

  it('fails authentication when the validator rejects the token', async () => {
    manager.setAuthValidator(async () => false);

    const client = new WebSocket(url);

    const closeCode = await new Promise<number>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for auth failure')), 5000);

      client.once('open', () => {
        client.send(
          JSON.stringify({
            type: 'auth',
            payload: {
              token: 'bad-token',
              userId: 'repo-1',
            },
            timestamp: Date.now(),
          })
        );
      });

      client.once('close', (code) => {
        clearTimeout(timeout);
        resolve(code);
      });

      client.once('error', (error) => {
        clearTimeout(timeout);
        reject(error);
      });
    });

    expect(closeCode).toBe(4003);
    client.close();
  });

  it('delivers issue updates to subscribed clients', async () => {
    manager.setAuthValidator(async () => true);
    socket = await connectAuthenticatedClient(url, 'repo-1');

    socket.send(
      JSON.stringify({
        type: 'subscribe',
        payload: { issueNumber: 123 },
        timestamp: Date.now(),
      })
    );

    await waitFor(() => manager.getStats().totalSubscriptions === 1);

    const broadcastPromise = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for issue update')), 5000);

      const handleMessage = (data: WebSocket.RawData) => {
        try {
          const message = JSON.parse(data.toString()) as {
            type: string;
            payload?: { issueNumber?: number; changes?: { state?: string } };
          };

          if (message.type === 'issue-updated') {
            clearTimeout(timeout);
            socket?.off('message', handleMessage);
            expect(message.payload?.issueNumber).toBe(123);
            expect(message.payload?.changes?.state).toBe('closed');
            resolve();
          }
        } catch (error) {
          clearTimeout(timeout);
          reject(error);
        }
      };

      socket?.on('message', handleMessage);
      manager.once('broadcast-complete', (event) => {
        expect(event).toMatchObject({
          issueKey: 'repo-1#123',
          delivered: 1,
        });
      });
    });

    manager.broadcastIssueUpdate('repo-1', 123, { state: 'closed' });
    await broadcastPromise;
  });

  it('clears sessions and subscriptions on shutdown', async () => {
    manager.setAuthValidator(async () => true);
    socket = await connectAuthenticatedClient(url, 'repo-1');

    socket.send(
      JSON.stringify({
        type: 'subscribe',
        payload: { issueNumber: 123 },
        timestamp: Date.now(),
      })
    );

    await waitFor(() => manager.getStats().totalSubscriptions === 1);

    manager.close();

    const stats = manager.getStats();
    expect(stats).toMatchObject({
      connectedClients: 0,
      totalSubscriptions: 0,
      queuedSessions: 0,
    });
  });

  it('rejects unauthenticated messages before auth', async () => {
    socket = new WebSocket(url);

    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for auth rejection')), 5000);

      socket?.once('open', () => {
        socket?.send(
          JSON.stringify({
            type: 'subscribe',
            payload: { issueNumber: 999 },
            timestamp: Date.now(),
          })
        );
      });

      socket?.once('close', (code) => {
        clearTimeout(timeout);
        expect(code).toBe(4001);
        resolve();
      });

      socket?.once('error', (error) => {
        clearTimeout(timeout);
        reject(error);
      });
    });
  });

  it('rejects malformed websocket messages after auth', async () => {
    manager.setAuthValidator(async () => true);
    socket = await connectAuthenticatedClient(url, 'repo-1');

    const errorMessage = new Promise<{ type: string; payload?: { error?: string } }>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timed out waiting for malformed message error')), 5000);

      socket?.once('message', (data) => {
        clearTimeout(timeout);
        try {
          resolve(JSON.parse(data.toString()));
        } catch (error) {
          reject(error);
        }
      });
    });

    socket.send('{not-json');

    const message = await errorMessage;
    expect(message.type).toBe('error');
    expect(message.payload?.error).toBe('Invalid message format');
    expect(manager.getStats().connectedClients).toBe(1);
  });
});
