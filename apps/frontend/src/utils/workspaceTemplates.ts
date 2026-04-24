// @file        apps/frontend/src/utils/workspaceTemplates.ts
// @module      utils/workspace-templates
// @description Frontend helpers for workspace template catalog

export type WorkspaceTemplateDefinition = {
  id: string
  name: string
  description: string
  settings: Record<string, unknown>
  pinnedExtensions: string[]
  devcontainer: {
    name: string
    image: string
    customizations: {
      vscode: {
        extensions: string[]
        settings: Record<string, unknown>
      }
    }
  }
  envSchema?: Record<string, { type: string; description: string; default?: any }>
  source: {
    settingsPath: string
    approvedManifestPath: string
    roleProfilePath?: string
  }
}

export type WorkspaceTemplateCatalogSnapshot = {
  templates: WorkspaceTemplateDefinition[]
  settings: Record<string, unknown>
  extensionManifest: {
    policyVersion: string
    policyDate: string
    manifestSignature: string
    approvedExtensions: Array<{
      id: string
      version: string
      tier: string
      reason: string
      pre_installed: boolean
      user_can_uninstall: boolean
    }>
    blockedExtensions: Array<{
      pattern: string
      reason: string
      alternative?: string
    }>
  }
}

const WORKSPACE_TEMPLATES_API_BASE = '/api/workspace-templates'

async function requestJson<T>(
  input: RequestInfo | URL,
  init?: RequestInit,
  allowNotFound = false
): Promise<T | null> {
  const response = await fetch(input, {
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    ...init,
  })

  if (allowNotFound && response.status === 404) {
    return null
  }

  if (!response.ok) {
    throw new Error(`Workspace templates request failed with ${response.status}`)
  }

  return (await response.json()) as T
}

export async function fetchWorkspaceTemplateCatalog(): Promise<WorkspaceTemplateCatalogSnapshot> {
  return requestJson<WorkspaceTemplateCatalogSnapshot>(
    `${WORKSPACE_TEMPLATES_API_BASE}/snapshot`
  ) as Promise<WorkspaceTemplateCatalogSnapshot>
}

export async function fetchWorkspaceTemplate(
  templateId: string
): Promise<WorkspaceTemplateDefinition | null> {
  return requestJson<WorkspaceTemplateDefinition>(
    `${WORKSPACE_TEMPLATES_API_BASE}/${encodeURIComponent(templateId)}`,
    undefined,
    true
  )
}

export async function fetchWorkspaceTemplateDevcontainer(
  templateId: string
): Promise<Record<string, unknown>> {
  return requestJson<Record<string, unknown>>(
    `${WORKSPACE_TEMPLATES_API_BASE}/${encodeURIComponent(templateId)}/devcontainer`
  ) as Promise<Record<string, unknown>>
}
