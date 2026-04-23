import * as fs from 'fs';
import * as path from 'path';
import { getAuditService } from '../audit/audit-service';
function emitManifestReadAudit(filePath) {
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
const DEFAULT_APPROVED_MANIFEST = path.resolve(__dirname, '../../../../../config/code-server/extensions/extensions-approved.json');
const DEFAULT_BLOCKED_MANIFEST = path.resolve(__dirname, '../../../../../config/code-server/extensions/extensions-blocked.json');
export class PrivateExtensionRegistryService {
    constructor(options = {}) {
        this.approvedManifestPath = options.approvedManifestPath ?? DEFAULT_APPROVED_MANIFEST;
        this.blockedManifestPath = options.blockedManifestPath ?? DEFAULT_BLOCKED_MANIFEST;
    }
    getSnapshot() {
        const approvedManifest = this.readJson(this.approvedManifestPath);
        const blockedManifest = this.readJson(this.blockedManifestPath);
        return {
            policyVersion: approvedManifest.policy_version,
            policyDate: approvedManifest.policy_date,
            manifestSignature: approvedManifest.manifest_signature,
            approvedExtensions: approvedManifest.extensions.map((extension) => ({ ...extension })),
            blockedExtensions: blockedManifest.blocked.map((extension) => ({ ...extension })),
        };
    }
    listApprovedExtensions() {
        const snapshot = this.getSnapshot();
        return snapshot.approvedExtensions;
    }
    listBlockedExtensions() {
        const snapshot = this.getSnapshot();
        return snapshot.blockedExtensions;
    }
    validateExtension(extensionId, requestedVersion) {
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
    canPublish(extensionId, version) {
        return this.validateExtension(extensionId, version);
    }
    findApprovedExtension(snapshot, extensionId) {
        return snapshot.approvedExtensions.find((extension) => extension.id === extensionId);
    }
    findBlockedExtension(snapshot, extensionId) {
        for (const blockedExtension of snapshot.blockedExtensions) {
            try {
                if (new RegExp(blockedExtension.pattern, 'i').test(extensionId)) {
                    return blockedExtension;
                }
            }
            catch {
                continue;
            }
        }
        return undefined;
    }
    readJson(filePath) {
        const raw = fs.readFileSync(filePath, 'utf8');
        emitManifestReadAudit(filePath);
        return JSON.parse(raw);
    }
}
export default PrivateExtensionRegistryService;
//# sourceMappingURL=index.js.map