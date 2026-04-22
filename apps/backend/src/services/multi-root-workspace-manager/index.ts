#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/multi-root-workspace-manager/index.ts
 * @module      collaboration/multi-root-workspace-manager
 * @description Multi-root workspace profiles with project-specific settings and shared roots
 */

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export interface WorkspaceProfileRoot {
  path: string;
  label?: string;
  primary?: boolean;
}

export interface WorkspaceProfile {
  id: string;
  userId: string;
  projectName: string;
  description: string | null;
  roots: WorkspaceProfileRoot[];
  settings: Record<string, any>;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateWorkspaceProfileInput {
  userId: string;
  projectName: string;
  roots: WorkspaceProfileRoot[];
  description?: string;
  settings?: Record<string, any>;
  isActive?: boolean;
}

export interface UpdateWorkspaceProfileInput {
  projectName?: string;
  description?: string | null;
  roots?: WorkspaceProfileRoot[];
  settings?: Record<string, any>;
  isActive?: boolean;
}

export class MultiRootWorkspaceManagerService extends EventEmitter {
  private logger = getLogger('MultiRootWorkspaceManagerService');
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
        CREATE TABLE IF NOT EXISTS workspace_profiles (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          project_name VARCHAR(255) NOT NULL,
          description TEXT,
          roots JSONB NOT NULL DEFAULT '[]'::jsonb,
          settings JSONB NOT NULL DEFAULT '{}'::jsonb,
          is_active BOOLEAN NOT NULL DEFAULT FALSE,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, project_name)
        )
      `);

      await client.query(`
        CREATE TABLE IF NOT EXISTS workspace_profile_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          profile_id UUID NOT NULL,
          action VARCHAR(64) NOT NULL,
          details JSONB,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`
        CREATE TABLE IF NOT EXISTS workspace_profile_roots (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          profile_id UUID NOT NULL,
          root_path TEXT NOT NULL,
          root_label TEXT,
          is_primary BOOLEAN NOT NULL DEFAULT FALSE,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);

      await client.query(`CREATE INDEX IF NOT EXISTS idx_workspace_profiles_user ON workspace_profiles(user_id, is_active, updated_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_workspace_profiles_project ON workspace_profiles(project_name)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_workspace_profile_history_profile ON workspace_profile_history(profile_id, created_at DESC)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_workspace_profile_roots_profile ON workspace_profile_roots(profile_id, root_path)`);
    } finally {
      client.release();
    }
  }

  async createProfile(input: CreateWorkspaceProfileInput): Promise<WorkspaceProfile> {
    const client = await this.pool.connect();
    try {
      if (!input.roots || input.roots.length === 0) {
        throw new Error('Workspace profile requires at least one root');
      }

      const normalizedRoots = this.normalizeRoots(input.roots);
      const result = await client.query(
        `
          INSERT INTO workspace_profiles (user_id, project_name, description, roots, settings, is_active)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
        `,
        [
          input.userId,
          input.projectName,
          input.description || null,
          JSON.stringify(normalizedRoots),
          JSON.stringify(input.settings || {}),
          input.isActive || false
        ]
      );

      const profile = this.rowToProfile(result.rows[0]);
      await client.query(
        `INSERT INTO workspace_profile_history (profile_id, action, details) VALUES ($1, $2, $3)`,
        [profile.id, 'created', JSON.stringify({ projectName: profile.projectName, roots: profile.roots.length })]
      );

      this.emit('profile-created', profile);
      return profile;
    } finally {
      client.release();
    }
  }

  async getProfile(profileId: string): Promise<WorkspaceProfile | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at FROM workspace_profiles WHERE id = $1`,
        [profileId]
      );

      if (result.rows.length === 0) return null;
      return this.rowToProfile(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async listProfiles(userId: string): Promise<WorkspaceProfile[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
         FROM workspace_profiles
         WHERE user_id = $1
         ORDER BY is_active DESC, updated_at DESC`,
        [userId]
      );

      return result.rows.map(row => this.rowToProfile(row));
    } finally {
      client.release();
    }
  }

  async getActiveProfile(userId: string): Promise<WorkspaceProfile | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
         FROM workspace_profiles
         WHERE user_id = $1 AND is_active = true
         ORDER BY updated_at DESC
         LIMIT 1`,
        [userId]
      );

      if (result.rows.length === 0) return null;
      return this.rowToProfile(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async updateProfile(profileId: string, updates: UpdateWorkspaceProfileInput): Promise<WorkspaceProfile> {
    const client = await this.pool.connect();
    try {
      const profile = await this.getProfile(profileId);
      if (!profile) {
        throw new Error(`Workspace profile ${profileId} not found`);
      }

      const nextProjectName = updates.projectName ?? profile.projectName;
      const nextDescription = updates.description !== undefined ? updates.description : profile.description;
      const nextRoots = updates.roots ? this.normalizeRoots(updates.roots) : profile.roots;
      const nextSettings = updates.settings ?? profile.settings;
      const nextActive = updates.isActive ?? profile.isActive;

      const result = await client.query(
        `
          UPDATE workspace_profiles
          SET project_name = $1,
              description = $2,
              roots = $3,
              settings = $4,
              is_active = $5,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $6
          RETURNING id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
        `,
        [nextProjectName, nextDescription, JSON.stringify(nextRoots), JSON.stringify(nextSettings), nextActive, profileId]
      );

      const updated = this.rowToProfile(result.rows[0]);
      await client.query(
        `INSERT INTO workspace_profile_history (profile_id, action, details) VALUES ($1, $2, $3)`,
        [profileId, 'updated', JSON.stringify({ projectName: updated.projectName, roots: updated.roots.length })]
      );

      this.emit('profile-updated', updated);
      return updated;
    } finally {
      client.release();
    }
  }

  async addRoot(profileId: string, root: WorkspaceProfileRoot): Promise<WorkspaceProfile> {
    const client = await this.pool.connect();
    try {
      const profile = await this.getProfile(profileId);
      if (!profile) {
        throw new Error(`Workspace profile ${profileId} not found`);
      }

      const nextRoots = profile.roots.filter(existing => existing.path !== root.path);
      const nextRoot = {
        path: root.path,
        label: root.label,
        primary: root.primary ?? nextRoots.length === 0
      };

      if (nextRoot.primary) {
        nextRoots.forEach(existing => {
          existing.primary = false;
        });
      }

      nextRoots.push(nextRoot);

      const result = await client.query(
        `
          UPDATE workspace_profiles
          SET roots = $1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $2
          RETURNING id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
        `,
        [JSON.stringify(nextRoots), profileId]
      );

      const updated = this.rowToProfile(result.rows[0]);
      await client.query(
        `INSERT INTO workspace_profile_history (profile_id, action, details) VALUES ($1, $2, $3)`,
        [profileId, 'root-added', JSON.stringify({ rootPath: root.path })]
      );

      this.emit('root-added', updated);
      return updated;
    } finally {
      client.release();
    }
  }

  async removeRoot(profileId: string, rootPath: string): Promise<WorkspaceProfile> {
    const client = await this.pool.connect();
    try {
      const profile = await this.getProfile(profileId);
      if (!profile) {
        throw new Error(`Workspace profile ${profileId} not found`);
      }

      const nextRoots = profile.roots.filter(root => root.path !== rootPath);
      if (nextRoots.length > 0 && !nextRoots.some(root => root.primary)) {
        nextRoots[0].primary = true;
      }

      const result = await client.query(
        `
          UPDATE workspace_profiles
          SET roots = $1,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $2
          RETURNING id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
        `,
        [JSON.stringify(nextRoots), profileId]
      );

      const updated = this.rowToProfile(result.rows[0]);
      await client.query(
        `INSERT INTO workspace_profile_history (profile_id, action, details) VALUES ($1, $2, $3)`,
        [profileId, 'root-removed', JSON.stringify({ rootPath })]
      );

      this.emit('root-removed', updated);
      return updated;
    } finally {
      client.release();
    }
  }

  async activateProfile(profileId: string): Promise<WorkspaceProfile> {
    const profile = await this.getProfile(profileId);
    if (!profile) {
      throw new Error(`Workspace profile ${profileId} not found`);
    }

    const client = await this.pool.connect();
    try {
      await client.query(`UPDATE workspace_profiles SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE user_id = $1`, [profile.userId]);
      const result = await client.query(
        `
          UPDATE workspace_profiles
          SET is_active = true, updated_at = CURRENT_TIMESTAMP
          WHERE id = $1
          RETURNING id, user_id, project_name, description, roots, settings, is_active, created_at, updated_at
        `,
        [profileId]
      );

      const active = this.rowToProfile(result.rows[0]);
      await client.query(
        `INSERT INTO workspace_profile_history (profile_id, action, details) VALUES ($1, $2, $3)`,
        [profileId, 'activated', JSON.stringify({ userId: profile.userId })]
      );

      this.emit('profile-activated', active);
      return active;
    } finally {
      client.release();
    }
  }

  async cloneProfile(profileId: string, newProjectName?: string): Promise<WorkspaceProfile> {
    const profile = await this.getProfile(profileId);
    if (!profile) {
      throw new Error(`Workspace profile ${profileId} not found`);
    }

    const cloned = await this.createProfile({
      userId: profile.userId,
      projectName: newProjectName || `${profile.projectName} copy`,
      description: profile.description || undefined,
      roots: profile.roots,
      settings: profile.settings,
      isActive: false
    });

    this.emit('profile-cloned', { sourceProfileId: profileId, profileId: cloned.id });
    return cloned;
  }

  async deleteProfile(profileId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`DELETE FROM workspace_profiles WHERE id = $1 RETURNING id, user_id`, [profileId]);
      if (result.rows.length === 0) {
        throw new Error(`Workspace profile ${profileId} not found`);
      }

      await client.query(
        `INSERT INTO workspace_profile_history (profile_id, action, details) VALUES ($1, $2, $3)`,
        [profileId, 'deleted', JSON.stringify({ userId: result.rows[0].user_id })]
      );

      this.emit('profile-deleted', { profileId });
    } finally {
      client.release();
    }
  }

  private normalizeRoots(roots: WorkspaceProfileRoot[]): WorkspaceProfileRoot[] {
    const normalized = roots.map((root, index) => ({
      path: root.path,
      label: root.label,
      primary: root.primary ?? index === 0
    }));

    const primaryIndex = normalized.findIndex(root => root.primary);
    if (primaryIndex > 0) {
      normalized.forEach((root, index) => {
        root.primary = index === primaryIndex;
      });
    }

    return normalized;
  }

  private rowToProfile(row: any): WorkspaceProfile {
    return {
      id: row.id,
      userId: row.user_id,
      projectName: row.project_name,
      description: row.description,
      roots: row.roots || [],
      settings: row.settings || {},
      isActive: row.is_active,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }
}

export async function initializeMultiRootWorkspaceManagerRoutes(service: MultiRootWorkspaceManagerService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('MultiRootWorkspaceManagerRoutes');

  router.post('/api/workspace-profiles', async (req, res) => {
    try {
      const { userId, projectName, roots, description, settings, isActive } = req.body;
      const profile = await service.createProfile({ userId, projectName, roots, description, settings, isActive });
      res.status(201).json(profile);
    } catch (error) {
      logger.error('Failed to create workspace profile', error);
      res.status(500).json({ error: 'Failed to create workspace profile' });
    }
  });

  router.get('/api/workspace-profiles/:userId', async (req, res) => {
    try {
      const profiles = await service.listProfiles(req.params.userId);
      res.json(profiles);
    } catch (error) {
      logger.error('Failed to list workspace profiles', error);
      res.status(500).json({ error: 'Failed to list workspace profiles' });
    }
  });

  router.get('/api/workspace-profiles/profile/:profileId', async (req, res) => {
    try {
      const profile = await service.getProfile(req.params.profileId);
      if (!profile) {
        res.status(404).json({ error: 'Workspace profile not found' });
        return;
      }
      res.json(profile);
    } catch (error) {
      logger.error('Failed to get workspace profile', error);
      res.status(500).json({ error: 'Failed to get workspace profile' });
    }
  });

  router.patch('/api/workspace-profiles/profile/:profileId', async (req, res) => {
    try {
      const profile = await service.updateProfile(req.params.profileId, req.body);
      res.json(profile);
    } catch (error) {
      logger.error('Failed to update workspace profile', error);
      res.status(500).json({ error: 'Failed to update workspace profile' });
    }
  });

  router.post('/api/workspace-profiles/profile/:profileId/roots', async (req, res) => {
    try {
      const profile = await service.addRoot(req.params.profileId, req.body);
      res.json(profile);
    } catch (error) {
      logger.error('Failed to add workspace profile root', error);
      res.status(500).json({ error: 'Failed to add workspace profile root' });
    }
  });

  router.delete('/api/workspace-profiles/profile/:profileId/roots', async (req, res) => {
    try {
      const { rootPath } = req.body;
      const profile = await service.removeRoot(req.params.profileId, rootPath);
      res.json(profile);
    } catch (error) {
      logger.error('Failed to remove workspace profile root', error);
      res.status(500).json({ error: 'Failed to remove workspace profile root' });
    }
  });

  router.post('/api/workspace-profiles/profile/:profileId/activate', async (req, res) => {
    try {
      const profile = await service.activateProfile(req.params.profileId);
      res.json(profile);
    } catch (error) {
      logger.error('Failed to activate workspace profile', error);
      res.status(500).json({ error: 'Failed to activate workspace profile' });
    }
  });

  router.post('/api/workspace-profiles/profile/:profileId/clone', async (req, res) => {
    try {
      const { projectName } = req.body;
      const profile = await service.cloneProfile(req.params.profileId, projectName);
      res.status(201).json(profile);
    } catch (error) {
      logger.error('Failed to clone workspace profile', error);
      res.status(500).json({ error: 'Failed to clone workspace profile' });
    }
  });

  router.delete('/api/workspace-profiles/profile/:profileId', async (req, res) => {
    try {
      await service.deleteProfile(req.params.profileId);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to delete workspace profile', error);
      res.status(500).json({ error: 'Failed to delete workspace profile' });
    }
  });

  router.get('/api/workspace-profiles/active/:userId', async (req, res) => {
    try {
      const profile = await service.getActiveProfile(req.params.userId);
      if (!profile) {
        res.status(404).json({ error: 'Active profile not found' });
        return;
      }
      res.json(profile);
    } catch (error) {
      logger.error('Failed to get active workspace profile', error);
      res.status(500).json({ error: 'Failed to get active workspace profile' });
    }
  });

  return router;
}
