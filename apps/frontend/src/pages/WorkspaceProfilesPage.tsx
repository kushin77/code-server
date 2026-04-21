import { useEffect, useMemo, useState } from 'react'
import { ALL_WORKSPACES, type WorkspaceTab } from '../utils/workspaceCatalog'
import {
  buildWorkspaceProfileSnapshot,
  getWorkspaceProfile,
  resolveWorkspaceRootProfile,
} from '../utils/workspaceProfiles'

type WorkspaceProfilesPageWorkspaceState = {
  activeWorkspace: WorkspaceTab
  recentRepoIds: string[]
  selectWorkspace: (workspaceId: string) => void
  workspacePolicy: {
    label: string
    canSwitchWorkspace: boolean
    canUseQuickSwitcher: boolean
    canRestoreSession: boolean
    canPinWorkspace: boolean
    maxRecentWorkspaces: number
  }
}

export type WorkspaceProfilesPageProps = {
  workspaceState: WorkspaceProfilesPageWorkspaceState
}

export function WorkspaceProfilesPage({ workspaceState }: WorkspaceProfilesPageProps) {
  const { activeWorkspace, selectWorkspace, workspacePolicy } = workspaceState
  const [selectedWorkspaceId, setSelectedWorkspaceId] = useState(activeWorkspace.id)
  const [selectedRootPath, setSelectedRootPath] = useState<string | undefined>()
  const [copyNotice, setCopyNotice] = useState<string | null>(null)

  useEffect(() => {
    setSelectedWorkspaceId(activeWorkspace.id)
  }, [activeWorkspace.id])

  const profile = useMemo(() => getWorkspaceProfile(selectedWorkspaceId), [selectedWorkspaceId])
  const profileSnapshot = useMemo(
    () => buildWorkspaceProfileSnapshot(selectedWorkspaceId, selectedRootPath),
    [selectedRootPath, selectedWorkspaceId]
  )
  const activeRoot = useMemo(
    () => resolveWorkspaceRootProfile(selectedWorkspaceId, selectedRootPath),
    [selectedRootPath, selectedWorkspaceId]
  )

  useEffect(() => {
    if (profile.roots.some((root) => root.path === selectedRootPath)) {
      return
    }

    setSelectedRootPath(profile.roots[0]?.path)
  }, [profile.roots, selectedRootPath])

  const handleWorkspaceSelect = (workspaceId: string) => {
    setSelectedWorkspaceId(workspaceId)
    selectWorkspace(workspaceId)
    setCopyNotice(null)
  }

  const handleCopyProfile = async () => {
    if (typeof navigator === 'undefined' || !navigator.clipboard) {
      setCopyNotice('Clipboard is not available in this environment')
      return
    }

    await navigator.clipboard.writeText(profileSnapshot.workspaceJson)
    setCopyNotice('Workspace profile JSON copied to clipboard')
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-100">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-violet-700">Multi-root profiles</p>
            <h2 className="mt-2 text-2xl font-bold text-slate-900">Workspace profiles and root-scoped context</h2>
            <p className="mt-2 max-w-2xl text-sm text-slate-600">
              Inspect how each project root resolves settings, debugger launch configs, terminal profiles, and extension scopes.
            </p>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-2xl bg-violet-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-violet-700">Active workspace</p>
              <p className="mt-1 text-lg font-semibold text-slate-900">{profileSnapshot.workspaceLabel}</p>
              <p className="text-sm text-slate-600">Root: {activeRoot.path}</p>
            </div>
            <div className="rounded-2xl bg-emerald-50 px-4 py-3">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">Merge order</p>
              <p className="mt-1 text-sm font-medium text-slate-700">{profileSnapshot.mergeOrder.join(' → ')}</p>
              <p className="text-xs text-slate-500">Global config is refined by workspace and root-folder scope.</p>
            </div>
          </div>
        </div>

        <div className="mt-6 grid gap-3 md:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Root folders</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{profile.roots.length}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Policy lane</p>
            <p className="mt-1 text-lg font-semibold text-slate-900">{workspacePolicy.label}</p>
            <p className="mt-1 text-xs text-slate-500">Workspace switching: {workspacePolicy.canSwitchWorkspace ? 'enabled' : 'restricted'}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Recent repos</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{workspaceState.recentRepoIds.length}</p>
          </div>
        </div>

        <div className="mt-6 grid gap-6 lg:grid-cols-[260px_minmax(0,1fr)]">
          <aside className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Workspace sets</p>
            <div className="mt-3 space-y-2">
              {ALL_WORKSPACES.map((workspace: WorkspaceTab) => {
                const isSelected = workspace.id === selectedWorkspaceId

                return (
                  <button
                    key={workspace.id}
                    type="button"
                    onClick={() => handleWorkspaceSelect(workspace.id)}
                    className={`flex w-full flex-col rounded-2xl border px-3 py-3 text-left transition ${
                      isSelected ? 'border-violet-500 bg-violet-50 shadow-sm' : 'border-slate-200 bg-white hover:border-violet-300'
                    }`}
                  >
                    <span className="text-sm font-semibold text-slate-900">{workspace.label}</span>
                    <span className="text-xs text-slate-500">{workspace.branch}</span>
                    <span className="mt-2 inline-flex w-fit rounded-full bg-slate-100 px-2 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-600">
                      {workspace.pinned ? 'Pinned' : 'Recent'}
                    </span>
                  </button>
                )
              })}
            </div>
          </aside>

          <div className="space-y-6">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
                <div>
                  <p className="text-sm font-semibold text-slate-900">{profile.workspaceLabel}</p>
                  <p className="text-sm text-slate-600">{profile.description}</p>
                </div>

                <div className="flex flex-wrap gap-2">
                  <button
                    type="button"
                    onClick={handleCopyProfile}
                    className="rounded-full border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-violet-400 hover:text-violet-700"
                  >
                    Copy workspace.json
                  </button>
                  <button
                    type="button"
                    onClick={() => selectWorkspace(profile.workspaceId)}
                    className="rounded-full bg-violet-600 px-3 py-2 text-sm font-medium text-white transition hover:bg-violet-700"
                  >
                    Activate profile
                  </button>
                </div>
              </div>

              {copyNotice ? <p className="mt-3 text-sm font-medium text-emerald-700">{copyNotice}</p> : null}

              <div className="mt-5 flex flex-wrap gap-2">
                {profile.roots.map((root) => {
                  const isSelected = root.path === activeRoot.path

                  return (
                    <button
                      key={root.path}
                      type="button"
                      onClick={() => setSelectedRootPath(root.path)}
                      className={`rounded-full px-3 py-2 text-sm font-medium transition ${
                        isSelected ? 'bg-slate-900 text-white' : 'border border-slate-300 bg-white text-slate-700 hover:border-violet-400 hover:text-violet-700'
                      }`}
                    >
                      {root.label}
                    </button>
                  )
                })}
              </div>
            </div>

            <div className="grid gap-6 xl:grid-cols-2">
              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Root settings</p>
                <p className="mt-1 text-lg font-semibold text-slate-900">{activeRoot.label}</p>
                <p className="text-sm text-slate-600">{activeRoot.path}</p>

                <dl className="mt-4 space-y-3">
                  {Object.entries(activeRoot.settings).map(([settingKey, settingValue]) => (
                    <div key={settingKey} className="rounded-xl border border-slate-200 bg-white px-3 py-2">
                      <dt className="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">{settingKey}</dt>
                      <dd className="mt-1 text-sm text-slate-800">{Array.isArray(settingValue) ? settingValue.join(', ') : String(settingValue)}</dd>
                    </div>
                  ))}
                </dl>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Debugger and terminal</p>
                <div className="mt-4 space-y-4">
                  <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
                    <p className="text-sm font-semibold text-slate-900">Debugger</p>
                    <p className="text-sm text-slate-600">{activeRoot.debugger.name}</p>
                    <p className="text-xs text-slate-500">
                      {activeRoot.debugger.type} · {activeRoot.debugger.request} · {activeRoot.debugger.cwd}
                    </p>
                    <p className="mt-2 text-xs text-slate-700">Program: {activeRoot.debugger.program}</p>
                  </div>

                  <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
                    <p className="text-sm font-semibold text-slate-900">Terminal</p>
                    <p className="text-sm text-slate-600">{activeRoot.terminal.name}</p>
                    <p className="text-xs text-slate-500">{activeRoot.terminal.shell} · {activeRoot.terminal.cwd}</p>
                    {activeRoot.terminal.env ? (
                      <p className="mt-2 text-xs text-slate-700">Env: {Object.entries(activeRoot.terminal.env).map(([key, value]) => `${key}=${value}`).join(', ')}</p>
                    ) : null}
                  </div>

                  <div className="rounded-xl border border-slate-200 bg-white px-3 py-3">
                    <p className="text-sm font-semibold text-slate-900">Scoped extensions</p>
                    <div className="mt-2 flex flex-wrap gap-2">
                      {activeRoot.enabledExtensions.map((extensionId) => (
                        <span key={extensionId} className="rounded-full bg-slate-100 px-2 py-1 text-xs font-medium text-slate-700">
                          {extensionId}
                        </span>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div className="rounded-2xl border border-dashed border-violet-200 bg-violet-50 p-5">
              <p className="text-xs font-semibold uppercase tracking-[0.24em] text-violet-700">workspace.json preview</p>
              <pre className="mt-3 overflow-x-auto rounded-2xl bg-slate-950 p-4 text-xs leading-6 text-slate-100">
                {profileSnapshot.workspaceJson}
              </pre>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
