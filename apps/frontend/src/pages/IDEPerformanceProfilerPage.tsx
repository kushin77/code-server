import { useMemo } from 'react'

import {
  getExtensionProfilerSnapshot,
  resetExtensionProfilerSamples,
  useExtensionMountProfiler,
  useExtensionProfilerSnapshot,
  type ExtensionProfilerSample,
} from '@/utils/extensionProfiler'

const EXTENSION_PROFILER_CATALOG = [
  { id: 'ticket-linking', label: 'Ticket linking', category: 'integration' },
  { id: 'cicd-status', label: 'CI/CD status sidebar', category: 'operations' },
  { id: 'otel-apm', label: 'OpenTelemetry APM', category: 'observability' },
  { id: 'sentry-errors', label: 'Sentry errors', category: 'observability' },
  { id: 'figma-embed', label: 'Figma embed', category: 'design' },
  { id: 'docs-editor', label: 'Docs editor', category: 'content' },
  { id: 'feature-flags', label: 'Feature flags panel', category: 'release' },
  { id: 'pagerduty-incidents', label: 'PagerDuty incidents', category: 'incident-response' },
  { id: 'ide-performance-profiler', label: 'IDE performance profiler', category: 'meta' },
] as const

type ProfilerWorkspaceState = {
  activeWorkspace: {
    id: string
    label: string
  }
}

export type IDEPerformanceProfilerPageProps = {
  workspaceState: ProfilerWorkspaceState
}

function formatDuration(durationMs: number): string {
  return `${durationMs.toFixed(durationMs < 10 ? 2 : 0)}ms`
}

function buildRecentSamples(samples: ExtensionProfilerSample[]): ExtensionProfilerSample[] {
  return [...samples].sort((left, right) => right.durationMs - left.durationMs)
}

export function IDEPerformanceProfilerPage({ workspaceState }: IDEPerformanceProfilerPageProps) {
  useExtensionMountProfiler({
    id: 'ide-performance-profiler',
    label: 'IDE performance profiler',
    category: 'meta',
  })

  const snapshot = useExtensionProfilerSnapshot()

  const catalogWithSamples = useMemo(() => {
    const sampleById = new Map(snapshot.samples.map((sample) => [sample.id, sample] as const))

    return EXTENSION_PROFILER_CATALOG.map((entry) => ({
      ...entry,
      sample: sampleById.get(entry.id),
    }))
  }, [snapshot.samples])

  const recentSamples = useMemo(() => buildRecentSamples(snapshot.samples), [snapshot.samples])
  const measuredCount = recentSamples.length
  const averageDurationMs =
    measuredCount === 0 ? 0 : recentSamples.reduce((total, sample) => total + sample.durationMs, 0) / measuredCount
  const slowestSample = recentSamples[0]
  const activeWorkspaceLabel = workspaceState.activeWorkspace.label

  const handleCopySnapshot = async () => {
    if (typeof navigator === 'undefined' || !navigator.clipboard) {
      return
    }

    await navigator.clipboard.writeText(JSON.stringify(getExtensionProfilerSnapshot(), null, 2))
  }

  const handleResetSamples = () => {
    resetExtensionProfilerSamples()
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm shadow-slate-100">
        <div className="relative bg-slate-950 px-6 py-6 text-white sm:px-8">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,_rgba(56,189,248,0.25),_transparent_40%),radial-gradient(circle_at_bottom_left,_rgba(244,114,182,0.18),_transparent_42%)]" />
          <div className="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.28em] text-sky-300">IDE profiler</p>
              <h2 className="mt-2 text-3xl font-bold tracking-tight">Per-extension overhead, captured from live mounts</h2>
              <p className="mt-2 max-w-3xl text-sm text-slate-300">
                Track how long individual IDE extensions take to activate, mount, and refresh. The current workspace is{' '}
                <span className="font-semibold text-white">{activeWorkspaceLabel}</span>.
              </p>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <button
                type="button"
                onClick={handleCopySnapshot}
                className="rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/20"
              >
                Copy snapshot
              </button>
              <button
                type="button"
                onClick={handleResetSamples}
                className="rounded-full bg-sky-400 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-sky-300"
              >
                Reset samples
              </button>
            </div>
          </div>
        </div>

        <div className="px-6 py-6 sm:px-8">
          <div className="grid gap-3 md:grid-cols-4">
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Measured samples</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{measuredCount}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Average duration</p>
              <p className="mt-2 text-3xl font-bold text-slate-900">{formatDuration(averageDurationMs)}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Slowest sample</p>
              <p className="mt-2 text-lg font-semibold text-slate-900">{slowestSample?.label ?? 'No samples yet'}</p>
              <p className="text-sm text-slate-600">{slowestSample ? formatDuration(slowestSample.durationMs) : 'Activate a panel to capture timings'}</p>
            </div>
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
              <p className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-500">Workspace</p>
              <p className="mt-2 text-lg font-semibold text-slate-900">{workspaceState.activeWorkspace.label}</p>
              <p className="text-sm text-slate-600">Profiler data is stored locally in the browser.</p>
            </div>
          </div>

          <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
            <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Extension catalog</p>
                  <h3 className="mt-1 text-xl font-bold text-slate-900">Current per-extension state</h3>
                </div>
                <p className="text-xs font-medium uppercase tracking-[0.2em] text-slate-500">{snapshot.updatedAt ? new Date(snapshot.updatedAt).toLocaleTimeString() : '—'}</p>
              </div>

              <div className="mt-4 overflow-hidden rounded-2xl border border-slate-200">
                <table className="min-w-full divide-y divide-slate-200 text-left text-sm">
                  <thead className="bg-slate-50 text-xs uppercase tracking-[0.18em] text-slate-500">
                    <tr>
                      <th className="px-4 py-3">Extension</th>
                      <th className="px-4 py-3">Category</th>
                      <th className="px-4 py-3">Kind</th>
                      <th className="px-4 py-3">Duration</th>
                      <th className="px-4 py-3">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 bg-white">
                    {catalogWithSamples.map((entry) => {
                      const sample = entry.sample

                      return (
                        <tr key={entry.id} className="align-top">
                          <td className="px-4 py-3 font-semibold text-slate-900">{entry.label}</td>
                          <td className="px-4 py-3 text-slate-600">{entry.category}</td>
                          <td className="px-4 py-3 text-slate-600">{sample?.kind ?? 'pending'}</td>
                          <td className="px-4 py-3 text-slate-900">{sample ? formatDuration(sample.durationMs) : '—'}</td>
                          <td className="px-4 py-3">
                            <span
                              className={`inline-flex rounded-full px-2 py-1 text-xs font-semibold uppercase tracking-[0.16em] ${
                                sample?.status === 'success'
                                  ? 'bg-emerald-100 text-emerald-800'
                                  : sample?.status === 'warning'
                                    ? 'bg-amber-100 text-amber-800'
                                    : 'bg-slate-100 text-slate-600'
                              }`}
                            >
                              {sample?.status ?? 'waiting'}
                            </span>
                            {sample?.note ? <p className="mt-1 text-xs text-slate-500">{sample.note}</p> : null}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded-2xl border border-slate-200 bg-slate-950 p-5 text-white shadow-sm">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-300">Slowest samples</p>
                <div className="mt-4 space-y-3">
                  {recentSamples.slice(0, 5).map((sample) => (
                    <div key={`${sample.id}-${sample.measuredAt}`} className="rounded-2xl border border-white/10 bg-white/5 px-4 py-3">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <p className="font-semibold text-white">{sample.label}</p>
                          <p className="text-xs uppercase tracking-[0.18em] text-slate-400">{sample.category} · {sample.kind}</p>
                        </div>
                        <p className="text-lg font-bold text-sky-300">{formatDuration(sample.durationMs)}</p>
                      </div>
                      {sample.note ? <p className="mt-2 text-sm text-slate-300">{sample.note}</p> : null}
                    </div>
                  ))}

                  {recentSamples.length === 0 ? (
                    <div className="rounded-2xl border border-dashed border-white/15 px-4 py-6 text-sm text-slate-300">
                      No extension timings have been captured yet. Open a panel, refresh a sidebar, or trigger an activation to populate this view.
                    </div>
                  ) : null}
                </div>
              </div>

              <div className="rounded-2xl border border-dashed border-sky-200 bg-sky-50 p-5">
                <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-700">Monitoring note</p>
                <p className="mt-2 text-sm text-slate-700">
                  Samples are written locally, so this profiler is safe to use without backend dependencies. The same hooks can later be forwarded to a shared telemetry endpoint if you want historical dashboards.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
