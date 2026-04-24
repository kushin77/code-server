// @file        apps/frontend/src/extensions/symbol-discussions-panel.tsx
// @module      extensions/symbol-discussions-panel
// @description React panel for inline code discussion lookups
import React, { useEffect, useState } from 'react';
import { fetchSymbolDiscussionsByLocation, } from '../utils/symbolDiscussions';
function clampLineNumber(value) {
    if (!value.trim()) {
        return undefined;
    }
    const parsed = Number.parseInt(value, 10);
    if (!Number.isFinite(parsed) || parsed < 1) {
        return undefined;
    }
    return parsed;
}
function describeLocation(filePath, lineNumber) {
    return lineNumber ? `${filePath}:${lineNumber}` : filePath;
}
function summarizeComment(discussion) {
    const comment = discussion.thread.comments[0];
    if (!comment) {
        return 'No comments have been added yet.';
    }
    const trimmed = comment.content.trim();
    return trimmed.length > 140 ? `${trimmed.slice(0, 140).trimEnd()}…` : trimmed;
}
export const SymbolDiscussionsPanel = ({ initialFilePath = '', initialLineNumber, }) => {
    const [filePath, setFilePath] = useState(initialFilePath);
    const [lineNumberText, setLineNumberText] = useState(initialLineNumber ? String(initialLineNumber) : '');
    const [result, setResult] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    useEffect(() => {
        if (!initialFilePath) {
            return;
        }
        setFilePath(initialFilePath);
        setLineNumberText(initialLineNumber ? String(initialLineNumber) : '');
        void loadDiscussions(initialFilePath, initialLineNumber);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [initialFilePath, initialLineNumber]);
    async function loadDiscussions(nextFilePath = filePath, nextLineNumber = clampLineNumber(lineNumberText)) {
        const trimmedFilePath = nextFilePath.trim();
        if (!trimmedFilePath) {
            setError('Enter a file path to load inline discussions.');
            setResult(null);
            return;
        }
        try {
            setLoading(true);
            setError(null);
            const discussionResult = await fetchSymbolDiscussionsByLocation(trimmedFilePath, nextLineNumber);
            setResult(discussionResult);
        }
        catch (loadError) {
            setResult(null);
            setError(loadError instanceof Error ? loadError.message : 'Failed to load inline discussions.');
        }
        finally {
            setLoading(false);
        }
    }
    const discussionCount = result?.count ?? 0;
    const locationLabel = result
        ? describeLocation(result.filePath, result.lineNumber)
        : describeLocation(filePath || 'No file selected', clampLineNumber(lineNumberText));
    return (<section className="mx-auto flex min-h-screen max-w-6xl flex-col gap-5 bg-[radial-gradient(circle_at_top,_rgba(15,23,42,0.94),_rgba(15,23,42,0.76)_58%,_rgba(30,41,59,0.94))] px-4 py-6 text-slate-100">
      <header className="rounded-[28px] border border-slate-700/60 bg-slate-900/80 px-6 py-5 shadow-2xl shadow-slate-950/40 backdrop-blur">
        <p className="text-xs font-semibold uppercase tracking-[0.26em] text-cyan-300">Inline threads</p>
        <div className="mt-3 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <h2 className="text-2xl font-semibold text-white">Symbol discussions by location</h2>
            <p className="mt-2 max-w-3xl text-sm text-slate-300">
              Resolve inline thread anchors by file path and line number, then inspect the live discussion cards attached to that code location.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-3">
            <div className="rounded-2xl border border-slate-700 bg-slate-800/80 px-4 py-3">
              <p className="text-[11px] uppercase tracking-[0.2em] text-slate-400">Location</p>
              <p className="mt-1 font-medium text-slate-100">{locationLabel}</p>
            </div>
            <div className="rounded-2xl border border-slate-700 bg-slate-800/80 px-4 py-3">
              <p className="text-[11px] uppercase tracking-[0.2em] text-slate-400">Threads</p>
              <p className="mt-1 font-medium text-slate-100">{discussionCount}</p>
            </div>
            <div className="rounded-2xl border border-slate-700 bg-slate-800/80 px-4 py-3 sm:col-span-1 col-span-2">
              <p className="text-[11px] uppercase tracking-[0.2em] text-slate-400">Status</p>
              <p className={`mt-1 font-medium ${loading ? 'text-amber-300' : error ? 'text-rose-300' : 'text-emerald-300'}`}>
                {loading ? 'Loading discussions' : error ? 'Needs attention' : 'Ready'}
              </p>
            </div>
          </div>
        </div>
      </header>

      <div className="rounded-[28px] border border-slate-700/60 bg-slate-900/75 p-5 shadow-xl shadow-slate-950/30 backdrop-blur">
        <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_220px_auto] md:items-end">
          <label className="block">
            <span className="mb-2 block text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">File path</span>
            <input type="text" value={filePath} onChange={(event) => setFilePath(event.target.value)} placeholder="src/features/userService.ts" className="w-full rounded-2xl border border-slate-700 bg-slate-950/70 px-4 py-3 text-sm text-slate-100 outline-none transition placeholder:text-slate-500 focus:border-cyan-400"/>
          </label>

          <label className="block">
            <span className="mb-2 block text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">Line number</span>
            <input type="number" min={1} value={lineNumberText} onChange={(event) => setLineNumberText(event.target.value)} placeholder="42" className="w-full rounded-2xl border border-slate-700 bg-slate-950/70 px-4 py-3 text-sm text-slate-100 outline-none transition placeholder:text-slate-500 focus:border-cyan-400"/>
          </label>

          <button type="button" onClick={() => void loadDiscussions()} className="rounded-2xl bg-cyan-500 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-60" disabled={loading}>
            {loading ? 'Loading…' : 'Load discussions'}
          </button>
        </div>

        {error ? (<div className="mt-4 rounded-2xl border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
            {error}
          </div>) : null}

        {!loading && !error && result && result.discussions.length === 0 ? (<div className="mt-4 rounded-2xl border border-dashed border-slate-700 bg-slate-950/50 px-4 py-8 text-center text-sm text-slate-400">
            No inline discussions are anchored to {describeLocation(result.filePath, result.lineNumber)}.
          </div>) : null}

        <div className="mt-5 grid gap-4">
          {result?.discussions.map((discussion) => {
            const commentCount = discussion.thread.comments.length;
            return (<article key={discussion.id} className="rounded-[24px] border border-slate-700 bg-slate-950/80 p-4 shadow-lg shadow-slate-950/20 transition hover:border-cyan-400/50">
                <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-[0.2em] text-cyan-300">{discussion.symbolType}</p>
                    <h3 className="mt-1 text-lg font-semibold text-white">{discussion.thread.title}</h3>
                    <p className="mt-1 text-sm text-slate-400">
                      {discussion.symbolName} · {describeLocation(discussion.filePath, discussion.lineNumber)}
                    </p>
                  </div>

                  <div className="flex flex-wrap gap-2 text-xs font-semibold uppercase tracking-[0.18em]">
                    <span className={`rounded-full px-3 py-1 ${discussion.thread.isResolved ? 'bg-emerald-500/15 text-emerald-300' : 'bg-amber-500/15 text-amber-200'}`}>
                      {discussion.thread.isResolved ? 'Resolved' : 'Open'}
                    </span>
                    <span className="rounded-full bg-slate-800 px-3 py-1 text-slate-300">
                      {commentCount} comment{commentCount === 1 ? '' : 's'}
                    </span>
                  </div>
                </div>

                <div className="mt-4 grid gap-3 md:grid-cols-[1.2fr_0.8fr]">
                  <div className="rounded-2xl border border-slate-800 bg-slate-900/80 px-4 py-3">
                    <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-400">Latest comment</p>
                    <p className="mt-2 text-sm leading-6 text-slate-200">{summarizeComment(discussion)}</p>
                  </div>

                  <div className="rounded-2xl border border-slate-800 bg-slate-900/80 px-4 py-3 text-sm text-slate-300">
                    <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-400">Thread metadata</p>
                    <dl className="mt-3 grid grid-cols-2 gap-2 text-xs">
                      <div>
                        <dt className="text-slate-500">Created by</dt>
                        <dd className="font-medium text-slate-200">{discussion.thread.createdBy}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Updated</dt>
                        <dd className="font-medium text-slate-200">{new Date(discussion.updatedAt).toLocaleString()}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">File</dt>
                        <dd className="font-medium text-slate-200">{discussion.filePath}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Line</dt>
                        <dd className="font-medium text-slate-200">{discussion.lineNumber}</dd>
                      </div>
                    </dl>
                  </div>
                </div>
              </article>);
        })}
        </div>
      </div>
    </section>);
};
export default SymbolDiscussionsPanel;
//# sourceMappingURL=symbol-discussions-panel.js.map