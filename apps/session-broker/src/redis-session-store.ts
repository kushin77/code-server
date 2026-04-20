// @file        apps/session-broker/src/redis-session-store.ts
// @module      session-management/persistence
// @description Redis-backed session store for distributed session broker HA
//
// Replaces in-memory Maps with Redis for cross-host session persistence.
// Enables session-broker horizontal scaling and failover across .31 and .42 hosts.

import { createClient, RedisClientType } from 'redis';
import * as winston from 'winston';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

// Configuration from environment
const REDIS_SENTINEL_URLS = (process.env.REDIS_SENTINEL_URLS || 'redis-sentinel://redis-sentinel-1:26379,redis-sentinel-arbiter:26379/mymaster').split(',');
const REDIS_SENTINEL_DB = Number(process.env.REDIS_SENTINEL_DB || '1');
const SESSION_REDIS_TTL_SECONDS = Number(process.env.SESSION_REDIS_TTL_SECONDS || '86400'); // 1 day default
const SESSION_REDIS_NAMESPACE = process.env.SESSION_REDIS_NAMESPACE || 'session-broker';

// Type definitions (local; these mirror types in index.ts)
export interface SessionContext {
  sessionId: string;
  userId: string;
  teamId: string;
  username: string;
  email: string;
  dataProfile: string;
  dataProfileValidated?: boolean;
  provenance?: any;
  containerName?: string;
  containerId?: string;
  containerPort: number;
  baseImageId?: string;
  createdAt: Date;
  expiresAt: Date;
  quotas?: any;
  status: string;
  lastActivity?: Date;
  auditTrail?: SessionAuditEvent[];
  [key: string]: any;
}

export interface SessionAuditEvent {
  eventId: string;
  sessionId: string;
  timestamp: number;
  eventHash: string;
  [key: string]: any;
}

export class RedisSessionStore {
  private client: RedisClientType | null = null;
  private connected: boolean = false;
  private maxReconnectAttempts: number = 10;

  constructor() {
    // Client will be created in connect()
  }

  private parseSentinelUrls(): Array<{ host: string; port: number }> {
    return REDIS_SENTINEL_URLS.map((url: string) => {
      // Parse format: redis-sentinel://host:port
      const match = url.match(/redis-sentinel:\/\/([^:]+):(\d+)/);
      if (!match) {
        throw new Error(`Invalid Sentinel URL format: ${url}`);
      }
      return {
        host: match[1],
        port: Number(match[2]),
      };
    });
  }

  private setupEventHandlers(): void {
    if (!this.client) return;

    this.client.on('connect', () => {
      logger.info('Redis connected');
      this.connected = true;
    });

    this.client.on('error', (err: Error) => {
      logger.error('Redis error', { error: err.message });
      this.connected = false;
    });

    this.client.on('ready', () => {
      logger.info('Redis ready');
      this.connected = true;
    });

    this.client.on('close', () => {
      logger.warn('Redis connection closed');
      this.connected = false;
    });
  }

  async connect(): Promise<void> {
    try {
      const sentinels = this.parseSentinelUrls();
      
      // Create Redis client with Sentinel configuration
      this.client = createClient({
        socket: {
          reconnectStrategy: (retries: number) => {
            if (retries > this.maxReconnectAttempts) {
              logger.error('Max Redis reconnection attempts exceeded', { retries });
              return new Error('Redis reconnection limit exceeded');
            }
            const delay = Math.min(1000 * Math.pow(2, retries), 30000);
            logger.warn('Redis reconnecting', { retries, delayMs: delay });
            return delay;
          },
        } as any,
        sentinels: sentinels as any,
        sentinelName: 'mymaster',
        db: REDIS_SENTINEL_DB,
      } as any);

      this.setupEventHandlers();
      await this.client.connect();
      this.connected = true;
      logger.info('Redis session store connected');
    } catch (error: any) {
      logger.error('Failed to connect to Redis', { error: error.message });
      this.connected = false;
      throw error;
    }
  }

  async disconnect(): Promise<void> {
    if (this.client) {
      try {
        await this.client.quit();
        this.connected = false;
        logger.info('Redis session store disconnected');
      } catch (error: any) {
        logger.error('Error disconnecting from Redis', { error: error.message });
      }
    }
  }

  // Session storage operations
  async storeSession(sessionId: string, context: SessionContext): Promise<void> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:session:${sessionId}`;
      const serialized = JSON.stringify({
        ...context,
        createdAt: context.createdAt instanceof Date ? context.createdAt.getTime() : context.createdAt,
        lastActivity: context.lastActivity instanceof Date ? context.lastActivity.getTime() : context.lastActivity,
        expiresAt: context.expiresAt instanceof Date ? context.expiresAt.getTime() : context.expiresAt,
      });

      await this.client.setEx(key, SESSION_REDIS_TTL_SECONDS, serialized);
      
      // Add to session list sets
      const listKey = `${SESSION_REDIS_NAMESPACE}:list:sessions`;
      const userListKey = `${SESSION_REDIS_NAMESPACE}:user_sessions:${context.userId}`;
      await this.client.sAdd(listKey, sessionId);
      await this.client.sAdd(userListKey, sessionId);

      logger.debug('Session stored in Redis', { sessionId });
    } catch (error: any) {
      logger.error('Failed to store session in Redis', { sessionId, error: error.message });
      throw error;
    }
  }

  async getSession(sessionId: string): Promise<SessionContext | null> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:session:${sessionId}`;
      const data = await this.client.get(key);
      
      if (!data) return null;

      const context = JSON.parse(data);
      // Convert timestamps back to Date objects if they're numbers
      if (typeof context.createdAt === 'number') context.createdAt = new Date(context.createdAt);
      if (typeof context.lastActivity === 'number') context.lastActivity = new Date(context.lastActivity);
      if (typeof context.expiresAt === 'number') context.expiresAt = new Date(context.expiresAt);

      return context as SessionContext;
    } catch (error: any) {
      logger.error('Failed to retrieve session from Redis', { sessionId, error: error.message });
      throw error;
    }
  }

  async deleteSession(sessionId: string, userId?: string): Promise<void> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:session:${sessionId}`;
      await this.client.del(key);

      // Remove from list sets
      const listKey = `${SESSION_REDIS_NAMESPACE}:list:sessions`;
      await this.client.sRem(listKey, sessionId);

      if (userId) {
        const userListKey = `${SESSION_REDIS_NAMESPACE}:user_sessions:${userId}`;
        await this.client.sRem(userListKey, sessionId);
      }

      logger.debug('Session deleted from Redis', { sessionId });
    } catch (error: any) {
      logger.error('Failed to delete session from Redis', { sessionId, error: error.message });
      throw error;
    }
  }

  async getAllSessions(): Promise<SessionContext[]> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const listKey = `${SESSION_REDIS_NAMESPACE}:list:sessions`;
      const sessionIds = await this.client.sMembers(listKey);

      const sessions: SessionContext[] = [];
      for (const sessionId of sessionIds) {
        const session = await this.getSession(sessionId);
        if (session) {
          sessions.push(session);
        }
      }

      return sessions;
    } catch (error: any) {
      logger.error('Failed to retrieve all sessions from Redis', { error: error.message });
      throw error;
    }
  }

  async getUserSessions(userId: string): Promise<SessionContext[]> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const userListKey = `${SESSION_REDIS_NAMESPACE}:user_sessions:${userId}`;
      const sessionIds = await this.client.sMembers(userListKey);

      const sessions: SessionContext[] = [];
      for (const sessionId of sessionIds) {
        const session = await this.getSession(sessionId);
        if (session) {
          sessions.push(session);
        }
      }

      return sessions;
    } catch (error: any) {
      logger.error('Failed to retrieve user sessions from Redis', { userId, error: error.message });
      throw error;
    }
  }

  // Audit event storage
  async storeAuditEvent(sessionId: string, event: SessionAuditEvent): Promise<void> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:events:${sessionId}`;
      const serialized = JSON.stringify(event);
      await this.client.rPush(key, serialized);
      // Expire list after TTL
      await this.client.expire(key, SESSION_REDIS_TTL_SECONDS);

      logger.debug('Audit event stored', { sessionId, eventId: event.eventId });
    } catch (error: any) {
      logger.error('Failed to store audit event', { sessionId, error: error.message });
      throw error;
    }
  }

  async getAuditEvents(sessionId: string): Promise<SessionAuditEvent[]> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:events:${sessionId}`;
      const data = await this.client.lRange(key, 0, -1);

      return data.map((item) => JSON.parse(item) as SessionAuditEvent);
    } catch (error: any) {
      logger.error('Failed to retrieve audit events', { sessionId, error: error.message });
      throw error;
    }
  }

  // Deletion manifest storage
  async storeDeletionManifest(sessionId: string, manifest: any): Promise<void> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:deletion:${sessionId}`;
      const serialized = JSON.stringify(manifest);
      await this.client.setEx(key, SESSION_REDIS_TTL_SECONDS * 2, serialized); // 2x TTL for deletions
      logger.debug('Deletion manifest stored', { sessionId });
    } catch (error: any) {
      logger.error('Failed to store deletion manifest', { sessionId, error: error.message });
      throw error;
    }
  }

  async getDeletionManifest(sessionId: string): Promise<any | null> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:deletion:${sessionId}`;
      const data = await this.client.get(key);
      return data ? JSON.parse(data) : null;
    } catch (error: any) {
      logger.error('Failed to retrieve deletion manifest', { sessionId, error: error.message });
      throw error;
    }
  }

  // Shadow replay artifact storage
  async storeShadowReplayArtifact(sessionId: string, artifact: any): Promise<void> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:shadow_replay:${sessionId}`;
      const serialized = JSON.stringify(artifact);
      await this.client.setEx(key, SESSION_REDIS_TTL_SECONDS * 2, serialized);
      logger.debug('Shadow replay artifact stored', { sessionId });
    } catch (error: any) {
      logger.error('Failed to store shadow replay artifact', { sessionId, error: error.message });
      throw error;
    }
  }

  async getShadowReplayArtifact(sessionId: string): Promise<any | null> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const key = `${SESSION_REDIS_NAMESPACE}:shadow_replay:${sessionId}`;
      const data = await this.client.get(key);
      return data ? JSON.parse(data) : null;
    } catch (error: any) {
      logger.error('Failed to retrieve shadow replay artifact', { sessionId, error: error.message });
      throw error;
    }
  }

  // Health checks and metrics
  async healthCheck(): Promise<boolean> {
    if (!this.client) return false;

    try {
      await this.client.ping();
      return true;
    } catch (error: any) {
      logger.error('Redis health check failed', { error: error.message });
      return false;
    }
  }

  async getMetrics(): Promise<any> {
    if (!this.client) throw new Error('Redis client not connected');

    try {
      const listKey = `${SESSION_REDIS_NAMESPACE}:list:sessions`;
      const sessionCount = await this.client.sCard(listKey);

      // Estimate memory usage (rough approximation)
      const info = await this.client.info('memory');
      const memoryMatch = info.match(/used_memory:(\d+)/);
      const memoryUsageBytes = memoryMatch ? Number(memoryMatch[1]) : 0;

      return {
        connected: this.connected,
        sessionCount,
        memoryUsageBytes,
      };
    } catch (error: any) {
      logger.error('Failed to gather Redis metrics', { error: error.message });
      throw error;
    }
  }

  // Cleanup and close connection
  async close(): Promise<void> {
    if (this.client) {
      try {
        await this.client.quit();
        this.connected = false;
        logger.info('Redis session store closed');
      } catch (error: any) {
        logger.error('Error closing Redis connection', { error: error.message });
        throw error;
      }
    }
  }
}

export default RedisSessionStore;
