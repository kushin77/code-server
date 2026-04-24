import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuthStore } from '@/store';
import { ALL_WORKSPACES, DEFAULT_RECENT_WORKSPACES, buildRecentWorkspaceIds, getSuggestedWorkspaceId, getWorkspaceById, notifyWorkspaceTabsChanged, readStoredWorkspaceTabs, writeStoredWorkspaceTabs, } from '@/utils/workspaceCatalog';
const STORAGE_KEY = 'workspace-onboarding:v1';
const STEPS = [
    {
        key: 'welcome',
        label: 'Welcome',
        title: 'Confirm the account and the starter lane.',
        description: 'New members should verify their identity, role, and the workspace the team expects them to start from.',
    },
    {
        key: 'workspace',
        label: 'Workspace',
        title: 'Choose the repo that matches the first day of work.',
        description: 'Picking a starter workspace updates the active repo tabs and keeps the onboarding path consistent.',
    },
    {
        key: 'checklist',
        label: 'Checklist',
        title: 'Review the first-hour checklist.',
        description: 'Use this as the handoff gate before the workspace is considered ready.',
    },
    {
        key: 'launch',
        label: 'Finish',
        title: 'Mark onboarding complete and move into the dashboard.',
        description: 'The selected workspace and checklist state are persisted locally for the current browser profile.',
    },
];
const CHECKLIST_ITEMS = [
    {
        key: 'mfa',
        label: 'Confirm MFA is enabled',
        description: 'Verify the account is protected before the first workspace session is opened.',
    },
    {
        key: 'workspace',
        label: 'Select the starter workspace',
        description: 'Pick the repo that matches the first task or team lane.',
    },
    {
        key: 'handoff',
        label: 'Read the handoff notes',
        description: 'Review the runbook and onboarding documentation before making changes.',
    },
    {
        key: 'sessions',
        label: 'Open the sessions view',
        description: 'Know where to launch or inspect ephemeral sessions when needed.',
    },
];
function formatRole(roleId) {
    return roleId
        .split(/[-_]/)
        .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
        .join(' ');
}
function createDefaultOnboardingState(suggestedWorkspaceId, mfaEnabled) {
    return {
        stepIndex: 0,
        selectedWorkspaceId: suggestedWorkspaceId,
        completed: false,
        completedAt: null,
        checklist: {
            mfa: mfaEnabled,
            workspace: false,
            handoff: false,
            sessions: false,
        },
    };
}
function readOnboardingState(suggestedWorkspaceId, mfaEnabled) {
    if (typeof window === 'undefined') {
        return createDefaultOnboardingState(suggestedWorkspaceId, mfaEnabled);
    }
    try {
        const rawState = window.localStorage.getItem(STORAGE_KEY);
        if (!rawState) {
            return createDefaultOnboardingState(suggestedWorkspaceId, mfaEnabled);
        }
        const parsedState = JSON.parse(rawState);
        const selectedWorkspaceId = getWorkspaceById(parsedState.selectedWorkspaceId ?? '')
            ? parsedState.selectedWorkspaceId
            : suggestedWorkspaceId;
        const checklist = (parsedState.checklist ?? {});
        return {
            stepIndex: Number.isInteger(parsedState.stepIndex) ? Math.min(Math.max(parsedState.stepIndex ?? 0, 0), STEPS.length - 1) : 0,
            selectedWorkspaceId,
            completed: parsedState.completed === true,
            completedAt: typeof parsedState.completedAt === 'number' ? parsedState.completedAt : null,
            checklist: {
                mfa: checklist.mfa ?? mfaEnabled,
                workspace: checklist.workspace === true,
                handoff: checklist.handoff === true,
                sessions: checklist.sessions === true,
            },
        };
    }
    catch {
        return createDefaultOnboardingState(suggestedWorkspaceId, mfaEnabled);
    }
}
function writeOnboardingState(state) {
    if (typeof window === 'undefined') {
        return;
    }
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}
export function WorkspaceOnboardingWizard() {
    const { user } = useAuthStore();
    const roleIds = useMemo(() => user?.roles.map((role) => role.roleId) ?? [], [user?.roles]);
    const suggestedWorkspaceId = useMemo(() => getSuggestedWorkspaceId(roleIds), [roleIds]);
    const [state, setState] = useState(() => readOnboardingState(suggestedWorkspaceId, user?.mfaEnabled ?? false));
    useEffect(() => {
        setState((current) => {
            if (getWorkspaceById(current.selectedWorkspaceId)) {
                return current;
            }
            return {
                ...current,
                selectedWorkspaceId: suggestedWorkspaceId,
            };
        });
    }, [suggestedWorkspaceId]);
    useEffect(() => {
        writeOnboardingState(state);
    }, [state]);
    const selectedWorkspace = useMemo(() => {
        return getWorkspaceById(state.selectedWorkspaceId) ?? ALL_WORKSPACES[0];
    }, [state.selectedWorkspaceId]);
    const checklistCompletedCount = Object.values(state.checklist).filter(Boolean).length;
    const checklistProgress = Math.round((checklistCompletedCount / CHECKLIST_ITEMS.length) * 100);
    const currentStep = STEPS[state.stepIndex] ?? STEPS[0];
    const currentTabs = readStoredWorkspaceTabs(typeof window === 'undefined' ? undefined : window.localStorage);
    const handleWorkspaceSelect = (workspaceId) => {
        const workspace = getWorkspaceById(workspaceId);
        if (!workspace) {
            return;
        }
        setState((current) => ({
            ...current,
            selectedWorkspaceId: workspaceId,
            checklist: {
                ...current.checklist,
                workspace: true,
            },
            completed: false,
            completedAt: null,
        }));
        const maxRecentCount = currentTabs.recentRepoIds.length || DEFAULT_RECENT_WORKSPACES.length;
        writeStoredWorkspaceTabs(typeof window === 'undefined' ? undefined : window.localStorage, {
            activeRepoId: workspaceId,
            recentRepoIds: buildRecentWorkspaceIds(workspaceId, currentTabs.recentRepoIds, maxRecentCount),
        });
        notifyWorkspaceTabsChanged();
    };
    const toggleChecklist = (key) => {
        setState((current) => ({
            ...current,
            checklist: {
                ...current.checklist,
                [key]: !current.checklist[key],
            },
        }));
    };
    const handleNext = () => {
        setState((current) => ({
            ...current,
            stepIndex: Math.min(current.stepIndex + 1, STEPS.length - 1),
        }));
    };
    const handleBack = () => {
        setState((current) => ({
            ...current,
            stepIndex: Math.max(current.stepIndex - 1, 0),
        }));
    };
    const handleFinish = () => {
        if (checklistCompletedCount < CHECKLIST_ITEMS.length) {
            return;
        }
        setState((current) => ({
            ...current,
            completed: true,
            completedAt: Date.now(),
            stepIndex: STEPS.length - 1,
            checklist: {
                ...current.checklist,
                workspace: true,
            },
        }));
        const nextRecentRepoIds = buildRecentWorkspaceIds(selectedWorkspace.id, currentTabs.recentRepoIds, currentTabs.recentRepoIds.length || DEFAULT_RECENT_WORKSPACES.length);
        writeStoredWorkspaceTabs(typeof window === 'undefined' ? undefined : window.localStorage, {
            activeRepoId: selectedWorkspace.id,
            recentRepoIds: nextRecentRepoIds,
        });
        notifyWorkspaceTabsChanged();
    };
    const handleRestart = () => {
        setState(createDefaultOnboardingState(suggestedWorkspaceId, user?.mfaEnabled ?? false));
    };
    return (<section className="mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
      <header className="overflow-hidden rounded-[2rem] border border-slate-200 bg-gradient-to-br from-slate-950 via-slate-900 to-emerald-900 px-6 py-8 text-white shadow-xl shadow-slate-200/60 sm:px-8">
        <div className="max-w-3xl space-y-4">
          <p className="text-xs font-semibold uppercase tracking-[0.32em] text-emerald-200">Workspace onboarding</p>
          <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">Bring a new teammate from login to a ready workspace.</h2>
          <p className="text-sm leading-6 text-slate-200 sm:text-base">
            Pick a starter repo, review the first-hour checklist, and keep the active workspace aligned with the team lane.
          </p>
        </div>

        <div className="mt-6 grid gap-3 rounded-3xl border border-white/10 bg-white/5 p-4 text-sm text-slate-100 sm:grid-cols-3">
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-300">Member</p>
            <p className="mt-1 font-medium">{user?.fullName || user?.email || 'New team member'}</p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-300">Suggested lane</p>
            <p className="mt-1 font-medium">{selectedWorkspace.label}</p>
          </div>
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-slate-300">Progress</p>
            <p className="mt-1 font-medium">
              Step {currentStep ? state.stepIndex + 1 : 1}/{STEPS.length} · {checklistProgress}% complete
            </p>
          </div>
        </div>
      </header>

      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(320px,0.9fr)]">
        <article className="rounded-[2rem] border border-slate-200 bg-white p-6 shadow-sm shadow-slate-200/70">
          <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.28em] text-emerald-700">Step {state.stepIndex + 1}</p>
              <h3 className="mt-2 text-2xl font-semibold text-slate-900">{currentStep.title}</h3>
              <p className="mt-2 max-w-2xl text-sm text-slate-600">{currentStep.description}</p>
            </div>
            <div className="rounded-full bg-slate-100 px-4 py-2 text-sm font-medium text-slate-700">
              {checklistCompletedCount}/{CHECKLIST_ITEMS.length} checklist items complete
            </div>
          </div>

          <div className="mt-6 flex flex-wrap gap-2">
            {STEPS.map((step, index) => (<button key={step.key} type="button" onClick={() => setState((current) => ({ ...current, stepIndex: index }))} className={`rounded-full px-4 py-2 text-sm font-medium transition ${index === state.stepIndex
                ? 'bg-slate-900 text-white'
                : 'border border-slate-300 text-slate-600 hover:border-emerald-300 hover:text-emerald-700'}`}>
                {step.label}
              </button>))}
          </div>

          {!state.completed ? (<div className="mt-6 space-y-6">
              {state.stepIndex === 0 ? (<section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
                  <div className="rounded-3xl border border-slate-200 bg-slate-50 p-5">
                    <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Identity check</p>
                    <div className="mt-3 space-y-2 text-sm text-slate-700">
                      <p>
                        Name: <span className="font-semibold text-slate-900">{user?.fullName || 'Unassigned member'}</span>
                      </p>
                      <p>
                        Email: <span className="font-semibold text-slate-900">{user?.email || 'no-email@example.com'}</span>
                      </p>
                      <p>
                        MFA: <span className="font-semibold text-slate-900">{user?.mfaEnabled ? 'enabled' : 'needs confirmation'}</span>
                      </p>
                    </div>
                    <div className="mt-4 flex flex-wrap gap-2">
                      {roleIds.length > 0 ? (roleIds.map((roleId) => (<span key={roleId} className="rounded-full bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-600">
                            {formatRole(roleId)}
                          </span>))) : (<span className="rounded-full bg-white px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-600">
                          No role assigned
                        </span>)}
                    </div>
                  </div>

                  <aside className="rounded-3xl border border-emerald-200 bg-emerald-50 p-5">
                    <p className="text-xs font-semibold uppercase tracking-[0.24em] text-emerald-700">Recommended lane</p>
                    <p className="mt-2 text-lg font-semibold text-slate-900">{selectedWorkspace.label}</p>
                    <p className="mt-1 text-sm text-slate-600">Branch: {selectedWorkspace.branch}</p>
                    <p className="mt-4 text-sm text-slate-700">
                      The wizard will keep the current workspace tabs aligned with this selection.
                    </p>
                    <button type="button" onClick={() => handleWorkspaceSelect(suggestedWorkspaceId)} className="mt-4 rounded-full bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-700">
                      Use recommended workspace
                    </button>
                  </aside>
                </section>) : null}

              {state.stepIndex === 1 ? (<section>
                  <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                    {ALL_WORKSPACES.map((workspace) => {
                    const isSelected = workspace.id === selectedWorkspace.id;
                    return (<button key={workspace.id} type="button" onClick={() => handleWorkspaceSelect(workspace.id)} className={`rounded-3xl border p-5 text-left transition ${isSelected
                            ? 'border-emerald-400 bg-emerald-50 shadow-sm'
                            : 'border-slate-200 bg-slate-50 hover:border-slate-300 hover:bg-white'}`}>
                          <div className="flex items-start justify-between gap-4">
                            <div>
                              <p className="text-base font-semibold text-slate-900">{workspace.label}</p>
                              <p className="mt-1 text-sm text-slate-500">{workspace.branch}</p>
                            </div>
                            <span className={`rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] ${workspace.pinned ? 'bg-white text-emerald-700' : 'bg-white text-slate-500'}`}>
                              {workspace.pinned ? 'Pinned' : 'Recent'}
                            </span>
                          </div>
                          <p className="mt-4 text-sm text-slate-600">
                            {workspace.id === suggestedWorkspaceId
                            ? 'Recommended for this role and onboarding path.'
                            : 'Available as an alternate workspace for the first session.'}
                          </p>
                          <div className="mt-4 flex items-center justify-between text-sm font-medium text-slate-700">
                            <span>{isSelected ? 'Selected' : 'Select workspace'}</span>
                            <span className="rounded-full bg-white px-3 py-1 text-xs uppercase tracking-[0.18em] text-slate-500">
                              {workspace.id}
                            </span>
                          </div>
                        </button>);
                })}
                  </div>
                </section>) : null}

              {state.stepIndex === 2 ? (<section className="space-y-4">
                  {CHECKLIST_ITEMS.map((item) => (<label key={item.key} className={`flex cursor-pointer gap-4 rounded-3xl border p-4 transition ${state.checklist[item.key] ? 'border-emerald-300 bg-emerald-50' : 'border-slate-200 bg-slate-50 hover:border-slate-300'}`}>
                      <input checked={state.checklist[item.key]} className="mt-1 h-5 w-5 rounded border-slate-300 text-emerald-600 focus:ring-emerald-200" type="checkbox" onChange={() => toggleChecklist(item.key)}/>
                      <span>
                        <span className="block text-sm font-semibold text-slate-900">{item.label}</span>
                        <span className="mt-1 block text-sm text-slate-600">{item.description}</span>
                      </span>
                    </label>))}
                </section>) : null}

              {state.stepIndex === 3 ? (<section className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_300px]">
                  <div className="rounded-3xl border border-slate-200 bg-slate-50 p-5">
                    <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Ready to launch</p>
                    <h4 className="mt-2 text-xl font-semibold text-slate-900">Review the handoff once before you finish.</h4>
                    <div className="mt-4 space-y-3 text-sm text-slate-700">
                      <p>
                        Selected workspace: <span className="font-semibold text-slate-900">{selectedWorkspace.label}</span>
                      </p>
                      <p>
                        Branch: <span className="font-semibold text-slate-900">{selectedWorkspace.branch}</span>
                      </p>
                      <p>
                        Role set: <span className="font-semibold text-slate-900">{roleIds.length > 0 ? roleIds.map(formatRole).join(', ') : 'Default starter lane'}</span>
                      </p>
                      <p>
                        Checklist complete: <span className="font-semibold text-slate-900">{checklistCompletedCount === CHECKLIST_ITEMS.length ? 'yes' : 'not yet'}</span>
                      </p>
                    </div>
                  </div>

                  <aside className="rounded-3xl border border-emerald-200 bg-emerald-50 p-5">
                    <p className="text-xs font-semibold uppercase tracking-[0.24em] text-emerald-700">Outcome</p>
                    <p className="mt-2 text-sm text-slate-700">
                      Finishing onboarding persists the current workspace, marks the checklist complete, and keeps the dashboard in sync.
                    </p>
                    <div className="mt-4 rounded-2xl bg-white px-4 py-3 text-sm text-slate-700">
                      <p className="font-semibold text-slate-900">Current progress</p>
                      <p className="mt-1">{checklistProgress}% of the checklist is complete.</p>
                    </div>
                  </aside>
                </section>) : null}
            </div>) : (<section className="mt-6 rounded-[1.75rem] border border-emerald-200 bg-emerald-50 p-6">
              <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.24em] text-emerald-700">Onboarding complete</p>
                  <h4 className="mt-2 text-2xl font-semibold text-slate-900">{selectedWorkspace.label} is ready for the first session.</h4>
                  <p className="mt-2 max-w-2xl text-sm text-slate-700">
                    The active workspace and checklist state have been persisted for this browser profile. The dashboard will now track the selected starter lane.
                  </p>
                </div>
                <div className="flex flex-wrap gap-3">
                  <Link className="rounded-full bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-700" to="/">
                    Open dashboard
                  </Link>
                  <Link className="rounded-full border border-emerald-300 bg-white px-4 py-2 text-sm font-medium text-emerald-800 transition hover:border-emerald-400" to="/sessions">
                    Review sessions
                  </Link>
                </div>
              </div>
            </section>)}

          {!state.completed ? (<div className="mt-6 flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 pt-5">
              <div className="flex flex-wrap gap-2">
                <button type="button" onClick={handleBack} disabled={state.stepIndex === 0} className="rounded-full border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-slate-400 disabled:cursor-not-allowed disabled:opacity-50">
                  Back
                </button>
                <button type="button" onClick={handleNext} disabled={state.stepIndex === STEPS.length - 1} className="rounded-full bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-50">
                  Next
                </button>
              </div>

              <div className="flex flex-wrap gap-2">
                <button type="button" onClick={handleRestart} className="rounded-full border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition hover:border-emerald-400 hover:text-emerald-700">
                  Restart
                </button>
                <button type="button" onClick={handleFinish} disabled={checklistCompletedCount < CHECKLIST_ITEMS.length} className="rounded-full bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-50">
                  Finish onboarding
                </button>
              </div>
            </div>) : null}
        </article>

        <aside className="space-y-4">
          <section className="rounded-[1.75rem] border border-slate-200 bg-white p-5 shadow-sm shadow-slate-200/60">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Workspace summary</p>
            <p className="mt-2 text-xl font-semibold text-slate-900">{selectedWorkspace.label}</p>
            <p className="mt-1 text-sm text-slate-600">Branch: {selectedWorkspace.branch}</p>
            <div className="mt-4 flex flex-wrap gap-2">
              <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-slate-600">
                {selectedWorkspace.pinned ? 'Pinned' : 'Recent'}
              </span>
              <span className="rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-emerald-700">
                Suggested: {selectedWorkspace.id === suggestedWorkspaceId ? 'yes' : 'no'}
              </span>
            </div>
            <div className="mt-4 rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-700">
              <p className="font-semibold text-slate-900">Recent workspace lanes</p>
              <p className="mt-1">
                {currentTabs.recentRepoIds.length > 0
            ? currentTabs.recentRepoIds.map((workspaceId) => getWorkspaceById(workspaceId)?.label ?? workspaceId).join(' · ')
            : 'No recent workspace lanes yet.'}
              </p>
            </div>
          </section>

          <section className="rounded-[1.75rem] border border-slate-200 bg-slate-50 p-5">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-500">Quick actions</p>
            <div className="mt-4 flex flex-col gap-3">
              <Link className="rounded-full bg-slate-900 px-4 py-2 text-center text-sm font-medium text-white transition hover:bg-slate-700" to="/">
                Go to dashboard
              </Link>
              <Link className="rounded-full border border-slate-300 px-4 py-2 text-center text-sm font-medium text-slate-700 transition hover:border-slate-400 hover:bg-white" to="/sessions">
                Launch sessions view
              </Link>
            </div>
          </section>

          <section className="rounded-[1.75rem] border border-dashed border-emerald-200 bg-emerald-50 p-5">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-emerald-700">Handoff note</p>
            <p className="mt-2 text-sm leading-6 text-slate-700">
              New teammates can return here later to reset their starter lane, confirm the checklist, or switch to a different repository context.
            </p>
          </section>
        </aside>
      </div>
    </section>);
}
//# sourceMappingURL=WorkspaceOnboardingWizard.js.map