#!/usr/bin/env node
/**
 * @file        scripts/integrations/slack-slash-commands-service.js
 * @module      integrations/slack
 * @description Slack slash commands for code review sessions with immutable session tokens
 *
 * IaC Principles:
 * - Immutable: Session tokens frozen once created
 * - Idempotent: Same slash command = same session (via idempotency key)
 * - Versioned: Session versions for audit trail
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class SlackSlashCommandsService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.slackSigningSecret = options.slackSigningSecret || process.env.SLACK_SIGNING_SECRET;
        this.slackBotToken = options.slackBotToken || process.env.SLACK_BOT_TOKEN;
        this.workspaceUrl = options.workspaceUrl || process.env.WORKSPACE_URL || 'https://ide.kushnir.cloud';
        
        // Immutable sessions (versioned, frozen)
        this.sessions = new Map(); // sessionId → frozen session
        this.sessionsByUserId = new Map(); // userId → [sessionId, ...]
        this.sessionsByTeamId = new Map(); // teamId → [sessionId, ...]
        
        // Idempotent command tracking
        this.commandTokens = new Map(); // commandToken → processed timestamp
    }
    
    /**
     * Validate Slack request signature
     */
    validateSlackSignature(headers, body) {
        const signature = headers['x-slack-signature'];
        const timestamp = headers['x-slack-request-timestamp'];
        
        // Prevent replay attacks (5 minute window)
        const now = Math.floor(Date.now() / 1000);
        if (Math.abs(now - parseInt(timestamp)) > 300) {
            return false;
        }
        
        const baseString = `v0:${timestamp}:${body}`;
        const hash = crypto
            .createHmac('sha256', this.slackSigningSecret)
            .update(baseString)
            .digest('hex');
        
        return `v0=${hash}` === signature;
    }
    
    /**
     * Handle /code-review command (immutable, idempotent)
     * Usage: /code-review @alice src/auth.ts
     */
    async handleCodeReviewCommand(commandData) {
        const commandToken = `${commandData.team_id}-${commandData.trigger_id}-${commandData.user_id}`;
        
        // Idempotent: if already processed, return existing
        if (this.commandTokens.has(commandToken)) {
            const sessionId = this.findSessionByToken(commandToken);
            if (sessionId) {
                const session = this.sessions.get(sessionId);
                return {
                    status: 'already-created',
                    sessionId,
                    url: session.url,
                };
            }
        }
        
        // Parse command
        const parts = commandData.text.split(/\s+/);
        const reviewers = parts.filter(p => p.startsWith('@')).map(p => p.slice(1));
        const files = parts.filter(p => !p.startsWith('@'));
        
        // Create immutable session
        const session = {
            // Immutable identifiers
            id: `session-${crypto.randomUUID()}`,
            commandToken,
            workspaceId: commandData.team_id,
            initiatorId: commandData.user_id,
            initiatorName: commandData.user_name,
            
            // Session context (immutable)
            reviewers,
            files,
            channelId: commandData.channel_id,
            channelName: commandData.channel_name,
            
            // Immutable session token
            sessionToken: crypto.randomBytes(32).toString('hex'),
            
            // Expiry (immutable once created)
            createdAt: new Date().toISOString(),
            expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(), // 24h
            ttlSeconds: 86400,
            
            // Status
            status: 'active',
            
            // Session URL
            url: `${this.workspaceUrl}/review/${crypto.randomBytes(16).toString('hex')}?token=${this.hashToken(crypto.randomBytes(32).toString('hex'))}`,
            
            // Version for audit
            version: 1,
        };
        
        // Freeze session for immutability
        Object.freeze(session);
        this.sessions.set(session.id, session);
        
        // Track by user and team
        if (!this.sessionsByUserId.has(commandData.user_id)) {
            this.sessionsByUserId.set(commandData.user_id, []);
        }
        this.sessionsByUserId.get(commandData.user_id).push(session.id);
        
        if (!this.sessionsByTeamId.has(commandData.team_id)) {
            this.sessionsByTeamId.set(commandData.team_id, []);
        }
        this.sessionsByTeamId.get(commandData.team_id).push(session.id);
        
        // Mark command as processed (idempotent)
        this.commandTokens.set(commandToken, new Date().toISOString());
        
        this.emit('code-review-created', {
            sessionId: session.id,
            initiator: commandData.user_name,
            reviewers,
            files,
            url: session.url,
        });
        
        return {
            status: 'created',
            sessionId: session.id,
            url: session.url,
            expiresAt: session.expiresAt,
        };
    }
    
    /**
     * Handle /workspace-share command (immutable, idempotent)
     * Usage: /workspace-share --duration 30m --users @alice @bob
     */
    async handleWorkspaceShareCommand(commandData) {
        const commandToken = `${commandData.team_id}-${commandData.trigger_id}-${commandData.user_id}`;
        
        // Idempotent: if already processed, return existing
        if (this.commandTokens.has(commandToken)) {
            const sessionId = this.findSessionByToken(commandToken);
            if (sessionId) {
                const session = this.sessions.get(sessionId);
                return {
                    status: 'already-created',
                    sessionId,
                    url: session.url,
                };
            }
        }
        
        // Parse command
        const args = this.parseWorkspaceShareArgs(commandData.text);
        
        // Create immutable session
        const session = {
            // Immutable identifiers
            id: `session-${crypto.randomUUID()}`,
            commandToken,
            type: 'workspace-share',
            workspaceId: commandData.team_id,
            initiatorId: commandData.user_id,
            initiatorName: commandData.user_name,
            
            // Share context (immutable)
            sharedUsers: args.users || [],
            sharedChannels: args.channels || [],
            permissions: args.permissions || ['view', 'comment'],
            
            // Expiry (immutable)
            createdAt: new Date().toISOString(),
            expiresAt: new Date(Date.now() + args.durationMs).toISOString(),
            ttlSeconds: Math.round(args.durationMs / 1000),
            
            // Status
            status: 'active',
            
            // Session URL
            url: `${this.workspaceUrl}/share/${crypto.randomBytes(16).toString('hex')}?token=${this.hashToken(crypto.randomBytes(32).toString('hex'))}`,
            
            // Version for audit
            version: 1,
        };
        
        // Freeze session for immutability
        Object.freeze(session);
        this.sessions.set(session.id, session);
        
        // Track by user
        if (!this.sessionsByUserId.has(commandData.user_id)) {
            this.sessionsByUserId.set(commandData.user_id, []);
        }
        this.sessionsByUserId.get(commandData.user_id).push(session.id);
        
        // Mark command as processed (idempotent)
        this.commandTokens.set(commandToken, new Date().toISOString());
        
        this.emit('workspace-share-created', {
            sessionId: session.id,
            initiator: commandData.user_name,
            sharedUsers: args.users,
            duration: args.duration,
            url: session.url,
        });
        
        return {
            status: 'created',
            sessionId: session.id,
            url: session.url,
            duration: args.duration,
            expiresAt: session.expiresAt,
        };
    }
    
    /**
     * Parse workspace share arguments
     */
    parseWorkspaceShareArgs(text) {
        const args = {
            users: [],
            channels: [],
            permissions: ['view', 'comment'],
            duration: '30m',
            durationMs: 30 * 60 * 1000,
        };
        
        // Parse --duration
        const durationMatch = text.match(/--duration\s+(\d+[smh])/);
        if (durationMatch) {
            const val = durationMatch[1];
            const num = parseInt(val);
            const unit = val.replace(/\d/g, '');
            
            if (unit === 's') args.durationMs = num * 1000;
            else if (unit === 'm') args.durationMs = num * 60 * 1000;
            else if (unit === 'h') args.durationMs = num * 60 * 60 * 1000;
            
            args.duration = durationMatch[1];
        }
        
        // Parse --users
        const usersMatch = text.match(/--users\s+([@\w\s]+?)(?=--|\s*$)/);
        if (usersMatch) {
            args.users = usersMatch[1]
                .split(/\s+/)
                .filter(u => u)
                .map(u => u.replace('@', ''));
        }
        
        return args;
    }
    
    /**
     * Find session by command token
     */
    findSessionByToken(commandToken) {
        for (const [sessionId, session] of this.sessions) {
            if (session.commandToken === commandToken) {
                return sessionId;
            }
        }
        return null;
    }
    
    /**
     * Hash session token
     */
    hashToken(token) {
        return crypto
            .createHash('sha256')
            .update(token)
            .digest('hex');
    }
    
    /**
     * Get session details (immutable snapshot)
     */
    getSessionDetails(sessionId) {
        const session = this.sessions.get(sessionId);
        if (!session) return null;
        
        const now = Date.now();
        const expiresAt = new Date(session.expiresAt).getTime();
        
        return Object.freeze({
            id: session.id,
            type: session.type || 'code-review',
            status: expiresAt < now ? 'expired' : session.status,
            initiator: session.initiatorName,
            
            // Context
            reviewers: session.reviewers,
            files: session.files,
            sharedUsers: session.sharedUsers,
            permissions: session.permissions,
            
            // Expiry
            createdAt: session.createdAt,
            expiresAt: session.expiresAt,
            timeRemaining: Math.max(0, Math.round((expiresAt - now) / 1000)),
            
            // URL
            url: session.url,
        });
    }
    
    /**
     * Get active sessions for user (immutable snapshot)
     */
    getUserSessions(userId) {
        const sessionIds = this.sessionsByUserId.get(userId) || [];
        const sessions = [];
        
        const now = Date.now();
        
        for (const sessionId of sessionIds) {
            const session = this.sessions.get(sessionId);
            if (!session) continue;
            
            const expiresAt = new Date(session.expiresAt).getTime();
            if (expiresAt >= now) {
                sessions.push({
                    id: session.id,
                    type: session.type || 'code-review',
                    initiator: session.initiatorName,
                    createdAt: session.createdAt,
                    expiresAt: session.expiresAt,
                    url: session.url,
                });
            }
        }
        
        return Object.freeze(sessions);
    }
    
    /**
     * Validate session token
     */
    validateSessionToken(sessionId, token) {
        const session = this.sessions.get(sessionId);
        if (!session) return false;
        
        const now = Date.now();
        const expiresAt = new Date(session.expiresAt).getTime();
        
        if (expiresAt < now) return false; // Expired
        
        // Check token
        const tokenHash = this.hashToken(token);
        return tokenHash === session.sessionToken || token === session.sessionToken;
    }
    
    /**
     * Post message to Slack (immutable session link)
     */
    async postSessionToSlack(sessionId, channelId) {
        const session = this.sessions.get(sessionId);
        if (!session) throw new Error('Session not found');
        
        const blocks = [
            {
                type: 'section',
                text: {
                    type: 'mrkdwn',
                    text: `👉 *Code Review Session Started*\n*Initiated by* ${session.initiatorName}\n*Reviewers*: ${session.reviewers.join(', ')}\n*Files*: ${session.files.join(', ')}`,
                },
            },
            {
                type: 'section',
                text: {
                    type: 'mrkdwn',
                    text: `🔗 *Join Session*\n<${session.url}|Click to join code review>\n\n⏰ *Expires* ${new Date(session.expiresAt).toLocaleString()}`,
                },
            },
        ];
        
        return {
            channel: channelId,
            blocks,
            text: `Code review session: ${session.url}`,
        };
    }
}

module.exports = SlackSlashCommandsService;
