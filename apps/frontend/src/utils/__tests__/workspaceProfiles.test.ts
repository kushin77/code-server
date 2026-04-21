import { describe, expect, it } from 'vitest'

import {
  buildWorkspaceProfileSnapshot,
  getWorkspaceProfile,
  resolveWorkspaceRootProfile,
} from '../workspaceProfiles'

describe('workspaceProfiles', () => {
  it('returns a manifest-backed profile for the portal workspace', () => {
    const profile = getWorkspaceProfile('portal-main')

    expect(profile).not.toBeNull()
    expect(profile?.workspaceLabel).toBe('Portal main')
    expect(profile?.roots).toHaveLength(2)
    expect(profile?.roots?.[0].label).toBe('Frontend root')
  })

  it('resolves the selected root from the manifest when provided', () => {
    const root = resolveWorkspaceRootProfile('portal-main', 'apps/frontend')

    expect(root.label).toBe('Frontend root')
    expect(root.path).toBe('apps/frontend')
    expect(root.debugger?.name).toBe('Portal UI')
    expect(root.terminal?.shell).toBe('pnpm')
    expect(root.enabledExtensions).toContain('dbaeumer.vscode-eslint')
  })

  it('builds a manifest preview snapshot for the selected workspace', () => {
    const snapshot = buildWorkspaceProfileSnapshot('portal-main', 'apps/frontend')

    expect(snapshot.activeProfileId).toBe('portal-main')
    expect(snapshot.workspaceLabel).toBe('Portal main')
    expect(snapshot.mergeOrder).toEqual([1, 2, 3, 4, 5])
    expect(snapshot.profiles).toHaveLength(1)
    expect(snapshot.workspaceJson).toContain('"selected_root": "apps/frontend"')
    expect(snapshot.workspaceJson).toContain('Frontend root')
  })

  it('falls back to a safe root profile when the workspace id is unknown', () => {
    const profile = getWorkspaceProfile('unknown-workspace')
    const root = resolveWorkspaceRootProfile('unknown-workspace')
    const snapshot = buildWorkspaceProfileSnapshot('unknown-workspace')

    expect(profile).toBeNull()
    expect(root.label).toBe('Workspace root')
    expect(root.path).toBe('unknown-workspace')
    expect(snapshot.activeProfileId).toBe('unknown-workspace')
    expect(snapshot.workspaceJson).toContain('unknown-workspace')
  })
})
