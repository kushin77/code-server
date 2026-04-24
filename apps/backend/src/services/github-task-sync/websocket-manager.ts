#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/websocket-manager.ts
// @module      services/github-task-sync
// @description WebSocket manager for authenticated GitHub task sync clients
// @owner       collab-9
// @status      active

import { EventEmitter } from 'events';
import WebSocket, { WebSocketServer } from 'ws';

type AuthValidator = (token: string, userId: string) => boolean | Promise<boolean>;

interface AuthMessage {
  type: 'auth';
  payload?: {
    token?: string;
    userId?: string;
  };
}

interface SubscribeMessage {
  type: 'subscribe';
  payload?: {
    issueNumber?: number;
  };
}

interface SessionState {
  userId: string;
  subscriptions: Set<number>;
}

export interface WebSocketManagerStats {
  connectedClients: number;
  totalSubscriptions: number;
  queuedSessions: number;
  sessions: Array<{
    userId: string;
    subscriptionCount: number;
  }>;
}

export default class WebSocketManager extends EventEmitter {
  private server: WebSocketServer | null = null;
  private readonly sessions = new Map<WebSocket, SessionState>();
  private readonly pendingSessions = new Set<WebSocket>();
  private authValidator: AuthValidator | null = null;

  attach(httpServer: any): void {
    if (this.server) {
      return;
    }

    this.server = new WebSocketServer({ server: httpServer, path: '/ws/task-sync' });
    this.server.on('connection', (socket) => this.handleConnection(socket));
  }

  setAuthValidator(validator: AuthValidator): void {
    this.authValidator = validator;
  }

  getStats(): WebSocketManagerStats {
    const sessions = Array.from(this.sessions.values()).map((session) => ({
      userId: session.userId,
      subscriptionCount: session.subscriptions.size,
    }));

    return {
      connectedClients: this.sessions.size,
      totalSubscriptions: sessions.reduce((total, session) => total + session.subscriptionCount, 0),
      queuedSessions: this.pendingSessions.size,
      sessions,
    };
  }

  broadcastIssueUpdate(owner: string, issueNumber: number, changes: Record<string, unknown>): number {
    const payload = {
      issueNumber,
      changes,
    };

    const message = JSON.stringify({
      type: 'issue-updated',
      payload,
      timestamp: Date.now(),
    });

    let delivered = 0;

    for (const [socket, session] of this.sessions.entries()) {
      if (session.userId !== owner || !session.subscriptions.has(issueNumber)) {
        continue;
      }

      if (socket.readyState === WebSocket.OPEN) {
        socket.send(message);
        delivered += 1;
      }
    }

    this.emit('broadcast-complete', {
      issueKey: `${owner}#${issueNumber}`,
      delivered,
      timestamp: Date.now(),
    });

    return delivered;
  }

  close(): void {
    for (const socket of this.sessions.keys()) {
      if (socket.readyState === WebSocket.OPEN) {
        socket.close(1000, 'Server shutdown');
      }
    }

    for (const socket of this.pendingSessions) {
      if (socket.readyState === WebSocket.OPEN) {
        socket.close(1000, 'Server shutdown');
      }
    }

    this.sessions.clear();
    this.pendingSessions.clear();

    if (this.server) {
      this.server.close();
      this.server = null;
    }
  }

  private handleConnection(socket: WebSocket): void {
    this.pendingSessions.add(socket);

    socket.on('message', async (data: WebSocket.RawData) => {
      await this.handleMessage(socket, data);
    });

    socket.on('close', () => {
      this.pendingSessions.delete(socket);
      this.sessions.delete(socket);
    });

    socket.on('error', () => {
      this.pendingSessions.delete(socket);
      this.sessions.delete(socket);
    });
  }

  private async handleMessage(socket: WebSocket, data: WebSocket.RawData): Promise<void> {
    let message: AuthMessage | SubscribeMessage | { type?: string; payload?: any };

    try {
      message = JSON.parse(data.toString());
    } catch {
      if (this.sessions.has(socket)) {
        this.sendError(socket, 'Invalid message format');
        return;
      }

      socket.close(4001, 'Authentication required');
      return;
    }

    if (!this.sessions.has(socket)) {
      await this.handleAuthMessage(socket, message as AuthMessage);
      return;
    }

    if (message.type === 'subscribe') {
      this.handleSubscribeMessage(socket, message as SubscribeMessage);
      return;
    }

    this.sendError(socket, 'Unsupported message type');
  }

  private async handleAuthMessage(socket: WebSocket, message: AuthMessage): Promise<void> {
    if (message.type !== 'auth') {
      socket.close(4001, 'Authentication required');
      return;
    }

    const token = message.payload?.token;
    const userId = message.payload?.userId;

    if (!token || !userId) {
      socket.close(4003, 'Authentication failed');
      return;
    }

    const validator = this.authValidator ?? (async () => true);
    const isAllowed = await validator(token, userId);

    if (!isAllowed) {
      socket.close(4003, 'Authentication failed');
      return;
    }

    this.pendingSessions.delete(socket);
    this.sessions.set(socket, {
      userId,
      subscriptions: new Set<number>(),
    });

    if (socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({
        type: 'pong',
        timestamp: Date.now(),
      }));
    }
  }

  private handleSubscribeMessage(socket: WebSocket, message: SubscribeMessage): void {
    const session = this.sessions.get(socket);
    const issueNumber = message.payload?.issueNumber;

    if (!session || typeof issueNumber !== 'number') {
      this.sendError(socket, 'Invalid message format');
      return;
    }

    session.subscriptions.add(issueNumber);
  }

  private sendError(socket: WebSocket, error: string): void {
    if (socket.readyState !== WebSocket.OPEN) {
      return;
    }

    socket.send(JSON.stringify({
      type: 'error',
      payload: { error },
      timestamp: Date.now(),
    }));
  }
}