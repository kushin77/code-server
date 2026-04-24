// @file        apps/backend/src/services/shared-clipboard/index.ts
// @module      collaboration/shared-clipboard
// @description In-memory shared clipboard sessions with credential blocking and capped history

import { randomUUID } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { Router, type Request, type Response } from 'express';
import { getLogger } from '../../lib/logger.js';

export interface SharedClipboardParticipant {
  userId: string;
  userName: string;
  joinedAt: string;
  lastSeenAt: string;
}

export interface SharedClipboardHistoryEntry {
  entryId: string;
  sessionId: string;
  userId: string;
  userName: string;
  text: string;
  copiedAt: string;
}

export interface SharedClipboardSessionRecord {
  sessionId: string;
  workspaceId: string;
  ownerId: string;
  ownerName: string;
  participants: SharedClipboardParticipant[];
  history: SharedClipboardHistoryEntry[];
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
  lastCopiedAt: string | null;
}

export interface CreateSharedClipboardSessionInput {
  workspaceId: string;
  userId: string;
  userName?: string;
}

export interface JoinSharedClipboardSessionInput {
  userId: string;
  userName?: string;
}

export interface CopySharedClipboardInput {
  userId: string;
  userName?: string;
  text: string;
}

export interface SharedClipboardOptions {
  historyLimit?: number;
}

const DEFAULT_HISTORY_LIMIT = 20;

const CREDENTIAL_PATTERNS: RegExp[] = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/i,
  /(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})/i,
  /AKIA[0-9A-Z]{16}/,
  /ASIA[0-9A-Z]{16}/,
  /xox[baprs]-[A-Za-z0-9-]{10,}/i,
  /Bearer\s+[A-Za-z0-9\-._~+/]+=*/i,
];

const normalizeText = (value: unknown, fallback = ''): string => {
  if (typeof value !== 'string') {
    return fallback;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : fallback;
};

const normalizeClipboardText = (value: unknown): string => {
  return typeof value === 'string' ? value : '';
};

const requireText = (value: unknown, field: string): string => {
  const text = normalizeText(value);
  if (!text) {
    throw new Error(`Missing required field: ${field}`);
  }

  return text;
};

const cloneParticipant = (participant: SharedClipboardParticipant): SharedClipboardParticipant => ({
  ...participant,
});

const cloneEntry = (entry: SharedClipboardHistoryEntry): SharedClipboardHistoryEntry => ({
  ...entry,
});

const cloneSession = (session: SharedClipboardSessionRecord): SharedClipboardSessionRecord => ({
  ...session,
  participants: session.participants.map(cloneParticipant),
  history: session.history.map(cloneEntry),
});

const isCredentialLike = (text: string): boolean => CREDENTIAL_PATTERNS.some((pattern) => pattern.test(text));

export class SharedClipboardService extends EventEmitter {
  private readonly logger = getLogger('SharedClipboardService');
  private readonly historyLimit: number;
  private readonly sessions = new Map<string, SharedClipboardSessionRecord>();

  constructor(options: SharedClipboardOptions = {}) {
    super();
    this.historyLimit = options.historyLimit ?? DEFAULT_HISTORY_LIMIT;
  }

  createSession(input: CreateSharedClipboardSessionInput): SharedClipboardSessionRecord {
    const workspaceId = requireText(input.workspaceId, 'workspaceId');
    const userId = requireText(input.userId, 'userId');
    const userName = normalizeText(input.userName, userId);
    const timestamp = new Date().toISOString();

    const session: SharedClipboardSessionRecord = {
      sessionId: `clipboard-${randomUUID()}`,
      workspaceId,
      ownerId: userId,
      ownerName: userName,
      participants: [
        {
          userId,
          userName,
          joinedAt: timestamp,
          lastSeenAt: timestamp,
        },
      ],
      history: [],
      isActive: true,
      createdAt: timestamp,
      updatedAt: timestamp,
      lastCopiedAt: null,
    };

    this.sessions.set(session.sessionId, session);
    this.emit('session_created', cloneSession(session));
    this.logger.info('Created shared clipboard session', { sessionId: session.sessionId, workspaceId });

    return cloneSession(session);
  }

  joinSession(sessionId: string, input: JoinSharedClipboardSessionInput): SharedClipboardSessionRecord {
    const session = this.requireSession(sessionId);
    const userId = requireText(input.userId, 'userId');
    const userName = normalizeText(input.userName, userId);
    const timestamp = new Date().toISOString();

    const participant = session.participants.find((entry) => entry.userId === userId);
    if (participant) {
      participant.userName = userName;
      participant.lastSeenAt = timestamp;
    } else {
      session.participants.push({
        userId,
        userName,
        joinedAt: timestamp,
        lastSeenAt: timestamp,
      });
    }

    session.updatedAt = timestamp;
    this.emit('participant_joined', { sessionId, userId, userName });
    return cloneSession(session);
  }

  leaveSession(sessionId: string, userId: string): SharedClipboardSessionRecord {
    const session = this.requireSession(sessionId);
    const normalizedUserId = requireText(userId, 'userId');
    const timestamp = new Date().toISOString();

    session.participants = session.participants.filter((participant) => participant.userId !== normalizedUserId);
    session.updatedAt = timestamp;

    this.emit('participant_left', { sessionId, userId: normalizedUserId });
    return cloneSession(session);
  }

  copyText(sessionId: string, input: CopySharedClipboardInput): SharedClipboardHistoryEntry {
    const session = this.requireSession(sessionId);
    const userId = requireText(input.userId, 'userId');
    const userName = normalizeText(input.userName, userId);
    const text = normalizeClipboardText(input.text);

    if (!text) {
      throw new Error('Clipboard text is required');
    }

    if (!session.participants.some((participant) => participant.userId === userId)) {
      throw new Error('User is not a participant in this clipboard session');
    }

    if (isCredentialLike(text)) {
      throw new Error('Clipboard content looks like a credential and was blocked');
    }

    const copiedAt = new Date().toISOString();
    const entry: SharedClipboardHistoryEntry = {
      entryId: `clipboard-entry-${randomUUID()}`,
      sessionId,
      userId,
      userName,
      text,
      copiedAt,
    };

    session.history.push(entry);
    if (session.history.length > this.historyLimit) {
      session.history = session.history.slice(session.history.length - this.historyLimit);
    }

    session.updatedAt = copiedAt;
    session.lastCopiedAt = copiedAt;

    this.emit('clipboard_copied', cloneEntry(entry));
    return cloneEntry(entry);
  }

  getSession(sessionId: string): SharedClipboardSessionRecord | null {
    const session = this.sessions.get(requireText(sessionId, 'sessionId'));
    return session ? cloneSession(session) : null;
  }

  listWorkspaceSessions(workspaceId: string): SharedClipboardSessionRecord[] {
    const normalizedWorkspaceId = requireText(workspaceId, 'workspaceId');
    return Array.from(this.sessions.values())
      .filter((session) => session.workspaceId === normalizedWorkspaceId)
      .map(cloneSession);
  }

  getHistory(sessionId: string): SharedClipboardHistoryEntry[] {
    return this.requireSession(sessionId).history.map(cloneEntry);
  }

  private requireSession(sessionId: string): SharedClipboardSessionRecord {
    const normalizedSessionId = requireText(sessionId, 'sessionId');
    const session = this.sessions.get(normalizedSessionId);

    if (!session) {
      throw new Error(`Shared clipboard session not found: ${normalizedSessionId}`);
    }

    return session;
  }
}

const authenticate = (_req: Request, _res: Response, next: (error?: unknown) => void): void => next();

export function initializeSharedClipboardRoutes(service: SharedClipboardService): Router {
  const router = Router();
  const logger = getLogger('SharedClipboardRoutes');

  router.post('/api/shared-clipboard/sessions', authenticate, (req: Request, res: Response) => {
    try {
      const session = service.createSession({
        workspaceId: req.body?.workspaceId,
        userId: req.body?.userId,
        userName: req.body?.userName,
      });

      res.status(201).json({ session });
    } catch (error) {
      logger.error('Failed to create shared clipboard session', { error });
      res.status(400).json({ error: error instanceof Error ? error.message : 'Failed to create session' });
    }
  });

  router.post('/api/shared-clipboard/sessions/:sessionId/join', authenticate, (req: Request, res: Response) => {
    try {
      const session = service.joinSession(req.params.sessionId, {
        userId: req.body?.userId,
        userName: req.body?.userName,
      });

      res.json({ session });
    } catch (error) {
      logger.error('Failed to join shared clipboard session', { error, sessionId: req.params.sessionId });
      res.status(400).json({ error: error instanceof Error ? error.message : 'Failed to join session' });
    }
  });

  router.post('/api/shared-clipboard/sessions/:sessionId/leave', authenticate, (req: Request, res: Response) => {
    try {
      const session = service.leaveSession(req.params.sessionId, req.body?.userId);

      res.json({ session });
    } catch (error) {
      logger.error('Failed to leave shared clipboard session', { error, sessionId: req.params.sessionId });
      res.status(400).json({ error: error instanceof Error ? error.message : 'Failed to leave session' });
    }
  });

  router.post('/api/shared-clipboard/sessions/:sessionId/copy', authenticate, (req: Request, res: Response) => {
    try {
      const entry = service.copyText(req.params.sessionId, {
        userId: req.body?.userId,
        userName: req.body?.userName,
        text: req.body?.text,
      });

      res.status(201).json({ entry, history: service.getHistory(req.params.sessionId) });
    } catch (error) {
      logger.error('Failed to sync shared clipboard text', { error, sessionId: req.params.sessionId });
      res.status(400).json({ error: error instanceof Error ? error.message : 'Failed to sync clipboard' });
    }
  });

  router.get('/api/shared-clipboard/sessions/:sessionId', authenticate, (req: Request, res: Response) => {
    try {
      const session = service.getSession(req.params.sessionId);

      if (!session) {
        return res.status(404).json({ error: 'Session not found' });
      }

      res.json({ session });
    } catch (error) {
      logger.error('Failed to fetch shared clipboard session', { error, sessionId: req.params.sessionId });
      res.status(500).json({ error: 'Failed to fetch session' });
    }
  });

  router.get('/api/shared-clipboard/sessions/:sessionId/history', authenticate, (req: Request, res: Response) => {
    try {
      res.json({
        history: service.getHistory(req.params.sessionId),
        session: service.getSession(req.params.sessionId),
      });
    } catch (error) {
      logger.error('Failed to fetch shared clipboard history', { error, sessionId: req.params.sessionId });
      res.status(400).json({ error: error instanceof Error ? error.message : 'Failed to fetch history' });
    }
  });

  router.get('/api/shared-clipboard/workspaces/:workspaceId/sessions', authenticate, (req: Request, res: Response) => {
    try {
      const sessions = service.listWorkspaceSessions(req.params.workspaceId);
      res.json({ sessions, count: sessions.length });
    } catch (error) {
      logger.error('Failed to list shared clipboard sessions', { error, workspaceId: req.params.workspaceId });
      res.status(400).json({ error: error instanceof Error ? error.message : 'Failed to list sessions' });
    }
  });

  return router;
}
