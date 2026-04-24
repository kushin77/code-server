export type TeamHubActivityKind = 'system' | 'presence' | 'collaboration' | 'navigation' | 'settings';

export interface TeamHubActivityEntry {
  id: string;
  kind: TeamHubActivityKind;
  title: string;
  detail?: string;
  timestamp: number;
}

export const MAX_ACTIVITY_ENTRIES = 8;

const escapeHtml = (value: string): string => value
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;');

export const createActivityEntry = (
  kind: TeamHubActivityKind,
  title: string,
  detail?: string,
  timestamp: number = Date.now()
): TeamHubActivityEntry => ({
  id: `${kind}-${timestamp}-${Math.random().toString(16).slice(2, 8)}`,
  kind,
  title,
  detail,
  timestamp,
});

export const prependActivityEntry = (
  entries: TeamHubActivityEntry[],
  entry: TeamHubActivityEntry,
  maxEntries: number = MAX_ACTIVITY_ENTRIES
): TeamHubActivityEntry[] => {
  const deduplicated = [entry, ...entries.filter((existing) => existing.id !== entry.id)];

  return deduplicated.slice(0, maxEntries);
};

const formatRelativeTime = (timestamp: number, referenceDate: Date): string => {
  const deltaMs = referenceDate.getTime() - timestamp;
  if (deltaMs < 60_000) {
    return 'Just now';
  }

  const minutes = Math.floor(deltaMs / 60_000);
  if (minutes < 60) {
    return `${minutes}m ago`;
  }

  const hours = Math.floor(minutes / 60);
  return `${hours}h ago`;
};

export const renderActivityFeedHtml = (entries: TeamHubActivityEntry[], referenceDate: Date = new Date()): string => {
  if (entries.length === 0) {
    return '<div class="empty-state">No recent activity yet.</div>';
  }

  return `
    <div class="activity-list">
      ${entries.map((entry) => `
        <article class="activity-entry activity-${escapeHtml(entry.kind)}">
          <div class="activity-topline">
            <strong>${escapeHtml(entry.title)}</strong>
            <span class="activity-time">${escapeHtml(formatRelativeTime(entry.timestamp, referenceDate))}</span>
          </div>
          ${entry.detail ? `<div class="activity-detail">${escapeHtml(entry.detail)}</div>` : ''}
        </article>
      `).join('')}
    </div>`;
};