// @file        apps/extensions/team-hub/src/timezone-overlay.ts
// @module      collab/presence
// @description Time zone overlay on team member presence cards
// @governance  GOV-002: IaC, immutable, idempotent
// Issue #1105: [Collab-4.2] Time zone overlay on team member presence cards

import * as vscode from "vscode";
import type { TeamHubUser } from "./types";

export interface TimezoneInfo {
  timezone: string;           // IANA timezone, e.g. "America/New_York"
  localTime: string;          // Formatted local time
  utcOffset: string;          // e.g. "+05:30"
  isWorkingHours: boolean;    // Within configured working hours
  hoursFromYou: number;       // Difference from current user's timezone
}

export function getTimezoneInfo(
  user: TeamHubUser,
  viewerTimezone?: string
): TimezoneInfo | null {
  const tz = user.timezone;
  if (!tz) return null;

  try {
    const now = new Date();

    // Get user's local time
    const localTime = now.toLocaleTimeString("en-US", {
      timeZone: tz,
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
    });

    // Get UTC offset string
    const utcOffset = getUtcOffsetString(tz, now);

    // Check working hours
    const localHour = getLocalHour(tz, now);
    const startHour = user.workingHours?.startHour ?? 9;
    const endHour = user.workingHours?.endHour ?? 18;
    const isWorkingHours = localHour >= startHour && localHour < endHour;

    // Calculate hours difference from viewer
    const viewerOffset = viewerTimezone
      ? getUtcOffsetMinutes(viewerTimezone, now)
      : getUtcOffsetMinutes("UTC", now);
    const userOffset = getUtcOffsetMinutes(tz, now);
    const diffMinutes = userOffset - viewerOffset;
    const hoursFromYou = diffMinutes / 60;

    return {
      timezone: tz,
      localTime,
      utcOffset,
      isWorkingHours,
      hoursFromYou,
    };
  } catch {
    return null;
  }
}

function getLocalHour(timezone: string, date: Date): number {
  const str = date.toLocaleString("en-US", {
    timeZone: timezone,
    hour: "numeric",
    hour12: false,
  });
  return parseInt(str, 10);
}

function getUtcOffsetMinutes(timezone: string, date: Date): number {
  const utcMs = date.getTime();
  const localStr = date.toLocaleString("en-US", {
    timeZone: timezone,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    hour12: false,
  });
  const localMs = new Date(localStr).getTime();
  return Math.round((localMs - utcMs) / 60000);
}

function getUtcOffsetString(timezone: string, date: Date): string {
  const minutes = getUtcOffsetMinutes(timezone, date);
  const sign = minutes >= 0 ? "+" : "-";
  const absMin = Math.abs(minutes);
  const hours = Math.floor(absMin / 60).toString().padStart(2, "0");
  const mins = (absMin % 60).toString().padStart(2, "0");
  return `${sign}${hours}:${mins}`;
}

// ── Presence card tooltip enrichment ─────────────────────────────────────────

export function buildPresenceTooltip(
  user: TeamHubUser,
  viewerTimezone?: string
): vscode.MarkdownString {
  const md = new vscode.MarkdownString("", true);
  md.isTrusted = true;

  const tzInfo = getTimezoneInfo(user, viewerTimezone);

  md.appendMarkdown(`**${user.displayName}**\n\n`);

  if (tzInfo) {
    const workIcon = tzInfo.isWorkingHours ? "🟢" : "🌙";
    const diffStr = formatHoursDiff(tzInfo.hoursFromYou);

    md.appendMarkdown(`${workIcon} ${tzInfo.localTime} (${tzInfo.utcOffset})\n\n`);
    md.appendMarkdown(`🌍 \`${tzInfo.timezone}\`\n\n`);
    if (diffStr) {
      md.appendMarkdown(`⏱ ${diffStr} from you\n\n`);
    }
    if (!tzInfo.isWorkingHours) {
      md.appendMarkdown(`> Outside working hours\n\n`);
    }
  }

  if (user.currentFile) {
    md.appendMarkdown(`📄 \`${user.currentFile}\`\n\n`);
  }
  if (user.currentTask) {
    md.appendMarkdown(`✅ ${user.currentTask}\n\n`);
  }
  if (user.customStatus) {
    md.appendMarkdown(`💬 ${user.customStatus}\n\n`);
  }

  return md;
}

function formatHoursDiff(hours: number): string {
  if (hours === 0) return "";
  const abs = Math.abs(hours);
  const ahead = hours > 0;
  const label = abs === 0.5 ? "30 min" : `${abs}h`;
  return ahead ? `${label} ahead` : `${label} behind`;
}

// ── Quick pick for team timezone overview ──────────────────────────────────

export async function showTeamTimezoneOverview(
  users: TeamHubUser[],
  viewerTimezone: string
): Promise<void> {
  const items = users
    .filter((u) => u.timezone)
    .sort((a, b) => {
      const tzA = getTimezoneInfo(a, viewerTimezone);
      const tzB = getTimezoneInfo(b, viewerTimezone);
      return (tzA?.hoursFromYou ?? 0) - (tzB?.hoursFromYou ?? 0);
    })
    .map((user) => {
      const tzInfo = getTimezoneInfo(user, viewerTimezone)!;
      const workIcon = tzInfo.isWorkingHours ? "🟢" : "🌙";

      return {
        label: `${workIcon} ${user.displayName}`,
        description: `${tzInfo.localTime} (${tzInfo.utcOffset})`,
        detail: [
          tzInfo.timezone,
          tzInfo.isWorkingHours ? "Working hours" : "After hours",
          formatHoursDiff(tzInfo.hoursFromYou) || "Same timezone",
        ].join(" · "),
      };
    });

  if (items.length === 0) {
    vscode.window.showInformationMessage(
      "No team members have timezone configured."
    );
    return;
  }

  await vscode.window.showQuickPick(items, {
    title: "Team Timezone Overview",
    placeHolder: "Team members sorted by timezone",
    matchOnDescription: true,
  });
}

// ── VSCode Command Registration ───────────────────────────────────────────────

export function registerTimezoneCommands(
  ctx: vscode.ExtensionContext,
  getUsers: () => TeamHubUser[],
  currentUserTimezone: string
): void {
  ctx.subscriptions.push(
    vscode.commands.registerCommand(
      "teamHub.presence.showTimezoneOverview",
      () => showTeamTimezoneOverview(getUsers(), currentUserTimezone)
    )
  );
}
