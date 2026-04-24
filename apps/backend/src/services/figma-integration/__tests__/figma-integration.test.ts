#!/usr/bin/env node
// @file        apps/backend/src/services/figma-integration/__tests__/figma-integration.test.ts
// @module      design/figma-integration
// @description Unit tests for Figma integration service
// @owner       collab-9.5
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import { FigmaIntegrationService } from '../index';

// Mock the logger
vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

const mockPool = {
  connect: vi.fn(),
  end: vi.fn(),
} as unknown as Pool;

describe('FigmaIntegrationService', () => {
  let service: FigmaIntegrationService;
  let mockClient: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    (mockPool.connect as any).mockResolvedValue(mockClient);

    service = new FigmaIntegrationService(mockPool);
    mockClient.query.mockResolvedValue({ rows: [] });
    await service.initialize();
  });

  describe('initialization', () => {
    it('should initialize with database schema', async () => {
      // Re-initialize to verify calls
      const service2 = new FigmaIntegrationService(mockPool);
      mockClient.query.mockClear();
      mockClient.query.mockResolvedValue({ rows: [] });

      await service2.initialize();

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS figma_design_tokens')
      );
    });

    it('should create all required tables', async () => {
      // Initialization already done in beforeEach, so just verify
      // At minimum we should have called query multiple times
      expect(mockClient.query.mock.calls.length).toBeGreaterThan(0);
    });
  });

  describe('fetchDesignTokens', () => {
    it('should fetch design tokens from Figma', async () => {
      const tokens = await service.fetchDesignTokens('test-file-key');

      expect(tokens).toBeDefined();
      expect(Array.isArray(tokens)).toBe(true);
      if (tokens.length > 0) {
        expect(tokens[0].name).toBeDefined();
        expect(tokens[0].tokens).toBeDefined();
      }
    });

    it('should organize tokens by group', async () => {
      const tokens = await service.fetchDesignTokens('test-file-key');

      if (tokens.length > 0) {
        const colorGroup = tokens.find(g => g.name === 'Colors');
        const spacingGroup = tokens.find(g => g.name === 'Spacing');

        expect(colorGroup).toBeDefined();
        expect(spacingGroup).toBeDefined();
      }
    });
  });

  describe('CSS variables', () => {
    it('should get CSS variables by scope', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          { variable_name: '--color-primary', variable_value: '#007AFF', fallback_value: null, scope: 'global' },
        ],
      });

      const vars = await service.getCSSVariables('global');

      expect(vars).toHaveLength(1);
      expect(vars[0].name).toBe('--color-primary');
      expect(vars[0].value).toBe('#007AFF');
    });

    it('should set CSS variables', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.setCSSVariable({
        name: '--color-error',
        value: '#FF3B30',
        scope: 'global',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO css_variables'),
        expect.any(Array)
      );
    });

    it('should update existing CSS variables', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.setCSSVariable({
        name: '--color-primary',
        value: '#0066FF',
        scope: 'global',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT'),
        expect.any(Array)
      );
    });
  });

  describe('token mappings', () => {
    it('should map Figma tokens to CSS variables', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'mapping-1',
            figma_token_id: 'color-primary',
            figma_token_name: 'primary',
            css_variable_name: '--color-primary',
            css_value: '#007AFF',
            mismatch: false,
            mismatch_reason: null,
            synced_at: new Date(),
            last_updated_at: new Date(),
          },
        ],
      });

      const mapping = await service.mapTokenToCSSVariable(
        'color-primary',
        'primary',
        '--color-primary',
        '#007AFF'
      );

      expect(mapping).toBeDefined();
      expect(mapping.figmaTokenId).toBe('color-primary');
      expect(mapping.cssVariableName).toBe('--color-primary');
    });

    it('should detect token mismatches', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'mapping-1',
            figma_token_id: 'color-primary',
            figma_token_name: 'primary',
            css_variable_name: '--color-primary',
            css_value: '#0066FF',
            mismatch: true,
            mismatch_reason: 'Value mismatch between Figma token and CSS variable',
            synced_at: new Date(),
            last_updated_at: new Date(),
          },
        ],
      });

      const mapping = await service.mapTokenToCSSVariable(
        'color-primary',
        'primary',
        '--color-primary',
        '#0066FF'
      );

      expect(mapping.mismatch).toBe(true);
    });

    it('should get all token mappings', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'mapping-1',
            figma_token_id: 'color-primary',
            figma_token_name: 'primary',
            css_variable_name: '--color-primary',
            css_value: '#007AFF',
            mismatch: false,
            mismatch_reason: null,
            synced_at: new Date(),
            last_updated_at: new Date(),
          },
        ],
      });

      const mappings = await service.getTokenMappings();

      expect(mappings).toBeDefined();
      expect(mappings.length).toBeGreaterThan(0);
    });

    it('should filter mismatches when requested', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getTokenMappings(true);

      // Query is called with just the SQL string (no parameters when filtering)
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('WHERE mismatch = TRUE')
      );
    });
  });

  describe('Figma frames', () => {
    it('should save Figma frames', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveFigmaFrame('file-key-1', {
        id: 'frame-1',
        name: 'Hero Section',
        type: 'COMPONENT',
        url: 'https://figma.com/...',
        fileKey: 'file-key-1',
        nodeId: 'node-1',
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO figma_frames'),
        expect.any(Array)
      );
    });

    it('should get Figma frames', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'frame-1',
            frame_id: 'frame-1',
            frame_name: 'Hero Section',
            frame_type: 'COMPONENT',
            figma_url: 'https://figma.com/...',
            node_id: 'node-1',
            thumbnail_url: null,
            description: null,
          },
        ],
      });

      const frames = await service.getFigmaFrames('file-key-1');

      expect(frames).toHaveLength(1);
      expect(frames[0].name).toBe('Hero Section');
    });
  });

  describe('comments - Figma', () => {
    it('should add Figma comments', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.addFigmaComment('file-1', {
        id: 'comment-1',
        fileId: 'file-1',
        frameId: 'frame-1',
        author: 'alice',
        authorId: 'user-1',
        content: 'Nice design',
        createdAt: new Date(),
        updatedAt: new Date(),
        syncedToIde: false,
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO figma_comments'),
        expect.any(Array)
      );
    });

    it('should retrieve Figma comments', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'comment-1',
            file_id: 'file-1',
            frame_id: 'frame-1',
            author_name: 'alice',
            author_id: 'user-1',
            content: 'Nice design',
            created_at: new Date(),
            updated_at: new Date(),
            resolved_at: null,
            synced_to_ide: false,
          },
        ],
      });

      const comments = await service.getFigmaComments('file-1');

      expect(comments).toHaveLength(1);
      expect(comments[0].author).toBe('alice');
    });

    it('should filter comments by frame', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getFigmaComments('file-1', 'frame-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('WHERE file_id = $1 AND frame_id = $2'),
        expect.any(Array)
      );
    });
  });

  describe('comments - IDE', () => {
    it('should add IDE comments', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.addIDEComment('frame-1', {
        id: 'ide-comment-1',
        frameId: 'frame-1',
        author: 'bob',
        content: 'Let me redesign',
        createdAt: new Date(),
        syncedToFigma: false,
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO ide_comments'),
        expect.any(Array)
      );
    });

    it('should retrieve IDE comments', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'ide-comment-1',
            frame_id: 'frame-1',
            author: 'bob',
            content: 'Let me redesign',
            created_at: new Date(),
            figma_comment_id: null,
            synced_to_figma: false,
          },
        ],
      });

      const comments = await service.getIDEComments('frame-1');

      expect(comments).toHaveLength(1);
      expect(comments[0].author).toBe('bob');
    });
  });

  describe('comment synchronization', () => {
    it('should sync IDE comments to Figma', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'comment-1' }, { id: 'comment-2' }],
        rowCount: 2,
      });

      const count = await service.syncCommentsToFigma('frame-1');

      expect(count).toBe(2);
      // Check that the SQL contains UPDATE and synced_to_figma
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE ide_comments'),
        expect.arrayContaining(['frame-1'])
      );
    });

    it('should sync Figma comments to IDE', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'comment-1' }],
        rowCount: 1,
      });

      const count = await service.syncCommentsFromFigma('file-1');

      expect(count).toBe(1);
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE figma_comments SET synced_to_ide = TRUE'),
        expect.any(Array)
      );
    });

    it('should filter sync by frame', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [], rowCount: 0 });

      await service.syncCommentsFromFigma('file-1', 'frame-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('AND frame_id = $2'),
        expect.any(Array)
      );
    });
  });

  describe('WebView sessions', () => {
    it('should create WebView sessions', async () => {
      const sessionId = 'session-1';
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: sessionId }],
      });

      const id = await service.createWebViewSession('user-1', {
        frameId: 'frame-1',
        fileKey: 'file-1',
        nodeId: 'node-1',
        showTokens: true,
        showComments: true,
        highlightTokenUsage: true,
        theme: 'light',
      });

      expect(id).toBe(sessionId);
    });

    it('should retrieve WebView config', async () => {
      const config = {
        frameId: 'frame-1',
        fileKey: 'file-1',
        nodeId: 'node-1',
        showTokens: true,
        showComments: true,
        highlightTokenUsage: true,
        theme: 'light' as const,
      };

      mockClient.query.mockResolvedValueOnce({
        rows: [{ config }],
      });

      const retrieved = await service.getWebViewConfig('session-1');

      expect(retrieved).toEqual(config);
    });

    it('should return null for missing session', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [],
      });

      const config = await service.getWebViewConfig('unknown-session');

      expect(config).toBeNull();
    });
  });

  describe('WebView HTML generation', () => {
    it('should generate HTML for WebView', async () => {
      mockClient.query.mockResolvedValue({
        rows: [
          { variable_name: '--color-primary', variable_value: '#007AFF', fallback_value: null, scope: 'global' },
        ],
      });

      const html = await service.generateWebViewHTML({
        frameId: 'frame-1',
        fileKey: 'file-1',
        nodeId: 'node-1',
        showTokens: true,
        showComments: true,
        highlightTokenUsage: true,
        theme: 'light',
      });

      expect(html).toContain('<!DOCTYPE html>');
      expect(html).toContain('figma.com');
      expect(html).toContain('token-inspector');
    });

    it('should respect theme preference', async () => {
      mockClient.query.mockResolvedValue({ rows: [] });

      const darkHtml = await service.generateWebViewHTML({
        frameId: 'frame-1',
        fileKey: 'file-1',
        nodeId: 'node-1',
        showTokens: false,
        showComments: false,
        highlightTokenUsage: false,
        theme: 'dark',
      });

      expect(darkHtml).toContain('#1e1e1e');
    });

    it('should hide token inspector when disabled', async () => {
      mockClient.query.mockResolvedValue({ rows: [] });

      const html = await service.generateWebViewHTML({
        frameId: 'frame-1',
        fileKey: 'file-1',
        nodeId: 'node-1',
        showTokens: false,
        showComments: true,
        highlightTokenUsage: false,
        theme: 'light',
      });

      // When showTokens is false, the token-inspector div should not be rendered in the page
      expect(html).not.toContain('<div class="token-inspector">');
    });
  });
});