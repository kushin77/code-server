#!/usr/bin/env node
// @file        apps/backend/src/routes/figma-integration.ts
// @module      design/figma-integration
// @description REST API routes for Figma integration
// @owner       collab-9.5
// @status      active

import { Router } from 'express';
import { Pool } from 'pg';
import { FigmaIntegrationService } from '../services/figma-integration';
import { AuditService } from '../services/audit/audit-service';
import { getLogger } from '../lib/logger';

const logger = getLogger('FigmaIntegrationRoutes');

export function initializeFigmaIntegrationRoutes(pool: Pool, auditService?: AuditService): Router {
  const router = Router();
  const figmaService = new FigmaIntegrationService(pool, auditService);

  figmaService.initialize().catch(error => {
    logger.error('Failed to initialize figma integration service', { error });
  });

  // GET /api/figma/tokens/:fileKey - Get design tokens for a file
  router.get('/tokens/:fileKey', async (req, res) => {
    try {
      const { fileKey } = req.params;
      const tokens = await figmaService.fetchDesignTokens(fileKey);

      res.json({
        success: true,
        fileKey,
        tokenGroups: tokens,
      });
    } catch (error) {
      logger.error('Failed to fetch design tokens', { error, fileKey: req.params.fileKey });
      res.status(500).json({ error: 'Failed to fetch design tokens' });
    }
  });

  // GET /api/figma/css-variables - Get CSS variables
  router.get('/css-variables', async (req, res) => {
    try {
      const { scope = 'global' } = req.query;
      const variables = await figmaService.getCSSVariables(scope as any);

      res.json({
        success: true,
        scope,
        variables,
      });
    } catch (error) {
      logger.error('Failed to get CSS variables', { error });
      res.status(500).json({ error: 'Failed to get CSS variables' });
    }
  });

  // POST /api/figma/css-variables - Set CSS variable
  router.post('/css-variables', async (req, res) => {
    try {
      const { name, value, fallback, scope = 'global' } = req.body;

      if (!name || !value) {
        return res.status(400).json({ error: 'Missing required fields: name, value' });
      }

      await figmaService.setCSSVariable({
        name,
        value,
        fallback,
        scope,
      });

      res.json({ success: true, message: 'CSS variable set' });
    } catch (error) {
      logger.error('Failed to set CSS variable', { error, body: req.body });
      res.status(500).json({ error: 'Failed to set CSS variable' });
    }
  });

  // POST /api/figma/token-mapping - Map Figma token to CSS variable
  router.post('/token-mapping', async (req, res) => {
    try {
      const { tokenId, tokenName, cssVariableName, cssValue } = req.body;

      if (!tokenId || !cssVariableName) {
        return res.status(400).json({ error: 'Missing required fields: tokenId, cssVariableName' });
      }

      const mapping = await figmaService.mapTokenToCSSVariable(
        tokenId,
        tokenName,
        cssVariableName,
        cssValue
      );

      res.json({
        success: true,
        mapping,
      });
    } catch (error) {
      logger.error('Failed to map token', { error, body: req.body });
      res.status(500).json({ error: 'Failed to map token' });
    }
  });

  // GET /api/figma/token-mappings - Get all token mappings
  router.get('/token-mappings', async (req, res) => {
    try {
      const { showMismatches = 'false' } = req.query;
      const mappings = await figmaService.getTokenMappings(showMismatches === 'true');

      const mismatches = mappings.filter(m => m.mismatch);

      res.json({
        success: true,
        total: mappings.length,
        mismatches: mismatches.length,
        mappings,
      });
    } catch (error) {
      logger.error('Failed to get token mappings', { error });
      res.status(500).json({ error: 'Failed to get token mappings' });
    }
  });

  // POST /api/figma/frames - Save Figma frame
  router.post('/frames', async (req, res) => {
    try {
      const { fileKey, frame } = req.body;

      if (!fileKey || !frame) {
        return res.status(400).json({ error: 'Missing required fields: fileKey, frame' });
      }

      await figmaService.saveFigmaFrame(fileKey, frame);

      res.json({ success: true, message: 'Frame saved' });
    } catch (error) {
      logger.error('Failed to save frame', { error, body: req.body });
      res.status(500).json({ error: 'Failed to save frame' });
    }
  });

  // GET /api/figma/frames/:fileKey - Get frames for a file
  router.get('/frames/:fileKey', async (req, res) => {
    try {
      const { fileKey } = req.params;
      const frames = await figmaService.getFigmaFrames(fileKey);

      res.json({
        success: true,
        fileKey,
        frames,
      });
    } catch (error) {
      logger.error('Failed to get frames', { error, fileKey: req.params.fileKey });
      res.status(500).json({ error: 'Failed to get frames' });
    }
  });

  // POST /api/figma/comments - Add Figma comment
  router.post('/comments', async (req, res) => {
    try {
      const { fileId, comment } = req.body;

      if (!fileId || !comment) {
        return res.status(400).json({ error: 'Missing required fields: fileId, comment' });
      }

      await figmaService.addFigmaComment(fileId, comment);

      res.json({ success: true, message: 'Comment added' });
    } catch (error) {
      logger.error('Failed to add comment', { error, body: req.body });
      res.status(500).json({ error: 'Failed to add comment' });
    }
  });

  // GET /api/figma/comments/:fileId - Get Figma comments
  router.get('/comments/:fileId', async (req, res) => {
    try {
      const { fileId } = req.params;
      const { frameId } = req.query;

      const comments = await figmaService.getFigmaComments(fileId, frameId as string);

      res.json({
        success: true,
        fileId,
        comments,
      });
    } catch (error) {
      logger.error('Failed to get comments', { error, fileId: req.params.fileId });
      res.status(500).json({ error: 'Failed to get comments' });
    }
  });

  // POST /api/figma/ide-comments - Add IDE comment
  router.post('/ide-comments', async (req, res) => {
    try {
      const { frameId, comment } = req.body;

      if (!frameId || !comment) {
        return res.status(400).json({ error: 'Missing required fields: frameId, comment' });
      }

      await figmaService.addIDEComment(frameId, comment);

      res.json({ success: true, message: 'IDE comment added' });
    } catch (error) {
      logger.error('Failed to add IDE comment', { error, body: req.body });
      res.status(500).json({ error: 'Failed to add IDE comment' });
    }
  });

  // GET /api/figma/ide-comments/:frameId - Get IDE comments
  router.get('/ide-comments/:frameId', async (req, res) => {
    try {
      const { frameId } = req.params;
      const comments = await figmaService.getIDEComments(frameId);

      res.json({
        success: true,
        frameId,
        comments,
      });
    } catch (error) {
      logger.error('Failed to get IDE comments', { error, frameId: req.params.frameId });
      res.status(500).json({ error: 'Failed to get IDE comments' });
    }
  });

  // POST /api/figma/sync-to-figma/:frameId - Sync IDE comments to Figma
  router.post('/sync-to-figma/:frameId', async (req, res) => {
    try {
      const { frameId } = req.params;
      const count = await figmaService.syncCommentsToFigma(frameId);

      res.json({
        success: true,
        synced: count,
      });
    } catch (error) {
      logger.error('Failed to sync comments to Figma', { error, frameId: req.params.frameId });
      res.status(500).json({ error: 'Failed to sync comments' });
    }
  });

  // POST /api/figma/sync-from-figma/:fileId - Sync Figma comments to IDE
  router.post('/sync-from-figma/:fileId', async (req, res) => {
    try {
      const { fileId } = req.params;
      const { frameId } = req.query;
      const count = await figmaService.syncCommentsFromFigma(fileId, frameId as string);

      res.json({
        success: true,
        synced: count,
      });
    } catch (error) {
      logger.error('Failed to sync comments from Figma', { error, fileId: req.params.fileId });
      res.status(500).json({ error: 'Failed to sync comments' });
    }
  });

  // POST /api/figma/webview-session - Create WebView session
  router.post('/webview-session', async (req, res) => {
    try {
      const { userId, config } = req.body;

      if (!userId || !config) {
        return res.status(400).json({ error: 'Missing required fields: userId, config' });
      }

      const sessionId = await figmaService.createWebViewSession(userId, config);

      res.json({
        success: true,
        sessionId,
      });
    } catch (error) {
      logger.error('Failed to create webview session', { error, body: req.body });
      res.status(500).json({ error: 'Failed to create session' });
    }
  });

  // GET /api/figma/webview/:sessionId - Get WebView HTML
  router.get('/webview/:sessionId', async (req, res) => {
    try {
      const { sessionId } = req.params;
      const config = await figmaService.getWebViewConfig(sessionId);

      if (!config) {
        return res.status(404).json({ error: 'Session not found' });
      }

      const html = await figmaService.generateWebViewHTML(config);

      res.set('Content-Type', 'text/html');
      res.send(html);
    } catch (error) {
      logger.error('Failed to get webview', { error, sessionId: req.params.sessionId });
      res.status(500).json({ error: 'Failed to load webview' });
    }
  });

  return router;
}

export { FigmaIntegrationService } from '../services/figma-integration';
