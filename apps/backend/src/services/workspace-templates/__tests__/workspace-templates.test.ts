import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { WorkspaceTemplateCatalogService } from '../index';

const emitSpy = vi.fn();

vi.mock('../../audit/audit-service', () => ({
  getAuditService: vi.fn(() => ({
    emit: emitSpy,
  })),
}));

describe('WorkspaceTemplateCatalogService', () => {
  const tempDirs: string[] = [];

  afterEach(() => {
    emitSpy.mockClear();
    while (tempDirs.length > 0) {
      const tempDir = tempDirs.pop();
      if (tempDir) {
        fs.rmSync(tempDir, { recursive: true, force: true });
      }
    }
  });

  function createService() {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'workspace-templates-'));
    tempDirs.push(tempDir);

    const settingsPath = path.join(tempDir, 'settings.json');
    const approvedManifestPath = path.join(tempDir, 'extensions-approved.json');
    const blockedManifestPath = path.join(tempDir, 'extensions-blocked.json');

    fs.writeFileSync(
      settingsPath,
      [
        '{',
        '  "telemetry.telemetryLevel": "off",',
        '  "extensions.autoCheckUpdates": false,',
        '  "extensions.autoUpdate": false,',
        '  "update.mode": "none",',
        '  "security.workspace.trust.enabled": true,',
        '  "security.workspace.trust.startupPrompt": "once",',
        '  "extensions.gallery.serviceUrl": "",',
        '  "extensions.gallery.itemUrl": "",',
        '  "extensions.gallery.resourceUrlTemplate": "",',
        '  "extensions.recommendations": false,',
        '  "extensions.ignoreRecommendations": true,',
        '  "git.requireGitUserConfig": true,',
        '  "git.autofetch": false,',
        '  "git.confirmSync": true,',
        '  "git.allowForcePush": false,',
        '  "github.branchProtection": true,',
        '  "editor.fontSize": 14',
        '}',
      ].join('\n')
    );

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
            },
          ],
        },
        null,
        2
      )
    );

    return new WorkspaceTemplateCatalogService({
      settingsPath,
      approvedManifestPath,
      blockedManifestPath,
    });
  }

  it('builds a pinned collaboration template from the canonical SSOT inputs', () => {
    const service = createService();

    const snapshot = service.getSnapshot();

    expect(snapshot.templates).toHaveLength(1);
    expect(snapshot.templates[0].id).toBe('collaboration-core');
    expect(snapshot.templates[0].pinnedExtensions).toEqual([
      'GitHub.copilot@1.295.0',
      'esbenp.prettier-vscode@10.4.0',
    ]);
    expect(snapshot.templates[0].settings['extensions.autoUpdate']).toBe(false);
    expect(snapshot.templates[0].settings['telemetry.telemetryLevel']).toBe('off');
    expect(emitSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        method: 'READ',
        path: expect.stringContaining('settings.json'),
        resourceType: 'config',
        fileAction: 'read',
      })
    );
  });

  it('returns the collaboration-core template by id', () => {
    const service = createService();

    const template = service.getTemplate('collaboration-core');

    expect(template?.name).toBe('Collaboration Core Workspace');
    expect(template?.source.settingsPath).toContain('settings.json');
    expect(template?.source.approvedManifestPath).toContain('extensions-approved.json');
  });

  it('synthesizes a devcontainer payload from the same template inputs', () => {
    const service = createService();

    const devcontainer = service.buildDevcontainer('collaboration-core');

    expect(devcontainer.image).toContain('devcontainers/base:ubuntu');
    expect(devcontainer.customizations.vscode.extensions).toContain('GitHub.copilot@1.295.0');
    expect(devcontainer.customizations.vscode.settings['git.requireGitUserConfig']).toBe(true);
  });

  it('throws for unknown workspace templates', () => {
    const service = createService();

    expect(() => service.buildDevcontainer('missing-template')).toThrow('Unknown workspace template');
  });

  it('scans and includes role-specific templates', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'role-templates-'));
    tempDirs.push(tempDir);
    process.env.ROLE_SETTINGS_DIR = tempDir;

    const devProfile = {
      role: 'developer',
      description: 'Dev environment',
      settings: { 'editor.fontSize': 16 },
    };
    fs.writeFileSync(path.join(tempDir, 'developer-profile.json'), JSON.stringify(devProfile));

    const service = createService();
    const snapshot = service.getSnapshot();

     const roleTemplate = snapshot.templates.find((t) => t.id === 'role-developer');
    expect(roleTemplate).toBeDefined();
    expect(roleTemplate?.name).toBe('Developer Environment');
    expect(roleTemplate?.settings['editor.fontSize']).toBe(16);
    expect(roleTemplate?.envSchema).toBeDefined();
    expect(roleTemplate?.envSchema?.PROJECT_NAME).toBeDefined();

    delete process.env.ROLE_SETTINGS_DIR;
  });

  it('audits role profile and directory reads', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'role-audit-'));
    tempDirs.push(tempDir);
    process.env.ROLE_SETTINGS_DIR = tempDir;

    fs.writeFileSync(path.join(tempDir, 'admin-profile.json'), JSON.stringify({ role: 'admin' }));

    const service = createService();
    service.getSnapshot();

    const auditCalls = emitSpy.mock.calls.map((call) => call[0]);

    expect(auditCalls).toContainEqual(
      expect.objectContaining({
        method: 'LIST',
        path: expect.stringMatching(new RegExp(tempDir.replace(/\\/g, '\\\\'), 'i')),
        resourceType: 'config',
      })
    );

    expect(auditCalls).toContainEqual(
      expect.objectContaining({
        method: 'READ',
        path: expect.stringMatching(new RegExp(path.join(tempDir, 'admin-profile.json').replace(/\\/g, '\\\\'), 'i')),
        resourceType: 'config',
      })
    );

    delete process.env.ROLE_SETTINGS_DIR;
  });
});
