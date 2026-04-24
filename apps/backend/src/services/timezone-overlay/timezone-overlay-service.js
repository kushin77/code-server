import { EventEmitter } from 'events';
import pino from 'pino';
export class TimeZoneOverlayService extends EventEmitter {
    constructor(options) {
        super();
        this.userTimeZones = new Map();
        this.logger = options.logger || pino({
            base: { service: 'timezone-overlay' },
        });
    }
    static getInstance(options = {}) {
        if (!this.instance) {
            this.instance = new TimeZoneOverlayService(options);
        }
        return this.instance;
    }
    /**
     * Set user's time zone
     */
    setUserTimeZone(userId, timeZone) {
        const now = new Date();
        const userTimeZone = Intl.DateTimeFormat('en-US', { timeZone }).format(now);
        // Get UTC offset
        const utcDate = new Date(now.toLocaleString('en-US', { timeZone: 'UTC' }));
        const tzDate = new Date(now.toLocaleString('en-US', { timeZone }));
        const utcOffset = (utcDate.getTime() - tzDate.getTime()) / (1000 * 60);
        const info = {
            userId,
            timeZone,
            utcOffset: -utcOffset,
            isDaylightSavings: this.isDaylightSavings(timeZone),
            currentLocalTime: new Date(now.toLocaleString('en-US', { timeZone })),
        };
        this.userTimeZones.set(userId, info);
        this.logger.info(`Set time zone for user ${userId} to ${timeZone}`);
        this.emit('timezone-updated', info);
        return info;
    }
    /**
     * Get user's time zone info
     */
    getUserTimeZone(userId) {
        return this.userTimeZones.get(userId);
    }
    /**
     * Get current local time for a user
     */
    getUserLocalTime(userId) {
        const tzInfo = this.userTimeZones.get(userId);
        if (!tzInfo)
            return null;
        const now = new Date();
        const formatter = new Intl.DateTimeFormat('en-US', {
            timeZone: tzInfo.timeZone,
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: true,
        });
        return formatter.format(now);
    }
    /**
     * Get UTC offset string (e.g., "UTC-5:00")
     */
    getUTCOffsetString(userId) {
        const tzInfo = this.userTimeZones.get(userId);
        if (!tzInfo)
            return null;
        const hours = Math.floor(Math.abs(tzInfo.utcOffset) / 60);
        const minutes = Math.abs(tzInfo.utcOffset) % 60;
        const sign = tzInfo.utcOffset >= 0 ? '+' : '-';
        return `UTC${sign}${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
    }
    /**
     * Get time zone name with DST indicator
     */
    getTimeZoneDisplay(userId) {
        const tzInfo = this.userTimeZones.get(userId);
        if (!tzInfo)
            return null;
        const dstIndicator = tzInfo.isDaylightSavings ? ' (DST)' : '';
        return `${tzInfo.timeZone}${dstIndicator}`;
    }
    /**
     * Check if daylight savings is active for a time zone
     */
    isDaylightSavings(timeZone) {
        const now = new Date();
        const january = new Date(now.getFullYear(), 0, 1);
        const july = new Date(now.getFullYear(), 6, 1);
        const januaryOffset = this.getTimeZoneOffset(january, timeZone);
        const julyOffset = this.getTimeZoneOffset(july, timeZone);
        const currentOffset = this.getTimeZoneOffset(now, timeZone);
        return currentOffset > januaryOffset && currentOffset <= julyOffset;
    }
    /**
     * Get offset for specific date and timezone
     */
    getTimeZoneOffset(date, timeZone) {
        const utcDate = new Date(date.toLocaleString('en-US', { timeZone: 'UTC' }));
        const tzDate = new Date(date.toLocaleString('en-US', { timeZone }));
        return (utcDate.getTime() - tzDate.getTime()) / (1000 * 60);
    }
    /**
     * Format time zone info for presence display
     */
    formatForPresenceCard(presence) {
        const tzInfo = this.userTimeZones.get(presence.userId);
        return {
            userId: presence.userId,
            userName: presence.userName,
            status: presence.status,
            timeZone: tzInfo?.timeZone,
            localTime: tzInfo ? this.getUserLocalTime(presence.userId) : undefined,
            utcOffset: tzInfo?.utcOffset,
            customStatus: presence.customStatus,
        };
    }
    /**
     * Get all users sorted by time zone
     */
    getUsersByTimeZone() {
        const grouped = new Map();
        this.userTimeZones.forEach((tzInfo, userId) => {
            const tzKey = tzInfo.timeZone;
            if (!grouped.has(tzKey)) {
                grouped.set(tzKey, []);
            }
            const localTime = this.getUserLocalTime(userId);
            if (localTime) {
                grouped.get(tzKey).push({ userId, localTime });
            }
        });
        return grouped;
    }
    /**
     * Get time zone statistics
     */
    getStatistics() {
        const stats = {
            totalUsers: this.userTimeZones.size,
            timeZones: new Map(),
            usersOnDST: 0,
        };
        this.userTimeZones.forEach((tzInfo) => {
            const count = stats.timeZones.get(tzInfo.timeZone) || 0;
            stats.timeZones.set(tzInfo.timeZone, count + 1);
            if (tzInfo.isDaylightSavings) {
                stats.usersOnDST++;
            }
        });
        return {
            ...stats,
            timeZones: Object.fromEntries(stats.timeZones),
        };
    }
    /**
     * Get users in specific time zone
     */
    getUsersByTimeZoneName(timeZone) {
        const users = [];
        this.userTimeZones.forEach((tzInfo, userId) => {
            if (tzInfo.timeZone === timeZone) {
                users.push(userId);
            }
        });
        return users;
    }
    /**
     * Remove user time zone
     */
    removeUserTimeZone(userId) {
        this.userTimeZones.delete(userId);
        this.logger.info(`Removed time zone for user ${userId}`);
        this.emit('timezone-removed', { userId });
    }
    /**
     * Get all supported time zones
     */
    getSupportedTimeZones() {
        return Intl.supportedValuesOf('timeZone');
    }
    /**
     * Reset service
     */
    reset() {
        this.userTimeZones.clear();
        this.emit('service-reset');
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.reset();
        TimeZoneOverlayService.instance = null;
        this.emit('shutdown');
    }
}
TimeZoneOverlayService.instance = null;
export function createTimeZoneOverlayService(options = {}) {
    return TimeZoneOverlayService.getInstance(options);
}
//# sourceMappingURL=timezone-overlay-service.js.map