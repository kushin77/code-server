/**
 * Workspace profile management utilities
 */

export interface WorkspaceDebuggerProfile {
  name: string
  type: string
  request: string
  cwd: string
  program: string
  runtimeExecutable?: string
  args?: string[]
  config?: Record<string, unknown>
  env?: Record<string, string>
}

export interface WorkspaceTerminalProfile {
  name: string
  shell: string
  cwd: string
  env?: Record<string, string>
}

export interface WorkspaceRoot {
  path: string
  label?: string
  settings: Record<string, unknown>
  debugger: WorkspaceDebuggerProfile
  terminal: WorkspaceTerminalProfile
  enabledExtensions: string[]
}

export interface WorkspaceProfile {
  id: string
  name: string
  workspaceLabel: string
  description: string
  root: string
  workspaceId: string
  roots: WorkspaceRoot[]
  mergeOrder: number[]
  settings: Record<string, unknown>
}

export interface WorkspaceProfileSnapshot {
  profiles: WorkspaceProfile[]
  activeProfileId: string | null
  lastUpdated: number
  workspaceJson?: string
  workspaceLabel?: string
  mergeOrder?: number[]
}

type WorkspaceProfileManifest = WorkspaceProfile
type StoredWorkspaceTabs = {
  activeRepoId: string
  recentRepoIds: string[]
}

const WORKSPACE_PROFILE_MANIFESTS: Record<string, WorkspaceProfileManifest> = {
  'portal-main': {
    id: 'portal-main',
    name: 'Portal main',
    workspaceLabel: 'Portal main',
    description: 'Primary repo surface for the portal and RBAC dashboard.',
    root: 'apps/frontend',
    workspaceId: 'portal-main',
    mergeOrder: [1, 2, 3, 4, 5],
    settings: {
      'workbench.startupEditor': 'none',
      'files.autoSave': 'afterDelay',
      'editor.formatOnSave': true,
    },
    roots: [
      {
        path: 'apps/frontend',
        label: 'Frontend root',
        settings: {
          'editor.defaultFormatter': 'dbaeumer.vscode-eslint',
          'typescript.tsdk': 'node_modules/typescript/lib',
          'files.exclude': ['**/.next', '**/dist', '**/coverage'],
        },
        debugger: {
          name: 'Portal UI',
          type: 'pwa-node',
          request: 'launch',
          cwd: 'apps/frontend',
          program: 'apps/frontend/src/main.tsx',
          runtimeExecutable: 'node',
          args: ['--enable-source-maps'],
        },
        terminal: {
          name: 'Frontend terminal',
          shell: 'pnpm',
          cwd: 'apps/frontend',
          env: { NODE_ENV: 'development', VITE_APP_NAME: 'portal' },
        },
        enabledExtensions: ['dbaeumer.vscode-eslint', 'bradlc.vscode-tailwindcss', 'ms-vscode.vscode-typescript-next'],
      },
      {
        path: 'apps/backend',
        label: 'Backend root',
        settings: {
          'editor.defaultFormatter': 'esbenp.prettier-vscode',
          'files.exclude': ['**/dist', '**/coverage'],
        },
        debugger: {
          name: 'API server',
          type: 'node',
          request: 'launch',
          cwd: 'apps/backend',
          program: 'apps/backend/src/index.ts',
          runtimeExecutable: 'node',
        },
        terminal: {
          name: 'Backend terminal',
          shell: 'pnpm',
          cwd: 'apps/backend',
          env: { NODE_ENV: 'development' },
        },
        enabledExtensions: ['esbenp.prettier-vscode', 'ms-azuretools.vscode-docker'],
      },
    ],
  },
  'docs-review': {
    id: 'docs-review',
    name: 'Docs review',
    workspaceLabel: 'Docs review',
    description: 'Runbook and governance doc set used during release prep.',
    root: 'docs',
    workspaceId: 'docs-review',
    mergeOrder: [1, 2, 3, 4, 5],
    settings: { 'files.autoSave': 'off', 'editor.wordWrap': 'on' },
    roots: [
      {
        path: 'docs',
        label: 'Docs root',
        settings: { 'editor.defaultFormatter': 'esbenp.prettier-vscode', 'markdown.preview.breaks': true },
        debugger: {
          name: 'Docs preview',
          type: 'pwa-node',
          request: 'launch',
          cwd: 'docs',
          program: 'docs/scripts/preview.ts',
          runtimeExecutable: 'node',
        },
        terminal: { name: 'Docs terminal', shell: 'pnpm', cwd: 'docs' },
        enabledExtensions: ['yzhang.markdown-all-in-one', 'bierner.markdown-mermaid'],
      },
    ],
  },
  'ops-control': {
    id: 'ops-control',
    name: 'Ops control',
    workspaceLabel: 'Ops control',
    description: 'Operational automation, redeploy gates, and failover controls.',
    root: 'scripts',
    workspaceId: 'ops-control',
    mergeOrder: [1, 2, 3, 4, 5],
    settings: { 'files.autoSave': 'off', 'terminal.integrated.defaultProfile.windows': 'PowerShell' },
    roots: [
      {
        path: 'scripts',
        label: 'Operations root',
        settings: { 'editor.defaultFormatter': 'esbenp.prettier-vscode', 'files.exclude': ['**/node_modules', '**/dist'] },
        debugger: {
          name: 'Ops automation',
          type: 'node',
          request: 'launch',
          cwd: 'scripts',
          program: 'scripts/ops/run-resilience-campaign.sh',
          runtimeExecutable: 'node',
        },
        terminal: { name: 'Ops terminal', shell: 'bash', cwd: 'scripts', env: { CI: 'true' } },
        enabledExtensions: ['timonwong.shellcheck', 'ms-vscode.powershell'],
      },
    ],
  },
  'dev-sandbox': {
    id: 'dev-sandbox',
    name: 'Dev sandbox',
    workspaceLabel: 'Dev sandbox',
    description: 'Experimental feature branch workspace for pilot navigation flows.',
    root: 'apps/frontend',
    workspaceId: 'dev-sandbox',
    mergeOrder: [1, 2, 3, 4, 5],
    settings: { 'workbench.startupEditor': 'readme', 'editor.formatOnSave': true },
    roots: [
      {
        path: 'apps/frontend',
        label: 'Frontend root',
        settings: { 'editor.defaultFormatter': 'dbaeumer.vscode-eslint', 'typescript.tsdk': 'node_modules/typescript/lib' },
        debugger: {
          name: 'Sandbox preview',
          type: 'pwa-node',
          request: 'launch',
          cwd: 'apps/frontend',
          program: 'apps/frontend/src/main.tsx',
          runtimeExecutable: 'node',
        },
        terminal: { name: 'Sandbox terminal', shell: 'pnpm', cwd: 'apps/frontend' },
        enabledExtensions: ['dbaeumer.vscode-eslint', 'bradlc.vscode-tailwindcss'],
      },
    ],
  },
  'security-lab': {
    id: 'security-lab',
    name: 'Security lab',
    workspaceLabel: 'Security lab',
    description: 'Security hardening workspace with stricter repo access controls.',
    root: 'apps/backend',
    workspaceId: 'security-lab',
    mergeOrder: [1, 2, 3, 4, 5],
    settings: { 'workbench.startupEditor': 'none', 'files.exclude': ['**/.secrets', '**/dist', '**/coverage'] },
    roots: [
      {
        path: 'apps/backend',
        label: 'Security root',
        settings: { 'editor.defaultFormatter': 'esbenp.prettier-vscode', 'terminal.integrated.shellIntegration.enabled': false },
        debugger: {
          name: 'Security server',
          type: 'node',
          request: 'launch',
          cwd: 'apps/backend',
          program: 'apps/backend/src/index.ts',
          runtimeExecutable: 'node',
        },
        terminal: { name: 'Security terminal', shell: 'bash', cwd: 'apps/backend' },
        enabledExtensions: ['timonwong.shellcheck', 'gruntfuggly.todo-tree'],
      },
    ],
  },
}

function cloneWorkspaceRoot(root: WorkspaceRoot): WorkspaceRoot {
  return {
    ...root,
    settings: { ...root.settings },
    debugger: {
      ...root.debugger,
      args: root.debugger.args ? [...root.debugger.args] : undefined,
      env: root.debugger.env ? { ...root.debugger.env } : undefined,
      config: root.debugger.config ? { ...root.debugger.config } : undefined,
    },
    terminal: {
      ...root.terminal,
      env: root.terminal.env ? { ...root.terminal.env } : undefined,
    },
    enabledExtensions: [...root.enabledExtensions],
  }
}

function cloneWorkspaceProfile(profile: WorkspaceProfile): WorkspaceProfile {
  return {
    ...profile,
    settings: { ...profile.settings },
    mergeOrder: [...profile.mergeOrder],
    roots: profile.roots.map((root) => cloneWorkspaceRoot(root)),
  }
}

function createFallbackRoot(workspaceId: string): WorkspaceRoot {
  return {
    path: workspaceId,
    label: 'Workspace root',
    settings: { 'workbench.startupEditor': 'welcomePage' },
    debugger: {
      name: 'Workspace debugger',
      type: 'pwa-node',
      request: 'launch',
      cwd: workspaceId,
      program: 'src/index.ts',
      runtimeExecutable: 'node',
    },
    terminal: { name: 'Workspace terminal', shell: 'pnpm', cwd: workspaceId },
    enabledExtensions: [],
  }
}

function getWorkspaceProfileManifest(workspaceId: string): WorkspaceProfileManifest | undefined {
  return WORKSPACE_PROFILE_MANIFESTS[workspaceId]
}

function createWorkspaceJson(profile: WorkspaceProfile, activeRoot: WorkspaceRoot): string {
  return JSON.stringify(
    {
      schema_version: 1,
      id: profile.workspaceId,
      name: profile.name,
      workspace_label: profile.workspaceLabel,
      description: profile.description,
      primary_root: profile.root,
      selected_root: activeRoot.path,
      merge_order: profile.mergeOrder,
      roots: profile.roots.map((root) => ({
        path: root.path,
        label: root.label,
        settings: root.settings,
        debugger: root.debugger,
        terminal: root.terminal,
        enabledExtensions: root.enabledExtensions,
      })),
      settings: profile.settings,
    },
    null,
    2,
  )
}

export function buildWorkspaceProfileSnapshot(root: string, selectedRoot?: string): WorkspaceProfileSnapshot {
  const profile = getWorkspaceProfileManifest(root)
  const activeRoot = resolveWorkspaceRootProfile(root, selectedRoot)

  return {
    profiles: profile ? [cloneWorkspaceProfile(profile)] : [],
    activeProfileId: profile?.workspaceId ?? root,
    lastUpdated: Date.now(),
    workspaceJson: profile
      ? createWorkspaceJson(profile, activeRoot)
      : JSON.stringify(
          {
            schema_version: 1,
            id: root,
            name: root,
            selected_root: activeRoot.path,
            roots: [activeRoot],
          },
          null,
          2,
        ),
    workspaceLabel: profile?.workspaceLabel ?? root,
    mergeOrder: profile?.mergeOrder ?? [1, 2, 3, 4, 5],
  }
}

export function getWorkspaceProfile(id: string): WorkspaceProfile | null {
  const profile = getWorkspaceProfileManifest(id)
  return profile ? cloneWorkspaceProfile(profile) : null
}

export function resolveWorkspaceRootProfile(root: string, selectedPath?: string): WorkspaceRoot {
  const profile = getWorkspaceProfileManifest(root)
  const roots = profile?.roots.map((entry) => cloneWorkspaceRoot(entry)) ?? []

  if (selectedPath) {
    const selectedRoot = roots.find((entry) => entry.path === selectedPath)
    if (selectedRoot) {
      return selectedRoot
    }
  }

  return roots[0] ?? createFallbackRoot(root)
}

export function readStoredWorkspaceTabs(storage: Storage | undefined): StoredWorkspaceTabs {
  if (!storage) {
    return { activeRepoId: 'portal-main', recentRepoIds: ['dev-sandbox', 'security-lab'] }
  }

  try {
    const activeRepoId = storage.getItem('workspace-tabs:active-repo') || 'portal-main'
    const recentRepoIds = JSON.parse(storage.getItem('workspace-tabs:recent-repos') || '[]') as string[]

    return {
      activeRepoId,
      recentRepoIds: Array.isArray(recentRepoIds) ? recentRepoIds : ['dev-sandbox', 'security-lab'],
    }
  } catch {
    return { activeRepoId: 'portal-main', recentRepoIds: ['dev-sandbox', 'security-lab'] }
  }
}

export function writeStoredWorkspaceTabs(storage: Storage | undefined, workspaceState: StoredWorkspaceTabs): void {
  if (!storage) {
    return
  }

  storage.setItem('workspace-tabs:active-repo', workspaceState.activeRepoId)
  storage.setItem('workspace-tabs:recent-repos', JSON.stringify(workspaceState.recentRepoIds))
}

export function buildRecentWorkspaceIds(activeRepoId: string, recentRepoIds: string[], maxCount = 2): string[] {
  return [activeRepoId, ...recentRepoIds.filter((workspaceId) => workspaceId !== activeRepoId)].slice(0, maxCount)
}

export function getSuggestedWorkspaceId(roleIds: string[]): string {
  const normalizedRoleIds = roleIds.map((roleId) => roleId.toLowerCase())
  if (normalizedRoleIds.includes('admin') || normalizedRoleIds.includes('auditor')) {
    return 'ops-control'
  }
  if (normalizedRoleIds.includes('developer')) {
    return 'dev-sandbox'
  }
  if (normalizedRoleIds.includes('reviewer')) {
    return 'docs-review'
  }
  if (normalizedRoleIds.includes('viewer')) {
    return 'portal-main'
  }
  return 'portal-main'
}

export function notifyWorkspaceTabsChanged(): void {
  if (typeof window === 'undefined') {
    return
  }

  window.dispatchEvent(new Event('workspace-tabs:changed'))
}
