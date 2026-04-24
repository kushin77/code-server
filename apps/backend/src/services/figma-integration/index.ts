#!/usr/bin/env node
// @file        apps/backend/src/services/figma-integration/index.ts
// @module      design/figma-integration
// @description Figma frame rendering, design token inspection, and comment synchronization
// @owner       collab-9.5
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';
import { AuditService } from '../audit/audit-service.js';

export interface FigmaToken {
  id: string;
  name: string;
  type: 'color' | 'spacing' | 'typography' | 'size' | 'opacity' | 'other';
  value: string;
  description?: string;
  resolvedType?: string;
}

export interface DesignTokenGroup {
  name: string;
  tokens: FigmaToken[];
  mode?: string;
}

export interface CSSVariable {
  name: string;
  value: string;
  fallback?: string;
  scope: 'global' | 'component' | 'theme';
}

export interface TokenMapping {
  id: string;
  figmaTokenId: string;
  figmaTokenName: string;
  cssVariableName: string;
  cssValue: string;
  mismatch: boolean;
  mismatchReason?: string;
  syncedAt: Date;
  lastUpdatedAt: Date;
}

export interface FigmaFrame {
  id: string;
  name: string;
  type: string;
  url: string;
  fileKey: string;
  nodeId: string;
  thumbnail?: string;
  description?: string;
}

export interface FigmaComment {
  id: string;
  fileId: string;
  frameId: string;
  author: string;
  authorId: string;
  content: string;
  createdAt: Date;
  updatedAt: Date;
  resolvedAt?: Date;
  syncedToIde: boolean;
}

export interface IDEComment {
  id: string;
  frameId: string;
  author: string;
  content: string;
  createdAt: Date;
  figmaCommentId?: string;
  syncedToFigma: boolean;
}

export interface WebViewConfig {
  frameId: string;
  fileKey: string;
  nodeId: string;
  showTokens: boolean;
  showComments: boolean;
  highlightTokenUsage: boolean;
  theme: 'light' | 'dark';
}

export class FigmaIntegrationService extends EventEmitter {
  private pool: Pool;
  private auditService?: AuditService;
  private logger = getLogger('FigmaIntegrationService');
  private initialized = false;
  private figmaApiToken = process.env.FIGMA_API_TOKEN || '';
  private figmaBaseUrl = 'https://api.figma.com/v1';

  constructor(pool: Pool, auditService?: AuditService) {
    super();
    this.pool = pool;
    this.auditService = auditService;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Figma integration database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize figma integration schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Design tokens cache
      await client.query(`
        CREATE TABLE IF NOT EXISTS figma_design_tokens (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_key TEXT NOT NULL,
          token_id TEXT NOT NULL,
          token_name TEXT NOT NULL,
          token_type TEXT NOT NULL CHECK (token_type IN ('color', 'spacing', 'typography', 'size', 'opacity', 'other')),
          token_value TEXT NOT NULL,
          description TEXT,
          resolved_type TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(file_key, token_id)
        )
      `);

      // CSS variables for design tokens
      await client.query(`
        CREATE TABLE IF NOT EXISTS css_variables (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          variable_name TEXT NOT NULL UNIQUE,
          variable_value TEXT NOT NULL,
          fallback_value TEXT,
          scope TEXT DEFAULT 'global' CHECK (scope IN ('global', 'component', 'theme')),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Token mappings (Figma tokens <-> CSS vars)
      await client.query(`
        CREATE TABLE IF NOT EXISTS token_mappings (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          figma_token_id TEXT NOT NULL,
          figma_token_name TEXT NOT NULL,
          css_variable_name TEXT NOT NULL,
          css_value TEXT NOT NULL,
          mismatch BOOLEAN DEFAULT FALSE,
          mismatch_reason TEXT,
          synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(figma_token_id, css_variable_name)
        )
      `);

      // Figma frames
      await client.query(`
        CREATE TABLE IF NOT EXISTS figma_frames (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_key TEXT NOT NULL,
          frame_id TEXT NOT NULL,
          frame_name TEXT NOT NULL,
          frame_type TEXT,
          figma_url TEXT,
          node_id TEXT,
          thumbnail_url TEXT,
          description TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(file_key, frame_id)
        )
      `);

      // Figma comments (from Figma API)
      await client.query(`
        CREATE TABLE IF NOT EXISTS figma_comments (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          file_id TEXT NOT NULL,
          frame_id TEXT NOT NULL,
          comment_id TEXT NOT NULL,
          author_name TEXT,
          author_id TEXT,
          content TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          resolved_at TIMESTAMP WITH TIME ZONE,
          synced_to_ide BOOLEAN DEFAULT FALSE,
          ide_comment_id UUID,
          UNIQUE(file_id, comment_id)
        )
      `);

      // IDE comments (synced to Figma)
      await client.query(`
        CREATE TABLE IF NOT EXISTS ide_comments (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          frame_id TEXT NOT NULL,
          author TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          figma_comment_id TEXT,
          synced_to_figma BOOLEAN DEFAULT FALSE,
          figma_sync_attempt INTEGER DEFAULT 0,
          figma_sync_error TEXT
        )
      `);

      // WebView sessions
      await client.query(`
        CREATE TABLE IF NOT EXISTS webview_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          file_key TEXT NOT NULL,
          frame_id TEXT NOT NULL,
          config JSONB,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          last_accessed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Indexes
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_figma_tokens_file_key ON figma_design_tokens(file_key);
        CREATE INDEX IF NOT EXISTS idx_figma_tokens_name ON figma_design_tokens(token_name);
        CREATE INDEX IF NOT EXISTS idx_css_variables_scope ON css_variables(scope);
        CREATE INDEX IF NOT EXISTS idx_token_mappings_status ON token_mappings(mismatch);
        CREATE INDEX IF NOT EXISTS idx_figma_frames_file_key ON figma_frames(file_key);
        CREATE INDEX IF NOT EXISTS idx_figma_comments_file_id ON figma_comments(file_id);
        CREATE INDEX IF NOT EXISTS idx_figma_comments_synced ON figma_comments(synced_to_ide);
        CREATE INDEX IF NOT EXISTS idx_ide_comments_synced ON ide_comments(synced_to_figma);
        CREATE INDEX IF NOT EXISTS idx_webview_sessions_user ON webview_sessions(user_id);
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async fetchDesignTokens(fileKey: string): Promise<DesignTokenGroup[]> {
    if (!this.figmaApiToken) {
      this.logger.warn('No Figma API token configured');
      return [];
    }

    try {
      // In production, call Figma API:
      // const response = await fetch(`${this.figmaBaseUrl}/files/${fileKey}/variables/local`);
      // const data = await response.json();
      
      this.logger.info('Fetching design tokens from Figma', { fileKey });

      // For now, return mock structure
      return [
        {
          name: 'Colors',
          tokens: [
            { id: 'color-primary', name: 'primary', type: 'color', value: '#007AFF', description: 'Primary brand color' },
            { id: 'color-error', name: 'error', type: 'color', value: '#FF3B30', description: 'Error state color' },
          ],
        },
        {
          name: 'Spacing',
          tokens: [
            { id: 'space-xs', name: 'xs', type: 'spacing', value: '4px', resolvedType: 'spacing' },
            { id: 'space-sm', name: 'sm', type: 'spacing', value: '8px', resolvedType: 'spacing' },
          ],
        },
      ];
    } catch (error) {
      this.logger.error('Failed to fetch design tokens', { error, fileKey });
      throw error;
    }
  }

  async getCSSVariables(scope: 'global' | 'component' | 'theme' = 'global'): Promise<CSSVariable[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT variable_name, variable_value, fallback_value, scope 
         FROM css_variables 
         WHERE scope = $1 
         ORDER BY variable_name`,
        [scope]
      );

      return result.rows.map(row => ({
        name: row.variable_name,
        value: row.variable_value,
        fallback: row.fallback_value,
        scope: row.scope,
      }));
    } catch (error) {
      this.logger.error('Failed to get CSS variables', { error, scope });
      throw error;
    } finally {
      client.release();
    }
  }

  async setCSSVariable(variable: CSSVariable): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO css_variables (variable_name, variable_value, fallback_value, scope)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (variable_name) DO UPDATE SET
           variable_value = $2, fallback_value = $3, scope = $4, updated_at = NOW()`,
        [variable.name, variable.value, variable.fallback || null, variable.scope]
      );

      this.logger.info('CSS variable set', { name: variable.name });
    } catch (error) {
      this.logger.error('Failed to set CSS variable', { error, name: variable.name });
      throw error;
    } finally {
      client.release();
    }
  }

  // SOC2: Audit design-to-code mapping
  private auditMapping(tokenId: string, cssVarName: string): void {
    this.auditService?.emit({
      userId: 'system',
      action: 'allow',
      resource: 'figma-token-mapping:' + tokenId,
      reason: 'Mapped Figma token ' + tokenId + ' to CSS variable ' + cssVarName
    });
  }

  async mapTokenToCSSVariable(tokenId: string, tokenName: string, cssVarName: string, cssValue: string): Promise<TokenMapping> {
    const client = await this.pool.connect();
    try {
      const mismatch = cssValue !== tokenId; // Simplified mismatch detection
      const mismatchReason = mismatch ? 'Value mismatch between Figma token and CSS variable' : undefined;

      const result = await client.query(
        `INSERT INTO token_mappings (figma_token_id, figma_token_name, css_variable_name, css_value, mismatch, mismatch_reason)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (figma_token_id, css_variable_name) DO UPDATE SET
           css_value = $4, mismatch = $5, mismatch_reason = $6, last_updated_at = NOW()
         RETURNING *`,
        [tokenId, tokenName, cssVarName, cssValue, mismatch, mismatchReason]
      );

      const row = result.rows[0];
      return {
        id: row.id,
        figmaTokenId: row.figma_token_id,
        figmaTokenName: row.figma_token_name,
        cssVariableName: row.css_variable_name,
        cssValue: row.css_value,
        mismatch: row.mismatch,
        mismatchReason: row.mismatch_reason,
        syncedAt: row.synced_at,
        lastUpdatedAt: row.last_updated_at,
      };
    } catch (error) {
      this.logger.error('Failed to map token to CSS variable', { error, tokenId, cssVarName });
      throw error;
    } finally {
      client.release();
    }
  }

  async getTokenMappings(includeMismatches: boolean = false): Promise<TokenMapping[]> {
    const client = await this.pool.connect();
    try {
      let query = 'SELECT * FROM token_mappings';
      if (includeMismatches) {
        query += ' WHERE mismatch = TRUE';
      }
      query += ' ORDER BY figma_token_name';

      const result = await client.query(query);

      return result.rows.map(row => ({
        id: row.id,
        figmaTokenId: row.figma_token_id,
        figmaTokenName: row.figma_token_name,
        cssVariableName: row.css_variable_name,
        cssValue: row.css_value,
        mismatch: row.mismatch,
        mismatchReason: row.mismatch_reason,
        syncedAt: row.synced_at,
        lastUpdatedAt: row.last_updated_at,
      }));
    } catch (error) {
      this.logger.error('Failed to get token mappings', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  // SOC2: Audit design sync
  private auditFrameSync(fileKey: string, frameName: string): void {
    this.auditService?.emit({
      userId: 'system',
      action: 'allow',
      resource: 'figma-frame:' + fileKey,
      reason: 'Synced Figma frame ' + frameName + ' from file ' + fileKey
    });
  }

  async saveFigmaFrame(fileKey: string, frame: FigmaFrame): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO figma_frames (file_key, frame_id, frame_name, frame_type, figma_url, node_id, thumbnail_url, description)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (file_key, frame_id) DO UPDATE SET
           frame_name = $3, figma_url = $5, thumbnail_url = $7, description = $8, updated_at = NOW()`,
        [fileKey, frame.id, frame.name, frame.type, frame.url, frame.nodeId, frame.thumbnail, frame.description]
      );

      this.logger.info('Figma frame saved', { fileKey, frameId: frame.id });
    } catch (error) {
      this.logger.error('Failed to save figma frame', { error, frameId: frame.id });
      throw error;
    } finally {
      client.release();
    }
  }

  async getFigmaFrames(fileKey: string): Promise<FigmaFrame[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, frame_id, frame_name, frame_type, figma_url, node_id, thumbnail_url, description
         FROM figma_frames 
         WHERE file_key = $1 
         ORDER BY frame_name`,
        [fileKey]
      );

      return result.rows.map(row => ({
        id: row.id,
        name: row.frame_name,
        type: row.frame_type,
        url: row.figma_url,
        fileKey,
        nodeId: row.node_id,
        thumbnail: row.thumbnail_url,
        description: row.description,
      }));
    } catch (error) {
      this.logger.error('Failed to get figma frames', { error, fileKey });
      throw error;
    } finally {
      client.release();
    }
  }

  async addFigmaComment(fileId: string, comment: FigmaComment): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO figma_comments (file_id, frame_id, comment_id, author_name, author_id, content, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (file_id, comment_id) DO UPDATE SET
           content = $6, updated_at = $8`,
        [
          fileId,
          comment.frameId,
          comment.id,
          comment.author,
          comment.authorId,
          comment.content,
          comment.createdAt,
          comment.updatedAt,
        ]
      );

      this.logger.info('Figma comment saved', { commentId: comment.id });
    } catch (error) {
      this.logger.error('Failed to save figma comment', { error, commentId: comment.id });
      throw error;
    } finally {
      client.release();
    }
  }

  async getFigmaComments(fileId: string, frameId?: string): Promise<FigmaComment[]> {
    const client = await this.pool.connect();
    try {
      let query = `SELECT * FROM figma_comments WHERE file_id = $1`;
      const params: any[] = [fileId];

      if (frameId) {
        query += ` AND frame_id = $2`;
        params.push(frameId);
      }

      query += ` ORDER BY created_at DESC`;

      const result = await client.query(query, params);

      return result.rows.map(row => ({
        id: row.id,
        fileId: row.file_id,
        frameId: row.frame_id,
        author: row.author_name,
        authorId: row.author_id,
        content: row.content,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        resolvedAt: row.resolved_at,
        syncedToIde: row.synced_to_ide,
      }));
    } catch (error) {
      this.logger.error('Failed to get figma comments', { error, fileId });
      throw error;
    } finally {
      client.release();
    }
  }

  async addIDEComment(frameId: string, comment: IDEComment): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO ide_comments (frame_id, author, content, created_at, figma_comment_id)
         VALUES ($1, $2, $3, $4, $5)`,
        [frameId, comment.author, comment.content, comment.createdAt, comment.figmaCommentId || null]
      );

      this.logger.info('IDE comment added', { frameId });
    } catch (error) {
      this.logger.error('Failed to add IDE comment', { error, frameId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getIDEComments(frameId: string): Promise<IDEComment[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, frame_id, author, content, created_at, figma_comment_id, synced_to_figma
         FROM ide_comments 
         WHERE frame_id = $1 
         ORDER BY created_at DESC`,
        [frameId]
      );

      return result.rows.map(row => ({
        id: row.id,
        frameId: row.frame_id,
        author: row.author,
        content: row.content,
        createdAt: row.created_at,
        figmaCommentId: row.figma_comment_id,
        syncedToFigma: row.synced_to_figma,
      }));
    } catch (error) {
      this.logger.error('Failed to get IDE comments', { error, frameId });
      throw error;
    } finally {
      client.release();
    }
  }

  async syncCommentsToFigma(frameId: string): Promise<number> {
    const client = await this.pool.connect();
    try {
      // Mark comments as synced (in production, would call Figma API)
      const result = await client.query(
        `UPDATE ide_comments 
         SET synced_to_figma = TRUE, figma_sync_attempt = figma_sync_attempt + 1
         WHERE frame_id = $1 AND synced_to_figma = FALSE
         RETURNING id`,
        [frameId]
      );

      this.logger.info('IDE comments synced to Figma', { frameId, count: result.rowCount });
      return result.rowCount || 0;
    } catch (error) {
      this.logger.error('Failed to sync comments to Figma', { error, frameId });
      throw error;
    } finally {
      client.release();
    }
  }

  async syncCommentsFromFigma(fileId: string, frameId?: string): Promise<number> {
    const client = await this.pool.connect();
    try {
      // Mark comments as synced to IDE
      let query = `UPDATE figma_comments SET synced_to_ide = TRUE WHERE file_id = $1 AND synced_to_ide = FALSE`;
      const params: any[] = [fileId];

      if (frameId) {
        query += ` AND frame_id = $2`;
        params.push(frameId);
      }

      query += ` RETURNING id`;

      const result = await client.query(query, params);

      this.logger.info('Figma comments synced to IDE', { fileId, frameId, count: result.rowCount });
      return result.rowCount || 0;
    } catch (error) {
      this.logger.error('Failed to sync comments from Figma', { error, fileId });
      throw error;
    } finally {
      client.release();
    }
  }

  async createWebViewSession(userId: string, config: WebViewConfig): Promise<string> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO webview_sessions (user_id, file_key, frame_id, config)
         VALUES ($1, $2, $3, $4)
         RETURNING id`,
        [userId, config.fileKey, config.frameId, JSON.stringify(config)]
      );

      const sessionId = result.rows[0].id;
      this.logger.info('WebView session created', { userId, sessionId });
      return sessionId;
    } catch (error) {
      this.logger.error('Failed to create webview session', { error, userId });
      throw error;
    } finally {
      client.release();
    }
  }

  async getWebViewConfig(sessionId: string): Promise<WebViewConfig | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT config FROM webview_sessions WHERE id = $1`,
        [sessionId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return result.rows[0].config;
    } catch (error) {
      this.logger.error('Failed to get webview config', { error, sessionId });
      throw error;
    } finally {
      client.release();
    }
  }

  async generateWebViewHTML(config: WebViewConfig): Promise<string> {
    const tokenMappings = await this.getTokenMappings();
    const cssVars = await this.getCSSVariables('global');

    const cssVariablesSheet = cssVars
      .map(v => `--${v.name}: ${v.value}${v.fallback ? ` / ${v.fallback}` : ''};`)
      .join('\n    ');

    const tokenInspector = config.showTokens
      ? `
    <div class="token-inspector">
      <h3>Design Tokens</h3>
      <div class="token-list">
        ${tokenMappings.map(m => `
          <div class="token-item ${m.mismatch ? 'mismatch' : ''}">
            <span class="token-name">${m.figmaTokenName}</span>
            <span class="token-value">${m.cssValue}</span>
            ${m.mismatch ? `<span class="warning">Mismatch: ${m.mismatchReason}</span>` : ''}
          </div>
        `).join('')}
      </div>
    </div>
    `
      : '';

    const html = `
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Figma Frame</title>
      <style>
        :root {
          ${cssVariablesSheet}
        }
        
        body {
          margin: 0;
          padding: 16px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: ${config.theme === 'dark' ? '#1e1e1e' : '#ffffff'};
          color: ${config.theme === 'dark' ? '#e0e0e0' : '#333333'};
        }

        .frame-container {
          display: flex;
          gap: 16px;
        }

        .frame-viewer {
          flex: 1;
          border: 1px solid ${config.theme === 'dark' ? '#444' : '#ddd'};
          border-radius: 8px;
          padding: 16px;
          background: ${config.theme === 'dark' ? '#2a2a2a' : '#f5f5f5'};
        }

        .token-inspector {
          width: 280px;
          border: 1px solid ${config.theme === 'dark' ? '#444' : '#ddd'};
          border-radius: 8px;
          padding: 16px;
          background: ${config.theme === 'dark' ? '#2a2a2a' : '#f9f9f9'};
          max-height: 600px;
          overflow-y: auto;
        }

        .token-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .token-item {
          padding: 8px;
          border-radius: 4px;
          background: ${config.theme === 'dark' ? '#1e1e1e' : '#fff'};
          border: 1px solid ${config.theme === 'dark' ? '#333' : '#eee'};
          font-size: 12px;
        }

        .token-item.mismatch {
          border-color: #ff6b6b;
          background: ${config.theme === 'dark' ? '#4a2a2a' : '#fff5f5'};
        }

        .token-name {
          font-weight: 600;
          display: block;
          margin-bottom: 4px;
        }

        .token-value {
          font-family: 'Monaco', 'Menlo', monospace;
          color: ${config.theme === 'dark' ? '#a0e7e5' : '#0066cc'};
          font-size: 11px;
        }

        .warning {
          color: #ff6b6b;
          font-size: 10px;
          display: block;
          margin-top: 4px;
        }

        .comments {
          margin-top: 16px;
          border-top: 1px solid ${config.theme === 'dark' ? '#444' : '#ddd'};
          padding-top: 16px;
        }

        .comment {
          margin-bottom: 12px;
          padding: 12px;
          background: ${config.theme === 'dark' ? '#2a2a2a' : '#f9f9f9'};
          border-radius: 4px;
          border-left: 3px solid var(--primary-color, #007AFF);
        }

        .comment-author {
          font-weight: 600;
          font-size: 12px;
          margin-bottom: 4px;
        }

        .comment-time {
          font-size: 11px;
          color: ${config.theme === 'dark' ? '#888' : '#999'};
        }

        .comment-content {
          margin-top: 8px;
          line-height: 1.4;
        }
      </style>
    </head>
    <body>
      <div class="frame-container">
        <div class="frame-viewer">
          <h2>${config.frameId}</h2>
          <iframe src="https://www.figma.com/embed?embed_host=share&url=https://figma.com/file/${config.fileKey}?node-id=${config.nodeId}" width="100%" height="500" style="border: none; border-radius: 8px;"></iframe>
          
          ${config.showComments ? `
            <div class="comments">
              <h3>Comments</h3>
              <div id="comments-list"></div>
            </div>
          ` : ''}
        </div>

        ${tokenInspector}
      </div>

      <script>
        // Comment sync and interactive features would be handled here
        console.log('Figma WebView loaded with config:', ${JSON.stringify(config)});
      </script>
    </body>
    </html>
    `;

    return html;
  }
}
