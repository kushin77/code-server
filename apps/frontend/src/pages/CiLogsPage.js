// @file        apps/frontend/src/pages/CiLogsPage.tsx
// @module      pages/ci-logs
// @description In-app CI logs panel for the active repository
import { Link, useLocation } from 'react-router-dom';
export function CiLogsPage() {
    const location = useLocation();
    const searchParams = new URLSearchParams(location.search);
    const repoSlug = searchParams.get('repo')?.trim() || 'kushin77/code-server';
    const workspaceLabel = searchParams.get('workspace')?.trim() || 'Active workspace';
    const actionsUrl = `https://github.com/${repoSlug}/actions`;
    return (<section className="mx-auto max-w-7xl px-4 py-6">
      <div className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-100">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-700">CI logs</p>
            <h2 className="mt-2 text-2xl font-bold text-slate-900">Branch CI log panel</h2>
            <p className="mt-2 max-w-2xl text-sm text-slate-600">
              This panel stays inside the IDE shell and points you to the GitHub Actions logs for {workspaceLabel}.
            </p>
          </div>

          <Link to="/" className="inline-flex items-center rounded-full border border-slate-300 bg-slate-50 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-sky-400 hover:text-sky-700">
            Back to dashboard
          </Link>
        </div>

        <div className="mt-6 grid gap-3 md:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Repository</p>
            <p className="mt-1 text-lg font-semibold text-slate-900">{repoSlug}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Workspace</p>
            <p className="mt-1 text-lg font-semibold text-slate-900">{workspaceLabel}</p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Logs source</p>
            <p className="mt-1 text-lg font-semibold text-slate-900">GitHub Actions</p>
          </div>
        </div>

        <div className="mt-6 rounded-2xl border border-sky-200 bg-sky-50 px-4 py-4">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-sky-700">Open logs</p>
          <a href={actionsUrl} target="_blank" rel="noopener noreferrer" className="mt-2 inline-flex items-center rounded-full border border-sky-300 bg-white px-4 py-2 text-sm font-medium text-sky-700 transition hover:border-sky-400 hover:text-sky-900">
            Open GitHub Actions
          </a>
        </div>
      </div>
    </section>);
}
export default CiLogsPage;
//# sourceMappingURL=CiLogsPage.js.map