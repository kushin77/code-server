import { ALL_WORKSPACES, getWorkspaceById } from './workspaceCatalog'

export type WorkspaceRootSettingValue = string | number | boolean | string[]

export type WorkspaceRootDebuggerProfile = {
  name: string
  type: string
  request: 'launch' | 'attach'
  cwd: string
  program: string
  args?: string[]
  env?: Record<string, string>
}

export type WorkspaceRootTerminalProfile = {
  name: string
  shell: string
  cwd: string
  env?: Record<string, string>
}

export type WorkspaceRootProfile = {
  path: string
  label: string
  settings: Record<string, WorkspaceRootSettingValue>
  debugger: WorkspaceRootDebuggerProfile
  terminal: WorkspaceRootTerminalProfile
  enabledExtensions: string[]
}

export type WorkspaceProfile = {
  workspaceId: string
  workspaceLabel: string
  description: string
  mergeOrder: string[]
  roots: WorkspaceRootProfile[]
}

export type WorkspaceProfileSnapshot = {
  workspaceId: string
  workspaceLabel: string
  description: string
  mergeOrder: string[]
  activeRoot: WorkspaceRootProfile
  workspaceJson: string
}

const DEFAULT_MERGE_ORDER = ['global', 'workspace', 'root-folder']

function createRootProfile(args: WorkspaceRootProfile): WorkspaceRootProfile {
  return args
}

function buildWorkspaceProfile(workspaceId: string): WorkspaceProfile {
  const workspace = getWorkspaceById(workspaceId) ?? ALL_WORKSPACES[0]
  const workspaceLabel = workspace?.label ?? workspaceId

  switch (workspaceId) {
    case 'portal-main':
      return {
        workspaceId,
        workspaceLabel,
        description: 'Primary portal lane with separate frontend and backend roots.',
        mergeOrder: DEFAULT_MERGE_ORDER,
        roots: [
          createRootProfile({
            path: 'apps/frontend',
            label: 'Frontend root',
            settings: {
              'eslint.enable': true,
              'editor.formatOnSave': true,
              'typescript.tsdk': 'node_modules/typescript/lib',
            },
            debugger: {
              name: 'Portal UI',
              type: 'pwa-chrome',
              request: 'launch',
              cwd: '${workspaceFolder}/apps/frontend',
              program: 'http://localhost:3000',
            },
            terminal: {
              name: 'Frontend shell',
              shell: 'pnpm dev',
              cwd: '${workspaceFolder}/apps/frontend',
              env: { NODE_ENV: 'development' },
            },
            enabledExtensions: ['dbaeumer.vscode-eslint', 'bradlc.vscode-tailwindcss'],
          }),
          createRootProfile({
            path: 'apps/backend',
            label: 'Backend root',
            settings: {
              'eslint.enable': true,
              'editor.formatOnSave': true,
              'typescript.tsdk': 'node_modules/typescript/lib',
            },
            debugger: {
              name: 'Backend API',
              type: 'pwa-node',
              request: 'launch',
              cwd: '${workspaceFolder}/apps/backend',
              program: '${workspaceFolder}/apps/backend/src/index.ts',
            },
            terminal: {
              name: 'Backend shell',
              shell: 'pnpm test --watch',
              cwd: '${workspaceFolder}/apps/backend',
              env: { NODE_OPTIONS: '--enable-source-maps' },
            },
            enabledExtensions: ['dbaeumer.vscode-eslint', 'ms-vscode.vscode-typescript-next'],
          }),
        ],
      }
    case 'docs-review':
      return {
        workspaceId,
        workspaceLabel,
        description: 'Documentation review lane with markdown and runbook roots.',
        mergeOrder: DEFAULT_MERGE_ORDER,
        roots: [
          createRootProfile({
            path: 'docs',
            label: 'Docs root',
            settings: {
              'markdown.preview.breaks': true,
              'editor.wordWrap': 'on',
              'editor.formatOnSave': true,
            },
            debugger: {
              name: 'Docs preview',
              type: 'chrome',
              request: 'launch',
              cwd: '${workspaceFolder}/docs',
              program: 'http://localhost:4173',
            },
            terminal: {
              name: 'Docs server',
              shell: 'pnpm dev',
              cwd: '${workspaceFolder}/docs',
            },
            enabledExtensions: ['yzhang.markdown-all-in-one', 'bierner.markdown-preview-github-styles'],
          }),
          createRootProfile({
            path: 'docs/ops',
            label: 'Runbooks root',
            settings: {
              'markdown.preview.breaks': true,
              'editor.wordWrap': 'bounded',
              'files.trimTrailingWhitespace': true,
            },
            debugger: {
              name: 'Runbook preview',
              type: 'chrome',
              request: 'launch',
              cwd: '${workspaceFolder}/docs/ops',
              program: 'http://localhost:4174',
            },
            terminal: {
              name: 'Runbook lint',
              shell: 'pnpm lint',
              cwd: '${workspaceFolder}/docs/ops',
            },
            enabledExtensions: ['yzhang.markdown-all-in-one'],
          }),
        ],
      }
    case 'ops-control':
      return {
        workspaceId,
        workspaceLabel,
        description: 'Operational automation lane with config, scripts, and IaC roots.',
        mergeOrder: DEFAULT_MERGE_ORDER,
        roots: [
          createRootProfile({
            path: 'config',
            label: 'Config root',
            settings: {
              'yaml.validate': true,
              'editor.formatOnSave': true,
              'files.insertFinalNewline': true,
            },
            debugger: {
              name: 'Config validation',
              type: 'node',
              request: 'launch',
              cwd: '${workspaceFolder}/config',
              program: '${workspaceFolder}/config/scripts/validate-config.ts',
            },
            terminal: {
              name: 'Config check',
              shell: 'pnpm test',
              cwd: '${workspaceFolder}/config',
            },
            enabledExtensions: ['redhat.vscode-yaml', 'tamasfe.even-better-toml'],
          }),
          createRootProfile({
            path: 'scripts',
            label: 'Automation root',
            settings: {
              'shellcheck.enable': true,
              'files.insertFinalNewline': true,
              'editor.formatOnSave': false,
            },
            debugger: {
              name: 'Shell automation',
              type: 'node',
              request: 'launch',
              cwd: '${workspaceFolder}/scripts',
              program: '${workspaceFolder}/scripts/ops/run.ts',
            },
            terminal: {
              name: 'Ops shell',
              shell: 'bash',
              cwd: '${workspaceFolder}/scripts',
              env: { CI: '1' },
            },
            enabledExtensions: ['timonwong.shellcheck'],
          }),
          createRootProfile({
            path: 'terraform',
            label: 'IaC root',
            settings: {
              'terraform.experimentalFeatures.validateOnSave': true,
              'editor.formatOnSave': true,
            },
            debugger: {
              name: 'Terraform plan',
              type: 'node',
              request: 'launch',
              cwd: '${workspaceFolder}/terraform',
              program: '${workspaceFolder}/terraform/scripts/plan.ts',
            },
            terminal: {
              name: 'Terraform shell',
              shell: 'terraform plan',
              cwd: '${workspaceFolder}/terraform',
            },
            enabledExtensions: ['hashicorp.terraform'],
          }),
        ],
      }
    case 'security-lab':
      return {
        workspaceId,
        workspaceLabel,
        description: 'Security hardening lane with backend, config, and scripted validation roots.',
        mergeOrder: DEFAULT_MERGE_ORDER,
        roots: [
          createRootProfile({
            path: 'apps/backend',
            label: 'Backend hardening root',
            settings: {
              'eslint.enable': true,
              'editor.formatOnSave': true,
              'typescript.tsdk': 'node_modules/typescript/lib',
            },
            debugger: {
              name: 'Security regression',
              type: 'pwa-node',
              request: 'launch',
              cwd: '${workspaceFolder}/apps/backend',
              program: '${workspaceFolder}/apps/backend/src/index.ts',
            },
            terminal: {
              name: 'Security scan',
              shell: 'pnpm audit',
              cwd: '${workspaceFolder}/apps/backend',
            },
            enabledExtensions: ['dbaeumer.vscode-eslint', 'ms-vscode.vscode-typescript-next'],
          }),
          createRootProfile({
            path: 'config',
            label: 'Config hardening root',
            settings: {
              'yaml.validate': true,
              'files.trimTrailingWhitespace': true,
              'editor.formatOnSave': true,
            },
            debugger: {
              name: 'Policy validation',
              type: 'node',
              request: 'launch',
              cwd: '${workspaceFolder}/config',
              program: '${workspaceFolder}/config/scripts/validate-policy.ts',
            },
            terminal: {
              name: 'Policy shell',
              shell: 'pnpm test',
              cwd: '${workspaceFolder}/config',
            },
            enabledExtensions: ['redhat.vscode-yaml'],
          }),
          createRootProfile({
            path: 'scripts',
            label: 'Validation root',
            settings: {
              'shellcheck.enable': true,
              'files.trimTrailingWhitespace': true,
              'editor.formatOnSave': false,
            },
            debugger: {
              name: 'Red-team harness',
              type: 'node',
              request: 'launch',
              cwd: '${workspaceFolder}/scripts',
              program: '${workspaceFolder}/scripts/ops/run-security-harness.ts',
            },
            terminal: {
              name: 'Validation shell',
              shell: 'bash',
              cwd: '${workspaceFolder}/scripts',
              env: { SECURITY_REVIEW: '1' },
            },
            enabledExtensions: ['timonwong.shellcheck'],
          }),
        ],
      }
    default:
      return {
        workspaceId,
        workspaceLabel,
        description: 'Default multi-root profile for the current workspace.',
        mergeOrder: DEFAULT_MERGE_ORDER,
        roots: [
          createRootProfile({
            path: '.',
            label: 'Workspace root',
            settings: {
              'editor.formatOnSave': true,
            },
            debugger: {
              name: 'Generic workspace',
              type: 'node',
              request: 'launch',
              cwd: '${workspaceFolder}',
              program: '${workspaceFolder}/src/index.ts',
            },
            terminal: {
              name: 'Workspace shell',
              shell: 'bash',
              cwd: '${workspaceFolder}',
            },
            enabledExtensions: ['dbaeumer.vscode-eslint'],
          }),
        ],
      }
  }
}

export function getWorkspaceProfile(workspaceId: string): WorkspaceProfile {
  return buildWorkspaceProfile(workspaceId)
}

export function resolveWorkspaceRootProfile(workspaceId: string, rootPath?: string): WorkspaceRootProfile {
  const profile = buildWorkspaceProfile(workspaceId)
  if (!rootPath) {
    return profile.roots[0]
  }

  return profile.roots.find((root) => root.path === rootPath) ?? profile.roots[0]
}

export function buildWorkspaceProfileSnapshot(workspaceId: string, activeRootPath?: string): WorkspaceProfileSnapshot {
  const profile = buildWorkspaceProfile(workspaceId)
  const activeRoot = resolveWorkspaceRootProfile(workspaceId, activeRootPath)

  return {
    workspaceId: profile.workspaceId,
    workspaceLabel: profile.workspaceLabel,
    description: profile.description,
    mergeOrder: profile.mergeOrder,
    activeRoot,
    workspaceJson: serializeWorkspaceProfile(profile),
  }
}

export function serializeWorkspaceProfile(profile: WorkspaceProfile): string {
  const config = {
    workspaceId: profile.workspaceId,
    workspaceLabel: profile.workspaceLabel,
    mergeOrder: profile.mergeOrder,
    perRootSettings: profile.roots.reduce<Record<string, Record<string, WorkspaceRootSettingValue>>>((accumulator, root) => {
      accumulator[root.path] = root.settings
      return accumulator
    }, {}),
    perRootDebugger: profile.roots.reduce<Record<string, WorkspaceRootDebuggerProfile>>((accumulator, root) => {
      accumulator[root.path] = root.debugger
      return accumulator
    }, {}),
    perRootTerminalProfiles: profile.roots.reduce<Record<string, WorkspaceRootTerminalProfile>>((accumulator, root) => {
      accumulator[root.path] = root.terminal
      return accumulator
    }, {}),
    perRootExtensions: profile.roots.reduce<Record<string, string[]>>((accumulator, root) => {
      accumulator[root.path] = root.enabledExtensions
      return accumulator
    }, {}),
  }

  return JSON.stringify(config, null, 2)
}