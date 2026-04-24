#!/usr/bin/env node
// @file        apps/backend/src/routes/session-recording.ts
// @module      routes/session-recording
// @description Routes for session recording, playback, export, and sharing

import { Router, Request, Response } from 'express';
import service, { ExportOptions } from '../services/session/session-recording-service';
import { getLogger } from '../lib/logger';

const logger = getLogger('SessionRecordingRoutes');
const router = Router();

/**
 * Start recording a session
 * POST /api/sessions/:sessionId/recording/start
 */
router.post('/sessions/:sessionId/recording/start', (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;
    const { userId, workspaceId } = req.body;

    if (!sessionId || !userId || !workspaceId) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: sessionId, userId, workspaceId',
      });
    }

    const recording = service.startRecording(sessionId, userId, workspaceId);

    res.status(201).json({
      success: true,
      data: recording,
    });
  } catch (error) {
    logger.error(`Failed to start recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Stop recording
 * POST /api/recordings/:recordingId/stop
 */
router.post('/recordings/:recordingId/stop', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const recording = service.stopRecording(recordingId);
    if (!recording) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found or already stopped',
      });
    }

    res.status(200).json({ success: true, data: recording });
  } catch (error) {
    logger.error(`Failed to stop recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Pause recording
 * POST /api/recordings/:recordingId/pause
 */
router.post('/recordings/:recordingId/pause', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.pauseRecording(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found or not active',
      });
    }

    const recording = service.getRecording(recordingId);
    res.status(200).json({ success: true, data: recording });
  } catch (error) {
    logger.error(`Failed to pause recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Resume recording
 * POST /api/recordings/:recordingId/resume
 */
router.post('/recordings/:recordingId/resume', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.resumeRecording(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found or not active',
      });
    }

    const recording = service.getRecording(recordingId);
    res.status(200).json({ success: true, data: recording });
  } catch (error) {
    logger.error(`Failed to resume recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get recording details
 * GET /api/recordings/:recordingId
 */
router.get('/recordings/:recordingId', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const recording = service.getRecording(recordingId);
    if (!recording) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found',
      });
    }

    res.status(200).json({ success: true, data: recording });
  } catch (error) {
    logger.error(`Failed to get recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Delete recording
 * DELETE /api/recordings/:recordingId
 */
router.delete('/recordings/:recordingId', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.deleteRecording(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found',
      });
    }

    res.status(200).json({
      success: true,
      data: { recordingId, deleted: true },
    });
  } catch (error) {
    logger.error(`Failed to delete recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * List recordings for a session
 * GET /api/sessions/:sessionId/recordings
 */
router.get('/sessions/:sessionId/recordings', (req: Request, res: Response) => {
  try {
    const { sessionId } = req.params;

    const recordings = service.listRecordingsForSession(sessionId);

    res.status(200).json({
      success: true,
      data: recordings,
      count: recordings.length,
    });
  } catch (error) {
    logger.error(`Failed to list session recordings: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * List recordings for a user
 * GET /api/users/:userId/recordings
 */
router.get('/users/:userId/recordings', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    const recordings = service.listRecordingsForUser(userId);

    res.status(200).json({
      success: true,
      data: recordings,
      count: recordings.length,
    });
  } catch (error) {
    logger.error(`Failed to list user recordings: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Record file change
 * POST /api/recordings/:recordingId/file
 */
router.post('/recordings/:recordingId/file', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const change = req.body;

    const result = service.recordFileChange(recordingId, change);
    if (!result) {
      return res.status(400).json({
        success: false,
        error: 'Failed to record file change',
      });
    }

    res.status(200).json({ success: true, data: { recorded: true } });
  } catch (error) {
    logger.error(`Failed to record file change: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Record terminal event
 * POST /api/recordings/:recordingId/terminal
 */
router.post('/recordings/:recordingId/terminal', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const event = req.body;

    const result = service.recordTerminalEvent(recordingId, event);
    if (!result) {
      return res.status(400).json({
        success: false,
        error: 'Failed to record terminal event',
      });
    }

    res.status(200).json({ success: true, data: { recorded: true } });
  } catch (error) {
    logger.error(`Failed to record terminal event: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Record debug event
 * POST /api/recordings/:recordingId/debug
 */
router.post('/recordings/:recordingId/debug', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const event = req.body;

    const result = service.recordDebugEvent(recordingId, event);
    if (!result) {
      return res.status(400).json({
        success: false,
        error: 'Failed to record debug event',
      });
    }

    res.status(200).json({ success: true, data: { recorded: true } });
  } catch (error) {
    logger.error(`Failed to record debug event: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Record chat message
 * POST /api/recordings/:recordingId/chat
 */
router.post('/recordings/:recordingId/chat', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const message = req.body;

    const result = service.recordChatMessage(recordingId, message);
    if (!result) {
      return res.status(400).json({
        success: false,
        error: 'Failed to record chat message',
      });
    }

    res.status(200).json({ success: true, data: { recorded: true } });
  } catch (error) {
    logger.error(`Failed to record chat message: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Start playback
 * POST /api/recordings/:recordingId/playback/start
 */
router.post('/recordings/:recordingId/playback/start', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const playback = service.startPlayback(recordingId);
    if (!playback) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found',
      });
    }

    res.status(200).json({ success: true, data: playback });
  } catch (error) {
    logger.error(`Failed to start playback: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Pause playback
 * POST /api/recordings/:recordingId/playback/pause
 */
router.post('/recordings/:recordingId/playback/pause', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.pausePlayback(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Playback not found',
      });
    }

    const state = service.getPlaybackState(recordingId);
    res.status(200).json({ success: true, data: state });
  } catch (error) {
    logger.error(`Failed to pause playback: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Resume playback
 * POST /api/recordings/:recordingId/playback/resume
 */
router.post('/recordings/:recordingId/playback/resume', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.resumePlayback(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Playback not found',
      });
    }

    const state = service.getPlaybackState(recordingId);
    res.status(200).json({ success: true, data: state });
  } catch (error) {
    logger.error(`Failed to resume playback: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Set playback speed
 * PATCH /api/recordings/:recordingId/playback/speed
 */
router.patch('/recordings/:recordingId/playback/speed', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const { speed } = req.body;

    if (!speed || typeof speed !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'Invalid speed value',
      });
    }

    const result = service.setPlaybackSpeed(recordingId, speed);
    if (!result) {
      return res.status(400).json({
        success: false,
        error: 'Speed must be between 0.5 and 10',
      });
    }

    const state = service.getPlaybackState(recordingId);
    res.status(200).json({ success: true, data: state });
  } catch (error) {
    logger.error(`Failed to set playback speed: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Seek in recording
 * POST /api/recordings/:recordingId/playback/seek
 */
router.post('/recordings/:recordingId/playback/seek', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const { timeMs } = req.body;

    if (typeof timeMs !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'Invalid time value',
      });
    }

    const result = service.seek(recordingId, timeMs);
    if (!result) {
      return res.status(400).json({
        success: false,
        error: 'Invalid seek time',
      });
    }

    const state = service.getPlaybackState(recordingId);
    res.status(200).json({ success: true, data: state });
  } catch (error) {
    logger.error(`Failed to seek: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Toggle layer visibility
 * PATCH /api/recordings/:recordingId/playback/layer/:layer
 */
router.patch('/recordings/:recordingId/playback/layer/:layer', (req: Request, res: Response) => {
  try {
    const { recordingId, layer } = req.params;

    const validLayers = ['files', 'terminal', 'debug', 'chat'];
    if (!validLayers.includes(layer)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid layer. Valid layers: files, terminal, debug, chat',
      });
    }

    const result = service.toggleLayer(recordingId, layer as 'files' | 'terminal' | 'debug' | 'chat');
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Playback not found',
      });
    }

    const state = service.getPlaybackState(recordingId);
    res.status(200).json({ success: true, data: state });
  } catch (error) {
    logger.error(`Failed to toggle layer: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Stop playback
 * POST /api/recordings/:recordingId/playback/stop
 */
router.post('/recordings/:recordingId/playback/stop', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.stopPlayback(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Playback not found',
      });
    }

    res.status(200).json({ success: true, data: { stopped: true } });
  } catch (error) {
    logger.error(`Failed to stop playback: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get playback state
 * GET /api/recordings/:recordingId/playback
 */
router.get('/recordings/:recordingId/playback', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const state = service.getPlaybackState(recordingId);
    if (!state) {
      return res.status(404).json({
        success: false,
        error: 'Playback not found',
      });
    }

    res.status(200).json({ success: true, data: state });
  } catch (error) {
    logger.error(`Failed to get playback state: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Generate share token
 * POST /api/recordings/:recordingId/share
 */
router.post('/recordings/:recordingId/share', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const token = service.generateShareToken(recordingId);
    if (!token) {
      return res.status(404).json({
        success: false,
        error: 'Recording not found',
      });
    }

    const recording = service.getRecording(recordingId);
    res.status(200).json({
      success: true,
      data: {
        token,
        url: recording?.shareUrl,
      },
    });
  } catch (error) {
    logger.error(`Failed to generate share token: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get recording by share token
 * GET /api/recordings/share/:token
 */
router.get('/recordings/share/:token', (req: Request, res: Response) => {
  try {
    const { token } = req.params;

    const recording = service.getRecordingByShareToken(token);
    if (!recording) {
      return res.status(404).json({
        success: false,
        error: 'Shared recording not found',
      });
    }

    res.status(200).json({ success: true, data: recording });
  } catch (error) {
    logger.error(`Failed to get shared recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Revoke share token
 * DELETE /api/recordings/:recordingId/share
 */
router.delete('/recordings/:recordingId/share', (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;

    const result = service.revokeShareToken(recordingId);
    if (!result) {
      return res.status(404).json({
        success: false,
        error: 'Recording or share token not found',
      });
    }

    res.status(200).json({
      success: true,
      data: { recordingId, revoked: true },
    });
  } catch (error) {
    logger.error(`Failed to revoke share token: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Export recording
 * POST /api/recordings/:recordingId/export
 */
router.post('/recordings/:recordingId/export', async (req: Request, res: Response) => {
  try {
    const { recordingId } = req.params;
    const { format, quality, speed, width, height } = req.body;

    if (!format || !quality) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: format, quality',
      });
    }

    const options: ExportOptions = {
      format,
      quality,
      speed: speed || 1,
      width: width || 1920,
      height: height || 1080,
    };

    const path = await service.exportRecording(recordingId, options);
    if (!path) {
      return res.status(400).json({
        success: false,
        error: 'Export failed',
      });
    }

    const recording = service.getRecording(recordingId);
    res.status(200).json({
      success: true,
      data: {
        path,
        url: recording?.exportedVideoUrl,
      },
    });
  } catch (error) {
    logger.error(`Failed to export recording: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get frame at time
 * GET /api/recordings/:recordingId/frame/:timeMs
 */
router.get('/recordings/:recordingId/frame/:timeMs', (req: Request, res: Response) => {
  try {
    const { recordingId, timeMs } = req.params;

    const frame = service.getFrameAtTime(recordingId, parseInt(timeMs, 10));
    if (!frame) {
      return res.status(404).json({
        success: false,
        error: 'Frame not found',
      });
    }

    res.status(200).json({ success: true, data: frame });
  } catch (error) {
    logger.error(`Failed to get frame: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

/**
 * Get statistics
 * GET /api/recordings/stats/all
 */
router.get('/recordings/stats/all', (req: Request, res: Response) => {
  try {
    const stats = service.getStatistics();

    res.status(200).json({
      success: true,
      data: stats,
    });
  } catch (error) {
    logger.error(`Failed to get statistics: ${error}`);
    res.status(500).json({ success: false, error: String(error) });
  }
});

export default router;
