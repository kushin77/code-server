/**
 * @file        apps/backend/src/services/git-signing/hook-setup-service.ts
 * @module      security/git-signing
 * @description Pre-commit hook setup and management for gitsign enforcement
 */
import { promises as fs } from 'fs';
import path from 'path';
import { EventEmitter } from 'events';
/**
 * GitHookSetupService: Install and manage pre-commit hooks for signature enforcement
 */
export class GitHookSetupService extends EventEmitter {
    constructor(auditService) {
        super();
        this.auditService = auditService;
        this.isInitialized = false;
        this.hooks = new Map();
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        console.log('[GitHookSetupService] Initialized');
    }
    /**
     * Install gitsign pre-commit hook in workspace
     */
    async installHook(workspaceId, gitDir, config) {
        const hooksDir = path.join(gitDir, '.git', 'hooks');
        const hookPath = path.join(hooksDir, 'prepare-commit-msg');
        try {
            // Ensure hooks directory exists
            await fs.mkdir(hooksDir, { recursive: true });
            // Generate hook script
            const hookScript = this.generateHookScript(config);
            // Write hook file
            await fs.writeFile(hookPath, hookScript, { mode: 0o755 });
            console.log(`[GitHookSetupService] Installed hook at ${hookPath}`);
            if (this.auditService) {
                this.auditService.emit({
                    userId: 'system',
                    action: 'create',
                    resourceType: 'file',
                    resource: `git-hook:${hookPath}`,
                    metadata: {
                        workspaceId,
                        gitDir,
                        hookType: 'prepare-commit-msg',
                        config,
                    },
                    reason: 'SOC2: Automated Git hook installation for signature enforcement',
                });
            }
            const hookConfig = {
                id: `hook-${workspaceId}-${Date.now()}`,
                workspaceId,
                enabled: true,
                hookPath,
                gitsignPath: process.env.GITSIGN_PATH || '/usr/local/bin/gitsign',
                config,
                environment: {
                    SIGSTORE_OIDC_ISSUER: process.env.SIGSTORE_OIDC_ISSUER || 'https://oauth2.googleapis.com',
                    SIGSTORE_OIDC_CLIENT_ID: process.env.SIGSTORE_OIDC_CLIENT_ID || 'sigstore',
                },
                createdAt: Date.now(),
                updatedAt: Date.now(),
            };
            this.hooks.set(hookPath, hookConfig);
            this.emit('hook-installed', hookConfig);
            return hookConfig;
        }
        catch (error) {
            console.error(`[GitHookSetupService] Failed to install hook:`, error);
            throw error;
        }
    }
    /**
     * Remove gitsign pre-commit hook
     */
    async removeHook(hookPath) {
        try {
            // Check if file exists and contains gitsign marker
            const content = await fs.readFile(hookPath, 'utf-8');
            if (!content.includes('gitsign')) {
                throw new Error('Hook does not appear to be a gitsign hook');
            }
            // Remove the file
            await fs.unlink(hookPath);
            if (this.auditService) {
                this.auditService.emit({
                    userId: 'system',
                    action: 'delete',
                    resourceType: 'file',
                    resource: `git-hook:${hookPath}`,
                    metadata: {
                        hookPath,
                    },
                    reason: 'SOC2: Manual/Automated Git hook removal',
                });
            }
            this.hooks.delete(hookPath);
            console.log(`[GitHookSetupService] Removed hook at ${hookPath}`);
            this.emit('hook-removed', { hookPath });
        }
        catch (error) {
            console.error(`[GitHookSetupService] Failed to remove hook:`, error);
            throw error;
        }
    }
    /**
     * Update hook configuration
     */
    async updateHookConfig(hookPath, config) {
        const hookConfig = this.hooks.get(hookPath);
        if (!hookConfig) {
            throw new Error(`Hook not found: ${hookPath}`);
        }
        // Update configuration
        hookConfig.config = config;
        hookConfig.updatedAt = Date.now();
        // Regenerate hook script
        const hookScript = this.generateHookScript(config);
        await fs.writeFile(hookPath, hookScript, { mode: 0o755 });
        if (this.auditService) {
            this.auditService.emit({
                userId: 'system',
                action: 'update',
                resourceType: 'file',
                resource: `git-hook:${hookPath}`,
                metadata: {
                    hookPath,
                    config,
                    timestamp: hookConfig.updatedAt,
                },
                reason: 'SOC2: Git hook configuration updated',
            });
        }
        console.log(`[GitHookSetupService] Updated hook at ${hookPath}`);
        this.emit('hook-updated', hookConfig);
        return hookConfig;
    }
    /**
     * Verify hook is properly installed
     */
    async verifyHook(hookPath) {
        try {
            const content = await fs.readFile(hookPath, 'utf-8');
            // Check for required markers
            const hasGitsignMarker = content.includes('gitsign');
            const hasShebang = content.startsWith('#!/');
            const isExecutable = (await fs.stat(hookPath)).mode & 0o111;
            const valid = hasGitsignMarker && hasShebang && isExecutable > 0;
            if (this.auditService) {
                this.auditService.emit({
                    userId: 'system',
                    action: 'read',
                    resourceType: 'file',
                    resource: `git-hook:${hookPath}`,
                    metadata: {
                        hookPath,
                        validationResult: valid,
                        hasGitsignMarker,
                        hasShebang,
                        isExecutable: isExecutable > 0,
                    },
                    reason: 'SOC2: Git hook verification check',
                });
            }
            if (!valid) {
                console.warn(`[GitHookSetupService] Hook validation failed for ${hookPath}`);
            }
            return valid;
        }
        catch (error) {
            console.error(`[GitHookSetupService] Failed to verify hook:`, error);
            return false;
        }
    }
    /**
     * List all installed hooks
     */
    listHooks() {
        return Array.from(this.hooks.values());
    }
    /**
     * Get specific hook configuration
     */
    getHook(hookPath) {
        return this.hooks.get(hookPath);
    }
    /**
     * Private: Generate the pre-commit hook script
     */
    generateHookScript(config) {
        const gitsignPath = process.env.GITSIGN_PATH || '/usr/local/bin/gitsign';
        return `#!/bin/bash
# This file is auto-generated by gitsign hook setup service
# DO NOT EDIT MANUALLY - changes will be overwritten

set -euo pipefail

# gitsign pre-commit hook for signature enforcement
# Provider: ${config.provider}
# Identity: ${config.identity}
# Required: ${config.required}

GITSIGN_PATH="${gitsignPath}"
TIMEOUT=${config.timeout}

# Export environment for gitsign
export SIGSTORE_OIDC_ISSUER="\${SIGSTORE_OIDC_ISSUER:-https://oauth2.googleapis.com}"
export SIGSTORE_OIDC_CLIENT_ID="\${SIGSTORE_OIDC_CLIENT_ID:-sigstore}"

# Get the commit hash being prepared
COMMIT_MSG_FILE="\$1"
COMMIT_SOURCE="\${2:-message}"

# Skip signing for merge commits and amends from rebase
if [[ "\${COMMIT_SOURCE}" == "merge" ]] || [[ "\${COMMIT_SOURCE}" == "squash" ]]; then
  exit 0
fi

# Run gitsign to sign the commit
if ! timeout "\${TIMEOUT}" "\${GITSIGN_PATH}" sign \\
  --identity="${config.identity}" \\
  --hook=prepare-commit-msg \\
  "\${COMMIT_MSG_FILE}"; then
  
  if [ \$? -eq 124 ]; then
    echo "Error: gitsign signing timed out after \${TIMEOUT}ms" >&2
    exit 1
  fi
  
  if [ "${config.required}" = "true" ]; then
    echo "Error: Failed to sign commit. Commit signature is required." >&2
    exit 1
  fi
  
  echo "Warning: Failed to sign commit, continuing without signature" >&2
fi

exit 0
`;
    }
}
/**
 * Global service instance
 */
let hookSetupInstance = null;
/**
 * Get global hook setup service instance
 */
export async function getGitHookSetupService() {
    if (!hookSetupInstance) {
        hookSetupInstance = new GitHookSetupService();
        await hookSetupInstance.initialize();
    }
    return hookSetupInstance;
}
//# sourceMappingURL=hook-setup-service.js.map