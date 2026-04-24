import * as vscode from 'vscode';
import type { TeamHubConfig, TeamHubSnapshot, TeamHubUser, PresenceStatus } from './types';
import { renderActivityFeedHtml, type TeamHubActivityEntry } from './activity-feed';
import {
  findBestMeetingSlot,
  formatLocalTime,
  formatMeetingSlot,
  formatWorkingHours,
  getWorkingHoursWarning
} from './collaboration-utils';

const escapeHtml = (value: string): string => value
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

const statusLabel: Record<PresenceStatus, string> = {
  online: 'Online',
  away: 'Away',
  offline: 'Offline'
};

const statusEmoji: Record<PresenceStatus, string> = {
  online: '🟢',
  away: '🟡',
  offline: '⚫'
};

const renderUserCard = (user: TeamHubUser, config: TeamHubConfig, referenceDate: Date, currentFile?: string): string => {
  const sameFile = config.highlightSameFile && Boolean(currentFile && user.currentFile === currentFile);
  const sameFileBadge = sameFile ? `<span class="badge badge-same">Same file${user.currentLine ? ` · L${user.currentLine}` : ''}</span>` : '';
  const meetingModeBadge = user.status === 'dnd' ? '<span class="badge badge-meeting">📞 Meeting mode</span>' : '';
  const localTimeLabel = formatLocalTime(referenceDate, user.timezone);
  const workingHoursLabel = formatWorkingHours(user.workingHours);
  const workingHoursWarning = getWorkingHoursWarning(user, referenceDate);
  const avatar = config.showAvatars && user.avatarUrl
    ? `<img class="avatar" src="${escapeHtml(user.avatarUrl)}" alt="${escapeHtml(user.displayName)}" />`
    : `<div class="avatar avatar-fallback">${escapeHtml(user.displayName.slice(0, 1).toUpperCase())}</div>`;
  const metaRows = [
    user.currentFile ? `File: ${escapeHtml(user.currentFile)}` : 'No file open',
    `Local time: ${escapeHtml(localTimeLabel)}`,
    `Working hours: ${escapeHtml(workingHoursLabel)}`,
    user.currentFunction ? `Function: ${escapeHtml(user.currentFunction)}` : undefined,
    user.currentTask ? `Task: ${escapeHtml(user.currentTask)}` : undefined,
    user.customStatus ? `Custom status: ${escapeHtml(user.customStatus)}` : undefined,
    user.currentLine ? `Line ${user.currentLine}` : undefined
  ].filter((row): row is string => Boolean(row));

  return `
    <article class="user-card ${sameFile ? 'same-file' : ''}">
      ${avatar}
      <div class="user-body">
        <div class="user-topline">
          <strong>${escapeHtml(user.displayName)}</strong>
          <span class="status-dot status-${user.status}">${statusEmoji[user.status]} ${statusLabel[user.status]}</span>
        </div>
        ${metaRows.map((row) => `<div class="user-meta">${row}</div>`).join('')}
        ${workingHoursWarning ? `<div class="user-meta warning">${escapeHtml(workingHoursWarning)}</div>` : ''}
        ${sameFileBadge}
        ${meetingModeBadge}
      </div>
      <div class="user-actions">
        <button data-action="mention" data-user-id="${escapeHtml(user.id)}">@Mention</button>
        <button data-action="focus-file" data-user-id="${escapeHtml(user.id)}">Go To File</button>
      </div>
    </article>`;
};

const renderStatusSection = (title: string, users: TeamHubUser[], config: TeamHubConfig, referenceDate: Date, currentFile?: string): string => {
  return `
    <section class="status-section">
      <header>
        <h3>${title} (${users.length})</h3>
      </header>
      <div class="user-list">
        ${users.length > 0 ? users.map((user) => renderUserCard(user, config, referenceDate, currentFile)).join('') : '<div class="empty-state">No collaborators</div>'}
      </div>
    </section>`;
};

export const renderTeamHubWebviewHtml = (
  snapshot: TeamHubSnapshot,
  config: TeamHubConfig,
  webview: vscode.Webview,
  activityEntries: TeamHubActivityEntry[] = [],
  privateViewEnabled: boolean = false
): string => {
  const nonce = `${Date.now().toString(16)}${Math.random().toString(16).slice(2)}`;
  const cspSource = webview.cspSource;

  const grouped = snapshot.groupedUsers;
  const sameFileUsers = snapshot.sameFileUsers;
  const referenceDate = new Date(snapshot.updatedAt);
  const allUsers = [snapshot.currentUser, ...snapshot.users.filter((user) => user.id !== snapshot.currentUser.id)];
  const meetingSuggestion = findBestMeetingSlot(allUsers, referenceDate, 30, snapshot.currentUser.timezone);

  return `<!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${cspSource} https: data:; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <style>
        body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); margin: 0; padding: 12px; background: var(--vscode-editor-background); }
        .hero { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 14px; }
        .hero h2 { margin: 0; font-size: 1.1rem; }
        .hero-actions, .quick-actions, .user-actions { display: flex; gap: 8px; flex-wrap: wrap; }
        .quick-actions { margin: 14px 0; }
        .command-panel { margin: 14px 0; display: grid; gap: 10px; }
        .command-row { display: flex; gap: 8px; flex-wrap: wrap; }
        .command-input { flex: 1 1 280px; min-width: 220px; padding: 7px 10px; border-radius: 6px; border: 1px solid var(--vscode-editorWidget-border); background: var(--vscode-input-background); color: var(--vscode-input-foreground); }
        button { border: 1px solid var(--vscode-button-border, transparent); background: var(--vscode-button-background); color: var(--vscode-button-foreground); padding: 6px 10px; border-radius: 6px; cursor: pointer; }
        button:hover { background: var(--vscode-button-hoverBackground); }
        .card, .user-card { border: 1px solid var(--vscode-editorWidget-border); border-radius: 10px; padding: 10px; background: var(--vscode-editorWidget-background); }
        .user-card { display: grid; grid-template-columns: auto 1fr auto; gap: 10px; align-items: start; margin-bottom: 8px; }
        .user-card.same-file { outline: 1px solid var(--vscode-terminal-ansiGreen); }
        .avatar, .avatar-fallback { width: 32px; height: 32px; border-radius: 999px; display: grid; place-items: center; overflow: hidden; }
        .avatar-fallback { background: var(--vscode-badge-background); color: var(--vscode-badge-foreground); font-weight: 700; }
        .avatar img { width: 100%; height: 100%; object-fit: cover; }
        .user-body { min-width: 0; }
        .user-topline { display: flex; justify-content: space-between; gap: 8px; align-items: center; }
        .user-meta { opacity: 0.8; font-size: 0.88rem; word-break: break-word; }
        .warning { color: var(--vscode-editorWarning-foreground); opacity: 1; }
        .badge { display: inline-flex; align-items: center; border-radius: 999px; padding: 2px 8px; font-size: 0.75rem; margin-top: 6px; }
        .badge-same { background: var(--vscode-terminal-ansiGreen); color: var(--vscode-editor-background); }
        .badge-meeting { background: var(--vscode-editorInfo-foreground); color: var(--vscode-editor-background); }
        .status-dot { font-size: 0.78rem; }
        .panel-grid { display: grid; gap: 12px; }
        .current-file { margin-top: 12px; }
        .meeting-suggestion { margin: 12px 0; }
        .activity-list { display: grid; gap: 8px; }
        .activity-entry { border-radius: 8px; padding: 8px 10px; background: var(--vscode-editor-background); border: 1px solid var(--vscode-editorWidget-border); }
        .activity-topline { display: flex; justify-content: space-between; gap: 10px; align-items: center; }
        .activity-time { font-size: 0.8rem; opacity: 0.7; white-space: nowrap; }
        .activity-detail { margin-top: 4px; font-size: 0.88rem; opacity: 0.82; }
        .activity-system { border-left: 3px solid var(--vscode-terminal-ansiBlue); }
        .activity-presence { border-left: 3px solid var(--vscode-terminal-ansiGreen); }
        .activity-collaboration { border-left: 3px solid var(--vscode-terminal-ansiCyan); }
        .activity-navigation { border-left: 3px solid var(--vscode-terminal-ansiYellow); }
        .activity-settings { border-left: 3px solid var(--vscode-terminal-ansiMagenta); }
        .private-banner { display: flex; justify-content: space-between; gap: 12px; align-items: center; margin-bottom: 12px; padding: 10px 12px; border-radius: 8px; background: rgba(255, 204, 0, 0.1); border: 1px solid rgba(255, 204, 0, 0.35); }
        .empty-state { opacity: 0.65; padding: 10px 0; }
        h3 { margin: 0 0 8px; font-size: 0.9rem; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.8; }
      </style>
    </head>
    <body>
      <div class="hero">
        <h2>KC IDE Team Hub</h2>
        <div class="hero-actions">
          <button data-action="refresh">Refresh</button>
          <button data-action="settings">Settings</button>
        </div>
      </div>

      <div class="card">
        <strong>${escapeHtml(snapshot.currentUser.displayName)}</strong>
        <div class="user-meta">${escapeHtml(snapshot.currentFile ?? 'No active file')}</div>
        <div class="user-meta">Local time: ${escapeHtml(formatLocalTime(referenceDate, snapshot.currentUser.timezone))}</div>
        <div class="user-meta">Working hours: ${escapeHtml(formatWorkingHours(snapshot.currentUser.workingHours))}</div>
        ${snapshot.currentUser.status === 'dnd' ? '<div class="user-meta warning">📞 Meeting mode active. Non-urgent notifications are queued.</div>' : ''}
        ${snapshot.currentUser.currentFunction ? `<div class="user-meta">Function: ${escapeHtml(snapshot.currentUser.currentFunction)}</div>` : ''}
        ${snapshot.currentUser.currentTask ? `<div class="user-meta">Task: ${escapeHtml(snapshot.currentUser.currentTask)}</div>` : ''}
        ${snapshot.currentUser.customStatus ? `<div class="user-meta">Custom status: ${escapeHtml(snapshot.currentUser.customStatus)}</div>` : ''}
        ${getWorkingHoursWarning(snapshot.currentUser, referenceDate) ? `<div class="user-meta warning">${escapeHtml(getWorkingHoursWarning(snapshot.currentUser, referenceDate) ?? '')}</div>` : ''}
        <div class="user-meta">Last seen ${new Date(snapshot.updatedAt).toLocaleTimeString()}</div>
      </div>

      <div class="card meeting-suggestion">
        <h3>Best overlap meeting slot</h3>
        ${meetingSuggestion ? `
          <div class="user-meta">${escapeHtml(formatMeetingSlot(meetingSuggestion, snapshot.currentUser.timezone))}</div>
          <div class="user-meta">${meetingSuggestion.availableUsers.length} people available: ${escapeHtml(meetingSuggestion.availableUsers.map((user) => user.displayName).join(', '))}</div>
        ` : '<div class="empty-state">No overlapping working window found.</div>'}
      </div>

      <div class="quick-actions">
        <button data-action="start-meet">Start Meet</button>
        <button data-action="share-workspace">Share Link</button>
        <button data-action="toggle-isolation">${privateViewEnabled ? 'Exit Private View' : 'Private View'}</button>
      </div>

      ${privateViewEnabled ? `
        <div class="private-banner">
          <div>
            <strong>Private view enabled.</strong>
            <div class="user-meta">Collaborator presence is hidden in this workspace until you exit private view.</div>
          </div>
          <button data-action="toggle-isolation">Show Collaborators</button>
        </div>
      ` : ''}

      <div class="card command-panel">
        <h3>Agent Command Interface</h3>
        <div class="user-meta">Try: open sidebar, start meet, share workspace, refresh presence, open settings, toggle private mode</div>
        <div class="command-row">
          <input id="teamhub-command" class="command-input" type="text" placeholder="Type a KC IDE command" />
          <button data-action="run-command">Run Command</button>
        </div>
      </div>

      <div class="card">
        <h3>Activity Feed</h3>
        ${renderActivityFeedHtml(activityEntries, referenceDate)}
      </div>

      <div class="panel-grid">
        ${renderStatusSection('Online', grouped.online, config, referenceDate, snapshot.currentFile)}
        ${renderStatusSection('Away', grouped.away, config, referenceDate, snapshot.currentFile)}
        ${renderStatusSection('Offline', grouped.offline, config, referenceDate, snapshot.currentFile)}
      </div>

      <div class="card current-file">
        <h3>Current File</h3>
        <div>${escapeHtml(snapshot.currentFile ?? 'No file selected')}</div>
        ${snapshot.currentUser.currentFunction ? `<div class="user-meta">Current function: ${escapeHtml(snapshot.currentUser.currentFunction)}</div>` : ''}
        <div class="user-meta">${sameFileUsers.length > 0 ? `Also viewing: ${sameFileUsers.map((user) => user.displayName).join(', ')}` : 'No same-file collaborators right now'}</div>
      </div>

      <script nonce="${nonce}">
        const vscode = acquireVsCodeApi();
        document.querySelectorAll('[data-action]').forEach((button) => {
          button.addEventListener('click', () => {
            const action = button.getAttribute('data-action');
            const userId = button.getAttribute('data-user-id');
            const commandText = commandInput && commandInput.value ? commandInput.value : undefined;
            vscode.postMessage({ action, userId, commandText });
            if (action === 'run-command' && commandInput) {
              commandInput.value = '';
            }
          });
        });

        if (commandInput) {
          commandInput.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
              vscode.postMessage({ action: 'run-command', commandText: commandInput.value });
              commandInput.value = '';
            }
          });
        }
      </script>
    </body>
  </html>`;
};
