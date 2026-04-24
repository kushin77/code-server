import * as fs from 'fs';
import * as path from 'path';

import { getAuditService } from '../audit/audit-service';
import {
  PrivateExtensionRegistryService,
  type PrivateExtensionRegistrySnapshot,
} from '../private-extension-registry';

export interface WorkspaceTemplateCatalogOptions {
  settingsPath?: string;
  approvedManifestPath?: string;
  blockedManifestPath?: string;
}

export interface WorkspaceTemplateDevcontainer {
  name: string;
  image: string;
  customizations: {
    vscode: {
      extensions: string[];
      settings: Record<string, unknown>;
    };
  };
}

export interface WorkspaceTemplateDefinition {
  id: string;
  name: string;
  description: string;
  settings: Record<string, unknown>;
  pinnedExtensions: string[];
  devcontainer: WorkspaceTemplateDevcontainer;
  envSchema?: Record<string, { type: string; description: string; default?: any }>;
  source: {
    settingsPath: string;
    approvedManifestPath: string;
    roleProfilePath?: string;
  };
}

export interface WorkspaceTemplateCatalogSnapshot {
  templates: WorkspaceTemplateDefinition[];
  settings: Record<string, unknown>;
  extensionManifest: PrivateExtensionRegistrySnapshot;
}

const DEFAULT_SETTINGS_PATH = path.resolve(__dirname, '../../../../../config/code-server/settings.json');

const TEMPLATE_ID = 'collaboration-core';
const TEMPLATE_NAME = 'Collaboration Core Workspace';
const TEMPLATE_DESCRIPTION = 'Pinned workspace template built from enterprise settings and approved extensions';

const ROLE_SETTINGS_DIR = path.resolve(__dirname, '../../../../../config/role-settings');

const STANDARD_ENV_SCHEMA = {
  PROJECT_NAME: { type: 'string', description: 'Name of the current project' },
  WORKSPACE_OWNER: { type: 'string', description: 'Owner of the workspace' },
  DOCKER_REGISTRY: { type: 'string', description: 'Enterprise Docker registry URL', default: 'registry.kushnir.cloud' },
};

const IMMUTABLE_SETTING_KEYS = [
  'telemetry.telemetryLevel',
  'extensions.autoCheckUpdates',
  'extensions.autoUpdate',
  'update.mode',
  'security.workspace.trust.enabled',
  'security.workspace.trust.startupPrompt',
  'extensions.gallery.serviceUrl',
  'extensions.gallery.itemUrl',
  'extensions.gallery.resourceUrlTemplate',
  'extensions.recommendations',
  'extensions.ignoreRecommendations',
  'git.requireGitUserConfig',
  'git.autofetch',
  'git.confirmSync',
  'git.allowForcePush',
  'github.branchProtection',
];

function parseJsonc(raw: string): Record<string, unknown> {
  const stripped = raw
    .replace(/^\s*\/\/.*$/gm, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .trim();

  return JSON.parse(stripped) as Record<string, unknown>;
}

function extractImmutableSettings(settings: Record<string, unknown>): Record<string, unknown> {
  const extracted: Record<string, unknown> = {};

  for (const key of IMMUTABLE_SETTING_KEYS) {
    if (Object.prototype.hasOwnProperty.call(settings, key)) {
      extracted[key] = settings[key];
    }
  }

  return extracted;
}

function formatExtensionId(extensionId: string, version: string): string {
  return `${extensionId}@${version}`;
}

function emitSettingsReadAudit(filePath: string): void {
  getAuditService()?.emit({
    userId: 'system',
    role: 'system',
    identityType: 'automation',
    method: 'READ',
    path: filePath,
    action: 'allow',
    resourceType: 'config',
    resource: filePath,
    fileAction: 'read',
  });
}

function emitDirectoryReadAudit(dirPath: string): void {
  getAuditService()?.emit({
    userId: 'system',
    role: 'system',
    identityType: 'automation',
    method: 'LIST',
    path: dirPath,
    action: 'allow',
    resourceType: 'config',
    resource: dirPath,
    fileAction: 'read',
  });
}

function emitRoleProfileReadAudit(filePath: string): void {
  getAuditService()?.emit({
    userId: 'system',
    role: 'system',
    identityType: 'automation',
    method: 'READ',
    path: filePath,
    action: 'allow',
    resourceType: 'config',
    resource: filePath,
    fileAction: 'read',
  });
}

export class WorkspaceTemplateCatalogService {
  private readonly settingsPath: string;
  private readonly approvedManifestPath: string;
  private readonly registry: PrivateExtensionRegistryService;

  constructor(options: WorkspaceTemplateCatalogOptions = {}) {
    this.settingsPath = options.settingsPath ?? DEFAULT_SETTINGS_PATH;
    this.approvedManifestPath = options.approvedManifestPath ?? path.resolve(__dirname, '../../../../../config/code-server/extensions/extensions-approved.json');
    this.registry = new PrivateExtensionRegistryService({
      approvedManifestPath: this.approvedManifestPath,
      blockedManifestPath: options.blockedManifestPath,
    });
  }

  getSnapshot(): WorkspaceTemplateCatalogSnapshot {
    const settings = this.loadSettings();
    const extensionManifest = this.registry.getSnapshot();
    const standardTemplate = this.buildCollaborationCoreTemplate(settings, extensionManifest);
    const roleTemplates = this.buildRoleSpecificTemplates(extensionManifest);

    return {
      templates: [standardTemplate, ...roleTemplates],
      settings: standardTemplate.settings,
      extensionManifest,
    };
  }

  private buildRoleSpecificTemplates(
    extensionManifest: PrivateExtensionRegistrySnapshot
  ): WorkspaceTemplateDefinition[] {
    const templates: WorkspaceTemplateDefinition[] = [];
    const roleSettingsDir = this.getRoleSettingsDir();

    if (!fs.existsSync(roleSettingsDir)) {
      return templates;
    }

    const files = fs.readdirSync(roleSettingsDir);
    emitDirectoryReadAudit(roleSettingsDir);

    for (const file of files) {
      if (!file.endsWith('-profile.json')) continue;

      try {
        const filePath = path.join(roleSettingsDir, file);
        const raw = fs.readFileSync(filePath, 'utf8');
        emitRoleProfileReadAudit(filePath);

        const profile = JSON.parse(raw);
        const role = profile.role || file.replace('-profile.json', '');

        templates.push({
          id: `role-${role}`,
          name: `${role.charAt(0).toUpperCase() + role.slice(1)} Environment`,
          description: profile.description || `Standard workspace for ${role} role`,
          settings: profile.settings || {},
          pinnedExtensions: extensionManifest.approvedExtensions.map((ext) => formatExtensionId(ext.id, ext.version)),
          devcontainer: {
            name: `${role} Workspace`,
            image: 'mcr.microsoft.com/devcontainers/base:ubuntu',
            customizations: {
              vscode: {
                extensions: extensionManifest.approvedExtensions.map((ext) => formatExtensionId(ext.id, ext.version)),
                settings: profile.settings || {},
              },
            },
          },
          envSchema: STANDARD_ENV_SCHEMA,
          source: {
            settingsPath: this.settingsPath,
            approvedManifestPath: this.approvedManifestPath,
            roleProfilePath: filePath,
          },
        });
      } catch (error) {
        console.error(`Failed to load role profile ${file}:`, error);
      }
    }

    return templates;
  }

  private getRoleSettingsDir(): string {
    return (process.env.ROLE_SETTINGS_DIR as string) || ROLE_SETTINGS_DIR;
  }

  listTemplates(): WorkspaceTemplateDefinition[] {
    return this.getSnapshot().templates;
  }

  getTemplate(templateId: string): WorkspaceTemplateDefinition | undefined {
    return this.listTemplates().find((template) => template.id === templateId);
  }

  buildDevcontainer(templateId: string): WorkspaceTemplateDevcontainer {
    const template = this.getTemplate(templateId);

    if (!template) {
      throw new Error(`Unknown workspace template: ${templateId}`);
    }

    return template.devcontainer;
  }

  private loadSettings(): Record<string, unknown> {
    const raw = fs.readFileSync(this.settingsPath, 'utf8');
    emitSettingsReadAudit(this.settingsPath);
    const parsed = parseJsonc(raw);

    return extractImmutableSettings(parsed);
  }

  private buildCollaborationCoreTemplate(
    settings: Record<string, unknown>,
    extensionManifest: PrivateExtensionRegistrySnapshot
  ): WorkspaceTemplateDefinition {
    const pinnedExtensions = extensionManifest.approvedExtensions.map((extension) =>
      formatExtensionId(extension.id, extension.version)
    );

    return {
      id: TEMPLATE_ID,
      name: TEMPLATE_NAME,
      description: TEMPLATE_DESCRIPTION,
      settings,
      pinnedExtensions,
      devcontainer: {
        name: TEMPLATE_NAME,
        image: 'mcr.microsoft.com/devcontainers/base:ubuntu',
        customizations: {
          vscode: {
            extensions: pinnedExtensions,
            settings,
          },
        },
      },
      envSchema: STANDARD_ENV_SCHEMA,
      source: {
        settingsPath: this.settingsPath,
        approvedManifestPath: this.approvedManifestPath,
      },
    };
  }
}

export default WorkspaceTemplateCatalogService;
