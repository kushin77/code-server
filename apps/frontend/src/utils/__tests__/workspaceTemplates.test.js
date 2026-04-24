/** @vitest-environment jsdom */
import { describe, expect, it, vi } from 'vitest';
import { fetchWorkspaceTemplate, fetchWorkspaceTemplateCatalog, fetchWorkspaceTemplateDevcontainer, } from '../workspaceTemplates';
const mockFetch = vi.fn();
global.fetch = mockFetch;
describe('workspaceTemplates helpers', () => {
    it('fetches the workspace template catalog', async () => {
        const catalogSnapshot = {
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
        mockFetch.mockResolvedValueOnce({
            ok: true,
            status: 200,
            json: async () => catalogSnapshot,
        });
        const result = await fetchWorkspaceTemplateCatalog();
        expect(result.templates).toHaveLength(1);
        expect(result.templates[0].id).toBe('collaboration-core');
        expect(mockFetch).toHaveBeenCalledWith('/api/workspace-templates/snapshot', expect.any(Object));
    });
    it('fetches a single workspace template by id', async () => {
        const template = {
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
        };
        mockFetch.mockResolvedValueOnce({
            ok: true,
            status: 200,
            json: async () => template,
        });
        const result = await fetchWorkspaceTemplate('collaboration-core');
        expect(result?.id).toBe('collaboration-core');
        expect(result?.name).toBe('Collaboration Core');
        expect(mockFetch).toHaveBeenCalledWith('/api/workspace-templates/collaboration-core', expect.any(Object));
    });
    it('returns null when template is not found', async () => {
        mockFetch.mockResolvedValueOnce({
            ok: false,
            status: 404,
        });
        const result = await fetchWorkspaceTemplate('missing-template');
        expect(result).toBeNull();
    });
    it('fetches devcontainer for a template', async () => {
        const devcontainer = {
            name: 'Collaboration Core',
            image: 'mcr.microsoft.com/devcontainers/base:ubuntu',
            customizations: {
                vscode: {
                    extensions: ['ms-vscode.vscode-typescript-next@5.3.3'],
                    settings: { 'telemetry.telemetryLevel': 'off' },
                },
            },
        };
        mockFetch.mockResolvedValueOnce({
            ok: true,
            status: 200,
            json: async () => devcontainer,
        });
        const result = await fetchWorkspaceTemplateDevcontainer('collaboration-core');
        expect(result.name).toBe('Collaboration Core');
        expect(result.image).toBe('mcr.microsoft.com/devcontainers/base:ubuntu');
        expect(mockFetch).toHaveBeenCalledWith('/api/workspace-templates/collaboration-core/devcontainer', expect.any(Object));
    });
});
//# sourceMappingURL=workspaceTemplates.test.js.map