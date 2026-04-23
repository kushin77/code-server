/**
 * @file        apps/backend/src/services/presence-timezone/index.ts
 * @module      collaboration/presence
 * @description Team member time zone management and overlay service for presence cards
 */
import { EventEmitter } from 'events';
export class PresenceTimezoneService extends EventEmitter {
    static getInstance(config) {
        if (!PresenceTimezoneService.instance) {
            PresenceTimezoneService.instance = new PresenceTimezoneService(config);
        }
        return PresenceTimezoneService.instance;
    }
    constructor(config) {
        super();
        this.timezones = new Map();
        this.config = {
            defaultWorkingHoursStart: 9,
            defaultWorkingHoursEnd: 17,
            updateIntervalMs: 60000, // update every minute
        };
        this.updateInterval = null;
        if (config) {
            this.config = { ...this.config, ...config };
        }
        // Add common timezones
        const commonTimezones = [
            'America/New_York',
            'America/Chicago',
            'America/Denver',
            'America/Los_Angeles',
            'Europe/London',
            'Europe/Paris',
            'Europe/Berlin',
            'Europe/Amsterdam',
            'Asia/Tokyo',
            'Asia/Shanghai',
            'Asia/Hong_Kong',
            'Asia/Singapore',
            'Australia/Sydney',
            'Australia/Melbourne',
            'Asia/Dubai',
            'Asia/Kolkata',
            'America/Toronto',
            'America/Vancouver',
        ];
        commonTimezones.forEach((tz) => {
            this.timezones.set(tz, {
                timezone: tz,
                workingHoursStart: this.config.defaultWorkingHoursStart,
                workingHoursEnd: this.config.defaultWorkingHoursEnd,
            });
        });
        console.log('[PresenceTimezone] Presence timezone service initialized');
    }
    /**
     * Register or update a user's timezone preference
     */
    registerUserTimezone(userId, teamId, timezone, workingHoursStart, workingHoursEnd) {
        // Validate working hours first (before timezone check)
        if (workingHoursStart !== undefined &&
            (workingHoursStart < 0 || workingHoursStart > 23)) {
            throw new Error(`Invalid working hours start: ${workingHoursStart}`);
        }
        if (workingHoursEnd !== undefined &&
            (workingHoursEnd < 0 || workingHoursEnd > 23)) {
            throw new Error(`Invalid working hours end: ${workingHoursEnd}`);
        }
        // Validate timezone
        if (!this.timezones.has(timezone) && !this.isValidTimezone(timezone)) {
            throw new Error(`Unknown timezone: ${timezone}`);
        }
        const key = `${teamId}:${userId}`;
        // Update stored timezone record
        this.timezones.set(key, {
            timezone,
            workingHoursStart: workingHoursStart ?? this.config.defaultWorkingHoursStart,
            workingHoursEnd: workingHoursEnd ?? this.config.defaultWorkingHoursEnd,
        });
        const tzInfo = this.getTimezoneInfo(userId, teamId, timezone, workingHoursStart, workingHoursEnd);
        this.emit('timezone-registered', {
            userId,
            teamId,
            timezone,
            workingHoursStart: tzInfo.workingHoursStart,
            workingHoursEnd: tzInfo.workingHoursEnd,
        });
        return tzInfo;
    }
    /**
     * Check if timezone is valid using a quick format check
     */
    isValidTimezone(tz) {
        // Quick validation: should have one or more path components
        return /^[A-Za-z_]+\/[A-Za-z_]+/.test(tz);
    }
    /**
     * Get current timezone info for a user
     */
    getTimezoneInfo(userId, teamId, timezone, workingHoursStart, workingHoursEnd) {
        const key = `${teamId}:${userId}`;
        const stored = this.timezones.get(key);
        const start = workingHoursStart ?? stored?.workingHoursStart ?? this.config.defaultWorkingHoursStart;
        const end = workingHoursEnd ?? stored?.workingHoursEnd ?? this.config.defaultWorkingHoursEnd;
        const now = new Date();
        const utcTime = new Date(now.toLocaleString('en-US', { timeZone: 'UTC' }));
        const tzTime = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
        const utcOffset = Math.round((tzTime.getTime() - utcTime.getTime()) / 60000);
        const isDaylightSaving = this.isDaylightSavingTime(timezone, now);
        const currentHour = tzTime.getHours();
        const currentMinute = tzTime.getMinutes();
        const isCurrentlyWorking = currentHour >= start && currentHour < end;
        // Calculate next work start
        let nextWorkStart;
        let nextWorkEnd;
        if (!isCurrentlyWorking) {
            if (currentHour < start) {
                // Today's work hasn't started yet
                nextWorkStart = new Date(now);
                nextWorkStart.setHours(start, 0, 0, 0);
            }
            else {
                // Today's work has ended, next work is tomorrow
                nextWorkStart = new Date(now);
                nextWorkStart.setDate(nextWorkStart.getDate() + 1);
                nextWorkStart.setHours(start, 0, 0, 0);
            }
        }
        if (isCurrentlyWorking) {
            nextWorkEnd = new Date(now);
            nextWorkEnd.setHours(end, 0, 0, 0);
        }
        return {
            userId,
            teamId,
            timezone,
            currentTime: tzTime,
            currentHour,
            currentMinute,
            utcOffset,
            isDaylightSaving,
            workingHoursStart: start,
            workingHoursEnd: end,
            isCurrentlyWorking,
            nextWorkStart,
            nextWorkEnd,
        };
    }
    /**
     * Get presence with timezone information
     */
    getPresenceWithTimezone(userId, teamId, presence, lastActive, timezone) {
        const tz = timezone ?? 'America/New_York';
        const tzInfo = this.getTimezoneInfo(userId, teamId, tz);
        return {
            userId,
            teamId,
            presence,
            timezone: tzInfo,
            lastActive,
        };
    }
    /**
     * Get team-wide timezone statistics
     */
    getTeamTimezoneStats(teamId, memberTimezones) {
        const distribution = {};
        let workingMembersCount = 0;
        const offsets = [];
        Object.entries(memberTimezones).forEach(([userId, timezone]) => {
            // Count distribution
            distribution[timezone] = (distribution[timezone] || 0) + 1;
            // Check if working
            const tzInfo = this.getTimezoneInfo(userId, teamId, timezone);
            if (tzInfo.isCurrentlyWorking) {
                workingMembersCount++;
            }
            offsets.push(tzInfo.utcOffset);
        });
        // Calculate work hours range
        let minHour = 23;
        let maxHour = 0;
        Object.entries(memberTimezones).forEach(([userId, timezone]) => {
            const tzInfo = this.getTimezoneInfo(userId, teamId, timezone);
            minHour = Math.min(minHour, tzInfo.workingHoursStart);
            maxHour = Math.max(maxHour, tzInfo.workingHoursEnd);
        });
        const averageOffset = offsets.length > 0 ? Math.round(offsets.reduce((a, b) => a + b, 0) / offsets.length) : 0;
        return {
            teamId,
            memberCount: Object.keys(memberTimezones).length,
            timezoneDistribution: distribution,
            workingMembersCount,
            workingHoursRange: {
                start: minHour,
                end: maxHour,
            },
            averageUTCOffset: averageOffset,
        };
    }
    /**
     * Get list of all registered timezones
     */
    listTimezones() {
        const commonTzs = new Set();
        Array.from(this.timezones.keys()).forEach((key) => {
            // Filter out user-specific timezones (those with :)
            if (!key.includes(':')) {
                commonTzs.add(key);
            }
        });
        return Array.from(commonTzs).sort();
    }
    /**
     * Convert time from one timezone to another
     */
    convertTime(time, fromTimezone, toTimezone) {
        const fromTime = new Date(time.toLocaleString('en-US', { timeZone: fromTimezone }));
        const utcTime = new Date(time.toLocaleString('en-US', { timeZone: 'UTC' }));
        const fromOffset = Math.round((fromTime.getTime() - utcTime.getTime()) / 60000);
        const toTime = new Date(time.toLocaleString('en-US', { timeZone: toTimezone }));
        const toOffset = Math.round((toTime.getTime() - utcTime.getTime()) / 60000);
        const diff = (toOffset - fromOffset) * 60000;
        return new Date(time.getTime() + diff);
    }
    /**
     * Get suggested meeting times that work for multiple timezones
     */
    suggestMeetingTimes(teamId, memberTimezones, durationMinutes = 60) {
        const suggestions = [];
        const now = new Date();
        // Check next 7 days, 30-min intervals
        for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
            for (let hour = 6; hour < 22; hour++) {
                for (let minute = 0; minute < 60; minute += 30) {
                    const candidateTime = new Date(now);
                    candidateTime.setDate(candidateTime.getDate() + dayOffset);
                    candidateTime.setHours(hour, minute, 0, 0);
                    // Check if this time works for all members
                    let worksForAll = true;
                    Object.entries(memberTimezones).forEach(([userId, timezone]) => {
                        const tzInfo = this.getTimezoneInfo(userId, teamId, timezone);
                        const converted = this.convertTime(candidateTime, 'UTC', timezone);
                        const checkHour = converted.getHours();
                        // Check if within working hours and reasonable (6am-10pm)
                        if (!(checkHour >= 6 && checkHour < 22)) {
                            worksForAll = false;
                        }
                    });
                    if (worksForAll && suggestions.length < 3) {
                        suggestions.push(candidateTime);
                    }
                }
            }
        }
        return suggestions;
    }
    /**
     * Check if time is in daylight saving time for timezone
     */
    isDaylightSavingTime(timezone, date) {
        // Simplified DST check - for a real implementation, use a proper timezone library
        // This checks if the offset is different between winter and summer
        const january = new Date(date.getFullYear(), 0, 1);
        const july = new Date(date.getFullYear(), 6, 1);
        const januaryOffset = new Date(january.toLocaleString('en-US', { timeZone: timezone })).getTime() -
            new Date(january.toLocaleString('en-US', { timeZone: 'UTC' })).getTime();
        const julyOffset = new Date(july.toLocaleString('en-US', { timeZone: timezone })).getTime() -
            new Date(july.toLocaleString('en-US', { timeZone: 'UTC' })).getTime();
        const currentOffset = new Date(date.toLocaleString('en-US', { timeZone: timezone })).getTime() -
            new Date(date.toLocaleString('en-US', { timeZone: 'UTC' })).getTime();
        return Math.abs(currentOffset - julyOffset) < Math.abs(currentOffset - januaryOffset);
    }
    /**
     * Reset service state (for testing) - keeps common timezones
     */
    reset() {
        // Clear only user-specific timezones (those with :)
        const keysToDelete = [];
        this.timezones.forEach((_, key) => {
            if (key.includes(':')) {
                keysToDelete.push(key);
            }
        });
        keysToDelete.forEach((key) => this.timezones.delete(key));
        this.removeAllListeners();
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
    }
    /**
     * Shutdown service
     */
    shutdown() {
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
        this.reset();
        this.emit('shutdown');
    }
}
export default PresenceTimezoneService;
//# sourceMappingURL=index.js.map