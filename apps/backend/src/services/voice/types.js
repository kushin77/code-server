/**
 * @file        apps/backend/src/services/voice/types.ts
 * @module      services/voice
 * @description Types for voice channel service with WebRTC + LiveKit SFU backend
 *
 */
/**
 * Get connection quality helper
 */
export function getConnectionQuality(latency, packetLoss) {
    if (latency < 30 && packetLoss < 1)
        return 'excellent';
    if (latency < 60 && packetLoss < 2)
        return 'good';
    if (latency < 100 && packetLoss < 5)
        return 'fair';
    if (latency < 200 && packetLoss < 10)
        return 'poor';
    return 'very-poor';
}
//# sourceMappingURL=types.js.map