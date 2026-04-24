// @file apps/extensions/team-hub/src/local-folder-access.ts
// @module ide/workspace-management
// @description P2-1539 Phase 4: Local folder access and mounting for user's host
// @governance GOV-002: All file access logged, immutable audit trail, user-controlled permissions

import * as vscode from 'vscode';
import * as path from 'path';
import { promises as fs } from 'fs';

export interface LocalFolderMount {
  id: string;
  localPath: string;
  mountPath: string;
  displayName: string;
  created: string;
  accessed: string;
  permissions: 'read' | 'read-write';
  enabled: boolean;
}

export interface FileAccessEvent {
  id: string;
  timestamp: string;
  operation: 'read' | 'write' | 'delete' | 'rename';
  filePath: string;
  userId: string;
  success: boolean;
  bytes?: number;
}

export class LocalFolderAccessManager {
  private mounts: Map<string, LocalFolderMount> = new Map();
  private accessLog: FileAccessEvent[] = [];
  private outputChannel: vscode.OutputChannel;
  private workspaceRoot: string;

  constructor(workspaceRoot: string = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || '.') {
    this.workspaceRoot = workspaceRoot;
    this.outputChannel = vscode.window.createOutputChannel('KC IDE Local Folder Access');
  }

  /**
   * Request access to a local folder
   * User must approve before mount is created
   */
  async requestLocalFolderAccess(
    localPath: string,
    displayName: string,
    permissions: 'read' | 'read-write' = 'read-write'
  ): Promise<LocalFolderMount | null> {
    // Validate path exists
    try {
      const stat = await fs.stat(localPath);
      if (!stat.isDirectory()) {
        throw new Error('Path is not a directory');
      }
    } catch (error) {
      this.log(`[ERROR] Cannot access path ${localPath}: ${error}`, 'error');
      return null;
    }

    // Request user approval with warning
    const message = `KC IDE is requesting access to local folder:\n\n${localPath}\n\nPermissions: ${permissions}\n\nThis will mount the folder into your workspace.`;

    const approved = await vscode.window.showWarningMessage(
      message,
      { modal: true },
      'Allow',
      'Deny'
    );

    if (approved !== 'Allow') {
      this.log(`User declined folder access request for ${localPath}`, 'info');
      return null;
    }

    // Create mount
    const mount: LocalFolderMount = {
      id: `mount-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      localPath,
      mountPath: path.join('.local-folders', path.basename(localPath)),
      displayName,
      created: new Date().toISOString(),
      accessed: new Date().toISOString(),
      permissions,
      enabled: true
    };

    this.mounts.set(mount.id, mount);
    this.log(`Mounted local folder: ${displayName} (${permissions})`, 'info');

    return mount;
  }

  /**
   * List all mounted folders
   */
  getMounts(): LocalFolderMount[] {
    return Array.from(this.mounts.values()).filter(m => m.enabled);
  }

  /**
   * Get mount by ID
   */
  getMount(id: string): LocalFolderMount | undefined {
    return this.mounts.get(id);
  }

  /**
   * Revoke access to a mounted folder
   */
  async revokeAccess(mountId: string): Promise<boolean> {
    const mount = this.mounts.get(mountId);
    if (!mount) {
      return false;
    }

    mount.enabled = false;
    this.log(`Revoked access to ${mount.displayName}`, 'info');
    return true;
  }

  /**
   * Log file access operation
   */
  logFileAccess(
    operation: 'read' | 'write' | 'delete' | 'rename',
    filePath: string,
    userId: string,
    success: boolean,
    bytes?: number
  ): void {
    const event: FileAccessEvent = {
      id: `access-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      timestamp: new Date().toISOString(),
      operation,
      filePath,
      userId,
      success,
      bytes
    };

    this.accessLog.push(event);

    // Update accessed time on mount containing this file
    for (const mount of this.mounts.values()) {
      if (filePath.startsWith(mount.localPath)) {
        mount.accessed = new Date().toISOString();
        break;
      }
    }

    // Log to output channel
    const status = success ? '✓' : '✗';
    const sizeInfo = bytes ? ` (${bytes} bytes)` : '';
    this.log(`[${operation.toUpperCase()}] ${filePath}${sizeInfo} - ${status}`, 'info');

    // Keep log bounded
    if (this.accessLog.length > 10000) {
      this.accessLog = this.accessLog.slice(-5000);
    }
  }

  /**
   * Get access log for a specific mount
   */
  getAccessLog(mountId: string, limit: number = 100): FileAccessEvent[] {
    const mount = this.mounts.get(mountId);
    if (!mount) {
      return [];
    }

    return this.accessLog
      .filter(e => e.filePath.startsWith(mount.localPath))
      .slice(-limit);
  }

  /**
   * Check if operation is allowed based on permissions
   */
  canPerformOperation(mountId: string, operation: 'read' | 'write' | 'delete' | 'rename'): boolean {
    const mount = this.mounts.get(mountId);
    if (!mount || !mount.enabled) {
      return false;
    }

    if (operation === 'read') {
      return true; // Read always allowed
    }

    // Write, delete, rename require read-write permission
    return mount.permissions === 'read-write';
  }

  /**
   * Generate access summary for audit
   */
  generateAccessSummary(): {
    totalMounts: number;
    totalOperations: number;
    readOperations: number;
    writeOperations: number;
  } {
    const reads = this.accessLog.filter(e => e.operation === 'read').length;
    const writes = this.accessLog.filter(e => e.operation === 'write').length;

    return {
      totalMounts: this.mounts.size,
      totalOperations: this.accessLog.length,
      readOperations: reads,
      writeOperations: writes
    };
  }

  /**
   * Log to output channel
   */
  private log(message: string, severity: 'info' | 'warn' | 'error'): void {
    const prefix = severity.toUpperCase();
    this.outputChannel.appendLine(`[${new Date().toISOString()}] [${prefix}] ${message}`);

    if (severity === 'error') {
      console.error(`[LocalFolderAccess] ${message}`);
    } else {
      console.log(`[LocalFolderAccess] ${message}`);
    }
  }
}

export function createLocalFolderAccessManager(workspaceRoot?: string): LocalFolderAccessManager {
  return new LocalFolderAccessManager(workspaceRoot);
}
