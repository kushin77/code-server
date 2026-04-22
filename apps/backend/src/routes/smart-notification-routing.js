#!/usr/bin/env node
// @file        apps/backend/src/routes/smart-notification-routing.ts
// @module      collaboration/notification-routing
// @description REST API routes for smart notification routing service
// @owner       collab-4.6
// @status      active
import { Router } from 'express';
import { SmartNotificationRoutingService } from '../services/smart-notification-routing';
import { getLogger } from '../lib/logger';
const logger = getLogger('SmartNotificationRoutingRoutes');
export function initializeSmartNotificationRoutingRoutes(pool) {
    const router = Router();
    const notificationService = new SmartNotificationRoutingService(pool);
    notificationService.initialize().catch(error => {
        logger.error('Failed to initialize notification routing service', { error });
    });
    // POST /api/notification/status - Update user status
    router.post('/status', async (req, res) => {
        try {
            const { userId, status, location, calendarStatus, currentDevice } = req.body;
            if (!userId || !status) {
                return res.status(400).json({
                    error: 'Missing required fields: userId, status',
                });
            }
            await notificationService.updateUserStatus(userId, status, {
                location,
                calendarStatus,
                currentDevice,
            });
            res.json({
                success: true,
                message: 'User status updated',
            });
        }
        catch (error) {
            logger.error('Failed to update user status', { error, body: req.body });
            res.status(500).json({ error: 'Failed to update status' });
        }
    });
    // GET /api/notification/status/:userId - Get user status
    router.get('/status/:userId', async (req, res) => {
        try {
            const { userId } = req.params;
            const status = await notificationService.getUserStatus(userId);
            if (!status) {
                return res.status(404).json({ error: 'User status not found' });
            }
            res.json({
                success: true,
                status,
            });
        }
        catch (error) {
            logger.error('Failed to get user status', { error, userId: req.params.userId });
            res.status(500).json({ error: 'Failed to get status' });
        }
    });
    // POST /api/notification/routes - Set notification route
    router.post('/routes', async (req, res) => {
        try {
            const { userId, priority, channels, conditions } = req.body;
            if (!userId || !priority || !Array.isArray(channels)) {
                return res.status(400).json({
                    error: 'Missing required fields: userId, priority, channels (array)',
                });
            }
            const route = await notificationService.setNotificationRoute(userId, priority, channels, conditions);
            res.status(201).json({
                success: true,
                route,
            });
        }
        catch (error) {
            logger.error('Failed to set notification route', { error, body: req.body });
            res.status(500).json({ error: 'Failed to set route' });
        }
    });
    // GET /api/notification/routes/:userId/:priority - Get notification route
    router.get('/routes/:userId/:priority', async (req, res) => {
        try {
            const { userId, priority } = req.params;
            const route = await notificationService.getNotificationRoute(userId, priority);
            if (!route) {
                return res.status(404).json({ error: 'Route not found' });
            }
            res.json({
                success: true,
                route,
            });
        }
        catch (error) {
            logger.error('Failed to get notification route', { error, params: req.params });
            res.status(500).json({ error: 'Failed to get route' });
        }
    });
    // GET /api/notification/routes/:userId - Get all routes for user
    router.get('/routes/:userId', async (req, res) => {
        try {
            const { userId } = req.params;
            const routes = await notificationService.getUserRoutes(userId);
            res.json({
                success: true,
                count: routes.length,
                routes,
            });
        }
        catch (error) {
            logger.error('Failed to get user routes', { error, userId: req.params.userId });
            res.status(500).json({ error: 'Failed to get routes' });
        }
    });
    // POST /api/notification/send - Route and send notification
    router.post('/send', async (req, res) => {
        try {
            const { userId, notificationId, content, priority = 'normal' } = req.body;
            if (!userId || !notificationId || !content) {
                return res.status(400).json({
                    error: 'Missing required fields: userId, notificationId, content',
                });
            }
            const deliveries = await notificationService.routeNotification(userId, notificationId, content, priority);
            res.status(201).json({
                success: true,
                count: deliveries.length,
                deliveries,
            });
        }
        catch (error) {
            logger.error('Failed to route notification', { error, body: req.body });
            res.status(500).json({ error: 'Failed to send notification' });
        }
    });
    // POST /api/notification/delivery/:deliveryId/record - Record delivery attempt
    router.post('/delivery/:deliveryId/record', async (req, res) => {
        try {
            const { deliveryId } = req.params;
            const { success, failureReason } = req.body;
            if (success === undefined) {
                return res.status(400).json({
                    error: 'Missing required field: success (boolean)',
                });
            }
            await notificationService.recordDelivery(deliveryId, success, failureReason);
            res.json({
                success: true,
                message: 'Delivery recorded',
            });
        }
        catch (error) {
            logger.error('Failed to record delivery', { error, deliveryId: req.params.deliveryId });
            res.status(500).json({ error: 'Failed to record delivery' });
        }
    });
    // POST /api/notification/delivery/:deliveryId/delivered - Mark as delivered
    router.post('/delivery/:deliveryId/delivered', async (req, res) => {
        try {
            const { deliveryId } = req.params;
            await notificationService.markAsDelivered(deliveryId);
            res.json({
                success: true,
                message: 'Marked as delivered',
            });
        }
        catch (error) {
            logger.error('Failed to mark delivery as delivered', { error, deliveryId: req.params.deliveryId });
            res.status(500).json({ error: 'Failed to update delivery' });
        }
    });
    // POST /api/notification/delivery/:deliveryId/read - Mark as read
    router.post('/delivery/:deliveryId/read', async (req, res) => {
        try {
            const { deliveryId } = req.params;
            await notificationService.markAsRead(deliveryId);
            res.json({
                success: true,
                message: 'Marked as read',
            });
        }
        catch (error) {
            logger.error('Failed to mark delivery as read', { error, deliveryId: req.params.deliveryId });
            res.status(500).json({ error: 'Failed to update delivery' });
        }
    });
    // GET /api/notification/pending - Get pending deliveries
    router.get('/pending', async (req, res) => {
        try {
            const { limit = '10' } = req.query;
            const deliveries = await notificationService.getPendingDeliveries(parseInt(limit, 10));
            res.json({
                success: true,
                count: deliveries.length,
                deliveries,
            });
        }
        catch (error) {
            logger.error('Failed to get pending deliveries', { error });
            res.status(500).json({ error: 'Failed to get pending deliveries' });
        }
    });
    // GET /api/notification/delivery/:deliveryId/history - Get delivery history
    router.get('/delivery/:deliveryId/history', async (req, res) => {
        try {
            const { deliveryId } = req.params;
            const history = await notificationService.getDeliveryHistory(deliveryId);
            res.json({
                success: true,
                count: history.length,
                history,
            });
        }
        catch (error) {
            logger.error('Failed to get delivery history', { error, deliveryId: req.params.deliveryId });
            res.status(500).json({ error: 'Failed to get history' });
        }
    });
    return router;
}
export { SmartNotificationRoutingService } from '../services/smart-notification-routing';
//# sourceMappingURL=smart-notification-routing.js.map