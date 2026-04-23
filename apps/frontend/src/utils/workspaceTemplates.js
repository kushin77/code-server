// @file        apps/frontend/src/utils/workspaceTemplates.ts
// @module      utils/workspace-templates
// @description Frontend helpers for workspace template catalog
const WORKSPACE_TEMPLATES_API_BASE = '/api/workspace-templates';
async function requestJson(input, init, allowNotFound = false) {
    const response = await fetch(input, {
        headers: {
            'Content-Type': 'application/json',
            ...(init?.headers ?? {}),
        },
        ...init,
    });
    if (allowNotFound && response.status === 404) {
        return null;
    }
    if (!response.ok) {
        throw new Error(`Workspace templates request failed with ${response.status}`);
    }
    return (await response.json());
}
export async function fetchWorkspaceTemplateCatalog() {
    return requestJson(`${WORKSPACE_TEMPLATES_API_BASE}/snapshot`);
}
export async function fetchWorkspaceTemplate(templateId) {
    return requestJson(`${WORKSPACE_TEMPLATES_API_BASE}/${encodeURIComponent(templateId)}`, undefined, true);
}
export async function fetchWorkspaceTemplateDevcontainer(templateId) {
    return requestJson(`${WORKSPACE_TEMPLATES_API_BASE}/${encodeURIComponent(templateId)}/devcontainer`);
}
//# sourceMappingURL=workspaceTemplates.js.map