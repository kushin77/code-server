#!/usr/bin/env node
/**
 * @file        scripts/integrations/slack-integration-api.js
 * @module      integrations/slack
 * @description Slack integration REST API for slash commands and interactions
 */

const express = require('express');
const SlackIntegrationService = require('./slack-integration-service');

const app = express();
const PORT = process.env.SLACK_API_PORT || 9097;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Initialize service
const slackService = new SlackIntegrationService({
    botToken: process.env.SLACK_BOT_TOKEN,
    signingSecret: process.env.SLACK_SIGNING_SECRET,
    appId: process.env.SLACK_APP_ID,
    workspaceUrl: process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud'
});

// Event listeners
slackService.on('code-review-session-created', (data) => {
    console.log(`[Slack API] 📋 Code review session created: ${data.sessionId}`);
    console.log(`[Slack API]    Initiator: ${data.initiator}, Reviewee: ${data.reviewee}`);
});

slackService.on('session-message-posted', (data) => {
    console.log(`[Slack API] 💬 Session message posted to channel ${data.channelId}`);
});

slackService.on('file-opened', (data) => {
    console.log(`[Slack API] 📂 File opened: ${data.filePath}`);
});

slackService.on('sessions-cleaned', (data) => {
    console.log(`[Slack API] 🧹 Cleaned up ${data.removed} expired sessions`);
});

slackService.on('error', (data) => {
    console.error(`[Slack API] ❌ Error: ${data.message}`, data.error);
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'slack-integration-api', version: '1.0.0' });
});

/**
 * POST /slack/events
 * Slack event subscription endpoint (URL verification, slash commands, interactions)
 */
app.post('/slack/events', async (req, res) => {
    try {
        const timestamp = req.get('x-slack-request-timestamp');
        const signature = req.get('x-slack-signature');
        
        // Verify request signature
        const rawBody = JSON.stringify(req.body);
        if (!slackService.verifySignature(timestamp, signature, rawBody)) {
            console.warn('[Slack API] Invalid signature');
            return res.status(401).json({ error: 'Invalid signature' });
        }
        
        const { type, challenge, event } = req.body;
        
        // URL verification
        if (type === 'url_verification') {
            return res.json({ challenge });
        }
        
        // Handle events
        if (type === 'event_callback' && event) {
            res.json({ ok: true }); // Acknowledge immediately
            
            switch (event.type) {
                case 'app_mention':
                    await _handleAppMention(event);
                    break;
                case 'slash_commands':
                    await _handleSlashCommand(event);
                    break;
                case 'message':
                    await _handleMessage(event);
                    break;
            }
        } else {
            res.json({ ok: true });
        }
        
    } catch (error) {
        console.error('[Slack API] Error handling event:', error);
        res.status(500).json({ error: error.message });
    }
});

/**
 * POST /slack/slash/code-review
 * Handle /code-review slash command
 */
app.post('/slack/slash/code-review', async (req, res) => {
    try {
        const timestamp = req.get('x-slack-request-timestamp');
        const signature = req.get('x-slack-signature');
        
        // Verify signature
        const rawBody = req.rawBody || '';
        if (!slackService.verifySignature(timestamp, signature, rawBody)) {
            return res.status(401).json({ error: 'Invalid signature' });
        }
        
        const { user_id, user_name, channel_id, text } = req.body;
        
        const result = await slackService.handleCodeReviewCommand(
            user_id,
            user_name,
            channel_id,
            text
        );
        
        res.json({
            response_type: 'in_channel',
            text: `✅ Code review session created: ${result.url}`
        });
        
    } catch (error) {
        res.status(500).json({
            response_type: 'ephemeral',
            text: `❌ Error: ${error.message}`
        });
    }
});

/**
 * POST /slack/slash/open-file
 * Handle /open-file slash command
 */
app.post('/slack/slash/open-file', async (req, res) => {
    try {
        const timestamp = req.get('x-slack-request-timestamp');
        const signature = req.get('x-slack-signature');
        
        // Verify signature
        const rawBody = req.rawBody || '';
        if (!slackService.verifySignature(timestamp, signature, rawBody)) {
            return res.status(401).json({ error: 'Invalid signature' });
        }
        
        const { user_id, channel_id, text } = req.body;
        
        const result = await slackService.handleOpenFileCommand(
            user_id,
            channel_id,
            text
        );
        
        if (result.success) {
            res.json({
                response_type: 'ephemeral',
                text: `📂 Opening file...`
            });
        } else {
            res.json({
                response_type: 'ephemeral',
                text: `❌ ${result.error}`
            });
        }
        
    } catch (error) {
        res.status(500).json({
            response_type: 'ephemeral',
            text: `❌ Error: ${error.message}`
        });
    }
});

/**
 * GET /slack/session/:sessionId
 * Get session metadata
 */
app.get('/slack/session/:sessionId', async (req, res) => {
    try {
        const { sessionId } = req.params;
        
        const result = await slackService.getSessionMetadata(sessionId);
        
        if (result.error) {
            return res.status(404).json({ error: result.error });
        }
        
        res.json(result);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

/**
 * POST /slack/interactions
 * Handle interactive components (buttons, select menus, etc.)
 */
app.post('/slack/interactions', async (req, res) => {
    try {
        const timestamp = req.get('x-slack-request-timestamp');
        const signature = req.get('x-slack-signature');
        
        // Verify signature
        const rawBody = req.rawBody || '';
        if (!slackService.verifySignature(timestamp, signature, rawBody)) {
            return res.status(401).json({ error: 'Invalid signature' });
        }
        
        const payload = JSON.parse(req.body.payload);
        
        // Acknowledge immediately
        res.json({ ok: true });
        
        // Handle action
        const { type, actions, user, channel } = payload;
        
        if (type === 'block_actions' && actions) {
            for (const action of actions) {
                console.log(`[Slack API] 🔘 Action: ${action.action_id}`);
                
                // Handle specific actions
                switch (action.action_id) {
                    case 'join_session_btn':
                        console.log(`[Slack API] User ${user.id} joined session`);
                        break;
                    case 'open_file_btn':
                        console.log(`[Slack API] User ${user.id} opened file`);
                        break;
                }
            }
        }
        
    } catch (error) {
        console.error('[Slack API] Error handling interaction:', error);
        res.status(500).json({ error: error.message });
    }
});

/**
 * POST /slack/cleanup
 * Manually trigger session cleanup
 */
app.post('/slack/cleanup', (req, res) => {
    const removed = slackService.cleanupExpiredSessions();
    
    res.json({
        success: true,
        message: `Cleaned up ${removed} expired sessions`,
        remaining: slackService.sessionCache.size
    });
});

// Helper functions
async function _handleAppMention(event) {
    console.log(`[Slack API] 👥 App mentioned in channel ${event.channel}`);
}

async function _handleSlashCommand(event) {
    console.log(`[Slack API] ⚡ Slash command: ${event.command}`);
}

async function _handleMessage(event) {
    if (!event.bot_id) {
        console.log(`[Slack API] 💬 Message from user ${event.user} in channel ${event.channel}`);
    }
}

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('[Slack API] Unhandled error:', err);
    res.status(500).json({
        error: 'Internal server error',
        message: err.message
    });
});

// Start server
const server = app.listen(PORT, () => {
    console.log(`[Slack API] 🚀 Server running on port ${PORT}`);
    console.log(`[Slack API] Slack App ID: ${slackService.appId}`);
    console.log(`[Slack API] Workspace URL: ${slackService.workspaceUrl}`);
    console.log(`[Slack API] Health check: http://localhost:${PORT}/health`);
});

// Periodic cleanup of expired sessions (every 5 minutes)
setInterval(() => {
    slackService.cleanupExpiredSessions();
}, 5 * 60 * 1000);

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('[Slack API] SIGTERM received, shutting down gracefully...');
    server.close(() => {
        console.log('[Slack API] Server closed');
        process.exit(0);
    });
});

module.exports = { app, server, slackService };
