// @file        apps/session-broker/src/session-templates.ts
// @module      session-management/templates
// @description Session Templates manager for reusable session configurations in KC IDE
//
// Provides template management (CRUD), NAS-backed persistence, and cluster-aware orchestration.

import * as winston from 'winston';
import * as fs from 'fs';
import * as path from 'path';
import { RedisSessionStore, SessionContext } from './redis-session-store';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export interface SessionTemplate {
  id: string;
  name: string;
  description: string;
  createdBy: string;
  createdAt: Date;
  tags: string[];
  config: {
    environment: Record<string, string>;
    workspaceSettings: Record<string, unknown>;
    extensions: string[];
    debugConfig?: Record<string, unknown>;
  };
  snapshotId?: string; // Optional associated hibernation snapshot
}

export interface TemplateApplicationResult {
  success: boolean;
  sessionId: string;
  templateId: string;
  appliedAt: Date;
  errors?: string[];
}

/**
 * Manages session templates with NAS-backed persistence.
 * Idempotent: safe to apply same template multiple times.
 */
export class SessionTemplateManager {
  private nasBasePath: string;
  private templatesDir: string;

  constructor(
    private sessionStore: RedisSessionStore,
    nasBasePath: string = process.env.NAS_MOUNT_PATH || '/mnt/nas/persistent/code-server-enterprise/templates'
  ) {
    this.nasBasePath = nasBasePath;
    this.templatesDir = path.join(this.nasBasePath, 'session-templates');
    this.initializeDirectories();
  }

  /**
   * Initialize NAS directories for template storage.
   * Idempotent: safe to call multiple times.
   */
  private initializeDirectories(): void {
    try {
      if (!fs.existsSync(this.templatesDir)) {
        fs.mkdirSync(this.templatesDir, { recursive: true });
        logger.info('Initialized templates directory', { path: this.templatesDir });
      }
    } catch (error) {
      logger.error('Failed to initialize templates directory', { error, path: this.templatesDir });
    }
  }

  /**
   * Create a new session template.
   * Stores template to NAS for cluster-wide access.
   */
  async createTemplate(template: SessionTemplate): Promise<boolean> {
    try {
      const templatePath = path.join(this.templatesDir, `${template.id}.json`);
      const templateData = JSON.stringify(template, null, 2);
      fs.writeFileSync(templatePath, templateData);
      logger.info('Created session template', { templateId: template.id, path: templatePath });
      return true;
    } catch (error) {
      logger.error('Failed to create template', { error, templateId: template.id });
      return false;
    }
  }

  /**
   * Retrieve a template by ID from NAS.
   */
  async getTemplate(templateId: string): Promise<SessionTemplate | null> {
    try {
      const templatePath = path.join(this.templatesDir, `${templateId}.json`);
      if (!fs.existsSync(templatePath)) {
        logger.warn('Template not found', { templateId, path: templatePath });
        return null;
      }
      const data = fs.readFileSync(templatePath, 'utf-8');
      return JSON.parse(data);
    } catch (error) {
      logger.error('Failed to retrieve template', { error, templateId });
      return null;
    }
  }

  /**
   * List all available templates.
   */
  async listTemplates(): Promise<SessionTemplate[]> {
    try {
      if (!fs.existsSync(this.templatesDir)) {
        return [];
      }
      const files = fs.readdirSync(this.templatesDir).filter(f => f.endsWith('.json'));
      const templates: SessionTemplate[] = [];
      for (const file of files) {
        const data = fs.readFileSync(path.join(this.templatesDir, file), 'utf-8');
        templates.push(JSON.parse(data));
      }
      return templates;
    } catch (error) {
      logger.error('Failed to list templates', { error });
      return [];
    }
  }

  /**
   * Apply a template to a session.
   * Idempotent: safe to reapply to same session.
   */
  async applyTemplate(sessionId: string, templateId: string): Promise<TemplateApplicationResult> {
    const result: TemplateApplicationResult = {
      success: false,
      sessionId,
      templateId,
      appliedAt: new Date(),
      errors: [],
    };

    try {
      const template = await this.getTemplate(templateId);
      if (!template) {
        result.errors?.push(`Template not found: ${templateId}`);
        return result;
      }

      const session = await this.sessionStore.getSession(sessionId);
      if (!session) {
        result.errors?.push(`Session not found: ${sessionId}`);
        return result;
      }

      // Apply template configuration to session
      session.config = {
        ...session.config,
        environment: { ...session.config.environment, ...template.config.environment },
        workspaceSettings: { ...session.config.workspaceSettings, ...template.config.workspaceSettings },
        extensions: [...new Set([...(session.config.extensions || []), ...template.config.extensions])],
      };

      // If template has debug config, apply it
      if (template.config.debugConfig) {
        session.config.debugConfig = template.config.debugConfig;
      }

      await this.sessionStore.updateSession(sessionId, session);
      result.success = true;
      logger.info('Applied template to session', { sessionId, templateId });
      return result;
    } catch (error) {
      result.errors?.push(`Failed to apply template: ${error}`);
      logger.error('Failed to apply template', { error, sessionId, templateId });
      return result;
    }
  }

  /**
   * Delete a template.
   * Idempotent: safe to call for non-existent templates.
   */
  async deleteTemplate(templateId: string): Promise<boolean> {
    try {
      const templatePath = path.join(this.templatesDir, `${templateId}.json`);
      if (fs.existsSync(templatePath)) {
        fs.unlinkSync(templatePath);
        logger.info('Deleted session template', { templateId, path: templatePath });
      }
      return true;
    } catch (error) {
      logger.error('Failed to delete template', { error, templateId });
      return false;
    }
  }

  /**
   * Create a template from an existing session snapshot.
   * Useful for capturing known-good configurations.
   */
  async templateFromSnapshot(
    snapshotId: string,
    templateName: string,
    createdBy: string
  ): Promise<SessionTemplate | null> {
    try {
      const snapshotPath = path.join(this.nasBasePath, 'snapshots', `${snapshotId}.json`);
      if (!fs.existsSync(snapshotPath)) {
        logger.warn('Snapshot not found', { snapshotId, path: snapshotPath });
        return null;
      }

      const snapshotData = JSON.parse(fs.readFileSync(snapshotPath, 'utf-8'));
      const template: SessionTemplate = {
        id: `tmpl-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        name: templateName,
        description: `Template from snapshot ${snapshotId}`,
        createdBy,
        createdAt: new Date(),
        tags: ['snapshot-based'],
        config: snapshotData.config || {},
        snapshotId,
      };

      await this.createTemplate(template);
      return template;
    } catch (error) {
      logger.error('Failed to create template from snapshot', { error, snapshotId });
      return null;
    }
  }
}
