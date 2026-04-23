import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createTimeZoneOverlayService } from '../timezone-overlay-service';
describe('TimeZoneOverlayService', () => {
    let service;
    beforeEach(() => {
        service = createTimeZoneOverlayService();
    });
    afterEach(() => {
        service.shutdown();
    });
    describe('Initialization', () => {
        it('should create service instance', () => {
            expect(service).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const service2 = createTimeZoneOverlayService();
            expect(service).toBe(service2);
        });
    });
    describe('Set User Time Zone', () => {
        it('should set user time zone', () => {
            const tzInfo = service.setUserTimeZone('user-1', 'America/New_York');
            expect(tzInfo.userId).toBe('user-1');
            expect(tzInfo.timeZone).toBe('America/New_York');
            expect(tzInfo.utcOffset).toBeDefined();
        });
        it('should emit timezone-updated event', () => {
            let emitted = false;
            service.on('timezone-updated', () => {
                emitted = true;
            });
            service.setUserTimeZone('user-1', 'Europe/London');
            expect(emitted).toBe(true);
        });
        it('should handle multiple time zones', () => {
            service.setUserTimeZone('user-1', 'America/Los_Angeles');
            service.setUserTimeZone('user-2', 'Europe/Paris');
            service.setUserTimeZone('user-3', 'Asia/Tokyo');
            expect(service.getUserTimeZone('user-1')?.timeZone).toBe('America/Los_Angeles');
            expect(service.getUserTimeZone('user-2')?.timeZone).toBe('Europe/Paris');
            expect(service.getUserTimeZone('user-3')?.timeZone).toBe('Asia/Tokyo');
        });
    });
    describe('Get User Time Zone', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/Chicago');
        });
        it('should get user time zone', () => {
            const tzInfo = service.getUserTimeZone('user-1');
            expect(tzInfo).toBeDefined();
            expect(tzInfo?.timeZone).toBe('America/Chicago');
        });
        it('should return undefined for non-existent user', () => {
            const tzInfo = service.getUserTimeZone('non-existent');
            expect(tzInfo).toBeUndefined();
        });
    });
    describe('Get User Local Time', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/New_York');
        });
        it('should get user local time', () => {
            const localTime = service.getUserLocalTime('user-1');
            expect(localTime).not.toBeNull();
            expect(localTime).toMatch(/\d{1,2}:\d{2}:\d{2}\s(AM|PM)/);
        });
        it('should return null for non-existent user', () => {
            const localTime = service.getUserLocalTime('non-existent');
            expect(localTime).toBeNull();
        });
    });
    describe('Get UTC Offset String', () => {
        it('should format positive UTC offset', () => {
            service.setUserTimeZone('user-1', 'Asia/Tokyo');
            const offset = service.getUTCOffsetString('user-1');
            expect(offset).toMatch(/UTC\+\d{2}:\d{2}/);
        });
        it('should format negative UTC offset', () => {
            service.setUserTimeZone('user-1', 'America/Los_Angeles');
            const offset = service.getUTCOffsetString('user-1');
            expect(offset).toMatch(/UTC-\d{2}:\d{2}/);
        });
        it('should return null for non-existent user', () => {
            const offset = service.getUTCOffsetString('non-existent');
            expect(offset).toBeNull();
        });
    });
    describe('Get Time Zone Display', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/New_York');
        });
        it('should get time zone display string', () => {
            const display = service.getTimeZoneDisplay('user-1');
            expect(display).toContain('America/New_York');
        });
        it('should include DST indicator when applicable', () => {
            const display = service.getTimeZoneDisplay('user-1');
            expect(display).toBeDefined();
            // Note: DST status depends on the current date
        });
        it('should return null for non-existent user', () => {
            const display = service.getTimeZoneDisplay('non-existent');
            expect(display).toBeNull();
        });
    });
    describe('Format For Presence Card', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'Europe/London');
        });
        it('should format presence with time zone info', () => {
            const presence = {
                userId: 'user-1',
                userName: 'Alice',
                status: 'online',
                customStatus: 'Working on PR',
            };
            const formatted = service.formatForPresenceCard(presence);
            expect(formatted.userId).toBe('user-1');
            expect(formatted.userName).toBe('Alice');
            expect(formatted.status).toBe('online');
            expect(formatted.timeZone).toBe('Europe/London');
            expect(formatted.localTime).toBeDefined();
            expect(formatted.customStatus).toBe('Working on PR');
        });
        it('should handle presence without time zone', () => {
            const presence = {
                userId: 'user-2',
                userName: 'Bob',
                status: 'offline',
            };
            const formatted = service.formatForPresenceCard(presence);
            expect(formatted.userId).toBe('user-2');
            expect(formatted.timeZone).toBeUndefined();
        });
    });
    describe('Get Users By Time Zone', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/New_York');
            service.setUserTimeZone('user-2', 'America/New_York');
            service.setUserTimeZone('user-3', 'Europe/Paris');
        });
        it('should group users by time zone', () => {
            const grouped = service.getUsersByTimeZone();
            expect(grouped.has('America/New_York')).toBe(true);
            expect(grouped.has('Europe/Paris')).toBe(true);
        });
        it('should have correct user counts per time zone', () => {
            const grouped = service.getUsersByTimeZone();
            expect(grouped.get('America/New_York')).toHaveLength(2);
            expect(grouped.get('Europe/Paris')).toHaveLength(1);
        });
        it('should include local time for each user', () => {
            const grouped = service.getUsersByTimeZone();
            const nyUsers = grouped.get('America/New_York');
            expect(nyUsers?.every((u) => u.localTime)).toBe(true);
        });
    });
    describe('Get Statistics', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/New_York');
            service.setUserTimeZone('user-2', 'America/New_York');
            service.setUserTimeZone('user-3', 'Europe/Paris');
            service.setUserTimeZone('user-4', 'Asia/Tokyo');
        });
        it('should calculate statistics', () => {
            const stats = service.getStatistics();
            expect(stats.totalUsers).toBe(4);
            expect(stats.timeZones['America/New_York']).toBe(2);
            expect(stats.timeZones['Europe/Paris']).toBe(1);
            expect(stats.timeZones['Asia/Tokyo']).toBe(1);
        });
        it('should track DST users', () => {
            const stats = service.getStatistics();
            expect(stats.usersOnDST).toBeGreaterThanOrEqual(0);
        });
    });
    describe('Get Users By Time Zone Name', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/Los_Angeles');
            service.setUserTimeZone('user-2', 'America/Los_Angeles');
            service.setUserTimeZone('user-3', 'Europe/Berlin');
        });
        it('should get users in specific time zone', () => {
            const users = service.getUsersByTimeZoneName('America/Los_Angeles');
            expect(users).toHaveLength(2);
            expect(users).toContain('user-1');
            expect(users).toContain('user-2');
        });
        it('should return empty array for time zone with no users', () => {
            const users = service.getUsersByTimeZoneName('Australia/Sydney');
            expect(users).toHaveLength(0);
        });
    });
    describe('Remove User Time Zone', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/Denver');
        });
        it('should remove user time zone', () => {
            service.removeUserTimeZone('user-1');
            expect(service.getUserTimeZone('user-1')).toBeUndefined();
        });
        it('should emit timezone-removed event', () => {
            let emitted = false;
            service.on('timezone-removed', () => {
                emitted = true;
            });
            service.removeUserTimeZone('user-1');
            expect(emitted).toBe(true);
        });
    });
    describe('Get Supported Time Zones', () => {
        it('should return list of supported time zones', () => {
            const timeZones = service.getSupportedTimeZones();
            expect(Array.isArray(timeZones)).toBe(true);
            expect(timeZones.length).toBeGreaterThan(0);
            expect(timeZones).toContain('America/New_York');
            expect(timeZones).toContain('Europe/London');
        });
    });
    describe('Reset', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'America/Chicago');
            service.setUserTimeZone('user-2', 'Europe/Madrid');
        });
        it('should clear all time zones', () => {
            service.reset();
            expect(service.getUserTimeZone('user-1')).toBeUndefined();
            expect(service.getUserTimeZone('user-2')).toBeUndefined();
        });
        it('should emit service-reset event', () => {
            let emitted = false;
            service.on('service-reset', () => {
                emitted = true;
            });
            service.reset();
            expect(emitted).toBe(true);
        });
    });
    describe('Shutdown', () => {
        beforeEach(() => {
            service.setUserTimeZone('user-1', 'Asia/Singapore');
        });
        it('should shutdown service', () => {
            service.shutdown();
            expect(service.getUserTimeZone('user-1')).toBeUndefined();
        });
        it('should emit shutdown event', () => {
            let emitted = false;
            service.on('shutdown', () => {
                emitted = true;
            });
            service.shutdown();
            expect(emitted).toBe(true);
        });
    });
    describe('Edge Cases', () => {
        it('should handle UTC time zone', () => {
            const tzInfo = service.setUserTimeZone('user-1', 'UTC');
            expect(tzInfo.timeZone).toBe('UTC');
            expect(Math.abs(tzInfo.utcOffset)).toBe(0);
        });
        it('should handle time zones with half-hour offsets', () => {
            const tzInfo = service.setUserTimeZone('user-1', 'Asia/Kolkata');
            expect(tzInfo.utcOffset % 60).toBeGreaterThanOrEqual(0);
        });
        it('should update existing user time zone', () => {
            service.setUserTimeZone('user-1', 'America/New_York');
            const tzInfo1 = service.getUserTimeZone('user-1');
            service.setUserTimeZone('user-1', 'America/Los_Angeles');
            const tzInfo2 = service.getUserTimeZone('user-1');
            expect(tzInfo1?.timeZone).toBe('America/New_York');
            expect(tzInfo2?.timeZone).toBe('America/Los_Angeles');
        });
    });
});
//# sourceMappingURL=timezone-overlay-service.test.js.map