#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/message-compression-pipeline/index.ts
 * @module      collaboration/message-compression-pipeline
 * @description Gzip-backed collaboration message compression pipeline with metrics tracking
 */

import { EventEmitter } from 'events';
import * as lz4 from 'lz4js';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

type CompressionMethod = 'lz4' | 'lz4-delta';

interface CompressionInput {
  sessionId: string;
  channel: string;
  message: string;
  metadata?: Record<string, any>;
}

interface CompressionPayload {
  type: 'full' | 'delta';
  message?: string;
  baseMessageId?: string;
  prefixLength?: number;
  suffix?: string;
}

export interface CompressedMessage {
  id: string;
  sessionId: string;
  channel: string;
  compressionMethod: CompressionMethod;
  baseMessageId: string | null;
  originalSizeBytes: number;
  compressedSizeBytes: number;
  compressionRatio: number;
  compressedPayload: string;
  metadata: Record<string, any>;
  underOneKilobyte: boolean;
  createdAt: Date;
}

export interface CompressionPipelineMetrics {
  totalMessages: number;
  averageOriginalSizeBytes: number;
  averageCompressedSizeBytes: number;
  averageCompressionRatio: number;
  underOneKilobyteCount: number;
  compressionSavingsBytes: number;
  recordedAt: Date;
}

export class MessageCompressionPipelineService extends EventEmitter {
  private logger = getLogger('MessageCompressionPipelineService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        CREATE TABLE IF NOT EXISTS compressed_collaboration_messages (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL,
          channel VARCHAR(255) NOT NULL,
          compression_method VARCHAR(32) NOT NULL DEFAULT 'lz4',
          base_message_id UUID,
          original_size_bytes INTEGER NOT NULL,
          compressed_size_bytes INTEGER NOT NULL,
          compression_ratio FLOAT NOT NULL,
          compressed_payload TEXT NOT NULL,
          metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
          under_one_kb BOOLEAN NOT NULL DEFAULT FALSE,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`
        CREATE TABLE IF NOT EXISTS compression_pipeline_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          message_id UUID NOT NULL,
          session_id VARCHAR(255) NOT NULL,
          original_size_bytes INTEGER NOT NULL,
          compressed_size_bytes INTEGER NOT NULL,
          compression_ratio FLOAT NOT NULL,
          compression_time_ms FLOAT NOT NULL,
          under_one_kb BOOLEAN NOT NULL DEFAULT FALSE,
          recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`CREATE INDEX IF NOT EXISTS idx_compressed_messages_session ON compressed_collaboration_messages(session_id, created_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_compressed_messages_channel ON compressed_collaboration_messages(channel)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_compressed_messages_base ON compressed_collaboration_messages(base_message_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_compression_metrics_session ON compression_pipeline_metrics(session_id, recorded_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_compression_metrics_under_kb ON compression_pipeline_metrics(under_one_kb)`);
    } finally {
      client.release();
    }
  }

  async compressBatch(items: CompressionInput[]): Promise<CompressedMessage[]> {
    if (items.length === 0) return [];

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const previousByKey = new Map<string, { messageId: string; message: string }>();
      const compressed: CompressedMessage[] = [];

      for (const item of items) {
        const key = `${item.sessionId}::${item.channel}`;
        const previous = previousByKey.get(key);

        const messageBytes = Buffer.from(item.message, 'utf8');
        let compressionMethod: CompressionMethod = 'lz4';
        let baseMessageId: string | null = null;
        let payload: CompressionPayload = {
          type: 'full',
          message: item.message
        };

        if (previous) {
          const prefixLength = this.getCommonPrefixLength(previous.message, item.message);
          const suffix = item.message.slice(prefixLength);
          if (prefixLength > 0) {
            compressionMethod = 'lz4-delta';
            baseMessageId = previous.messageId;
            payload = {
              type: 'delta',
              baseMessageId,
              prefixLength,
              suffix
            };
          }
        }

        const compressedPayload = this.encodePayload(payload);
        const compressedSizeBytes = Buffer.byteLength(compressedPayload, 'utf8');
        const originalSizeBytes = messageBytes.byteLength;
        const compressionRatio = originalSizeBytes === 0 ? 0 : compressedSizeBytes / originalSizeBytes;
        const underOneKilobyte = compressedSizeBytes <= 1024;

        const result = await client.query(
          `
            INSERT INTO compressed_collaboration_messages
            (session_id, channel, compression_method, base_message_id, original_size_bytes, compressed_size_bytes, compression_ratio, compressed_payload, metadata, under_one_kb)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            RETURNING id, session_id, channel, compression_method, base_message_id, original_size_bytes, compressed_size_bytes, compression_ratio, compressed_payload, metadata, under_one_kb, created_at
          `,
          [
            item.sessionId,
            item.channel,
            compressionMethod,
            baseMessageId,
            originalSizeBytes,
            compressedSizeBytes,
            compressionRatio,
            compressedPayload,
            JSON.stringify(item.metadata || {}),
            underOneKilobyte
          ]
        );

        const messageRow = result.rows[0];
        const record = this.rowToCompressedMessage(messageRow);
        compressed.push(record);

        previousByKey.set(key, { messageId: record.id, message: item.message });

        await client.query(
          `
            INSERT INTO compression_pipeline_metrics
            (message_id, session_id, original_size_bytes, compressed_size_bytes, compression_ratio, compression_time_ms, under_one_kb)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
          `,
          [record.id, item.sessionId, originalSizeBytes, compressedSizeBytes, compressionRatio, 1, underOneKilobyte]
        );
      }

      await client.query('COMMIT');
      this.emit('batch-compressed', { count: compressed.length });
      return compressed;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async compressMessage(
    sessionId: string,
    channel: string,
    message: string,
    metadata: Record<string, any> = {}
  ): Promise<CompressedMessage> {
    const [compressed] = await this.compressBatch([
      { sessionId, channel, message, metadata }
    ]);
    this.emit('message-compressed', compressed);
    return compressed;
  }

  async decompressMessage(messageId: string): Promise<{ id: string; sessionId: string; channel: string; message: string; metadata: Record<string, any> } | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, session_id, channel, compression_method, base_message_id, compressed_payload, metadata FROM compressed_collaboration_messages WHERE id = $1`,
        [messageId]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      const payload = this.decodePayload(row.compressed_payload);
      const message = await this.resolveMessageFromPayload(client, row, payload);
      const decompressed = {
        id: row.id,
        sessionId: row.session_id,
        channel: row.channel,
        message,
        metadata: row.metadata || {}
      };

      this.emit('message-decompressed', decompressed);
      return decompressed;
    } finally {
      client.release();
    }
  }

  async getCompressedMessage(messageId: string): Promise<CompressedMessage | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          SELECT id, session_id, channel, compression_method, base_message_id, original_size_bytes, compressed_size_bytes, compression_ratio, compressed_payload, metadata, under_one_kb, created_at
          FROM compressed_collaboration_messages
          WHERE id = $1
        `,
        [messageId]
      );

      if (result.rows.length === 0) return null;
      const row = result.rows[0];
      return {
        id: row.id,
        sessionId: row.session_id,
        channel: row.channel,
        compressionMethod: row.compression_method,
        baseMessageId: row.base_message_id,
        originalSizeBytes: row.original_size_bytes,
        compressedSizeBytes: row.compressed_size_bytes,
        compressionRatio: row.compression_ratio,
        compressedPayload: row.compressed_payload,
        metadata: row.metadata || {},
        underOneKilobyte: row.under_one_kb,
        createdAt: row.created_at
      };
    } finally {
      client.release();
    }
  }

  async getSessionMessages(sessionId: string, limit: number = 20): Promise<CompressedMessage[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          SELECT id, session_id, channel, compression_method, base_message_id, original_size_bytes, compressed_size_bytes, compression_ratio, compressed_payload, metadata, under_one_kb, created_at
          FROM compressed_collaboration_messages
          WHERE session_id = $1
          ORDER BY created_at DESC
          LIMIT $2
        `,
        [sessionId, limit]
      );

      return result.rows.map(row => ({
        id: row.id,
        sessionId: row.session_id,
        channel: row.channel,
        compressionMethod: row.compression_method,
        baseMessageId: row.base_message_id,
        originalSizeBytes: row.original_size_bytes,
        compressedSizeBytes: row.compressed_size_bytes,
        compressionRatio: row.compression_ratio,
        compressedPayload: row.compressed_payload,
        metadata: row.metadata || {},
        underOneKilobyte: row.under_one_kb,
        createdAt: row.created_at
      }));
    } finally {
      client.release();
    }
  }

  async getPipelineMetrics(days: number = 7): Promise<CompressionPipelineMetrics> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `
          SELECT
            COUNT(*)::int AS total_messages,
            COALESCE(AVG(original_size_bytes), 0) AS average_original_size_bytes,
            COALESCE(AVG(compressed_size_bytes), 0) AS average_compressed_size_bytes,
            COALESCE(AVG(compression_ratio), 0) AS average_compression_ratio,
            COALESCE(SUM(CASE WHEN under_one_kb THEN 1 ELSE 0 END), 0) AS under_one_kb_count,
            COALESCE(SUM(original_size_bytes - compressed_size_bytes), 0) AS compression_savings_bytes
          FROM compression_pipeline_metrics
          WHERE recorded_at >= NOW() - INTERVAL '1 day' * $1
        `,
        [days]
      );

      const row = result.rows[0] || {};
      const metrics: CompressionPipelineMetrics = {
        totalMessages: Number(row.total_messages || 0),
        averageOriginalSizeBytes: Number(row.average_original_size_bytes || 0),
        averageCompressedSizeBytes: Number(row.average_compressed_size_bytes || 0),
        averageCompressionRatio: Number(row.average_compression_ratio || 0),
        underOneKilobyteCount: Number(row.under_one_kb_count || 0),
        compressionSavingsBytes: Number(row.compression_savings_bytes || 0),
        recordedAt: new Date()
      };

      this.emit('pipeline-metrics-calculated', metrics);
      return metrics;
    } finally {
      client.release();
    }
  }

  async cleanupOldMessages(daysOld: number = 30): Promise<number> {
    const client = await this.pool.connect();
    try {
      const cutoff = new Date(Date.now() - daysOld * 24 * 60 * 60 * 1000);
      const result = await client.query(
        `DELETE FROM compressed_collaboration_messages WHERE created_at < $1`,
        [cutoff]
      );

      await client.query(
        `DELETE FROM compression_pipeline_metrics WHERE recorded_at < $1`,
        [cutoff]
      );

      const deletedCount = result.rowCount || 0;
      this.emit('messages-cleaned', { count: deletedCount, daysOld });
      return deletedCount;
    } finally {
      client.release();
    }
  }

  private encodePayload(payload: CompressionPayload): string {
    const jsonBytes = Buffer.from(JSON.stringify(payload), 'utf8');
    return Buffer.from(lz4.compress(Array.from(jsonBytes))).toString('base64');
  }

  private decodePayload(encoded: string): CompressionPayload {
    const compressedBytes = Buffer.from(encoded, 'base64');
    const decompressed = Buffer.from(lz4.decompress(Array.from(compressedBytes))).toString('utf8');
    return JSON.parse(decompressed) as CompressionPayload;
  }

  private async resolveMessageFromPayload(
    client: any,
    row: any,
    payload: CompressionPayload
  ): Promise<string> {
    if (payload.type === 'full') {
      return payload.message || '';
    }

    if (!payload.baseMessageId || typeof payload.prefixLength !== 'number') {
      throw new Error('Invalid delta payload');
    }

    const baseResult = await client.query(
      `SELECT id, session_id, channel, compression_method, base_message_id, compressed_payload, metadata FROM compressed_collaboration_messages WHERE id = $1`,
      [payload.baseMessageId]
    );

    if (baseResult.rows.length === 0) {
      throw new Error(`Base message ${payload.baseMessageId} not found`);
    }

    const baseRow = baseResult.rows[0];
    const basePayload = this.decodePayload(baseRow.compressed_payload);
    const baseMessage = await this.resolveMessageFromPayload(client, baseRow, basePayload);
    const prefix = baseMessage.slice(0, payload.prefixLength);
    return `${prefix}${payload.suffix || ''}`;
  }

  private rowToCompressedMessage(row: any): CompressedMessage {
    return {
      id: row.id,
      sessionId: row.session_id,
      channel: row.channel,
      compressionMethod: row.compression_method,
      baseMessageId: row.base_message_id,
      originalSizeBytes: row.original_size_bytes,
      compressedSizeBytes: row.compressed_size_bytes,
      compressionRatio: row.compression_ratio,
      compressedPayload: row.compressed_payload,
      metadata: row.metadata || {},
      underOneKilobyte: row.under_one_kb,
      createdAt: row.created_at
    };
  }

  private getCommonPrefixLength(left: string, right: string): number {
    let index = 0;
    const maxLength = Math.min(left.length, right.length);
    while (index < maxLength && left[index] === right[index]) {
      index += 1;
    }
    return index;
  }
}

export async function initializeMessageCompressionPipelineRoutes(service: MessageCompressionPipelineService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('MessageCompressionPipelineRoutes');

  router.post('/api/message-compression/compress', async (req, res) => {
    try {
      const { sessionId, channel, message, metadata } = req.body;
      const compressed = await service.compressMessage(sessionId, channel, message, metadata || {});
      res.status(201).json(compressed);
    } catch (error) {
      logger.error('Failed to compress message', error);
      res.status(500).json({ error: 'Failed to compress message' });
    }
  });

  router.post('/api/message-compression/compress/batch', async (req, res) => {
    try {
      const { items } = req.body;
      if (!Array.isArray(items) || items.length === 0) {
        res.status(400).json({ error: 'Missing items array' });
        return;
      }

      const compressed = await service.compressBatch(items);
      res.status(201).json(compressed);
    } catch (error) {
      logger.error('Failed to compress message batch', error);
      res.status(500).json({ error: 'Failed to compress message batch' });
    }
  });

  router.get('/api/message-compression/messages/:messageId', async (req, res) => {
    try {
      const message = await service.getCompressedMessage(req.params.messageId);
      if (!message) {
        res.status(404).json({ error: 'Message not found' });
        return;
      }
      res.json(message);
    } catch (error) {
      logger.error('Failed to get compressed message', error);
      res.status(500).json({ error: 'Failed to get compressed message' });
    }
  });

  router.post('/api/message-compression/decompress/:messageId', async (req, res) => {
    try {
      const message = await service.decompressMessage(req.params.messageId);
      if (!message) {
        res.status(404).json({ error: 'Message not found' });
        return;
      }
      res.json(message);
    } catch (error) {
      logger.error('Failed to decompress message', error);
      res.status(500).json({ error: 'Failed to decompress message' });
    }
  });

  router.get('/api/message-compression/session/:sessionId', async (req, res) => {
    try {
      const limit = parseInt(req.query.limit as string, 10) || 20;
      const messages = await service.getSessionMessages(req.params.sessionId, limit);
      res.json(messages);
    } catch (error) {
      logger.error('Failed to get session messages', error);
      res.status(500).json({ error: 'Failed to get session messages' });
    }
  });

  router.get('/api/message-compression/metrics', async (req, res) => {
    try {
      const days = parseInt(req.query.days as string, 10) || 7;
      const metrics = await service.getPipelineMetrics(days);
      res.json(metrics);
    } catch (error) {
      logger.error('Failed to get pipeline metrics', error);
      res.status(500).json({ error: 'Failed to get pipeline metrics' });
    }
  });

  router.delete('/api/message-compression/cleanup', async (req, res) => {
    try {
      const daysOld = parseInt(req.query.daysOld as string, 10) || 30;
      const count = await service.cleanupOldMessages(daysOld);
      res.json({ cleaned: count });
    } catch (error) {
      logger.error('Failed to cleanup compressed messages', error);
      res.status(500).json({ error: 'Failed to cleanup compressed messages' });
    }
  });

  return router;
}
