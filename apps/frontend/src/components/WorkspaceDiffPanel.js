import { useEffect, useState } from 'react';
import { fetchLatestWorkspaceDiff, refreshWorkspaceDiff } from '../utils/workspaceDiff';
export function WorkspaceDiffPanel({ workspaceId, repoPath, workspaceLabel }) {
    const [snapshot, setSnapshot] = useState(null);
    const [loading, setLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [error, setError] = useState(null);
    useEffect(() => {
        let isActive = true;
        const loadSnapshot = async () => {
            setLoading(true);
            setError(null);
            try {
                const nextSnapshot = await fetchLatestWorkspaceDiff(workspaceId, repoPath);
                if (isActive) {
                    setSnapshot(nextSnapshot);
                }
            }
            catch (loadError) {
                if (isActive) {
                    setError(loadError instanceof Error ? loadError.message : 'Unable to load workspace diff');
                }
            }
            finally {
                if (isActive) {
                    setLoading(false);
                }
            }
        };
        void loadSnapshot();
        return () => {
            isActive = false;
        };
    }, [repoPath, workspaceId]);
    const handleRefresh = async () => {
        setRefreshing(true);
        setError(null);
        try {
            const nextSnapshot = await refreshWorkspaceDiff(workspaceId, repoPath);
            setSnapshot(nextSnapshot);
        }
        catch (refreshError) {
            setError(refreshError instanceof Error ? refreshError.message : 'Unable to refresh workspace diff');
        }
        finally {
            setRefreshing(false);
        }
    };
    return (<section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-cyan-700">Workspace diff</p>
          <h3 className="mt-1 text-lg font-semibold text-slate-900">What changed while you were away</h3>
          <p className="mt-1 text-sm text-slate-600">A snapshot of recent changes for {workspaceLabel} at {repoPath}.</p>
        </div>

        <button type="button" onClick={handleRefresh} disabled={refreshing} className="rounded-full border border-cyan-300 px-3 py-2 text-sm font-medium text-cyan-800 transition hover:border-cyan-400 hover:bg-cyan-50 disabled:cursor-not-allowed disabled:opacity-60">
          {refreshing ? 'Refreshing…' : 'Refresh workspace diff'}
        </button>
      </div>

      <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 p-4">
        {loading ? (<p className="text-sm text-slate-600">Loading the latest snapshot…</p>) : snapshot ? (<>
            <p className="text-sm font-semibold text-slate-900">{snapshot.summary}</p>
            <p className="mt-1 text-xs text-slate-500">Captured {new Date(snapshot.generatedAt).toLocaleString()}</p>

            {snapshot.changedFiles.length > 0 ? (<ul className="mt-4 space-y-2">
                {snapshot.changedFiles.map((file) => (<li key={`${file.status}:${file.path}`} className="rounded-xl border border-slate-200 bg-white px-3 py-2">
                    <p className="text-sm font-medium text-slate-900">{file.path}</p>
                    <p className="text-xs uppercase tracking-[0.18em] text-slate-500">
                      {file.status}
                      {file.previousPath ? ` · from ${file.previousPath}` : ''}
                    </p>
                  </li>))}
              </ul>) : (<p className="mt-3 text-sm text-slate-600">No file-level changes were recorded in the latest snapshot.</p>)}
          </>) : (<p className="text-sm text-slate-600">No workspace diff snapshot has been captured yet.</p>)}

        {error ? <p className="mt-3 text-sm font-medium text-rose-700">{error}</p> : null}
      </div>
    </section>);
}
//# sourceMappingURL=WorkspaceDiffPanel.js.map