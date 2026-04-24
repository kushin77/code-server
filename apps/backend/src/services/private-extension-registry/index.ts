import * as fs from 'fs';
import * as path from 'path';
import { getAuditService } from '../audit/audit-service';

export interface ApprovedExtensionEntry {
  id: string;
  version: string;
  tier: string;
  reason: string;
  pre_installed: boolean;
  user_can_uninstall: boolean;
}

export interface BlockedExtensionEntry {
  pattern: string;
  reason: string;
  alternative?: string;
}

export interface PrivateExtensionRegistrySnapshot {
  policyVersion: string;
  policyDate: string;
  manifestSignature: string;
  approvedExtensions: ApprovedExtensionEntry[];
  blockedExtensions: BlockedExtensionEntry[];
}

export interface PrivateExtensionRegistryDecision {
  extensionId: string;
  requestedVersion: string;
  allowed: boolean;
  status: 'approved' | 'blocked' | 'version-mismatch' | 'unknown-extension';
  reason: string;
  pinnedVersion?: string;
  tier?: string;
  matchedBlockedPattern?: string;
  alternative?: string;
}

export interface PrivateExtensionRegistryOptions {
  approvedManifestPath?: string;
  blockedManifestPath?: string;
}

function emitManifestReadAudit(filePath: string): void {
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

interface ApprovedManifest {
  policy_version: string;
  policy_date: string;
  manifest_signature: string;
  extensions: ApprovedExtensionEntry[];
}

interface BlockedManifest {
  policy_version: string;
  policy_date: string;
  blocked: BlockedExtensionEntry[];
}

const DEFAULT_APPROVED_MANIFEST = path.resolve(
  __dirname,
  '../../../../../config/code-server/extensions/extensions-approved.json'
);

const DEFAULT_BLOCKED_MANIFEST = path.resolve(
  __dirname,
  '../../../../../config/code-server/extensions/extensions-blocked.json'
);

export class PrivateExtensionRegistryService {
  private readonly approvedManifestPath: string;
  private readonly blockedManifestPath: string;

  constructor(options: PrivateExtensionRegistryOptions = {}) {
    this.approvedManifestPath = options.approvedManifestPath ?? DEFAULT_APPROVED_MANIFEST;
    this.blockedManifestPath = options.blockedManifestPath ?? DEFAULT_BLOCKED_MANIFEST;
  }

  getSnapshot(): PrivateExtensionRegistrySnapshot {
    const approvedManifest = this.readJson<ApprovedManifest>(this.approvedManifestPath);
    const blockedManifest = this.readJson<BlockedManifest>(this.blockedManifestPath);

    return {
      policyVersion: approvedManifest.policy_version,
      policyDate: approvedManifest.policy_date,
      manifestSignature: approvedManifest.manifest_signature,
      approvedExtensions: approvedManifest.extensions.map((extension) => ({ ...extension })),
      blockedExtensions: blockedManifest.blocked.map((extension) => ({ ...extension })),
    };
  }

  listApprovedExtensions(): ApprovedExtensionEntry[] {
    const snapshot = this.getSnapshot();
    return snapshot.approvedExtensions;
  }

  listBlockedExtensions(): BlockedExtensionEntry[] {
    const snapshot = this.getSnapshot();
    return snapshot.blockedExtensions;
  }

  validateExtension(extensionId: string, requestedVersion?: string): PrivateExtensionRegistryDecision {
    const snapshot = this.getSnapshot();
    const blockedExtension = this.findBlockedExtension(snapshot, extensionId);
    if (blockedExtension) {
      return {
        extensionId,
        requestedVersion: requestedVersion ?? '',
        allowed: false,
        status: 'blocked',
        reason: blockedExtension.reason,
        matchedBlockedPattern: blockedExtension.pattern,
        alternative: blockedExtension.alternative,
      };
    }

    const approvedExtension = this.findApprovedExtension(snapshot, extensionId);
    if (!approvedExtension) {
      return {
        extensionId,
        requestedVersion: requestedVersion ?? '',
        allowed: false,
        status: 'unknown-extension',
        reason: 'Extension is not present in the approved manifest',
      };
    }

    if (requestedVersion && requestedVersion !== approvedExtension.version) {
      return {
        extensionId,
        requestedVersion,
        allowed: false,
        status: 'version-mismatch',
        reason: `Pinned version is ${approvedExtension.version}`,
        pinnedVersion: approvedExtension.version,
        tier: approvedExtension.tier,
      };
    }

    return {
      extensionId,
      requestedVersion: requestedVersion ?? approvedExtension.version,
      allowed: true,
      status: 'approved',
      reason: 'Extension is approved and matches the pinned version',
      pinnedVersion: approvedExtension.version,
      tier: approvedExtension.tier,
    };
  }

  canPublish(extensionId: string, version: string): PrivateExtensionRegistryDecision {
    return this.validateExtension(extensionId, version);
  }

  private findApprovedExtension(
    snapshot: PrivateExtensionRegistrySnapshot,
    extensionId: string
  ): ApprovedExtensionEntry | undefined {
    return snapshot.approvedExtensions.find((extension) => extension.id === extensionId);
  }

  private findBlockedExtension(
    snapshot: PrivateExtensionRegistrySnapshot,
    extensionId: string
  ): BlockedExtensionEntry | undefined {
    for (const blockedExtension of snapshot.blockedExtensions) {
      try {
        if (new RegExp(blockedExtension.pattern, 'i').test(extensionId)) {
          return blockedExtension;
        }
      } catch {
        continue;
      }
    }

    return undefined;
  }

  private readJson<T>(filePath: string): T {
    const raw = fs.readFileSync(filePath, 'utf8');
    emitManifestReadAudit(filePath);
    return JSON.parse(raw) as T;
  }
}

export default PrivateExtensionRegistryService;