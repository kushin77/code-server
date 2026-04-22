#!/usr/bin/env bash
/**
 * @file        apps/backend/src/services/dependency-impact-graph/index.ts
 * @module      services/developer-experience
 * @description Dependency impact graph with blast radius calculation
 */

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface Dependency {
  moduleId: string;
  moduleName: string;
  dependsOn: string[];
  dependentOf: string[];
  blastRadiusScore: number;
  hasCircularDependency: boolean;
}

export interface DependencyGraph {
  modules: Dependency[];
  circularDependencies: string[][];
  highRiskModules: Dependency[];
}

export class DependencyImpactGraphService extends EventEmitter {
  private logger = getLogger('DependencyImpactGraphService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    this.logger.info('Initializing DependencyImpactGraphService');
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Create modules table
      await client.query(`
        CREATE TABLE IF NOT EXISTS dependency_modules (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          module_id VARCHAR(255) UNIQUE NOT NULL,
          module_name VARCHAR(255) NOT NULL,
          file_path TEXT,
          size_bytes INTEGER,
          last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create dependencies table
      await client.query(`
        CREATE TABLE IF NOT EXISTS module_dependencies (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          source_module_id VARCHAR(255) NOT NULL,
          target_module_id VARCHAR(255) NOT NULL,
          dependency_type VARCHAR(50),
          is_circular BOOLEAN DEFAULT false,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(source_module_id, target_module_id)
        )
      `);

      // Create blast radius cache table
      await client.query(`
        CREATE TABLE IF NOT EXISTS blast_radius_cache (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          module_id VARCHAR(255) UNIQUE NOT NULL,
          blast_radius_score FLOAT NOT NULL,
          affected_count INTEGER NOT NULL,
          calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create indexes
      await client.query(`CREATE INDEX IF NOT EXISTS idx_dependency_modules_id ON dependency_modules(module_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_module_dependencies_source ON module_dependencies(source_module_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_module_dependencies_target ON module_dependencies(target_module_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_blast_radius_module_id ON blast_radius_cache(module_id)`);

      this.logger.info('Dependency impact graph tables created successfully');
    } finally {
      client.release();
    }
  }

  async addModule(moduleId: string, moduleName: string, filePath?: string, sizeBytes?: number): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO dependency_modules (module_id, module_name, file_path, size_bytes)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (module_id) DO UPDATE SET module_name = $2, last_updated = CURRENT_TIMESTAMP`,
        [moduleId, moduleName, filePath, sizeBytes]
      );

      this.emit('module-added', { moduleId, moduleName });
    } finally {
      client.release();
    }
  }

  async addDependency(sourceModuleId: string, targetModuleId: string, type: string = 'import'): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO module_dependencies (source_module_id, target_module_id, dependency_type)
         VALUES ($1, $2, $3)
         ON CONFLICT (source_module_id, target_module_id) DO UPDATE SET dependency_type = $3`,
        [sourceModuleId, targetModuleId, type]
      );

      this.emit('dependency-added', { sourceModuleId, targetModuleId });
    } finally {
      client.release();
    }
  }

  async getDependency(moduleId: string): Promise<Dependency | null> {
    const client = await this.pool.connect();
    try {
      const moduleResult = await client.query(
        `SELECT module_id, module_name FROM dependency_modules WHERE module_id = $1`,
        [moduleId]
      );

      if (moduleResult.rows.length === 0) return null;

      const module = moduleResult.rows[0];

      // Get dependencies (what this module depends on)
      const dependsOnResult = await client.query(
        `SELECT target_module_id FROM module_dependencies WHERE source_module_id = $1`,
        [moduleId]
      );

      // Get dependents (what depends on this module)
      const dependentOfResult = await client.query(
        `SELECT source_module_id FROM module_dependencies WHERE target_module_id = $1`,
        [moduleId]
      );

      const blastRadius = await this.calculateBlastRadius(moduleId, client);
      const hasCircular = await this.hasCircularDependency(moduleId, client);

      return {
        moduleId: module.module_id,
        moduleName: module.module_name,
        dependsOn: dependsOnResult.rows.map(r => r.target_module_id),
        dependentOf: dependentOfResult.rows.map(r => r.source_module_id),
        blastRadiusScore: blastRadius,
        hasCircularDependency: hasCircular
      };
    } finally {
      client.release();
    }
  }

  private async calculateBlastRadius(moduleId: string, client: any): Promise<number> {
    // Check cache
    const cacheResult = await client.query(
      `SELECT blast_radius_score FROM blast_radius_cache WHERE module_id = $1`,
      [moduleId]
    );

    if (cacheResult.rows.length > 0) {
      return cacheResult.rows[0].blast_radius_score;
    }

    // BFS to find all affected modules
    const visited = new Set<string>();
    const queue = [moduleId];

    while (queue.length > 0) {
      const current = queue.shift();
      if (!current || visited.has(current)) continue;

      visited.add(current);

      const result = await client.query(
        `SELECT source_module_id FROM module_dependencies WHERE target_module_id = $1`,
        [current]
      );

      result.rows.forEach(row => {
        if (!visited.has(row.source_module_id)) {
          queue.push(row.source_module_id);
        }
      });
    }

    const affectedCount = visited.size - 1; // Exclude self
    const score = Math.min(100, affectedCount * 5); // Normalize to 0-100

    // Cache the result
    await client.query(
      `INSERT INTO blast_radius_cache (module_id, blast_radius_score, affected_count)
       VALUES ($1, $2, $3)
       ON CONFLICT (module_id) DO UPDATE SET blast_radius_score = $2, affected_count = $3, calculated_at = CURRENT_TIMESTAMP`,
      [moduleId, score, affectedCount]
    );

    return score;
  }

  private async hasCircularDependency(moduleId: string, client: any): Promise<boolean> {
    const visited = new Set<string>();
    const recursionStack = new Set<string>();

    const hasCycle = async (node: string): Promise<boolean> => {
      visited.add(node);
      recursionStack.add(node);

      const result = await client.query(
        `SELECT target_module_id FROM module_dependencies WHERE source_module_id = $1`,
        [node]
      );

      for (const row of result.rows) {
        const neighbor = row.target_module_id;
        if (!visited.has(neighbor)) {
          if (await hasCycle(neighbor)) {
            return true;
          }
        } else if (recursionStack.has(neighbor)) {
          return true;
        }
      }

      recursionStack.delete(node);
      return false;
    };

    return await hasCycle(moduleId);
  }

  async getGraph(): Promise<DependencyGraph> {
    const client = await this.pool.connect();
    try {
      const modulesResult = await client.query(`SELECT module_id, module_name FROM dependency_modules`);
      
      const modules: Dependency[] = [];
      const highRiskModules: Dependency[] = [];

      for (const moduleRow of modulesResult.rows) {
        const dep = await this.getDependency(moduleRow.module_id);
        if (dep) {
          modules.push(dep);
          if (dep.blastRadiusScore > 70 || dep.hasCircularDependency) {
            highRiskModules.push(dep);
          }
        }
      }

      // Find circular dependencies
      const circularDeps = await this.findCircularDependencies(client);

      return {
        modules,
        circularDependencies: circularDeps,
        highRiskModules
      };
    } finally {
      client.release();
    }
  }

  private async findCircularDependencies(client: any): Promise<string[][]> {
    const result = await client.query(
      `SELECT DISTINCT d1.source_module_id, d2.source_module_id
       FROM module_dependencies d1
       JOIN module_dependencies d2 ON d1.target_module_id = d2.source_module_id
       WHERE d2.target_module_id = d1.source_module_id`
    );

    return result.rows.map(row => [row.source_module_id, row.source_module_id]);
  }

  async cleanupOldData(daysOld: number = 30): Promise<number> {
    const client = await this.pool.connect();
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);

      const result = await client.query(
        `DELETE FROM module_dependencies
         WHERE created_at < $1`,
        [cutoffDate]
      );

      this.emit('data-cleaned', { count: result.rowCount, daysOld });

      return result.rowCount || 0;
    } finally {
      client.release();
    }
  }
}

export async function initializeDependencyImpactGraphRoutes(service: DependencyImpactGraphService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('DependencyImpactGraphRoutes');

  router.post('/api/dependencies/modules', async (req, res) => {
    try {
      const { moduleId, moduleName, filePath, sizeBytes } = req.body;
      await service.addModule(moduleId, moduleName, filePath, sizeBytes);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to add module', error);
      res.status(500).json({ error: 'Failed to add module' });
    }
  });

  router.post('/api/dependencies/links', async (req, res) => {
    try {
      const { sourceModuleId, targetModuleId, type } = req.body;
      await service.addDependency(sourceModuleId, targetModuleId, type);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to add dependency', error);
      res.status(500).json({ error: 'Failed to add dependency' });
    }
  });

  router.get('/api/dependencies/modules/:moduleId', async (req, res) => {
    try {
      const { moduleId } = req.params;
      const dep = await service.getDependency(moduleId);
      
      if (!dep) {
        return res.status(404).json({ error: 'Module not found' });
      }

      res.json(dep);
    } catch (error) {
      logger.error('Failed to get dependency', error);
      res.status(500).json({ error: 'Failed to get dependency' });
    }
  });

  router.get('/api/dependencies/graph', async (req, res) => {
    try {
      const graph = await service.getGraph();
      res.json(graph);
    } catch (error) {
      logger.error('Failed to get graph', error);
      res.status(500).json({ error: 'Failed to get graph' });
    }
  });

  return router;
}
