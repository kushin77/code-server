import React, { useCallback, useEffect, useMemo, useState } from 'react'

import { measureAsyncExtensionProfiler, useExtensionMountProfiler } from '@/utils/extensionProfiler'

type FeatureFlagProvider = 'launchdarkly' | 'unleash' | 'local'

type FeatureFlag = {
  key: string
  name: string
  description: string
  enabled: boolean
  provider: FeatureFlagProvider
  createdAt: string
  modifiedAt: string
}

const FEATURE_FLAGS_API_BASE = 'http://localhost:3100/api/flags'

function parseFlagsResponse(payload: unknown): FeatureFlag[] {
  if (Array.isArray(payload)) {
    return payload as FeatureFlag[]
  }

  if (payload && typeof payload === 'object') {
    const candidate = payload as { flags?: unknown }
    if (Array.isArray(candidate.flags)) {
      return candidate.flags as FeatureFlag[]
    }
  }

  return []
}

function formatDateLabel(value: string): string {
  if (!value) {
    return 'Unknown'
  }

  const parsed = Date.parse(value)
  return Number.isNaN(parsed) ? value : new Date(parsed).toLocaleString()
}

function providerLabel(provider: FeatureFlagProvider): string {
  switch (provider) {
    case 'launchdarkly':
      return 'LaunchDarkly'
    case 'unleash':
      return 'Unleash'
    default:
      return 'Local'
  }
}

function providerTone(provider: FeatureFlagProvider): string {
  switch (provider) {
    case 'launchdarkly':
      return 'border-cyan-200 bg-cyan-50 text-cyan-900'
    case 'unleash':
      return 'border-violet-200 bg-violet-50 text-violet-900'
    default:
      return 'border-slate-200 bg-slate-100 text-slate-700'
  }
}

function sortFlags(flags: FeatureFlag[]): FeatureFlag[] {
  return [...flags].sort((left, right) => {
    if (left.provider !== right.provider) {
      return left.provider.localeCompare(right.provider)
    }

    return left.name.localeCompare(right.name)
  })
}

async function readFeatureFlags(): Promise<FeatureFlag[]> {
  const response = await fetch(FEATURE_FLAGS_API_BASE)

  if (!response.ok) {
    throw new Error(`Failed to load flags (${response.status})`)
  }

  return parseFlagsResponse(await response.json())
}

async function toggleFeatureFlag(flagKey: string, enabled: boolean): Promise<void> {
  const response = await fetch(`${FEATURE_FLAGS_API_BASE}/${encodeURIComponent(flagKey)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ enabled }),
  })

  if (!response.ok) {
    throw new Error(`Failed to toggle ${flagKey}`)
  }
}

async function createFeatureFlag(flagKey: string, description: string): Promise<void> {
  const response = await fetch(FEATURE_FLAGS_API_BASE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key: flagKey, name: flagKey, description }),
  })

  if (!response.ok) {
    throw new Error(`Failed to create ${flagKey}`)
  }
}

async function deleteFeatureFlag(flagKey: string): Promise<void> {
  const response = await fetch(`${FEATURE_FLAGS_API_BASE}/${encodeURIComponent(flagKey)}`, {
    method: 'DELETE',
  })

  if (!response.ok) {
    throw new Error(`Failed to delete ${flagKey}`)
  }
}

async function exportFeatureFlags(): Promise<Record<string, boolean>> {
  const response = await fetch(`${FEATURE_FLAGS_API_BASE}/export`)

  if (!response.ok) {
    throw new Error(`Failed to export flags (${response.status})`)
  }

  const payload = await response.json()
  if (payload && typeof payload === 'object' && 'flags' in payload) {
    return (payload as { flags: Record<string, boolean> }).flags
  }

  return payload as Record<string, boolean>
}

export function FeatureFlagsPage(): React.ReactElement {
  useExtensionMountProfiler({
    id: 'feature-flags',
    label: 'Feature flags page',
    category: 'release',
  })

  const [flags, setFlags] = useState<FeatureFlag[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [searchTerm, setSearchTerm] = useState('')
  const [providerFilter, setProviderFilter] = useState<'all' | FeatureFlagProvider>('all')
  const [newFlagName, setNewFlagName] = useState('')
  const [newFlagDescription, setNewFlagDescription] = useState('')

  const loadFlags = useCallback(async () => {
    return measureAsyncExtensionProfiler(
      {
        id: 'feature-flags',
        label: 'Feature flags page',
        category: 'release',
        kind: 'load',
      },
      async () => {
        try {
          setLoading(true)
          setError(null)
          const nextFlags = await readFeatureFlags()
          setFlags(sortFlags(nextFlags))
          setNotice(`Loaded ${nextFlags.length} feature flags`)
        } catch (loadError) {
          setError(loadError instanceof Error ? loadError.message : 'Failed to load feature flags')
        } finally {
          setLoading(false)
        }
      }
    )
  }, [])

  useEffect(() => {
    void loadFlags()

    const refreshHandle = window.setInterval(() => {
      void loadFlags()
    }, 30000)

    return () => window.clearInterval(refreshHandle)
  }, [loadFlags])

  const filteredFlags = useMemo(() => {
    const normalizedSearch = searchTerm.trim().toLowerCase()

    return flags.filter((flag) => {
      const matchesSearch =
        normalizedSearch.length === 0 ||
        flag.key.toLowerCase().includes(normalizedSearch) ||
        flag.name.toLowerCase().includes(normalizedSearch) ||
        flag.description.toLowerCase().includes(normalizedSearch)

      const matchesProvider = providerFilter === 'all' || flag.provider === providerFilter

      return matchesSearch && matchesProvider
    })
  }, [flags, providerFilter, searchTerm])

  const summary = useMemo(() => {
    const enabledCount = flags.filter((flag) => flag.enabled).length
    const providerCounts = flags.reduce<Record<FeatureFlagProvider, number>>(
      (accumulator, flag) => ({
        ...accumulator,
        [flag.provider]: accumulator[flag.provider] + 1,
      }),
      { launchdarkly: 0, unleash: 0, local: 0 }
    )

    return {
      enabledCount,
      disabledCount: flags.length - enabledCount,
      providerCounts,
    }
  }, [flags])

  const handleToggleFlag = async (flag: FeatureFlag) => {
    try {
      setError(null)
      await toggleFeatureFlag(flag.key, !flag.enabled)
      await loadFlags()
    } catch (toggleError) {
      setError(toggleError instanceof Error ? toggleError.message : 'Failed to toggle flag')
    }
  }

  const handleCreateFlag = async () => {
    const nextFlagName = newFlagName.trim()

    if (!nextFlagName) {
      setError('Flag name cannot be empty')
      return
    }

    try {
      setError(null)
      await createFeatureFlag(nextFlagName, newFlagDescription.trim())
      setNewFlagName('')
      setNewFlagDescription('')
      setNotice(`Created flag ${nextFlagName}`)
      await loadFlags()
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : 'Failed to create flag')
    }
  }

  const handleDeleteFlag = async (flagKey: string) => {
    const confirmed = window.confirm(`Delete feature flag "${flagKey}"?`)
    if (!confirmed) {
      return
    }

    try {
      setError(null)
      await deleteFeatureFlag(flagKey)
      setNotice(`Deleted flag ${flagKey}`)
      await loadFlags()
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : 'Failed to delete flag')
    }
  }

  const handleExportFlags = async () => {
    try {
      setError(null)
      const exportedFlags = await exportFeatureFlags()
      const json = JSON.stringify(exportedFlags, null, 2)

      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(json)
        setNotice('Feature flag export copied to clipboard')
        return
      }

      const blob = new Blob([json], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = 'feature-flags.json'
      anchor.click()
      URL.revokeObjectURL(url)
      setNotice('Feature flag export downloaded')
    } catch (exportError) {
      setError(exportError instanceof Error ? exportError.message : 'Failed to export feature flags')
    }
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm shadow-slate-100">
        <div className="relative bg-slate-950 px-6 py-6 text-white sm:px-8">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,_rgba(16,185,129,0.22),_transparent_40%),radial-gradient(circle_at_bottom_left,_rgba(99,102,241,0.14),_transparent_42%)]" />
          <div className="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.28em] text-emerald-300">Feature flags</p>
              <h2 className="mt-2 text-3xl font-bold tracking-tight">Release controls with local, LaunchDarkly, and Unleash visibility</h2>
              <p className="mt-2 max-w-3xl text-sm text-slate-300">
                Review rollout state, create local flags, and keep the flag catalog visible directly inside the IDE shell.
              </p>
            </div>

            <div className="flex flex-wrap gap-3">
              <button
                type="button"
                onClick={() => void loadFlags()}
                disabled={loading}
                className="rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/20 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {loading ? 'Refreshing' : 'Refresh'}
              </button>
              <button
                type="button"
                onClick={() => void handleExportFlags()}
                className="rounded-full bg-emerald-400 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300"
              >
                Export JSON
              </button>
            </div>
          </div>
        </div>

        <div className="px-6 py-6 sm:px-8">
          <div className="grid gap-3 md:grid-cols-4">
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Total flags</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{flags.length}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Enabled</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.enabledCount}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Disabled</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{summary.disabledCount}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Providers</p>
              <p className="mt-2 text-sm font-semibold text-slate-900">
                L:{summary.providerCounts.launchdarkly} | U:{summary.providerCounts.unleash} | Local:{summary.providerCounts.local}
              </p>
            </div>
          </div>

          {error ? <div className="mt-6 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">{error}</div> : null}
          {notice ? <div className="mt-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-900">{notice}</div> : null}

          <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px]">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Catalog</p>
                  <h3 className="mt-1 text-xl font-bold text-slate-900">Current feature flags</h3>
                </div>

                <div className="flex flex-wrap gap-3">
                  <input
                    type="text"
                    value={searchTerm}
                    onChange={(event) => setSearchTerm(event.target.value)}
                    placeholder="Search flags"
                    className="min-w-[220px] rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 focus:border-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-100"
                  />

                  <select
                    value={providerFilter}
                    onChange={(event) => setProviderFilter(event.target.value as 'all' | FeatureFlagProvider)}
                    className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-900 focus:border-emerald-400 focus:outline-none focus:ring-2 focus:ring-emerald-100"
                  >
                    <option value="all">All providers</option>
                    <option value="local">Local</option>
                    <option value="launchdarkly">LaunchDarkly</option>
                    <option value="unleash">Unleash</option>
                  </select>
                </div>
              </div>

              <div className="mt-4 space-y-3">
                {filteredFlags.length === 0 ? (
                  <div className="rounded-2xl border border-dashed border-slate-300 bg-slate-50 px-4 py-6 text-sm text-slate-500">
                    {loading ? 'Loading feature flags...' : 'No flags match the current search and provider filters.'}
                  </div>
                ) : (
                  filteredFlags.map((flag) => (
                    <article key={flag.key} className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
                      <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                        <div className="flex gap-3">
                          <input
                            type="checkbox"
                            checked={flag.enabled}
                            onChange={() => void handleToggleFlag(flag)}
                            aria-label={`Toggle ${flag.name}`}
                            className="mt-1 h-4 w-4 rounded border-slate-300 text-emerald-600 focus:ring-emerald-200"
                          />

                          <div>
                            <div className="flex flex-wrap items-center gap-2">
                              <h4 className="text-lg font-semibold text-slate-900">{flag.name}</h4>
                              <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.16em] ${providerTone(flag.provider)}`}>
                                {providerLabel(flag.provider)}
                              </span>
                              <span className={`rounded-full border px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.16em] ${flag.enabled ? 'border-emerald-200 bg-emerald-100 text-emerald-900' : 'border-slate-300 bg-white text-slate-600'}`}>
                                {flag.enabled ? 'Enabled' : 'Disabled'}
                              </span>
                            </div>

                            <p className="mt-2 text-sm text-slate-600">{flag.description || 'No description provided.'}</p>
                            <p className="mt-2 text-xs uppercase tracking-[0.18em] text-slate-500">
                              {flag.key} | created {formatDateLabel(flag.createdAt)} | modified {formatDateLabel(flag.modifiedAt)}
                            </p>
                          </div>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          <button
                            type="button"
                            onClick={() => void handleToggleFlag(flag)}
                            className="rounded-full border border-slate-300 bg-white px-3 py-2 text-xs font-semibold uppercase tracking-[0.16em] text-slate-700 transition hover:border-emerald-400 hover:text-emerald-700"
                          >
                            {flag.enabled ? 'Disable' : 'Enable'}
                          </button>
                          <button
                            type="button"
                            onClick={() => void handleDeleteFlag(flag.key)}
                            className="rounded-full border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-semibold uppercase tracking-[0.16em] text-rose-700 transition hover:border-rose-300 hover:bg-rose-100"
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    </article>
                  ))
                )}
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded-2xl border border-slate-200 bg-slate-950 p-5 text-white shadow-sm">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-emerald-300">Create flag</p>
                <div className="mt-4 space-y-3">
                  <div>
                    <label className="mb-1 block text-sm font-medium text-slate-200">Flag key</label>
                    <input
                      type="text"
                      value={newFlagName}
                      onChange={(event) => setNewFlagName(event.target.value)}
                      placeholder="new_checkout"
                      className="w-full rounded-xl border border-white/15 bg-white/10 px-3 py-2 text-sm text-white placeholder:text-slate-400 focus:border-emerald-300 focus:outline-none focus:ring-2 focus:ring-emerald-200/20"
                    />
                  </div>

                  <div>
                    <label className="mb-1 block text-sm font-medium text-slate-200">Description</label>
                    <textarea
                      value={newFlagDescription}
                      onChange={(event) => setNewFlagDescription(event.target.value)}
                      placeholder="Optional rollout context"
                      rows={4}
                      className="w-full rounded-xl border border-white/15 bg-white/10 px-3 py-2 text-sm text-white placeholder:text-slate-400 focus:border-emerald-300 focus:outline-none focus:ring-2 focus:ring-emerald-200/20"
                    />
                  </div>

                  <button
                    type="button"
                    onClick={() => void handleCreateFlag()}
                    className="w-full rounded-full bg-emerald-400 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300"
                  >
                    Create local flag
                  </button>
                </div>
              </div>

              <div className="rounded-2xl border border-dashed border-emerald-200 bg-emerald-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-emerald-700">Service note</p>
                <p className="mt-2 text-sm text-slate-700">
                  This page talks to <span className="font-semibold">http://localhost:3100/api/flags</span> using the same contract as the feature-flag management panel.
                </p>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Quick facts</p>
                <ul className="mt-3 space-y-2 text-sm text-slate-700">
                  <li>Local flags are enabled by default at creation.</li>
                  <li>LaunchDarkly and Unleash flags are read-only here.</li>
                  <li>Use search and provider filters to isolate rollout state.</li>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}