// @file        apps/frontend/src/pages/TeamHubMetricsPage.tsx
// @module      pages/team-hub-metrics
// @description Team collaboration metrics page component

import { Link } from 'react-router-dom'

import { getDemoTeamNamesByStatus, getDemoTeamStatusCounts } from '@/utils/collaborationMetrics'

export function TeamHubMetricsPage() {
  const counts = getDemoTeamStatusCounts()
  const onlineNames = getDemoTeamNamesByStatus('online')

  return (
    <section className="mx-auto max-w-7xl px-4 py-6">
      <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-100">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-700">Collaboration</p>
            <h2 className="mt-2 text-2xl font-bold text-slate-900">Team online snapshot</h2>
            <p className="mt-2 max-w-2xl text-sm text-slate-600">
              This surface mirrors the presence strip in the app shell and shows the demo collaboration counts used by the status bar.
            </p>
          </div>

          <Link
            to="/"
            className="inline-flex items-center rounded-full border border-slate-300 bg-slate-50 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-sky-400 hover:text-sky-700"
          >
            Back to dashboard
          </Link>
        </div>

        <div className="mt-6 grid gap-3 md:grid-cols-3">
          <div className="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">Online</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{counts.online}</p>
          </div>
          <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-amber-700">Away</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{counts.away}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Offline</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{counts.offline}</p>
          </div>
        </div>

        <div className="mt-6 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Currently online</p>
          <p className="mt-2 text-sm text-slate-700">
            {onlineNames.length > 0 ? onlineNames.join(', ') : 'No users online right now'}
          </p>
        </div>
      </div>
    </section>
  )
}