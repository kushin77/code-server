import { Router } from 'express';
import { getAnomalyDetectionService } from '../services/anomaly-detection';
const router = Router();
router.post('/detect', async (req, res) => {
    try {
        const { currentEvent, recentEvents } = req.body;
        if (!currentEvent || !Array.isArray(recentEvents)) {
            return res.status(400).json({ error: 'Invalid request body' });
        }
        const service = getAnomalyDetectionService();
        const result = await service.detectAnomalies(currentEvent, recentEvents);
        res.json(result);
    }
    catch (error) {
        res.status(500).json({ error: 'Anomaly detection failed' });
    }
});
router.get('/profile/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const service = getAnomalyDetectionService();
        const stats = service.getProfileStats(userId);
        if (!stats) {
            return res.status(404).json({ error: 'No profile found' });
        }
        res.json(stats);
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve profile' });
    }
});
router.post('/retrain/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const { recentEvents } = req.body;
        if (!Array.isArray(recentEvents)) {
            return res.status(400).json({ error: 'recentEvents must be an array' });
        }
        const service = getAnomalyDetectionService();
        await service.retrain(userId, recentEvents);
        const stats = service.getProfileStats(userId);
        res.json({ message: 'Profile retraining completed', profileStats: stats });
    }
    catch (error) {
        res.status(500).json({ error: 'Profile retraining failed' });
    }
});
export default router;
//# sourceMappingURL=anomaly.js.map