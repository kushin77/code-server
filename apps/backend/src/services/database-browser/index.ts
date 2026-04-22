#!/usr/bin/env bash
/**
 * @file        apps/backend/src/services/database-browser/index.ts
 * @module      services/developer-experience
 * @description Multi-database browser with schema exploration and query execution
 */

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface DatabaseSchema {
  databaseType: string;
  databaseName: string;
  tables: Table[];
  views: View[];
}

export interface Table {
  name: string;
  columns: Column[];
  rowCount: number;
  size: string;
}

export interface Column {
  name: string;
  type: string;
  nullable: boolean;
  isPrimaryKey: boolean;
  defaultValue?: string;
}

export interface View {
  name: string;
  definition: string;
}

export interface QueryResult {
  queryId: string;
  query: string;
  rows: any[];
  rowCount: number;
  executionTime: number;
  columns: string[];
}

export class DatabaseBrowserService extends EventEmitter {
  private logger = getLogger('DatabaseBrowserService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    this.logger.info('Initializing DatabaseBrowserService');
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Create query_history table
      await client.query(`
        CREATE TABLE IF NOT EXISTS query_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          query_text TEXT NOT NULL,
          database_type VARCHAR(50) NOT NULL,
          database_name VARCHAR(255) NOT NULL,
          execution_time_ms FLOAT,
          row_count INTEGER,
          error_message TEXT,
          user_id UUID,
          executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create saved_queries table
      await client.query(`
        CREATE TABLE IF NOT EXISTS saved_queries (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          query_name VARCHAR(255) NOT NULL,
          query_text TEXT NOT NULL,
          database_type VARCHAR(50) NOT NULL,
          user_id UUID,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create query_export_history table
      await client.query(`
        CREATE TABLE IF NOT EXISTS query_export_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          query_id UUID NOT NULL,
          export_format VARCHAR(50),
          export_size_bytes INTEGER,
          exported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create indexes
      await client.query(`CREATE INDEX IF NOT EXISTS idx_query_history_database ON query_history(database_type, database_name, executed_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_saved_queries_user_id ON saved_queries(user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_query_export_history_query_id ON query_export_history(query_id)`);

      this.logger.info('Database browser tables created successfully');
    } finally {
      client.release();
    }
  }

  async getPostgresSchema(databaseName: string): Promise<DatabaseSchema> {
    const client = await this.pool.connect();
    try {
      // Get tables
      const tablesResult = await client.query(
        `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'`
      );

      const tables: Table[] = [];

      for (const tableRow of tablesResult.rows) {
        const tableName = tableRow.table_name;

        // Get columns
        const columnsResult = await client.query(
          `SELECT column_name, data_type, is_nullable, column_default
           FROM information_schema.columns
           WHERE table_name = $1
           ORDER BY ordinal_position`,
          [tableName]
        );

        // Check for primary key
        const pkResult = await client.query(
          `SELECT a.attname
           FROM pg_index i
           JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
           WHERE i.indrelname = $1`,
          [`${tableName}_pkey`]
        );

        const pkColumns = new Set(pkResult.rows.map(r => r.attname));

        const columns: Column[] = columnsResult.rows.map(col => ({
          name: col.column_name,
          type: col.data_type,
          nullable: col.is_nullable === 'YES',
          isPrimaryKey: pkColumns.has(col.column_name),
          defaultValue: col.column_default
        }));

        // Get row count
        const countResult = await client.query(
          `SELECT COUNT(*) as count FROM ${tableName}`
        );

        tables.push({
          name: tableName,
          columns,
          rowCount: countResult.rows[0].count,
          size: '0 MB' // Placeholder
        });
      }

      // Get views
      const viewsResult = await client.query(
        `SELECT table_name, view_definition FROM information_schema.views WHERE table_schema = 'public'`
      );

      const views: View[] = viewsResult.rows.map(row => ({
        name: row.table_name,
        definition: row.view_definition
      }));

      return {
        databaseType: 'PostgreSQL',
        databaseName,
        tables,
        views
      };
    } finally {
      client.release();
    }
  }

  async executeQuery(query: string, databaseType: string, databaseName: string, userId?: string): Promise<QueryResult> {
    const client = await this.pool.connect();
    try {
      const startTime = Date.now();
      let result: any;
      let error: any;

      try {
        result = await client.query(query);
      } catch (err) {
        error = err;
      }

      const executionTime = Date.now() - startTime;

      // Record in history
      await client.query(
        `INSERT INTO query_history (query_text, database_type, database_name, execution_time_ms, row_count, error_message, user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [query, databaseType, databaseName, executionTime, result?.rowCount || 0, error?.message, userId]
      );

      if (error) {
        throw error;
      }

      const columns = result.fields ? result.fields.map((f: any) => f.name) : [];

      this.emit('query-executed', { query, databaseType, executionTime });

      return {
        queryId: Math.random().toString(36),
        query,
        rows: result.rows || [],
        rowCount: result.rowCount || 0,
        executionTime,
        columns
      };
    } finally {
      client.release();
    }
  }

  async saveQuery(queryName: string, queryText: string, databaseType: string, userId?: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO saved_queries (query_name, query_text, database_type, user_id)
         VALUES ($1, $2, $3, $4)`,
        [queryName, queryText, databaseType, userId]
      );

      this.emit('query-saved', { queryName, databaseType });
    } finally {
      client.release();
    }
  }

  async getSavedQueries(userId?: string): Promise<any[]> {
    const client = await this.pool.connect();
    try {
      let query = `SELECT id, query_name, query_text, database_type, created_at FROM saved_queries`;
      const params: any[] = [];

      if (userId) {
        query += ` WHERE user_id = $1`;
        params.push(userId);
      }

      query += ` ORDER BY created_at DESC`;

      const result = await client.query(query, params);
      return result.rows;
    } finally {
      client.release();
    }
  }

  async exportQueryResults(query: string, format: 'csv' | 'json', databaseType: string): Promise<string> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(query);

      let exportData = '';

      if (format === 'csv') {
        const headers = result.fields ? result.fields.map((f: any) => f.name) : [];
        exportData = headers.join(',') + '\n';

        result.rows.forEach(row => {
          const values = headers.map(h => JSON.stringify(row[h] || ''));
          exportData += values.join(',') + '\n';
        });
      } else if (format === 'json') {
        exportData = JSON.stringify(result.rows, null, 2);
      }

      // Record export
      await client.query(
        `INSERT INTO query_export_history (query_id, export_format, export_size_bytes)
         VALUES ($1, $2, $3)`,
        [Math.random().toString(36), format, Buffer.byteLength(exportData)]
      );

      this.emit('export-completed', { format, size: exportData.length });

      return exportData;
    } finally {
      client.release();
    }
  }

  async getQueryHistory(databaseType: string, limit: number = 50): Promise<any[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, query_text, execution_time_ms, row_count, error_message, executed_at
         FROM query_history
         WHERE database_type = $1
         ORDER BY executed_at DESC
         LIMIT $2`,
        [databaseType, limit]
      );

      return result.rows;
    } finally {
      client.release();
    }
  }

  async autocompleteTableNames(databaseType: string, prefix?: string): Promise<string[]> {
    const client = await this.pool.connect();
    try {
      let query = `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'`;
      const params: any[] = [];

      if (prefix) {
        query += ` AND table_name ILIKE $1`;
        params.push(`${prefix}%`);
      }

      const result = await client.query(query, params);
      return result.rows.map(r => r.table_name);
    } finally {
      client.release();
    }
  }

  async autocompleteColumnNames(databaseType: string, tableName: string, prefix?: string): Promise<string[]> {
    const client = await this.pool.connect();
    try {
      let query = `SELECT column_name FROM information_schema.columns WHERE table_name = $1`;
      const params: any[] = [tableName];

      if (prefix) {
        query += ` AND column_name ILIKE $2`;
        params.push(`${prefix}%`);
      }

      const result = await client.query(query, params);
      return result.rows.map(r => r.column_name);
    } finally {
      client.release();
    }
  }

  async cleanupOldQueryHistory(daysOld: number = 30): Promise<number> {
    const client = await this.pool.connect();
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);

      const result = await client.query(
        `DELETE FROM query_history WHERE executed_at < $1`,
        [cutoffDate]
      );

      this.emit('history-cleaned', { count: result.rowCount, daysOld });

      return result.rowCount || 0;
    } finally {
      client.release();
    }
  }
}

export async function initializeDatabaseBrowserRoutes(service: DatabaseBrowserService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('DatabaseBrowserRoutes');

  router.get('/api/database/schema/:databaseType/:databaseName', async (req, res) => {
    try {
      const { databaseType, databaseName } = req.params;
      const schema = await service.getPostgresSchema(databaseName);
      res.json(schema);
    } catch (error) {
      logger.error('Failed to get schema', error);
      res.status(500).json({ error: 'Failed to get schema' });
    }
  });

  router.post('/api/database/query/execute', async (req, res) => {
    try {
      const { query, databaseType, databaseName, userId } = req.body;
      const result = await service.executeQuery(query, databaseType, databaseName, userId);
      res.json(result);
    } catch (error) {
      logger.error('Failed to execute query', error);
      res.status(500).json({ error: 'Query execution failed' });
    }
  });

  router.post('/api/database/query/save', async (req, res) => {
    try {
      const { queryName, queryText, databaseType, userId } = req.body;
      await service.saveQuery(queryName, queryText, databaseType, userId);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to save query', error);
      res.status(500).json({ error: 'Failed to save query' });
    }
  });

  router.get('/api/database/query/saved', async (req, res) => {
    try {
      const userId = req.query.userId as string;
      const queries = await service.getSavedQueries(userId);
      res.json(queries);
    } catch (error) {
      logger.error('Failed to get saved queries', error);
      res.status(500).json({ error: 'Failed to get saved queries' });
    }
  });

  router.post('/api/database/query/export', async (req, res) => {
    try {
      const { query, format, databaseType } = req.body;
      const data = await service.exportQueryResults(query, format, databaseType);
      res.set('Content-Type', format === 'csv' ? 'text/csv' : 'application/json');
      res.send(data);
    } catch (error) {
      logger.error('Failed to export query results', error);
      res.status(500).json({ error: 'Failed to export query results' });
    }
  });

  router.get('/api/database/query/history/:databaseType', async (req, res) => {
    try {
      const { databaseType } = req.params;
      const history = await service.getQueryHistory(databaseType);
      res.json(history);
    } catch (error) {
      logger.error('Failed to get query history', error);
      res.status(500).json({ error: 'Failed to get query history' });
    }
  });

  router.get('/api/database/autocomplete/tables', async (req, res) => {
    try {
      const { databaseType, prefix } = req.query;
      const tables = await service.autocompleteTableNames(databaseType as string, prefix as string);
      res.json(tables);
    } catch (error) {
      logger.error('Failed to autocomplete tables', error);
      res.status(500).json({ error: 'Failed to autocomplete tables' });
    }
  });

  router.get('/api/database/autocomplete/columns', async (req, res) => {
    try {
      const { databaseType, tableName, prefix } = req.query;
      const columns = await service.autocompleteColumnNames(databaseType as string, tableName as string, prefix as string);
      res.json(columns);
    } catch (error) {
      logger.error('Failed to autocomplete columns', error);
      res.status(500).json({ error: 'Failed to autocomplete columns' });
    }
  });

  return router;
}
