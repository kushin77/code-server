#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/websocket-broadcast.ts
// @module      backend/github-task-sync/websocket-broadcast
// @description WebSocket server for broadcasting GitHub webhook events to IDE clients
// @owner       collab-9
// @status      active

import { WebSocket, Server as WebSocketServer } from 'ws';
import { EventEmitter } from 'events';
import { getLogger } from '../../utils/logging';

const logger = getLogger('websocket-broadcast');

export interface BroadcastMessage {
  type: 'issue-created' | 'issue-updated' | 'issue-closed' | 'issue-reopened' | 'comment-added';
  issueNumber: number;
  action: string;
  data?: Record<string, any>;
  timestamp: number;
}

/**
 * WebSocket Broadcaster
 * Manages WebSocket connections and broadcasts webhook events to connected IDE clients
 */
export class WebSocketBroadcaster extends EventEmitter {
  private wss: WebSocketServer;
  private clients: Set<WebSocket> = new Set();

  constructor(server: any) {
    super();

    // Create WebSocket server attached to HTTP server
    this.wss = new WebSocketServer({ server, path: '/github-webhooks' });

    this.wss.on('connection', (ws: WebSocket) => {
      this.handleNewConnection(ws);
    });

    logger.info('WebSocket broadcaster initialized');
  }

  /**
   * Handle new WebSocket connection
   */
  private handleNewConnection(ws: WebSocket): void {
    this.clients.add(ws);
    logger.info(`WebSocket client connected (${this.clients.size} total)`);

    // Send welcome message
    this.sendToClient(ws, {
      type: 'issue-created',
      issueNumber: 0,
      action: 'system',
      data: { message: 'connected to webhook broadcast server' },
      timestamp: Date.now(),
    });

    // Emit connected event
    this.emit('client-connected', ws);

    // Handle client disconnect
    ws.on('close', () => {
      this.clients.delete(ws);
      logger.info(`WebSocket client disconnected (${this.clients.size} remaining)`);
      this.emit('client-disconnected', ws);
    });

    // Handle client errors
    ws.on('error', (error: Error) => {
      logger.error(`WebSocket client error: ${error.message}`);
      this.clients.delete(ws);
    });

    // Handle incoming messages (for future use - keep-alive pings, etc)
    ws.on('message', (data: Buffer) => {
      try {
        const message = JSON.parse(data.toString());
        logger.debug(`Received message from client: ${message.type}`);
      } catch (error) {
        logger.error(`Failed to parse client message: ${error}`);
      }
    });
  }

  /**
   * Send message to specific client
   */
  private sendToClient(ws: WebSocket, message: BroadcastMessage): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  /**
   * Broadcast webhook event to all connected clients
   */
  public broadcast(event: BroadcastMessage): void {
    if (this.clients.size === 0) {
      logger.debug(`No WebSocket clients connected, skipping broadcast`);
      return;
    }

    logger.info(`Broadcasting event to ${this.clients.size} clients: ${event.type} #${event.issueNumber}`);

    const failedClients: WebSocket[] = [];

    this.clients.forEach((ws: WebSocket) => {
      try {
        this.sendToClient(ws, event);
      } catch (error) {
        logger.error(`Failed to send message to client: ${error}`);
        failedClients.push(ws);
      }
    });

    // Remove failed clients
    failedClients.forEach((ws) => {
      this.clients.delete(ws);
    });
  }

  /**
   * Get connected client count
   */
  public getClientCount(): number {
    return this.clients.size;
  }

  /**
   * Shutdown WebSocket server
   */
  public shutdown(): void {
    logger.info('Shutting down WebSocket server');

    this.clients.forEach((ws) => {
      ws.close(1000, 'Server shutdown');
    });

    this.clients.clear();
    this.wss.close();
  }
}

export default WebSocketBroadcaster;