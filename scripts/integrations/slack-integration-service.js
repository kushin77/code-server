#!/usr/bin/env node
/**
 * @file        scripts/integrations/slack-integration-service.js
 * @module      integrations/slack
 * @description Slack integration service with slash command handling and shared sessions
 */

const axios = require('axios');
const crypto = require('crypto');
const EventEmitter = require('events');

class SlackIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.botToken = options.botToken || process.env.SLACK_BOT_TOKEN;
        this.signingSecret = options.signingSecret || process.env.SLACK_SIGNING_SECRET;
        this.appId = options.appId || process.env.SLACK_APP_ID;
        this.workspaceUrl = options.workspaceUrl || process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
        
        this.slackApiUrl = 'https://slack.com/api';
        this.sessionCache = new Map(); // Store session metadata
        this.sessionTTL = 60 * 60 * 1000; // 1 hour default
    }
    
    /**
     * Verify Slack request signature
     */
    verifySignature(timestamp, signature, body) {
        // Check timestamp is recent (within 5 minutes)
        const now = Math.floor(Date.now() / 1000);
        if (Math.abs(now - parseInt(timestamp)) > 300) {
            return false;
        }
        
        // Verify signature
        const baseString = \`v0:\${timestamp}:\${body}\`;
        const computedSignature = 'v0=' + crypto
            .createHmac('sha256', this.signingSecret)
            .update(baseString)
            .digest('hex');
        
        return crypto.timingSafeEqual(
            Buffer.from(signature),
            Buffer.from(computedSignature)
        );
    }
    
    /**
     * Handle /code-review slash command
     */
    async handleCodeReviewCommand(userId, userName, channelId, text) {
        try {
            // Parse command: /code-review @user file.ts [options]
            const args = text.trim().split(/\s+/);
            const mentionedUser = args[0]?.replace('@', '');
            const filePath = args[1] || 'root';
            const options = args.slice(2);
            
            // Create shared session
            const sessionId = this._generateSessionId();
            const expiryTime = new Date(Date.now() + this.sessionTTL);
            
            const sessionData = {
                id: sessionId,
                initiator: { userId, userName },
                reviewee: mentionedUser,
                filePath,
                channelId,
                createdAt: new Date(),
                expiresAt: expiryTime,
                options: {
                    readOnly: false,
                    cursorTracking: true,
                    liveTypeChecking: options.includes('--strict'),
                    recordSession: options.includes('--record')
                }
            };
            
            // Store session metadata
            this.sessionCache.set(sessionId, sessionData);
            
            // Generate session URL
            const sessionUrl = this._buildSessionUrl(sessionId, sessionData);
            
            // Post message to Slack with session link
            await this._postSessionMessage(channelId, {
                initiator: userName,
                reviewee: mentionedUser,
                filePath,
                sessionUrl,
                expiryTime,
                sessionId
            });
            
            this.emit('code-review-session-created', {
                sessionId,
                initiator: userName,
                reviewee: mentionedUser,
                channel: channelId
            });
            
            return {
                success: true,
                sessionId,
                url: sessionUrl,
                expiresAt: expiryTime
            };
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to create code review session',
                error: error.message,
                command: 'code-review'
            });
            throw error;
        }
    }
    
    /**
     * Handle /open-file slash command
     */
    async handleOpenFileCommand(userId, channelId, text) {
        try {
            const filePath = text.trim().split(/\s+/)[0];
            
            if (!filePath) {
                return {
                    success: false,
                    error: 'Please specify a file path: /open-file src/app.ts'
                };
            }
            
            const url = \`\${this.workspaceUrl}?file=\${encodeURIComponent(filePath)}\`;
            
            await axios.post(\`\${this.slackApiUrl}/chat.postMessage\`, {
                channel: channelId,
                blocks: [
                    {
                        type: 'section',
                        text: {
                            type: 'mrkdwn',
                            text: \`📁 Opening file: *\${filePath}*\`
                        }
                    },
                    {
                        type: 'actions',
                        elements: [
                            {
                                type: 'button',
                                text: {
                                    type: 'plain_text',
                                    text: '🚀 Open in IDE'
                                },
                                url,
                                action_id: 'open_file_btn'
                            }
                        ]
                    }
                ]
            }, {
                headers: {
                    'Authorization': \`Bearer \${this.botToken}\`,
                    'Content-Type': 'application/json'
                }
            });
            
            this.emit('file-opened', { filePath, userId });
            return { success: true, url };
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to handle open-file command',
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Get session metadata
     */
    async getSessionMetadata(sessionId) {
        const session = this.sessionCache.get(sessionId);
        
        if (!session) {
            return { error: 'Session not found or expired' };
        }
        
        // Check expiry
        if (new Date() > new Date(session.expiresAt)) {
            this.sessionCache.delete(sessionId);
            return { error: 'Session expired' };
        }
        
        return {
            success: true,
            session: {
                id: session.id,
                initiator: session.initiator,
                reviewee: session.reviewee,
                filePath: session.filePath,
                createdAt: session.createdAt,
                expiresAt: session.expiresAt,
                options: session.options
            }
        };
    }
    
    /**
     * Post interactive session message to Slack
     */
    async _postSessionMessage(channelId, sessionData) {
        const timeRemaining = this._formatTimeRemaining(sessionData.expiryTime);
        
        try {
            await axios.post(\`\${this.slackApiUrl}/chat.postMessage\`, {
                channel: channelId,
                blocks: [
                    {
                        type: 'header',
                        text: {
                            type: 'plain_text',
                            text: '🔍 Code Review Session',
                            emoji: true
                        }
                    },
                    {
                        type: 'section',
                        fields: [
                            {
                                type: 'mrkdwn',
                                text: \`*Initiated by:* @\${sessionData.initiator}\`
                            },
                            {
                                type: 'mrkdwn',
                                text: \`*Reviewee:* @\${sessionData.reviewee}\`
                            },
                            {
                                type: 'mrkdwn',
                                text: \`*File:* \\\`\${sessionData.filePath}\\\`\`
                            },
                            {
                                type: 'mrkdwn',
                                text: \`*Expires:* \${timeRemaining}\`
                            }
                        ]
                    },
                    {
                        type: 'section',
                        text: {
                            type: 'mrkdwn',
                            text: '*Session Link:*'
                        }
                    },
                    {
                        type: 'actions',
                        elements: [
                            {
                                type: 'button',
                                text: {
                                    type: 'plain_text',
                                    text: '🚀 Join Session'
                                },
                                url: sessionData.sessionUrl,
                                style: 'primary',
                                action_id: 'join_session_btn'
                            }
                        ]
                    }
                ]
            }, {
                headers: {
                    'Authorization': \`Bearer \${this.botToken}\`,
                    'Content-Type': 'application/json'
                }
            });
            
            this.emit('session-message-posted', { channelId });
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to post session message to Slack',
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Build session URL with parameters
     */
    _buildSessionUrl(sessionId, sessionData) {
        const params = new URLSearchParams({
            session: sessionId,
            file: sessionData.filePath,
            mode: 'collaborative',
            readonly: sessionData.options.readOnly ? 'true' : 'false'
        });
        
        return \`\${this.workspaceUrl}/session?\${params.toString()}\`;
    }
    
    /**
     * Generate session ID
     */
    _generateSessionId() {
        return \`slack-\${Date.now()}-\${crypto.randomBytes(8).toString('hex')}\`;
    }
    
    /**
     * Format time remaining for display
     */
    _formatTimeRemaining(expiryTime) {
        const now = new Date();
        const diffMs = expiryTime - now;
        const diffMins = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMins / 60);
        
        if (diffHours > 0) {
            return \`in \${diffHours}h\${diffMins % 60}m\`;
        } else {
            return \`in \${diffMins}m\`;
        }
    }
    
    /**
     * Send ephemeral message (visible to one user)
     */
    async sendEphemeralMessage(userId, channelId, text) {
        try {
            await axios.post(\`\${this.slackApiUrl}/chat.postEphemeral\`, {
                user: userId,
                channel: channelId,
                text
            }, {
                headers: {
                    'Authorization': \`Bearer \${this.botToken}\`,
                    'Content-Type': 'application/json'
                }
            });
            
            this.emit('ephemeral-message-sent', { userId });
            
        } catch (error) {
            this.emit('error', {
                message: 'Failed to send ephemeral message',
                error: error.message
            });
            throw error;
        }
    }
    
    /**
     * Clear expired sessions
     */
    cleanupExpiredSessions() {
        let removed = 0;
        for (const [sessionId, session] of this.sessionCache.entries()) {
            if (new Date() > new Date(session.expiresAt)) {
                this.sessionCache.delete(sessionId);
                removed++;
            }
        }
        
        if (removed > 0) {
            this.emit('sessions-cleaned', { removed, remaining: this.sessionCache.size });
        }
        
        return removed;
    }
}

module.exports = SlackIntegrationService;
