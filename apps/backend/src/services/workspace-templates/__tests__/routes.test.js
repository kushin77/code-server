import { describe, expect, it } from 'vitest';
class MockWorkspaceTemplateCatalogService {
    getSnapshot() {
        return {
            templates: [
                {
                    id: 'collaboration-core',
                    name: 'Collaboration Core',
                    description: 'Core workspace template',
                    settings: { 'telemetry.telemetryLevel': 'off' },
                    pinnedExtensions: ['ms-vscode.vscode-typescript-next@5.3.3'],
                    devcontainer: {
                        name: 'Collaboration Core',
                        image: 'mcr.microsoft.com/devcontainers/base:ubuntu',
                        customizations: {
                            vscode: {
                                extensions: ['ms-vscode.vscode-typescript-next@5.3.3'],
                                settings: { 'telemetry.telemetryLevel': 'off' },
                            },
                        },
                    },
                    source: {
                        settingsPath: '/config/code-server/settings.json',
                        approvedManifestPath: '/config/code-server/extensions/extensions-approved.json',
                    },
                },
            ],
            settings: { 'telemetry.telemetryLevel': 'off' },
            extensionManifest: {
                policyVersion: '1.0',
                policyDate: '2026-04-22',
                manifestSignature: 'abc123',
                approvedExtensions: [],
                blockedExtensions: [],
            },
        };
    }
    getTemplate(id) {
        const templates = this.getSnapshot().templates;
        return templates.find(t => t.id === id) || null;
    }
    buildDevcontainer(id) {
        const template = this.getTemplate(id);
        if (!template) {
            throw new Error(`Template ${id} not found`);
        }
        return template.devcontainer;
    }
}
describe('Workspace Template Routes', () => {
    it('snapshot endpoint returns the full catalog', async () => {
        const mockService = new MockWorkspaceTemplateCatalogService();
        const snapshot = mockService.getSnapshot();
        expect(snapshot.templates).toHaveLength(1);
        expect(snapshot.templates[0].id).toBe('collaboration-core');
        expect(snapshot.extensionManifest.policyVersion).toBe('1.0');
    });
    it('template endpoint returns correct template by id', async () => {
        const mockService = new MockWorkspaceTemplateCatalogService();
        const template = mockService.getTemplate('collaboration-core');
        expect(template).not.toBeNull();
        expect(template?.id).toBe('collaboration-core');
        expect(template?.name).toBe('Collaboration Core');
    });
    it('template endpoint returns null for missing template', async () => {
        const mockService = new MockWorkspaceTemplateCatalogService();
        const template = mockService.getTemplate('missing-template');
        expect(template).toBeNull();
    });
    it('devcontainer endpoint builds payload correctly', async () => {
        const mockService = new MockWorkspaceTemplateCatalogService();
        const devcontainer = mockService.buildDevcontainer('collaboration-core');
        expect(devcontainer.name).toBe('Collaboration Core');
        expect(devcontainer.image).toBe('mcr.microsoft.com/devcontainers/base:ubuntu');
        expect(devcontainer.customizations.vscode.extensions).toContain('ms-vscode.vscode-typescript-next@5.3.3');
    });
    it('devcontainer endpoint throws for missing template', async () => {
        const mockService = new MockWorkspaceTemplateCatalogService();
        expect(() => {
            mockService.buildDevcontainer('missing-template');
        }).toThrow('Template missing-template not found');
    });
});
//# sourceMappingURL=routes.test.js.map