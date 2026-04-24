/**
 * Workspace Templates Service Types
 * Git-managed workspace templates with fast provisioning (<30s)
 */

/**
 * Extension pinning
 */
export interface PinnedExtension {
  id: string;
  name: string;
  version: string;
  publisher: string;
  enabled: boolean;
  settings?: Record<string, unknown>;
}

/**
 * Environment variable schema
 */
export interface EnvVariable {
  name: string;
  value?: string;
  required: boolean;
  description?: string;
  type: 'string' | 'number' | 'boolean' | 'secret';
  default?: unknown;
}

/**
 * Environment schema
 */
export interface EnvSchema {
  version: string;
  variables: EnvVariable[];
}

/**
 * Dev container configuration
 */
export interface DevContainerConfig {
  name: string;
  image: string;
  features?: Record<string, Record<string, unknown>>;
  forwardPorts?: number[];
  postCreateCommand?: string;
  postStartCommand?: string;
  customizations?: {
    vscode?: {
      extensions: string[];
      settings: Record<string, unknown>;
    };
  };
  mounts?: string[];
  remoteUser?: string;
  remoteEnv?: Record<string, string>;
}

/**
 * Workspace settings template
 */
export interface WorkspaceSettingsTemplate {
  theme: string;
  fontSize: number;
  fontFamily: string;
  formatOnSave: boolean;
  tabSize: number;
  wordWrap: boolean;
  extensions: PinnedExtension[];
  keybindings?: Record<string, string>;
  custom?: Record<string, unknown>;
}

/**
 * Template file entry
 */
export interface TemplateFile {
  path: string;
  content: string;
  isTemplate: boolean; // If true, supports variable substitution
  executable?: boolean;
}

/**
 * Workspace template
 */
export interface WorkspaceTemplate {
  id: string;
  name: string;
  description: string;
  version: string;
  author: string;
  createdAt: number;
  updatedAt: number;
  tags: string[];
  visibility: 'private' | 'internal' | 'public';
  templateType: 'minimal' | 'standard' | 'full' | 'custom';
  settings: WorkspaceSettingsTemplate;
  extensions: PinnedExtension[];
  devcontainer: DevContainerConfig;
  envSchema: EnvSchema;
  files: TemplateFile[];
  gitConfig?: {
    defaultBranch: string;
    remoteOrigin?: string;
  };
  metadata: {
    iconUrl?: string;
    category: string;
    framework?: string;
    language?: string[];
    estimatedProvisionTime: number; // ms
  };
}

/**
 * Template provision request
 */
export interface TemplateProvisionRequest {
  templateId: string;
  userId: string;
  userEmail: string;
  workspaceName: string;
  workspacePath: string;
  envValues?: Record<string, unknown>;
  customSettings?: Partial<WorkspaceSettingsTemplate>;
  skipExtensions?: string[];
  skipFiles?: string[];
}

/**
 * Template provision result
 */
export interface TemplateProvisionResult {
  templateId: string;
  workspacePath: string;
  successful: boolean;
  startTime: number;
  endTime: number;
  duration: number; // ms
  filesCreated: number;
  extensionsInstalled: number;
  envVarsSet: number;
  errors?: {
    file: string;
    reason: string;
  }[];
  warnings?: string[];
}

/**
 * SOC2 audit entry for templates
 */
export interface TemplateAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'created' | 'provisioned' | 'updated' | 'deleted' | 'exported' | 'imported';
  status: 'success' | 'denied' | 'error';
  templateId: string;
  workspacePath?: string;
  ipAddress?: string;
  userAgent?: string;
  timestamp: number;
  duration?: number; // For provision operations
  details?: Record<string, unknown>;
}

/**
 * Template metadata
 */
export interface TemplateMetadata {
  templateId: string;
  name: string;
  version: string;
  author: string;
  createdAt: number;
  updatedAt: number;
  fileCount: number;
  extensionCount: number;
  visibility: 'private' | 'internal' | 'public';
  tags: string[];
  downloads: number;
  rating: number;
}

/**
 * Template statistics
 */
export interface TemplateStatistics {
  totalTemplates: number;
  templatesByType: Record<string, number>;
  templatesByVisibility: Record<string, number>;
  totalProvisioned: number;
  provisionedByUser: Record<string, number>;
  provisionedByTemplate: Record<string, number>;
  averageProvisionTime: number;
  provisionSuccessRate: number;
  totalExtensions: number;
  averageExtensionsPerTemplate: number;
}

/**
 * Template query
 */
export interface TemplateQuery {
  userId?: string;
  templateType?: string;
  visibility?: 'private' | 'internal' | 'public';
  tags?: string[];
  category?: string;
  language?: string;
  limit?: number;
  offset?: number;
}

/**
 * Template query result
 */
export interface TemplateQueryResult {
  templates: TemplateMetadata[];
  total: number;
  limit: number;
  offset: number;
}

/**
 * Template import source
 */
export interface TemplateImportSource {
  source: 'git' | 'file' | 'registry';
  url?: string;
  filePath?: string;
  branch?: string;
  commit?: string;
}

/**
 * Template export format
 */
export interface TemplateExport {
  format: 'zip' | 'tar' | 'json';
  templateId: string;
  version: string;
  timestamp: number;
  includeDevContainer: boolean;
  includeExtensions: boolean;
  includeFiles: boolean;
}

/**
 * Template service configuration
 */
export interface TemplateServiceConfig {
  enabled: boolean;
  auditLoggingEnabled: boolean;
  maxTemplatesPerUser: number;
  maxFilesPerTemplate: number;
  maxExtensionsPerTemplate: number;
  provisionTimeoutMs: number; // 30s default
  compressionEnabled: boolean;
  encryptionEnabled: boolean;
  maxAuditLogSize: number;
  storageBackend: 'memory' | 'disk' | 's3' | 'git';
  gitRepositoryUrl?: string;
  autoSync: boolean;
}

/**
 * Template provisioning options
 */
export interface ProvisioningOptions {
  installExtensions: boolean;
  createFiles: boolean;
  configureSettings: boolean;
  setupDevContainer: boolean;
  setEnvVars: boolean;
  initializeGit: boolean;
  skipMissing: boolean;
}

/**
 * Template category
 */
export type TemplateCategory =
  | 'web'
  | 'mobile'
  | 'backend'
  | 'devops'
  | 'datascience'
  | 'gamedev'
  | 'ml'
  | 'education'
  | 'other';
