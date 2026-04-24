import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockAuditService = { emit: vi.fn() };

vi.mock('../../audit/audit-service', () => ({
  getAuditService: () => mockAuditService,
}));
import { PrivateExtensionRegistryService } from '../index';

describe('PrivateExtensionRegistryService', () => {
  const tempDirs: string[] = [];

  beforeEach(() => {
    mockAuditService.emit.mockReset();
  });

  afterEach(() => {
    while (tempDirs.length > 0) {
      const tempDir = tempDirs.pop();
      if (tempDir) {
        fs.rmSync(tempDir, { recursive: true, force: true });
      }
    }
  });

  function createService() {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'private-extension-registry-'));
    tempDirs.push(tempDir);

    const approvedManifestPath = path.join(tempDir, 'extensions-approved.json');
    const blockedManifestPath = path.join(tempDir, 'extensions-blocked.json');

    fs.writeFileSync(
      approvedManifestPath,
      JSON.stringify(
        {
          policy_version: '1.0.0',
          policy_date: '2026-04-22',
          manifest_signature: 'abc123',
          extensions: [
            {
              id: 'GitHub.copilot',
              version: '1.295.0',
              tier: 'T1-Core',
              reason: 'AI code completion',
              pre_installed: true,
              user_can_uninstall: false,
            },
            {
              id: 'esbenp.prettier-vscode',
              version: '10.4.0',
              tier: 'T1-Core',
              reason: 'Formatting',
              pre_installed: false,
              user_can_uninstall: false,
            },
          ],
        },
        null,
        2
      )
    );

    fs.writeFileSync(
      blockedManifestPath,
      JSON.stringify(
        {
          policy_version: '1.0.0',
          policy_date: '2026-04-22',
          blocked: [
            {
              pattern: 'ms-vscode-remote.*',
              reason: 'Remote development extensions are incompatible with code-server web architecture',
              alternative: 'Use native browser-based code-server access',
            },
            {
              pattern: 'Codeium.*',
              reason: 'Redundant AI completion',
              alternative: 'GitHub Copilot',
            },
          ],
        },
        null,
        2
      )
    );

    return new PrivateExtensionRegistryService({
      approvedManifestPath,
      blockedManifestPath,
    });
  }

  it('returns a snapshot of the canonical manifests', () => {
    const service = createService();

    const snapshot = service.getSnapshot();

    expect(snapshot.policyVersion).toBe('1.0.0');
    expect(snapshot.policyDate).toBe('2026-04-22');
    expect(snapshot.manifestSignature).toBe('abc123');
    expect(snapshot.approvedExtensions).toHaveLength(2);
    expect(snapshot.blockedExtensions).toHaveLength(2);
    expect(mockAuditService.emit).toHaveBeenCalledTimes(2);
  });

  it('allows approved extensions that match the pinned version', () => {
    const service = createService();

    const decision = service.validateExtension('GitHub.copilot', '1.295.0');

    expect(decision.allowed).toBe(true);
    expect(decision.status).toBe('approved');
    expect(decision.pinnedVersion).toBe('1.295.0');
    expect(mockAuditService.emit).toHaveBeenCalledTimes(2);
  });

  it('rejects version drift for approved extensions', () => {
    const service = createService();

    const decision = service.canPublish('GitHub.copilot', '1.296.0');

    expect(decision.allowed).toBe(false);
    expect(decision.status).toBe('version-mismatch');
    expect(decision.pinnedVersion).toBe('1.295.0');
    expect(mockAuditService.emit).toHaveBeenCalledTimes(2);
  });

  it('rejects blocked extensions before approval lookup', () => {
    const service = createService();

    const decision = service.validateExtension('ms-vscode-remote.remote-containers', '1.0.0');

    expect(decision.allowed).toBe(false);
    expect(decision.status).toBe('blocked');
    expect(decision.matchedBlockedPattern).toBe('ms-vscode-remote.*');
    expect(mockAuditService.emit).toHaveBeenCalledTimes(2);
  });

  it('rejects extensions that are not present in the approved manifest', () => {
    const service = createService();

    const decision = service.validateExtension('unknown.publisher', '1.0.0');

    expect(decision.allowed).toBe(false);
    expect(decision.status).toBe('unknown-extension');
    expect(mockAuditService.emit).toHaveBeenCalledTimes(2);
  });
});