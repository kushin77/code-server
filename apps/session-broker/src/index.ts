#!/usr/bin/env ts-node
// @file        apps/session-broker/src/index.ts
// @module      session-management/broker
// @description Session broker service for per-user/per-session code-server isolation.
//              Routes authenticated users to isolated container contexts with resource quotas
//              and lifecycle management.
//

import express, { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';
import Docker from 'dockerode';
import { Pool as PgPool } from 'pg';
import winston from 'winston';
import Joi from 'joi';
import axios from 'axios';
import cookieParser from 'cookie-parser';

// ────────────────────────────────────────────────────────────────────────────
// Logging Setup
// ────────────────────────────────────────────────────────────────────────────

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'session-broker.log' })
  ]
});

// ────────────────────────────────────────────────────────────────────────────
// Type Definitions
// ────────────────────────────────────────────────────────────────────────────

interface SessionContext {
  sessionId: string;
  userId: string;
  username: string;
  email: string;
  containerName: string;
  containerId?: string;
  containerPort: number;
  baseImageId: string;
  createdAt: Date;
  expiresAt: Date;
  quotas: {
    cpuLimit: string;      // e.g., "2.0"
    memoryLimit: string;   // e.g., "4g"
    storageLimit: string;  // e.g., "50g"
  };
  status: 'creating' | 'running' | 'paused' | 'terminated';
  lastActivity: Date;
}

interface ContainerConfig {
  image: string;
  hostname: string;
  cpuLimit: string;
  memoryLimit: string;
  portMapping: { host: number; container: number };
  volumes: { [containerPath: string]: { bind: string; 'ro': boolean } };
  env: { [key: string]: string };
}

// ────────────────────────────────────────────────────────────────────────────
// Session Manager Class
// ────────────────────────────────────────────────────────────────────────────

class SessionManager {
  private docker: Docker;
  private db: PgPool;
  private sessions: Map<string, SessionContext> = new Map();
  private nextPort: number = 8081; // Start at 8081 (8080 is primary)

  constructor(dockerSocket: string, dbUrl: string) {
    const socketPath = dockerSocket.replace('unix://', '');
    this.docker = new Docker({ socketPath });
    this.db = new PgPool({ connectionString: dbUrl });
    logger.info('SessionManager initialized', { socketPath, dbUrl });
  }

  /**
   * Create isolated session for authenticated user
   */
  async createSession(userId: string, username: string, email: string, ttlSeconds: number = 28800): Promise<SessionContext> {
    const sessionId = uuidv4();
    const containerName = `code-server-${username}-${sessionId.substring(0, 8)}`;
    const containerPort = this.nextPort++;

    logger.info('Creating session', { sessionId, userId, username, containerPort });

    const session: SessionContext = {
      sessionId,
      userId,
      username,
      email,
      containerName,
      containerPort,
      baseImageId: process.env.CODE_SERVER_IMAGE_ID || 'code-server-enterprise:dev',
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + ttlSeconds * 1000),
      quotas: {
        cpuLimit: process.env.SESSION_CPU_LIMIT || '2.0',
        memoryLimit: process.env.SESSION_MEMORY_LIMIT || '4g',
        storageLimit: process.env.SESSION_STORAGE_LIMIT || '50g'
      },
      status: 'creating',
      lastActivity: new Date()
    };

    try {
      // Create container configuration
      const containerConfig = this.buildContainerConfig(session);

      // Create Docker container
      const container = await this.docker.createContainer({
        name: containerName,
        Hostname: containerConfig.hostname,
        Image: containerConfig.image,
        Env: Object.entries(containerConfig.env).map(([k, v]) => `${k}=${v}`),
        ExposedPorts: {
          '8080/tcp': {}
        },
        HostConfig: {
          PortBindings: {
            '8080/tcp': [{ HostPort: String(containerPort) }]
          },
          Binds: Object.entries(containerConfig.volumes).map(
            ([target, src]) => `${src.bind}:${target}:${src.ro ? 'ro' : 'rw'}`
          ),
          CpuQuota: parseInt(containerConfig.cpuLimit.replace(/^(\d+)\..*$/, '$1000000'), 10),
          Memory: this.parseMemory(containerConfig.memoryLimit)
        }
      });

      const containerId = container.id;
      session.containerId = containerId;

      // Start container
      await container.start();
      session.status = 'running';

      // Persist to database
      await this.persistSession(session);

      // Store in memory
      this.sessions.set(sessionId, session);

      logger.info('Session created successfully', {
        sessionId,
        containerId: containerId.substring(0, 12),
        containerName,
        containerPort,
        expiresAt: session.expiresAt
      });

      return session;
    } catch (error) {
      logger.error('Failed to create session', { sessionId, error: String(error) });
      session.status = 'terminated';
      throw new Error(`Session creation failed: ${error}`);
    }
  }

  /**
   * Get existing session by ID
   */
  async getSession(sessionId: string): Promise<SessionContext | null> {
    // Check memory cache first
    if (this.sessions.has(sessionId)) {
      const session = this.sessions.get(sessionId)!;
      session.lastActivity = new Date();
      return session;
    }

    // Load from database
    try {
      const result = await this.db.query(
        'SELECT * FROM sessions WHERE session_id = $1 AND status != $2',
        [sessionId, 'terminated']
      );
      if (result.rows.length > 0) {
        const dbSession = this.dbRowToSession(result.rows[0]);
        this.sessions.set(sessionId, dbSession);
        return dbSession;
      }
    } catch (error) {
      logger.error('Database query failed', { sessionId, error: String(error) });
    }

    return null;
  }

  /**
   * Get active session for a user (returns most recent/active one)
   */
  async getUserActiveSession(userId: string): Promise<SessionContext | null> {
    try {
      const result = await this.db.query(
        `SELECT * FROM sessions 
         WHERE user_id = $1 AND status = $2
         ORDER BY last_activity DESC 
         LIMIT 1`,
        [userId, 'running']
      );
      if (result.rows.length > 0) {
        const dbSession = this.dbRowToSession(result.rows[0]);
        this.sessions.set(dbSession.sessionId, dbSession);
        return dbSession;
      }
    } catch (error) {
      logger.error('Failed to get user session', { userId, error: String(error) });
    }
    return null;
  }

  /**
   * Terminate session and clean up container
   */
  async terminateSession(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      logger.warn('Session not found for termination', { sessionId });
      return;
    }

    logger.info('Terminating session', { sessionId, containerId: session.containerId });

    try {
      if (session.containerId) {
        const container = this.docker.getContainer(session.containerId);
        
        // Stop container
        await container.stop({ t: 10 });

        // Remove container
        await container.remove({ v: true });
      }

      session.status = 'terminated';
      await this.persistSession(session);
      this.sessions.delete(sessionId);

      logger.info('Session terminated successfully', { sessionId });
    } catch (error) {
      logger.error('Failed to terminate session', { sessionId, error: String(error) });
      throw error;
    }
  }

  /**
   * List all active sessions for a user
   */
  async listUserSessions(userId: string): Promise<SessionContext[]> {
    try {
      const result = await this.db.query(
        'SELECT * FROM sessions WHERE user_id = $1 AND status = $2 ORDER BY created_at DESC',
        [userId, 'running']
      );
      return result.rows.map((row: any) => this.dbRowToSession(row));
    } catch (error) {
      logger.error('Failed to list user sessions', { userId, error: String(error) });
      return [];
    }
  }

  /**
   * Update session activity timestamp
   */
  async updateActivity(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.lastActivity = new Date();
      await this.persistSession(session);
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Private Helper Methods
  // ────────────────────────────────────────────────────────────────────────

  private buildContainerConfig(session: SessionContext): ContainerConfig {
    const homeDir = `/home/${session.username}`;
    return {
      image: session.baseImageId,
      hostname: session.containerName,
      cpuLimit: session.quotas.cpuLimit,
      memoryLimit: session.quotas.memoryLimit,
      portMapping: { host: session.containerPort, container: 8080 },
      volumes: {
        '/home/coder/workspace': {
          bind: `/sessions/${session.sessionId}/workspace`,
          ro: false
        },
        '/home/coder/.local/share/code-server': {
          bind: `/sessions/${session.sessionId}/profile`,
          ro: false
        }
      },
      env: {
        PASSWORD: process.env.CODE_SERVER_PASSWORD || 'changeme',
        SUDO_PASSWORD: process.env.CODE_SERVER_PASSWORD || 'changeme',
        SERVICE_URL: 'https://open-vsx.org/vscode/gallery',
        ITEM_URL: 'https://open-vsx.org/vscode/item',
        CS_DISABLE_FILE_DOWNLOADS: 'false',
        NODE_OPTIONS: '--max-old-space-size=2048',
        SESSION_ID: session.sessionId,
        USER_ID: session.userId,
        USERNAME: session.username,
        USER_EMAIL: session.email,
        CONTAINER_NAME: session.containerName,
        EXPIRES_AT: session.expiresAt.toISOString()
      }
    };
  }

  private parseMemory(memStr: string): number {
    const match = memStr.match(/^(\d+)([kmg])$/i);
    if (!match) return 4 * 1024 * 1024 * 1024; // Default 4g
    const [, value, unit] = match;
    const bytes = parseInt(value, 10);
    switch (unit.toLowerCase()) {
      case 'k': return bytes * 1024;
      case 'm': return bytes * 1024 * 1024;
      case 'g': return bytes * 1024 * 1024 * 1024;
      default: return bytes;
    }
  }

  private async persistSession(session: SessionContext): Promise<void> {
    try {
      await this.db.query(
        `INSERT INTO sessions (session_id, user_id, username, email, container_id, container_name, 
         container_port, created_at, expires_at, status, last_activity, quotas, base_image_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
         ON CONFLICT (session_id) DO UPDATE SET
         status = $10, last_activity = $11, container_id = $5`,
        [
          session.sessionId,
          session.userId,
          session.username,
          session.email,
          session.containerId || null,
          session.containerName,
          session.containerPort,
          session.createdAt,
          session.expiresAt,
          session.status,
          session.lastActivity,
          JSON.stringify(session.quotas),
          session.baseImageId
        ]
      );
    } catch (error) {
      logger.error('Failed to persist session', { sessionId: session.sessionId, error: String(error) });
    }
  }

  private dbRowToSession(row: any): SessionContext {
    return {
      sessionId: row.session_id,
      userId: row.user_id,
      username: row.username,
      email: row.email,
      containerName: row.container_name,
      containerId: row.container_id,
      containerPort: row.container_port,
      baseImageId: row.base_image_id,
      createdAt: new Date(row.created_at),
      expiresAt: new Date(row.expires_at),
      quotas: row.quotas || {},
      status: row.status as SessionContext['status'],
      lastActivity: new Date(row.last_activity)
    };
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Express Application Setup
// ────────────────────────────────────────────────────────────────────────────

const app = express();
const manager = new SessionManager(
  process.env.DOCKER_SOCKET || 'unix:///var/run/docker.sock',
  process.env.DATABASE_URL || 'postgres://localhost/code-server'
);

app.use(express.json());
app.use(cookieParser());

// ────────────────────────────────────────────────────────────────────────────
// Authentication Middleware (Phase 2 Integration)
// ────────────────────────────────────────────────────────────────────────────

interface AuthUser {
  userId: string;
  username: string;
  email: string;
}

type BrokerRequest = Request & { authUser?: AuthUser };

const getAuthUser = (req: Request): AuthUser | null => {
  // Check for X-Auth-Request headers set by oauth2-proxy
  const email = req.headers['x-auth-request-email'] as string;
  const user = req.headers['x-auth-request-user'] as string;

  if (!email || !user) {
    return null;
  }

  return {
    userId: user || email.split('@')[0],
    username: user || email.split('@')[0],
    email: email
  };
};

// Middleware: Check auth and extract user info
app.use((req: Request, res: Response, next: NextFunction) => {
  // Skip auth for health checks, oauth2 routes, and public endpoints
  if (req.path === '/health' || req.path.startsWith('/oauth2') || req.path === '/ping') {
    return next();
  }

  const authUser = getAuthUser(req);
  if (authUser) {
    (req as BrokerRequest).authUser = authUser;
  }
  next();
});

// ────────────────────────────────────────────────────────────────────────────
// Request Logging Middleware
// ────────────────────────────────────────────────────────────────────────────

app.use((req: Request, res: Response, next: NextFunction) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    const logEntry: any = {
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip
    };
    const sessionId = req.cookies._code_server_session_id;
    const authUser = (req as BrokerRequest).authUser;

    if (authUser) {
      logEntry.userId = authUser.userId;
      logEntry.username = authUser.username;
      logEntry.email = authUser.email;
    }

    if (sessionId) {
      logEntry.sessionId = sessionId;
    }

    // Log different levels based on status code
    if (res.statusCode >= 500) {
      logger.error('Activity: Server Error', logEntry);
    } else if (res.statusCode >= 400) {
      logger.warn('Activity: Client Error', logEntry);
    } else {
      logger.info('Activity', logEntry);
    }
  });
  next();
});

// ────────────────────────────────────────────────────────────────────────────
// Routes
// ────────────────────────────────────────────────────────────────────────────

/**
 * POST /sessions
 * Create new isolated session for authenticated user
 */
app.post('/sessions', async (req: Request, res: Response) => {
  const schema = Joi.object({
    userId: Joi.string().uuid().required(),
    username: Joi.string().alphanum().min(3).max(32).required(),
    email: Joi.string().email().required(),
    ttlSeconds: Joi.number().min(3600).max(86400).default(28800)
  });

  const { error, value } = schema.validate(req.body);
  if (error) {
    return res.status(400).json({ error: error.message });
  }

  try {
    const session = await manager.createSession(
      value.userId,
      value.username,
      value.email,
      value.ttlSeconds
    );
    res.status(201).json({
      sessionId: session.sessionId,
      containerPort: session.containerPort,
      containerName: session.containerName,
      url: `http://localhost:${session.containerPort}`,
      expiresAt: session.expiresAt
    });
  } catch (error) {
    logger.error('Session creation API error', { error: String(error) });
    res.status(500).json({ error: 'Failed to create session' });
  }
});

/**
 * POST /oauth2/callback (Phase 2 Integration)
 * Hook called by oauth2-proxy on successful authentication
 * Creates a session immediately upon successful auth (for earlier session bootstrap)
 */
app.post('/oauth2/callback', async (req: Request, res: Response) => {
  try {
    // Extract user info from oauth2-proxy headers (should be set by oauth2-proxy on successful auth)
    const email = req.headers['x-auth-request-email'] as string;
    const username = req.headers['x-auth-request-user'] as string;

    if (!email || !username) {
      logger.warn('oauth2 callback missing auth headers');
      return res.status(400).json({ error: 'Missing authentication headers' });
    }

    // Create session for the newly authenticated user
    const userId = username || email.split('@')[0];
    let session = await manager.getUserActiveSession(userId);

    if (!session) {
      logger.info('Creating session on oauth2 callback', { userId, email });
      session = await manager.createSession(userId, username, email, 86400);
    } else {
      logger.info('Session already exists for user', { userId, sessionId: session.sessionId });
    }

    res.json({
      sessionId: session.sessionId,
      containerPort: session.containerPort,
      url: `http://localhost:${session.containerPort}`
    });
  } catch (error) {
    logger.error('OAuth2 callback error', { error: String(error) });
    res.status(500).json({ error: 'Failed to create session' });
  }
});

/**
 * POST /oauth2/logout (Phase 2 Integration)
 * Clean up user's session on logout
 * Called by oauth2-proxy sign_out flow
 */
app.post('/oauth2/logout', async (req: Request, res: Response) => {
  try {
    const rawSessionId = req.body?.sessionId ?? req.headers['x-session-id'];
    const sessionId = Array.isArray(rawSessionId) ? rawSessionId[0] : rawSessionId;
    
    if (sessionId) {
      logger.info('Terminating session on logout', { sessionId });
      await manager.terminateSession(sessionId);
    }

    res.status(204).send();
  } catch (error) {
    logger.error('Logout error', { error: String(error) });
    res.status(500).json({ error: 'Failed to logout' });
  }
});

/**
 * GET /sessions/:sessionId
 * Retrieve session details and status
 */
app.get('/sessions/:sessionId', async (req: Request, res: Response) => {
  try {
    const session = await manager.getSession(req.params.sessionId);
    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }
    res.json({
      sessionId: session.sessionId,
      status: session.status,
      containerPort: session.containerPort,
      containerName: session.containerName,
      url: `http://localhost:${session.containerPort}`,
      expiresAt: session.expiresAt,
      lastActivity: session.lastActivity,
      quotas: session.quotas
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to retrieve session' });
  }
});

/**
 * DELETE /sessions/:sessionId
 * Terminate session and clean up resources
 */
app.delete('/sessions/:sessionId', async (req: Request, res: Response) => {
  try {
    await manager.terminateSession(req.params.sessionId);
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: 'Failed to terminate session' });
  }
});

/**
 * GET /users/:userId/sessions
 * List all active sessions for a user
 */
app.get('/users/:userId/sessions', async (req: Request, res: Response) => {
  try {
    const sessions = await manager.listUserSessions(req.params.userId);
    res.json({
      userId: req.params.userId,
      sessions: sessions.map(s => ({
        sessionId: s.sessionId,
        status: s.status,
        containerPort: s.containerPort,
        createdAt: s.createdAt,
        expiresAt: s.expiresAt,
        lastActivity: s.lastActivity
      }))
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to list sessions' });
  }
});

/**
 * PUT /sessions/:sessionId/activity
 * Update session activity timestamp (keep-alive)
 */
app.put('/sessions/:sessionId/activity', async (req: Request, res: Response) => {
  try {
    await manager.updateActivity(req.params.sessionId);
    res.status(204).send();
  } catch (error) {
    res.status(500).json({ error: 'Failed to update activity' });
  }
});

/**
 * Health check endpoint
 */
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'healthy' });
});

/**
 * Default route handler (Phase 2 Integration)
 * Routes authenticated requests to user's isolated session container
 * Redirects unauthenticated requests to oauth2-proxy for authentication
 */
app.all('*', async (req: Request, res: Response) => {
  try {
    const authUser = (req as BrokerRequest).authUser;

    // Redirect unauthenticated requests to oauth2-proxy
    if (!authUser) {
      logger.warn('Unauthenticated request', { path: req.path, ip: req.ip });
      // oauth2-proxy will handle the redirect to /oauth2/start
      return res.redirect('/oauth2/start');
    }

    logger.info('Authenticated request', {
      path: req.path,
      user: authUser.username,
      email: authUser.email
    });

    // Get or create session for authenticated user
    let session = await manager.getUserActiveSession(authUser.userId);

    if (!session) {
      // Create new session
      logger.info('Creating new session', { userId: authUser.userId });
      session = await manager.createSession(
        authUser.userId,
        authUser.username,
        authUser.email,
        86400 // 24 hour TTL
      );
    }

    // Update last activity
    await manager.updateActivity(session.sessionId);

    // Set session cookie
    res.cookie('_code_server_session_id', session.sessionId, {
      httpOnly: true,
      secure: true,
      sameSite: 'lax',
      maxAge: 86400 * 1000
    });

    logger.info('Proxying to session container', {
      sessionId: session.sessionId,
      containerPort: session.containerPort,
      path: req.path
    });

    // Proxy request to the user's session container
    const targetUrl = `http://localhost:${session.containerPort}${req.path}${req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : ''}`;
    
    // Use axios for simpler proxying
    try {
      const response = await axios({
        method: req.method,
        url: targetUrl,
        headers: req.headers as Record<string, string>,
        data: req.method !== 'GET' && req.method !== 'HEAD' ? req.body : undefined,
        validateStatus: () => true // Accept all status codes
      });

      res.status(response.status);
      Object.entries(response.headers).forEach(([key, value]) => {
        if (!['content-encoding', 'transfer-encoding'].includes(key.toLowerCase())) {
          res.setHeader(key, value);
        }
      });
      res.send(response.data);
    } catch (proxyError) {
      logger.error('Proxy error', {
        sessionId: session.sessionId,
        targetUrl,
        error: String(proxyError)
      });
      res.status(503).json({ error: 'Session unavailable' });
    }
  } catch (error) {
    logger.error('Request handler error', { error: String(error), path: req.path });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ────────────────────────────────────────────────────────────────────────────
// Server Startup
// ────────────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  logger.info(`Session broker listening on port ${PORT}`);
});
