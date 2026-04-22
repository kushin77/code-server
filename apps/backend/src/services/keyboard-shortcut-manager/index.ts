#!/usr/bin/env bash
/**
 * @file        apps/backend/src/services/keyboard-shortcut-manager/index.ts
 * @module      services/developer-experience
 * @description Org-wide keyboard shortcut profiles with personal overrides and clash detection
 */

import { EventEmitter } from 'events';
import { Pool, PoolClient } from 'pg';
import { getLogger } from '../../lib/logger';

export interface ShortcutProfile {
  id: string;
  name: string;
  description: string;
  isOrgDefault: boolean;
  createdBy: string;
  createdAt: Date;
  shortcuts: Record<string, string>;
}

export interface PersonalOverride {
  id: string;
  userId: string;
  profileId: string;
  overrides: Record<string, string>;
  createdAt: Date;
}

export interface ShortcutClash {
  shortcut: string;
  conflict1: string;
  conflict2: string;
  severity: 'high' | 'medium' | 'low';
}

export class KeyboardShortcutManagerService extends EventEmitter {
  private logger = getLogger('KeyboardShortcutManagerService');
  private pool: Pool;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    this.logger.info('Initializing KeyboardShortcutManagerService');
    await this.createTables();
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Create shortcut_profiles table
      await client.query(`
        CREATE TABLE IF NOT EXISTS shortcut_profiles (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          name VARCHAR(255) NOT NULL,
          description TEXT,
          is_org_default BOOLEAN DEFAULT FALSE,
          created_by UUID NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          shortcuts JSONB NOT NULL
        )
      `);

      // Create personal_shortcut_overrides table
      await client.query(`
        CREATE TABLE IF NOT EXISTS personal_shortcut_overrides (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          profile_id UUID NOT NULL REFERENCES shortcut_profiles(id) ON DELETE CASCADE,
          overrides JSONB NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, profile_id)
        )
      `);

      // Create shortcut_usage_tracking table
      await client.query(`
        CREATE TABLE IF NOT EXISTS shortcut_usage_tracking (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          shortcut_key VARCHAR(100) NOT NULL,
          command VARCHAR(255),
          used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create shortcut_clash_detection table
      await client.query(`
        CREATE TABLE IF NOT EXISTS shortcut_clash_detection (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          shortcut_key VARCHAR(100) NOT NULL,
          profile_id1 UUID NOT NULL,
          profile_id2 UUID NOT NULL,
          conflict_command1 VARCHAR(255),
          conflict_command2 VARCHAR(255),
          severity VARCHAR(20),
          detected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create shortcut_team_sync table
      await client.query(`
        CREATE TABLE IF NOT EXISTS shortcut_team_sync (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id UUID NOT NULL,
          profile_id UUID NOT NULL REFERENCES shortcut_profiles(id) ON DELETE CASCADE,
          synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          sync_status VARCHAR(50)
        )
      `);

      // Create indexes
      await client.query(`CREATE INDEX IF NOT EXISTS idx_shortcut_profiles_org_default ON shortcut_profiles(is_org_default)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_personal_overrides_user_id ON personal_shortcut_overrides(user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_shortcut_usage_user_id ON shortcut_usage_tracking(user_id)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_shortcut_clash_shortcut ON shortcut_clash_detection(shortcut_key)`);
      await client.query(`CREATE INDEX IF NOT EXISTS idx_shortcut_team_sync_team_id ON shortcut_team_sync(team_id)`);

      this.logger.info('Keyboard shortcut manager tables created successfully');
    } finally {
      client.release();
    }
  }

  async createProfile(name: string, description: string, createdBy: string, shortcuts: Record<string, string>, isOrgDefault: boolean = false): Promise<string> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO shortcut_profiles (name, description, created_by, shortcuts, is_org_default)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id`,
        [name, description, createdBy, JSON.stringify(shortcuts), isOrgDefault]
      );

      const profileId = result.rows[0].id;
      this.emit('profile-created', { profileId, name, isOrgDefault });
      return profileId;
    } finally {
      client.release();
    }
  }

  async getProfile(profileId: string): Promise<ShortcutProfile | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, name, description, is_org_default, created_by, created_at, shortcuts FROM shortcut_profiles WHERE id = $1`,
        [profileId]
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        id: row.id,
        name: row.name,
        description: row.description,
        isOrgDefault: row.is_org_default,
        createdBy: row.created_by,
        createdAt: row.created_at,
        shortcuts: row.shortcuts
      };
    } finally {
      client.release();
    }
  }

  async getOrgDefaultProfile(): Promise<ShortcutProfile | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, name, description, is_org_default, created_by, created_at, shortcuts FROM shortcut_profiles WHERE is_org_default = TRUE LIMIT 1`
      );

      if (result.rows.length === 0) return null;

      const row = result.rows[0];
      return {
        id: row.id,
        name: row.name,
        description: row.description,
        isOrgDefault: row.is_org_default,
        createdBy: row.created_by,
        createdAt: row.created_at,
        shortcuts: row.shortcuts
      };
    } finally {
      client.release();
    }
  }

  async setPersonalOverrides(userId: string, profileId: string, overrides: Record<string, string>): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Check if override exists
      const existing = await client.query(
        `SELECT id FROM personal_shortcut_overrides WHERE user_id = $1 AND profile_id = $2`,
        [userId, profileId]
      );

      if (existing.rows.length > 0) {
        // Update existing
        await client.query(
          `UPDATE personal_shortcut_overrides SET overrides = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2 AND profile_id = $3`,
          [JSON.stringify(overrides), userId, profileId]
        );
      } else {
        // Insert new
        await client.query(
          `INSERT INTO personal_shortcut_overrides (user_id, profile_id, overrides) VALUES ($1, $2, $3)`,
          [userId, profileId, JSON.stringify(overrides)]
        );
      }

      this.emit('overrides-set', { userId, profileId, overrideCount: Object.keys(overrides).length });
    } finally {
      client.release();
    }
  }

  async getPersonalOverrides(userId: string, profileId: string): Promise<Record<string, string> | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT overrides FROM personal_shortcut_overrides WHERE user_id = $1 AND profile_id = $2`,
        [userId, profileId]
      );

      if (result.rows.length === 0) return null;
      return result.rows[0].overrides;
    } finally {
      client.release();
    }
  }

  async getMergedShortcuts(userId: string, profileId: string): Promise<Record<string, string>> {
    const client = await this.pool.connect();
    try {
      const profile = await this.getProfile(profileId);
      if (!profile) return {};

      const overrides = await this.getPersonalOverrides(userId, profileId);
      
      // Merge: profile shortcuts + personal overrides
      return { ...profile.shortcuts, ...overrides };
    } finally {
      client.release();
    }
  }

  async detectClashes(profileId1: string, profileId2: string): Promise<ShortcutClash[]> {
    const client = await this.pool.connect();
    try {
      const profile1 = await this.getProfile(profileId1);
      const profile2 = await this.getProfile(profileId2);

      if (!profile1 || !profile2) return [];

      const clashes: ShortcutClash[] = [];

      // Find shortcuts that have the same key but different commands
      for (const [shortcut, command1] of Object.entries(profile1.shortcuts)) {
        if (shortcut in profile2.shortcuts) {
          const command2 = profile2.shortcuts[shortcut];
          if (command1 !== command2) {
            // Determine severity
            let severity: 'high' | 'medium' | 'low' = 'low';
            if (shortcut.includes('Ctrl') || shortcut.includes('Cmd')) {
              severity = 'high';
            } else if (shortcut.includes('Alt')) {
              severity = 'medium';
            }

            clashes.push({
              shortcut,
              conflict1: command1,
              conflict2: command2,
              severity
            });

            // Record clash in database
            await client.query(
              `INSERT INTO shortcut_clash_detection (shortcut_key, profile_id1, profile_id2, conflict_command1, conflict_command2, severity)
               VALUES ($1, $2, $3, $4, $5, $6)`,
              [shortcut, profileId1, profileId2, command1, command2, severity]
            );
          }
        }
      }

      if (clashes.length > 0) {
        this.emit('clashes-detected', { profileId1, profileId2, clashCount: clashes.length });
      }

      return clashes;
    } finally {
      client.release();
    }
  }

  async trackUsage(userId: string, shortcutKey: string, command: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO shortcut_usage_tracking (user_id, shortcut_key, command) VALUES ($1, $2, $3)`,
        [userId, shortcutKey, command]
      );
    } finally {
      client.release();
    }
  }

  async getTopShortcuts(userId: string, limit: number = 10): Promise<any[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT shortcut_key, command, COUNT(*) as usage_count
         FROM shortcut_usage_tracking
         WHERE user_id = $1
         GROUP BY shortcut_key, command
         ORDER BY usage_count DESC
         LIMIT $2`,
        [userId, limit]
      );

      return result.rows;
    } finally {
      client.release();
    }
  }

  async syncProfileToTeam(profileId: string, teamId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO shortcut_team_sync (team_id, profile_id, sync_status) VALUES ($1, $2, 'synced')`,
        [teamId, profileId]
      );

      this.emit('profile-synced-to-team', { profileId, teamId });
    } finally {
      client.release();
    }
  }

  async getTeamSyncedProfiles(teamId: string): Promise<ShortcutProfile[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT p.id, p.name, p.description, p.is_org_default, p.created_by, p.created_at, p.shortcuts
         FROM shortcut_team_sync s
         JOIN shortcut_profiles p ON s.profile_id = p.id
         WHERE s.team_id = $1
         ORDER BY s.synced_at DESC`,
        [teamId]
      );

      return result.rows.map(row => ({
        id: row.id,
        name: row.name,
        description: row.description,
        isOrgDefault: row.is_org_default,
        createdBy: row.created_by,
        createdAt: row.created_at,
        shortcuts: row.shortcuts
      }));
    } finally {
      client.release();
    }
  }

  async quickSwitch(userId: string, fromProfileId: string, toProfileId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Get overrides from old profile
      const oldOverrides = await this.getPersonalOverrides(userId, fromProfileId);

      // Apply similar overrides to new profile if applicable
      if (oldOverrides && Object.keys(oldOverrides).length > 0) {
        await this.setPersonalOverrides(userId, toProfileId, oldOverrides);
      }

      this.emit('quick-switched', { userId, fromProfileId, toProfileId });
    } finally {
      client.release();
    }
  }

  async listProfiles(limit: number = 20): Promise<ShortcutProfile[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT id, name, description, is_org_default, created_by, created_at, shortcuts
         FROM shortcut_profiles
         ORDER BY created_at DESC
         LIMIT $1`,
        [limit]
      );

      return result.rows.map(row => ({
        id: row.id,
        name: row.name,
        description: row.description,
        isOrgDefault: row.is_org_default,
        createdBy: row.created_by,
        createdAt: row.created_at,
        shortcuts: row.shortcuts
      }));
    } finally {
      client.release();
    }
  }

  async deleteProfile(profileId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`DELETE FROM shortcut_profiles WHERE id = $1`, [profileId]);
      this.emit('profile-deleted', { profileId });
    } finally {
      client.release();
    }
  }

  async updateProfile(profileId: string, name: string, description: string, shortcuts: Record<string, string>): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE shortcut_profiles SET name = $1, description = $2, shortcuts = $3, updated_at = CURRENT_TIMESTAMP WHERE id = $4`,
        [name, description, JSON.stringify(shortcuts), profileId]
      );

      this.emit('profile-updated', { profileId, name });
    } finally {
      client.release();
    }
  }

  async cleanupOldUsageData(daysOld: number = 90): Promise<number> {
    const client = await this.pool.connect();
    try {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - daysOld);

      const result = await client.query(
        `DELETE FROM shortcut_usage_tracking WHERE used_at < $1`,
        [cutoffDate]
      );

      return result.rowCount || 0;
    } finally {
      client.release();
    }
  }
}

export async function initializeKeyboardShortcutManagerRoutes(service: KeyboardShortcutManagerService) {
  const { Router } = require('express');
  const router = Router();
  const logger = getLogger('KeyboardShortcutManagerRoutes');

  router.post('/api/shortcut-profiles', async (req, res) => {
    try {
      const { name, description, createdBy, shortcuts, isOrgDefault } = req.body;
      const profileId = await service.createProfile(name, description, createdBy, shortcuts, isOrgDefault);
      res.json({ profileId });
    } catch (error) {
      logger.error('Failed to create profile', error);
      res.status(500).json({ error: 'Failed to create profile' });
    }
  });

  router.get('/api/shortcut-profiles/:profileId', async (req, res) => {
    try {
      const profile = await service.getProfile(req.params.profileId);
      if (!profile) {
        res.status(404).json({ error: 'Profile not found' });
        return;
      }
      res.json(profile);
    } catch (error) {
      logger.error('Failed to get profile', error);
      res.status(500).json({ error: 'Failed to get profile' });
    }
  });

  router.get('/api/shortcut-profiles/org/default', async (req, res) => {
    try {
      const profile = await service.getOrgDefaultProfile();
      res.json(profile);
    } catch (error) {
      logger.error('Failed to get org default profile', error);
      res.status(500).json({ error: 'Failed to get org default profile' });
    }
  });

  router.post('/api/shortcut-profiles/:profileId/personal-overrides', async (req, res) => {
    try {
      const { userId, overrides } = req.body;
      await service.setPersonalOverrides(userId, req.params.profileId, overrides);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to set personal overrides', error);
      res.status(500).json({ error: 'Failed to set personal overrides' });
    }
  });

  router.get('/api/shortcut-profiles/:profileId/merged/:userId', async (req, res) => {
    try {
      const shortcuts = await service.getMergedShortcuts(req.params.userId, req.params.profileId);
      res.json(shortcuts);
    } catch (error) {
      logger.error('Failed to get merged shortcuts', error);
      res.status(500).json({ error: 'Failed to get merged shortcuts' });
    }
  });

  router.post('/api/shortcut-profiles/detect-clashes', async (req, res) => {
    try {
      const { profileId1, profileId2 } = req.body;
      const clashes = await service.detectClashes(profileId1, profileId2);
      res.json(clashes);
    } catch (error) {
      logger.error('Failed to detect clashes', error);
      res.status(500).json({ error: 'Failed to detect clashes' });
    }
  });

  router.post('/api/shortcut-usage/track', async (req, res) => {
    try {
      const { userId, shortcutKey, command } = req.body;
      await service.trackUsage(userId, shortcutKey, command);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to track usage', error);
      res.status(500).json({ error: 'Failed to track usage' });
    }
  });

  router.get('/api/shortcut-usage/top/:userId', async (req, res) => {
    try {
      const shortcuts = await service.getTopShortcuts(req.params.userId);
      res.json(shortcuts);
    } catch (error) {
      logger.error('Failed to get top shortcuts', error);
      res.status(500).json({ error: 'Failed to get top shortcuts' });
    }
  });

  router.post('/api/shortcut-profiles/:profileId/sync-to-team', async (req, res) => {
    try {
      const { teamId } = req.body;
      await service.syncProfileToTeam(req.params.profileId, teamId);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to sync profile to team', error);
      res.status(500).json({ error: 'Failed to sync profile to team' });
    }
  });

  router.get('/api/shortcut-profiles/team/:teamId/synced', async (req, res) => {
    try {
      const profiles = await service.getTeamSyncedProfiles(req.params.teamId);
      res.json(profiles);
    } catch (error) {
      logger.error('Failed to get team synced profiles', error);
      res.status(500).json({ error: 'Failed to get team synced profiles' });
    }
  });

  router.post('/api/shortcut-profiles/quick-switch', async (req, res) => {
    try {
      const { userId, fromProfileId, toProfileId } = req.body;
      await service.quickSwitch(userId, fromProfileId, toProfileId);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to quick switch', error);
      res.status(500).json({ error: 'Failed to quick switch' });
    }
  });

  router.get('/api/shortcut-profiles', async (req, res) => {
    try {
      const profiles = await service.listProfiles();
      res.json(profiles);
    } catch (error) {
      logger.error('Failed to list profiles', error);
      res.status(500).json({ error: 'Failed to list profiles' });
    }
  });

  return router;
}
