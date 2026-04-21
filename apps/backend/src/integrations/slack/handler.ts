// @file        apps/backend/src/integrations/slack/handler.ts
// @module      integrations/slack
// @description Slack slash command handler for IDE session sharing

import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { createHmac } from 'crypto';
import Redis from 'ioredis';

const SLACK_SIGNING_SECRET = process.env.SLACK_SIGNING_SECRET || '';
const SLACK_BOT_TOKEN = process.env.SLACK_BOT_TOKEN || '';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const SESSION_TTL_SECONDS = parseInt(process.env.SLACK_SESSION_TTL_SECONDS || '86400'); // 24 hours
const IDE_BASE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';

interface SlackShareRequest {
  token: string;
  team_id: string;
  api_app_id: string;
  command: string;
  text: string;
  user_id: string;
  user_name: string;
  team_domain: string;
  enterprise_id?: string;
  is_enterprise_install: boolean;
  channel_id: string;
  channel_name: string;
  response_url: string;
  trigger_id: string;
}

interface SharedSession {
  sessionId: string;
  createdBy: {
    userId: string;
    userName: string;
    teamId: string;
  };
  createdAt: number;
  expiresAt: number;
  shareUrl: string;
  channelId: string;
  repositoryPath?: string;
}

const redis = new Redis(REDIS_URL);

/**
 * Verify Slack request signature
 */
function verifySlackRequest(req: Request): boolean {
  const slackSignature = req.headers['x-slack-signature'] as string;
  const timestamp = req.headers['x-slack-request-timestamp'] as string;
  const body = req.rawBody as string;
  const slackSigningSecret = process.env.SLACK_SIGNING_SECRET || '';

  if (!slackSignature || !timestamp) {
    return false;
  }

  // Verify timestamp is within 5 minutes
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - parseInt(timestamp)) > 300) {
    return false;
  }

  // Verify signature
  const baseString = `v0:${timestamp}:${body}`;
  const hash = createHmac('sha256', slackSigningSecret)
    .update(baseString)
    .digest('hex');
  const computedSignature = `v0=${hash}`;

  return computedSignature === slackSignature;
}

/**
 * Create a shared IDE session
 */
async function createSharedSession(
  userId: string,
  userName: string,
  teamId: string,
  channelId: string,
  repositoryPath?: string
): Promise<SharedSession> {
  const sessionId = uuidv4();
  const createdAt = Date.now();
  const expiresAt = createdAt + SESSION_TTL_SECONDS * 1000;

  const session: SharedSession = {
    sessionId,
    createdBy: { userId, userName, teamId },
    createdAt,
    expiresAt,
    shareUrl: `${IDE_BASE_URL}/share/${sessionId}`,
    channelId,
    repositoryPath,
  };

  // Store session in Redis with TTL
  const key = `slack:session:${sessionId}`;
  await redis.setex(key, SESSION_TTL_SECONDS, JSON.stringify(session));

  // Index by channel for quick lookup
  const channelKey = `slack:channel:${channelId}:sessions`;
  await redis.lpush(channelKey, sessionId);
  await redis.expire(channelKey, SESSION_TTL_SECONDS);

  return session;
}

/**
 * Handler for /share-ide slash command
 */
async function handleShareIdeCommand(req: Request, res: Response): Promise<void> {
  try {
    // Verify request
    if (!verifySlackRequest(req)) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const payload = req.body as SlackShareRequest;

    // Validate request
    if (payload.command !== '/share-ide') {
      res.status(400).json({ error: 'Invalid command' });
      return;
    }

    // Create shared session
    const session = await createSharedSession(
      payload.user_id,
      payload.user_name,
      payload.team_id,
      payload.channel_id,
      payload.text.trim() || undefined
    );

    // Format response message
    const message = {
      response_type: 'in_channel',
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `🚀 <@${payload.user_id}> launched a shared IDE session!`,
          },
        },
        {
          type: 'section',
          fields: [
            {
              type: 'mrkdwn',
              text: `*Session ID:*\n\`${session.sessionId}\``,
            },
            {
              type: 'mrkdwn',
              text: `*Expires:*\n<!date^${Math.floor(session.expiresAt / 1000)}^{date_long_pretty} at {time}|${new Date(session.expiresAt).toISOString()}>`,
            },
            {
              type: 'mrkdwn',
              text: session.repositoryPath
                ? `*Repository:*\n\`${session.repositoryPath}\``
                : '*Repository:*\nDefault',
            },
            {
              type: 'mrkdwn',
              text: `*Max Users:*\n10 concurrent`,
            },
          ],
        },
        {
          type: 'actions',
          elements: [
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: 'Join Session',
                emoji: true,
              },
              url: session.shareUrl,
              action_id: 'join_session',
              style: 'primary',
            },
            {
              type: 'button',
              text: {
                type: 'plain_text',
                text: 'Copy Link',
                emoji: true,
              },
              action_id: 'copy_link',
              value: session.shareUrl,
            },
          ],
        },
        {
          type: 'context',
          elements: [
            {
              type: 'mrkdwn',
              text: `Session will auto-terminate when last user disconnects or after 24 hours, whichever comes first.`,
            },
          ],
        },
      ],
    };

    // Respond immediately with Slack format
    res.status(200).json(message);

    // Log session creation
    console.log(`[Slack] Shared session created: ${session.sessionId}`, {
      initiator: payload.user_name,
      channel: payload.channel_name,
      repository: session.repositoryPath || 'default',
      expiresAt: new Date(session.expiresAt).toISOString(),
    });
  } catch (error) {
    console.error('[Slack] Error handling share-ide command:', error);
    res.status(500).json({
      response_type: 'ephemeral',
      text: '❌ Failed to create shared session. Please try again later.',
    });
  }
}

/**
 * Retrieve session info by ID
 */
async function getSessionInfo(sessionId: string): Promise<SharedSession | null> {
  const key = `slack:session:${sessionId}`;
  const data = await redis.get(key);
  return data ? (JSON.parse(data) as SharedSession) : null;
}

/**
 * List active sessions for a channel
 */
async function getChannelSessions(channelId: string): Promise<SharedSession[]> {
  const key = `slack:channel:${channelId}:sessions`;
  const sessionIds = await redis.lrange(key, 0, -1);

  const sessions: SharedSession[] = [];
  for (const sessionId of sessionIds) {
    const session = await getSessionInfo(sessionId);
    if (session) {
      sessions.push(session);
    }
  }

  return sessions;
}

/**
 * Revoke session
 */
async function revokeSession(sessionId: string): Promise<boolean> {
  const key = `slack:session:${sessionId}`;
  const result = await redis.del(key);
  return result > 0;
}

// Export handlers and utilities
export {
  handleShareIdeCommand,
  getSessionInfo,
  getChannelSessions,
  revokeSession,
  createSharedSession,
  verifySlackRequest,
  type SlackShareRequest,
  type SharedSession,
};
