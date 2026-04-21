import { describe, expect, it } from 'vitest'
import { buildWorkspaceProfileSnapshot, getWorkspaceProfile, resolveWorkspaceRootProfile, serializeWorkspaceProfile } from '../workspaceProfiles'

describe('workspaceProfiles', () => {
  it('builds a profile snapshot with root-scoped configuration', () => {
    const profile = getWorkspaceProfile('portal-main')
    const snapshot = buildWorkspaceProfileSnapshot('portal-main', 'apps/backend')

    expect(profile.roots).toHaveLength(2)
    expect(snapshot.activeRoot.path).toBe('apps/backend')
    expect(snapshot.workspaceJson).toContain('perRootSettings')
    expect(snapshot.workspaceJson).toContain('apps/frontend')
  })

  it('falls back to the first root when the requested root is missing', () => {
    const root = resolveWorkspaceRootProfile('docs-review', 'missing-root')

    expect(root.path).toBe('docs')
  })

  it('serializes root settings, debugger, terminal, and extensions', () => {
    const profile = getWorkspaceProfile('ops-control')
    const serialized = serializeWorkspaceProfile(profile)

    expect(serialized).toContain('terraform')
    expect(serialized).toContain('perRootDebugger')
    expect(serialized).toContain('perRootTerminalProfiles')
    expect(serialized).toContain('perRootExtensions')
  })
})