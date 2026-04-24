import { useEffect, useMemo, useState } from 'react';
import { fetchTeamRichPresence, upsertRichPresence } from '../utils/richPresence';
const STATUS_OPTIONS = ['online', 'away', 'dnd', 'offline'];
function statusLabel(status) {
    switch (status) {
        case 'online':
            return 'Online';
        case 'away':
            return 'Away';
        case 'dnd':
            return 'Do not disturb';
        case 'offline':
            return 'Offline';
    }
}
export function RichPresencePanel({ teamId, currentUserId, currentDisplayName, teamName }) {
    const [snapshot, setSnapshot] = useState([]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState(null);
    const [status, setStatus] = useState('online');
    const [currentFile, setCurrentFile] = useState('');
    const [currentFunction, setCurrentFunction] = useState('');
    const [currentTask, setCurrentTask] = useState('');
    const [customStatus, setCustomStatus] = useState('');
    const onlineCount = useMemo(() => snapshot.filter((entry) => entry.status === 'online').length, [snapshot]);
    useEffect(() => {
        let active = true;
        const loadPresence = async () => {
            setLoading(true);
            setError(null);
            try {
                const nextSnapshot = await fetchTeamRichPresence(teamId);
                if (active) {
                    setSnapshot(nextSnapshot.presence);
                }
            }
            catch (loadError) {
                if (active) {
                    setError(loadError instanceof Error ? loadError.message : 'Unable to load rich presence');
                }
            }
            finally {
                if (active) {
                    setLoading(false);
                }
            }
        };
        void loadPresence();
        return () => {
            active = false;
        };
    }, [teamId]);
    const handleRefresh = async () => {
        setError(null);
        try {
            const nextSnapshot = await fetchTeamRichPresence(teamId);
            setSnapshot(nextSnapshot.presence);
        }
        catch (loadError) {
            setError(loadError instanceof Error ? loadError.message : 'Unable to load rich presence');
        }
    };
    const handleSave = async () => {
        if (!currentUserId) {
            setError('Sign in to publish your rich presence');
            return;
        }
        setSaving(true);
        setError(null);
        try {
            const nextRecord = await upsertRichPresence(teamId, currentUserId, {
                displayName: currentDisplayName ?? undefined,
                status,
                currentFile: currentFile.trim() || null,
                currentFunction: currentFunction.trim() || null,
                currentTask: currentTask.trim() || null,
                customStatus: customStatus.trim() || null,
            });
            setSnapshot((currentSnapshot) => {
                const withoutCurrentUser = currentSnapshot.filter((entry) => entry.userId !== nextRecord.userId);
                return [nextRecord, ...withoutCurrentUser].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
            });
        }
        catch (saveError) {
            setError(saveError instanceof Error ? saveError.message : 'Unable to save rich presence');
        }
        finally {
            setSaving(false);
        }
    };
    return (<section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm shadow-slate-100">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-700">Rich presence</p>
          <h2 className="mt-2 text-2xl font-bold text-slate-900">Team presence snapshot</h2>
          <p className="mt-2 max-w-2xl text-sm text-slate-600">
            Track who is online, what file they are in, and which task they are working on for {teamName}.
          </p>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="rounded-2xl bg-emerald-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">Online</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{onlineCount}</p>
          </div>
          <div className="rounded-2xl bg-slate-50 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Tracked</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{snapshot.length}</p>
          </div>
        </div>
      </div>

      <div className="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px]">
        <div className="space-y-3">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4">
            <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Current presence</p>
                <p className="mt-1 text-sm text-slate-700">
                  {loading ? 'Loading the latest presence snapshot...' : `${snapshot.length} people in ${teamName}`}
                </p>
              </div>

              <button type="button" onClick={handleRefresh} className="rounded-full border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 transition hover:border-sky-400 hover:text-sky-700">
                Refresh
              </button>
            </div>

            <div className="mt-4 space-y-3">
              {snapshot.length > 0 ? (snapshot.map((entry) => (<div key={`${entry.teamId}:${entry.userId}`} className="rounded-2xl border border-slate-200 bg-white px-4 py-3">
                    <div className="flex flex-col gap-2 md:flex-row md:items-start md:justify-between">
                      <div>
                        <p className="text-sm font-semibold text-slate-900">{entry.displayName}</p>
                        <p className="text-xs text-slate-500">Updated {new Date(entry.updatedAt).toLocaleString()}</p>
                      </div>
                      <span className="inline-flex w-fit rounded-full bg-slate-100 px-2 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-600">
                        {statusLabel(entry.status)}
                      </span>
                    </div>

                    <div className="mt-3 grid gap-2 text-sm text-slate-700 sm:grid-cols-2">
                      <div><span className="font-medium text-slate-900">File:</span> {entry.currentFile || 'Idle'}</div>
                      <div><span className="font-medium text-slate-900">Function:</span> {entry.currentFunction || 'N/A'}</div>
                      <div><span className="font-medium text-slate-900">Task:</span> {entry.currentTask || 'N/A'}</div>
                      <div><span className="font-medium text-slate-900">Status:</span> {entry.customStatus || 'No custom status'}</div>
                    </div>
                  </div>))) : (<div className="rounded-2xl border border-dashed border-slate-300 bg-white px-4 py-8 text-center text-sm text-slate-600">
                  No rich presence has been published yet.
                </div>)}
            </div>
          </div>

          {error ? <p className="text-sm font-medium text-rose-700">{error}</p> : null}
        </div>

        <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
          <p className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Publish your presence</p>
          <p className="mt-1 text-sm text-slate-600">
            {currentUserId ? `Posting as ${currentDisplayName ?? currentUserId}` : 'Sign in to publish your status.'}
          </p>

          <div className="mt-4 space-y-3">
            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Status</span>
              <select value={status} onChange={(event) => setStatus(event.target.value)} className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900">
                {STATUS_OPTIONS.map((option) => (<option key={option} value={option}>{statusLabel(option)}</option>))}
              </select>
            </label>

            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Current file</span>
              <input value={currentFile} onChange={(event) => setCurrentFile(event.target.value)} placeholder="src/components/RichPresencePanel.tsx" className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900"/>
            </label>

            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Current function</span>
              <input value={currentFunction} onChange={(event) => setCurrentFunction(event.target.value)} placeholder="renderPresenceList" className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900"/>
            </label>

            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Current task</span>
              <input value={currentTask} onChange={(event) => setCurrentTask(event.target.value)} placeholder="Polish presence panel" className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900"/>
            </label>

            <label className="block">
              <span className="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">Custom status</span>
              <input value={customStatus} onChange={(event) => setCustomStatus(event.target.value)} placeholder="Reviewing collaboration issues" className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900"/>
            </label>

            <button type="button" onClick={handleSave} disabled={saving || !currentUserId} className="w-full rounded-full bg-sky-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-sky-700 disabled:cursor-not-allowed disabled:opacity-60">
              {saving ? 'Saving...' : 'Publish status'}
            </button>
          </div>
        </div>
      </div>
    </section>);
}
//# sourceMappingURL=RichPresencePanel.js.map