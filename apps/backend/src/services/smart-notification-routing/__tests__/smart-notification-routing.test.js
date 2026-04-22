#!/usr/bin/env node
// @file        apps/backend/src/services/smart-notification-routing/__tests__/smart-notification-routing.test.ts
// @module      collaboration/notification-routing
// @description Unit tests for smart notification routing service
// @owner       collab-4.6
// @status      active
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { SmartNotificationRoutingService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: vi.fn(() => ({
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    })),
}));
const mockPool = {
    connect: vi.fn(),
    end: vi.fn(),
};
describe('SmartNotificationRoutingService', () => {
    let service;
    let mockClient;
    beforeEach(async () => {
        vi.clearAllMocks();
        mockClient = {
            query: vi.fn(),
            release: vi.fn(),
        };
        mockPool.connect.mockResolvedValue(mockClient);
        service = new SmartNotificationRoutingService(mockPool);
        mockClient.query.mockResolvedValue({ rows: [] });
        await service.initialize();
    });
    describe('initialization', () => {
        it('should initialize with database schema', async () => {
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS user_status'));
        });
        it('should create all required tables', async () => {
            const createTableCalls = mockClient.query.mock.calls.filter(call => call[0].includes('CREATE TABLE'));
            expect(createTableCalls.length).toBeGreaterThanOrEqual(5);
        });
    });
    describe('updateUserStatus', () => {
        it('should insert new user status', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // SELECT existing
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT
            await service.updateUserStatus('user-1', 'online', { location: 'office', currentDevice: 'ide' });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO user_status'), expect.any(Array));
        });
        it('should update existing user status', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'status-1' }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE
            await service.updateUserStatus('user-1', 'away');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE user_status'), expect.any(Array));
        });
        it('should include optional context fields', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ id: 'status-1' }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE
            await service.updateUserStatus('user-1', 'in-meeting', {
                location: 'meeting-room-1',
                calendarStatus: 'busy',
                currentDevice: 'mobile',
            });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE user_status'), expect.arrayContaining(['meeting-room-1', 'busy', 'mobile']));
        });
    });
    describe('getUserStatus', () => {
        it('should retrieve user status', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        user_id: 'user-1',
                        current_status: 'online',
                        last_status_change: new Date(),
                        location: 'office',
                        calendar_status: null,
                        current_device: 'ide',
                    }],
            });
            const status = await service.getUserStatus('user-1');
            expect(status).toBeDefined();
            expect(status?.currentStatus).toBe('online');
            expect(status?.location).toBe('office');
        });
        it('should return null if status not found', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const status = await service.getUserStatus('unknown');
            expect(status).toBeNull();
        });
    });
    describe('setNotificationRoute', () => {
        it('should create notification route', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const route = await service.setNotificationRoute('user-1', 'urgent', ['ide', 'slack']);
            expect(route).toBeDefined();
            expect(route.userId).toBe('user-1');
            expect(route.priority).toBe('urgent');
            expect(route.channels).toEqual(['ide', 'slack']);
        });
        it('should include routing conditions', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const conditions = [
                { status: 'online', channels: ['ide'] },
                { status: 'away', channels: ['slack'] },
            ];
            const route = await service.setNotificationRoute('user-1', 'normal', ['slack', 'matrix'], conditions);
            expect(route.conditions).toEqual(conditions);
        });
    });
    describe('getNotificationRoute', () => {
        it('should retrieve notification route', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        id: 'route-1',
                        user_id: 'user-1',
                        priority: 'urgent',
                        channels: ['ide', 'slack'],
                        conditions: null,
                        is_active: true,
                        created_at: new Date(),
                        updated_at: new Date(),
                    }],
            });
            const route = await service.getNotificationRoute('user-1', 'urgent');
            expect(route).toBeDefined();
            expect(route?.priority).toBe('urgent');
            expect(route?.channels).toEqual(['ide', 'slack']);
        });
        it('should return null if route not found', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const route = await service.getNotificationRoute('user-1', 'low');
            expect(route).toBeNull();
        });
    });
    describe('getUserRoutes', () => {
        it('should retrieve all routes for user', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'route-1',
                        user_id: 'user-1',
                        priority: 'urgent',
                        channels: ['ide'],
                        conditions: null,
                        is_active: true,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                    {
                        id: 'route-2',
                        user_id: 'user-1',
                        priority: 'normal',
                        channels: ['slack'],
                        conditions: null,
                        is_active: true,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                ],
            });
            const routes = await service.getUserRoutes('user-1');
            expect(routes).toHaveLength(2);
            expect(routes[0].priority).toBe('urgent');
            expect(routes[1].priority).toBe('normal');
        });
    });
    describe('routeNotification', () => {
        it('should route to IDE when user is online', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ current_status: 'online' }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // No custom route
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // Dedup check
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT delivery
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE dedup cache
            const deliveries = await service.routeNotification('user-1', 'notif-1', 'Test message', 'normal');
            expect(deliveries[0].channel).toBe('ide');
        });
        it('should route to Slack when user is away', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ current_status: 'away' }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // No custom route
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // Dedup check
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT delivery
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE dedup cache
            const deliveries = await service.routeNotification('user-1', 'notif-1', 'Test message', 'normal');
            expect(deliveries[0].channel).toBe('slack');
        });
        it('should route to Matrix when user is in meeting', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ current_status: 'in-meeting' }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // No custom route
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // Dedup check
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT delivery
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE dedup cache
            const deliveries = await service.routeNotification('user-1', 'notif-1', 'Test message', 'normal');
            expect(deliveries[0].channel).toBe('matrix');
        });
        it('should respect custom routing conditions', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ current_status: 'away' }],
            });
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        channels: ['slack'],
                        conditions: [
                            { status: 'away', channels: ['email'] },
                        ],
                    }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // Dedup check
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT delivery
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE dedup cache
            const deliveries = await service.routeNotification('user-1', 'notif-1', 'Test message', 'urgent');
            expect(deliveries[0].channel).toBe('email');
        });
        it('should handle deduplication', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ current_status: 'online' }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // No custom route
            mockClient.query.mockResolvedValueOnce({
                rows: [{ last_delivery_at: new Date() }], // Recent delivery
            }); // Dedup check
            const deliveries = await service.routeNotification('user-1', 'notif-1', 'Test message', 'normal');
            expect(deliveries).toHaveLength(0);
        });
        it('should create multiple deliveries for multiple channels', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ current_status: 'offline' }],
            });
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        channels: ['slack', 'matrix', 'email'],
                        conditions: null,
                    }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // Dedup check
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT 1
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT 2
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT 3
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE dedup
            const deliveries = await service.routeNotification('user-1', 'notif-1', 'Test message', 'normal');
            expect(deliveries.length).toBeGreaterThan(1);
        });
    });
    describe('recordDelivery', () => {
        it('should record successful delivery', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        status: 'pending',
                        attempt_count: 0,
                        max_attempts: 3,
                    }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT history
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // COMMIT
            await service.recordDelivery('delivery-1', true);
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE notification_deliveries'), expect.any(Array));
        });
        it('should record failed delivery', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        status: 'pending',
                        attempt_count: 0,
                        max_attempts: 3,
                    }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT history
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // COMMIT
            await service.recordDelivery('delivery-1', false, 'Connection timeout');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE notification_deliveries'), expect.arrayContaining(['Connection timeout']));
        });
        it('should mark as failed after max attempts', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
            mockClient.query.mockResolvedValueOnce({
                rows: [{
                        status: 'pending',
                        attempt_count: 2,
                        max_attempts: 3,
                    }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE (will set to failed)
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT history
            mockClient.query.mockResolvedValueOnce({ rows: [] }); // COMMIT
            await service.recordDelivery('delivery-1', false, 'Failed');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE notification_deliveries'), expect.arrayContaining(['failed']));
        });
    });
    describe('markAsDelivered', () => {
        it('should mark delivery as delivered', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.markAsDelivered('delivery-1');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining("status = 'delivered'"), expect.any(Array));
        });
    });
    describe('markAsRead', () => {
        it('should mark delivery as read', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.markAsRead('delivery-1');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining("status = 'read'"), expect.any(Array));
        });
    });
    describe('getPendingDeliveries', () => {
        it('should retrieve pending deliveries', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'delivery-1',
                        user_id: 'user-1',
                        notification_id: 'notif-1',
                        content: 'Test',
                        channel: 'slack',
                        status: 'pending',
                        attempt_count: 0,
                        max_attempts: 3,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                    {
                        id: 'delivery-2',
                        user_id: 'user-2',
                        notification_id: 'notif-2',
                        content: 'Test 2',
                        channel: 'ide',
                        status: 'pending',
                        attempt_count: 1,
                        max_attempts: 3,
                        created_at: new Date(),
                        updated_at: new Date(),
                    },
                ],
            });
            const deliveries = await service.getPendingDeliveries();
            expect(deliveries).toHaveLength(2);
            expect(deliveries[0].status).toBe('pending');
        });
        it('should respect limit parameter', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.getPendingDeliveries(5);
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('LIMIT'), expect.arrayContaining([5]));
        });
    });
    describe('getDeliveryHistory', () => {
        it('should retrieve delivery history', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        id: 'hist-1',
                        delivery_id: 'delivery-1',
                        status_from: 'pending',
                        status_to: 'sent',
                        reason: 'Sent to channel',
                        attempt_number: 1,
                        created_at: new Date(),
                    },
                    {
                        id: 'hist-2',
                        delivery_id: 'delivery-1',
                        status_from: 'sent',
                        status_to: 'delivered',
                        reason: 'User opened',
                        attempt_number: 1,
                        created_at: new Date(),
                    },
                ],
            });
            const history = await service.getDeliveryHistory('delivery-1');
            expect(history).toHaveLength(2);
            expect(history[0].statusFrom).toBe('pending');
            expect(history[1].statusTo).toBe('delivered');
        });
        it('should return empty array for unknown delivery', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const history = await service.getDeliveryHistory('unknown');
            expect(history).toHaveLength(0);
        });
    });
});
//# sourceMappingURL=smart-notification-routing.test.js.map