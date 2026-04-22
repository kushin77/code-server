#!/usr/bin/env node
/**
 * @file        scripts/integrations/slack-slash-commands-api.js
 * @module      integrations/slack
 * @description REST API for Slack slash commands with immutable session tokens
 */

const express = require('express');
const SlackSlashCommandsService = require('./slack-slash-commands-service');

const app = express();
const PORT = process.env.PORT || 9096;

// Initialize service
const slackService = new SlackSlashCommandsService({
    slackSigningSecret: process.env.SLACK_SIGNING_SECRET,
    slackBotToken: process.env.SLACK_BOT_TOKEN,
    workspaceUrl: process.env.WORKSPACE_URL || 'https://ide.kushnir.cloud',
});

// Idempotency cache for Slack commands
const slackCommandCache = new Map(); // triggerId → commandResult

// Event listeners
slackService.on('code-review-created', (context) => {
    console.log(`[Slack] Code review session: ${context.sessionId}`);
    console.log(`  Initiator: ${context.initiator}`);
    console.log(`  Reviewers: ${context.reviewers.join(', ')}`);
    console.log(`  Files: ${context.files.join(', ')}`);
    console.log(`  URL: ${context.url}`);
});

slackService.on('workspace-share-created', (context) => {
    console.log(`[Slack] Workspace share session: ${context.sessionId}`);
    console.log(`  Initiator: ${context.initiator}`);
    console.log(`  Duration: ${context.duration}`);
    console.log(`  URL: ${context.url}`);
});

// Middleware
app.use(express.raw({ type: 'application/x-www-form-urlencoded' }));
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'slack-slash-commands' });
});

// Slack slash command webhook
app.post('/slack/commands', (req, res) => {
    try {
        // Validate Slack signature
        const signature = req.headers['x-slack-signature'];
        const timestamp = req.headers['x-slack-request-timestamp'];
        const body = req.body;
        
        // For raw bodies
        let bodyStr = body;
        if (typeof body !== 'string') {
            bodyStr = JSON.stringify(body);
        }
        
        // Note: In production, validate signature
        // const isValid = slackService.validateSlackSignature({ 
        //     'x-slack-signature': signature,
        //     'x-slack-request-timestamp': timestamp 
        // }, bodyStr);
        // if (!isValid) return res.status(401).json({ error: 'Invalid signature' });
        
        // Parse command
        const command = typeof body === 'string' 
            ? new URLSearchParams(body)
            : body;
        
        const slashCommand = command.command || command.get('command');
        const triggerId = command.trigger_id || command.get('trigger_id');
        
        // Idempotency check - Slack trigger_id is unique per command invocation
        if (triggerId && slackCommandCache.has(triggerId)) {
            const cachedResult = slackCommandCache.get(triggerId);
            return res.json({
                ...cachedResult,
                cached: true
            });
        }
        
        // Handle command
        let result;
        
        if (slashCommand === '/code-review') {
            result = slackService.handleCodeReviewCommand({
                team_id: command.team_id || command.get('team_id'),
                user_id: command.user_id || command.get('user_id'),
                user_name: command.user_name || command.get('user_name'),
                channel_id: command.channel_id || command.get('channel_id'),
                channel_name: command.channel_name || command.get('channel_name'),
                trigger_id: triggerId,
                text: command.text || command.get('text'),
            });
        } else if (slashCommand === '/workspace-share') {
            result = slackService.handleWorkspaceShareCommand({
                team_id: command.team_id || command.get('team_id'),
                user_id: command.user_id || command.get('user_id'),
                user_name: command.user_name || command.get('user_name'),
                channel_id: command.channel_id || command.get('channel_id'),
                channel_name: command.channel_name || command.get('channel_name'),
                trigger_id: triggerId,
                text: command.text || command.get('text'),
            });
        }
        
        // Freeze result for immutability and cache for idempotency
        const frozenResult = Object.freeze({
            response_type: result.response_type || 'in_channel',
            text: result.text,
            blocks: result.blocks ? Object.freeze(result.blocks) : undefined,
            cached: false,
            timestamp: new Date().toISOString()
        });
        
        if (triggerId) {
            slackCommandCache.set(triggerId, frozenResult);
        }
        
        res.json(frozenResult);
            blocks: [
                {
                    type: 'section',
                    text: {
                        type: 'mrkdwn',
                        text: result.status === 'created'
                            ? `✅ Session created\n<${result.url}|Join session>\nExpires: ${result.expiresAt}`
                            : `ℹ️ Session already exists\n<${result.url}|Join session>`,
                    },
                },
            ],
        });
    } catch (err) {
        console.error('[Slack] Command error:', err);
        res.status(400).json({ error: err.message });
    }
});

// Get session details
app.get('/sessions/:sessionId', (req, res) => {
    try {
        const details = slackService.getSessionDetails(req.params.sessionId);
        
        if (!details) {
            return res.status(404).json({ error: 'Session not found' });
        }
        
        res.json(details);
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get user sessions
app.get('/users/:userId/sessions', (req, res) => {
    try {
        const sessions = slackService.getUserSessions(req.params.userId);
        res.json({
            userId: req.params.userId,
            total: sessions.length,
            sessions,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Validate session token
app.post('/sessions/:sessionId/validate', (req, res) => {
    try {
        const { token } = req.body;
        const isValid = slackService.validateSessionToken(req.params.sessionId, token);
        
        res.json({
            sessionId: req.params.sessionId,
            valid: isValid,
            timestamp: new Date().toISOString(),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Post session to Slack
app.post('/sessions/:sessionId/post-to-slack', (req, res) => {
    try {
        const { channelId } = req.body;
        const message = slackService.postSessionToSlack(req.params.sessionId, channelId);
        
        res.json({
            status: 'prepared',
            message,
            note: 'Use Slack Bot API to send this message',
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Slack Slash Commands API] Listening on port ${PORT}`);
    console.log(`[Slack Slash Commands API] POST /slack/commands - Slash command webhook`);
    console.log(`[Slack Slash Commands API] GET /sessions/:sessionId - Get session details`);
    console.log(`[Slack Slash Commands API] GET /users/:userId/sessions - Get user sessions`);
    console.log(`[Slack Slash Commands API] POST /sessions/:sessionId/validate - Validate token`);
});
