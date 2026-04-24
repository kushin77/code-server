#!/usr/bin/env node
// @file        apps/extensions/team-hub/src/websocket-manager.ts
// @module      extensions/team-hub/websocket-manager
// @description WebSocket manager for real-time GitHub issue updates
// @owner       collab-9
// @status      active

import * as vscode from 'vscode';
import WebSocket from 'ws';

export interface WebSocketConfig {
  url: string;
  reconnectIntervalMs?: number; // Default: 1000ms, exponential backoff
  maxReconnectAttempts?: number; // Default: 10
  heartbeatIntervalMs?: number; // Default: 30000ms
}

export interface WebSocketEvent {
  type: 'issue-created' | 'issue-updated' | 'issue-closed' | 'issue-reopened' | 'comment-added' | 'error' | 'connected' | 'disconnected';
  issueNumber?: number;
  action?: string;
  data?: Record<string, any>;
  timestamp: number;
}

/**
 * WebSocket Manager
 * Manages real-time WebSocket connection for GitHub issue updates
 * Implements automatic reconnection with exponential backoff
 */
export class WebSocketManager {
  private ws: WebSocket | null = null;
  private config: Required<WebSocketConfig>;
  private reconnectAttempts = 0;
  private heartbeatTimeout: NodeJS.Timeout | null = null;
  private reconnectTimeout: NodeJS.Timeout | null = null;
  private isIntentionallyClosed = false;
  private deduplicationCache: Set<string> = new Set();
  private eventListeners: Map<string, ((event: WebSocketEvent) => void)[]> = new Map();
  private outputChannel: vscode.OutputChannel;

  constructor(config: WebSocketConfig, outputChannel?: vscode.OutputChannel) {
    this.config = {
      reconnectIntervalMs: config.reconnectIntervalMs || 1000,
      maxReconnectAttempts: config.maxReconnectAttempts || 10,
      heartbeatIntervalMs: config.heartbeatIntervalMs || 30000,
      ...config,
    };

    this.outputChannel =
      outputChannel || vscode.window.createOutputChannel('GitHub Webhooks');
  }

  /**
   * Connect to WebSocket server
   */
  public async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        this.log(`Connecting to WebSocket: ${this.config.url}`);

        this.ws = new WebSocket(this.config.url);

        this.ws.on('open', () => {
          this.log('WebSocket connected');
          this.reconnectAttempts = 0;
          this.isIntentionallyClosed = false;
          this.startHeartbeat();
          this.emit({
            type: 'connected',
            timestamp: Date.now(),
          });
          resolve();
        });

        this.ws.on('message', (data: WebSocket.Data) => {
          this.handleMessage(data);
        });

        this.ws.on('error', (error: Error) => {
          this.log(`WebSocket error: ${error.message}`);
          this.emit({
            type: 'error',
            data: { error: error.message },
            timestamp: Date.now(),
          });
          reject(error);
        });

        this.ws.on('close', () => {
          this.log('WebSocket disconnected');
          this.stopHeartbeat();
          this.emit({
            type: 'disconnected',
            timestamp: Date.now(),
          });

          if (!this.isIntentionallyClosed) {
            this.attemptReconnect();
          }
        });
      } catch (error) {
        this.log(`Failed to create WebSocket: ${error}`);
        reject(error);
      }
    });
  }

  /**
   * Disconnect from WebSocket server
   */
  public disconnect(): void {
    this.isIntentionallyClosed = true;
    this.stopHeartbeat();

    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }

    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }

    this.log('WebSocket intentionally closed');
  }

  /**
   * Send message to server
   */
  public send(data: Record<string, any>): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    } else {
      this.log('Cannot send: WebSocket not connected');
    }
  }

  /**
   * Subscribe to event type
   */
  public on(
    eventType: WebSocketEvent['type'],
    listener: (event: WebSocketEvent) => void
  ): void {
    if (!this.eventListeners.has(eventType)) {
      this.eventListeners.set(eventType, []);
    }
    this.eventListeners.get(eventType)!.push(listener);
  }

  /**
   * Unsubscribe from event type
   */
  public off(
    eventType: WebSocketEvent['type'],
    listener: (event: WebSocketEvent) => void
  ): void {
    const listeners = this.eventListeners.get(eventType);
    if (listeners) {
      const index = listeners.indexOf(listener);
      if (index > -1) {
        listeners.splice(index, 1);
      }
    }
  }

  /**
   * Get connection status
   */
  public isConnected(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }

  /**
   * Handle incoming WebSocket message
   */
  private handleMessage(data: WebSocket.Data): void {
    try {
      const message = JSON.parse(data.toString());

      // Deduplicate events
      const eventId = `${message.type}-${message.issueNumber}-${message.timestamp}`;
      if (this.deduplicationCache.has(eventId)) {
        this.log(`Duplicate event ignored: ${eventId}`);
        return;
      }

      this.deduplicationCache.add(eventId);

      // Emit event
      this.emit({
        type: message.type,
        issueNumber: message.issueNumber,
        action: message.action,
        data: message.data,
        timestamp: message.timestamp || Date.now(),
      });
    } catch (error) {
      this.log(`Failed to parse WebSocket message: ${error}`);
    }
  }

  /**
   * Emit event to all listeners
   */
  private emit(event: WebSocketEvent): void {
    const listeners = this.eventListeners.get(event.type) || [];
    listeners.forEach((listener) => {
      try {
        listener(event);
      } catch (error) {
        this.log(`Error in event listener: ${error}`);
      }
    });
  }

  /**
   * Start heartbeat to keep connection alive
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();

    this.heartbeatTimeout = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.ws.ping();
      }
    }, this.config.heartbeatIntervalMs);
  }

  /**
   * Stop heartbeat
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimeout) {
      clearInterval(this.heartbeatTimeout);
      this.heartbeatTimeout = null;
    }
  }

  /**
   * Attempt to reconnect with exponential backoff
   */
  private attemptReconnect(): void {
    if (this.reconnectAttempts >= this.config.maxReconnectAttempts) {
      this.log('Max reconnection attempts reached. Giving up.');
      return;
    }

    this.reconnectAttempts++;
    const backoffMs =
      Math.min(
        this.config.reconnectIntervalMs * Math.pow(2, this.reconnectAttempts - 1),
        30000
      ) + Math.random() * 1000; // Add jitter

    this.log(`Reconnecting in ${backoffMs}ms (attempt ${this.reconnectAttempts})`);

    this.reconnectTimeout = setTimeout(() => {
      this.connect().catch((error) => {
        this.log(`Reconnection failed: ${error}`);
      });
    }, backoffMs);
  }

  /**
   * Log message to output channel
   */
  private log(message: string): void {
    this.outputChannel.appendLine(`[${new Date().toISOString()}] ${message}`);
  }

  /**
   * Cleanup resources
   */
  public dispose(): void {
    this.disconnect();
    this.deduplicationCache.clear();
    this.eventListeners.clear();
  }
}

export default WebSocketManager;