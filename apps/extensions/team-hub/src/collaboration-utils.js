const slugify = (value) => value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
const DEFAULT_WORKING_HOURS = { startHour: 9, endHour: 17 };
const getDisplayName = (value) => value.split(/\s+/)[0] || value;
const getResolvedTimeZone = (timeZone) => {
    return timeZone || Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
};
const formatHourLabel = (hour) => {
    const normalizedHour = ((hour % 24) + 24) % 24;
    const period = normalizedHour >= 12 ? 'PM' : 'AM';
    const displayHour = normalizedHour % 12 || 12;
    return `${displayHour}:00 ${period}`;
};
const formatTimeInZone = (date, timeZone) => {
    try {
        return new Intl.DateTimeFormat('en-US', {
            timeZone: getResolvedTimeZone(timeZone),
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        }).format(date);
    }
    catch {
        return new Intl.DateTimeFormat('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        }).format(date);
    }
};
const getLocalHour = (date, timeZone) => {
    try {
        const hour = new Intl.DateTimeFormat('en-US', {
            timeZone: getResolvedTimeZone(timeZone),
            hour: '2-digit',
            hour12: false
        }).format(date);
        return Number.parseInt(hour, 10);
    }
    catch {
        return date.getHours();
    }
};
const getWorkingHours = (user) => user.workingHours ?? DEFAULT_WORKING_HOURS;
const isWithinWorkingHours = (hour, workingHours) => {
    const start = Math.min(workingHours.startHour, workingHours.endHour);
    const end = Math.max(workingHours.startHour, workingHours.endHour);
    if (workingHours.startHour === workingHours.endHour) {
        return true;
    }
    if (workingHours.endHour > workingHours.startHour) {
        return hour >= start && hour < end;
    }
    return hour >= start || hour < end;
};
const isUserAvailableAt = (user, date) => {
    const hour = getLocalHour(date, user.timezone);
    return isWithinWorkingHours(hour, getWorkingHours(user));
};
export const formatLocalTime = (date, timeZone) => formatTimeInZone(date, timeZone);
export const formatWorkingHours = (workingHours) => {
    const hours = workingHours ?? DEFAULT_WORKING_HOURS;
    return `${formatHourLabel(hours.startHour)} - ${formatHourLabel(hours.endHour)}`;
};
export const getWorkingHoursWarning = (user, date) => {
    const localHour = getLocalHour(date, user.timezone);
    if (isWithinWorkingHours(localHour, getWorkingHours(user))) {
        return undefined;
    }
    return `Its ${formatLocalTime(date, user.timezone).replace(':00', '')} for ${getDisplayName(user.displayName)}`;
};
export const findBestMeetingSlot = (users, referenceDate, durationMinutes = 30, viewerTimeZone) => {
    if (users.length === 0) {
        return undefined;
    }
    const slotStart = new Date(referenceDate);
    slotStart.setSeconds(0, 0);
    const slotStartMs = slotStart.getTime();
    const slotStepMs = 30 * 60 * 1000;
    const durationMs = Math.max(durationMinutes, 15) * 60 * 1000;
    let bestSuggestion;
    for (let offset = 0; offset < 48; offset += 1) {
        const start = new Date(slotStartMs + (offset * slotStepMs));
        const end = new Date(start.getTime() + durationMs);
        const availableUsers = users.filter((user) => isUserAvailableAt(user, start));
        if (!bestSuggestion || availableUsers.length > bestSuggestion.availableUsers.length) {
            bestSuggestion = {
                start,
                end,
                availableUsers
            };
        }
    }
    return bestSuggestion;
};
export const formatMeetingSlot = (slot, timeZone) => {
    const start = formatLocalTime(slot.start, timeZone);
    const end = formatLocalTime(slot.end, timeZone);
    return `${start} - ${end}`;
};
export const buildMentionText = (user) => `@${user.displayName}`;
export const buildMeetLink = (users) => {
    const participantSlug = users.length > 0 ? slugify(users.map((user) => user.displayName).join('-')) : 'team-hub';
    return `https://meet.google.com/new?team=${encodeURIComponent(participantSlug)}`;
};
export const buildWorkspaceShareLink = (workspaceRoot, currentFile) => {
    return currentFile ? `${workspaceRoot}#${encodeURIComponent(currentFile)}` : workspaceRoot;
};
//# sourceMappingURL=collaboration-utils.js.map