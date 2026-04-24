import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as lz4 from 'lz4js';
import { MessageCompressionPipelineService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: () => ({
        info: vi.fn(),
        error: vi.fn(),
        debug: vi.fn(),
        warn: vi.fn()
    })
}));
describe('MessageCompressionPipelineService', () => {
    let service;
    let mockPool;
    let mockClient;
    const encodePayload = (payload) => {
        const encoded = Buffer.from(JSON.stringify(payload), 'utf8');
        return Buffer.from(lz4.compress(encoded)).toString('base64');
    };
    beforeEach(() => {
        mockClient = {
            query: vi.fn(),
            release: vi.fn()
        };
        mockPool = {
            connect: vi.fn().mockResolvedValue(mockClient)
        };
        service = new MessageCompressionPipelineService(mockPool);
    });
    it('should initialize compression tables', async () => {
        for (let i = 0; i < 7; i++) {
            mockClient.query.mockResolvedValueOnce({});
        }
        await service.initialize();
        expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('compressed_collaboration_messages'));
        expect(mockClient.release).toHaveBeenCalled();
    });
    it('should compress a message below 1 KB', async () => {
        const originalMessage = 'Focus update '.repeat(300);
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    original_size_bytes: Buffer.byteLength(originalMessage, 'utf8'),
                    compressed_size_bytes: 220,
                    compression_ratio: 0.05,
                    compressed_payload: 'compressed-payload',
                    metadata: { priority: 'high' },
                    under_one_kb: true,
                    created_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({});
        const compressed = await service.compressMessage('session-1', 'slack', originalMessage, { priority: 'high' });
        expect(compressed.id).toBe('message-1');
        expect(compressed.underOneKilobyte).toBe(true);
        expect(compressed.compressedSizeBytes).toBeLessThan(1024);
    });
    it('should decompress a stored message', async () => {
        const originalMessage = 'Deep work update for the team';
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    compressed_payload: encodePayload({ type: 'full', message: originalMessage }),
                    metadata: { topic: 'focus' }
                }]
        });
        const message = await service.decompressMessage('message-1');
        expect(message?.message).toBe(originalMessage);
        expect(message?.metadata.topic).toBe('focus');
    });
    it('should get a compressed message', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    original_size_bytes: 1200,
                    compressed_size_bytes: 220,
                    compression_ratio: 0.18,
                    compressed_payload: 'compressed-payload',
                    metadata: { topic: 'focus' },
                    under_one_kb: true,
                    created_at: new Date()
                }]
        });
        const message = await service.getCompressedMessage('message-1');
        expect(message?.sessionId).toBe('session-1');
        expect(message?.underOneKilobyte).toBe(true);
    });
    it('should get session messages', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [
                {
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    original_size_bytes: 1200,
                    compressed_size_bytes: 220,
                    compression_ratio: 0.18,
                    compressed_payload: 'compressed-payload',
                    metadata: { topic: 'focus' },
                    under_one_kb: true,
                    created_at: new Date()
                }
            ]
        });
        const messages = await service.getSessionMessages('session-1', 20);
        expect(messages).toHaveLength(1);
        expect(messages[0].channel).toBe('slack');
    });
    it('should calculate pipeline metrics', async () => {
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    total_messages: 3,
                    average_original_size_bytes: 1500,
                    average_compressed_size_bytes: 350,
                    average_compression_ratio: 0.23,
                    under_one_kb_count: 3,
                    compression_savings_bytes: 3450
                }]
        });
        const metrics = await service.getPipelineMetrics(7);
        expect(metrics.totalMessages).toBe(3);
        expect(metrics.underOneKilobyteCount).toBe(3);
    });
    it('should cleanup old messages', async () => {
        mockClient.query.mockResolvedValueOnce({ rowCount: 2 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 2 });
        const count = await service.cleanupOldMessages(30);
        expect(count).toBe(2);
    });
    it('should emit message-compressed event', async () => {
        let emittedEvent;
        service.on('message-compressed', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({});
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    original_size_bytes: 1000,
                    compressed_size_bytes: 200,
                    compression_ratio: 0.2,
                    compressed_payload: 'compressed-payload',
                    metadata: {},
                    under_one_kb: true,
                    created_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({});
        await service.compressMessage('session-1', 'slack', 'message'.repeat(200));
        expect(emittedEvent.id).toBe('message-1');
    });
    it('should emit message-decompressed event', async () => {
        let emittedEvent;
        service.on('message-decompressed', event => {
            emittedEvent = event;
        });
        const originalMessage = 'Deep work update for the team';
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    compressed_payload: encodePayload({ type: 'full', message: originalMessage }),
                    metadata: {}
                }]
        });
        await service.decompressMessage('message-1');
        expect(emittedEvent.id).toBe('message-1');
    });
    it('should emit pipeline-metrics-calculated event', async () => {
        let emittedEvent;
        service.on('pipeline-metrics-calculated', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    total_messages: 2,
                    average_original_size_bytes: 1000,
                    average_compressed_size_bytes: 250,
                    average_compression_ratio: 0.25,
                    under_one_kb_count: 2,
                    compression_savings_bytes: 1500
                }]
        });
        await service.getPipelineMetrics(7);
        expect(emittedEvent.totalMessages).toBe(2);
    });
    it('should return null for a missing message', async () => {
        mockClient.query.mockResolvedValueOnce({ rows: [] });
        const message = await service.getCompressedMessage('missing');
        expect(message).toBeNull();
    });
    it('should emit messages-cleaned event', async () => {
        let emittedEvent;
        service.on('messages-cleaned', event => {
            emittedEvent = event;
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 4 });
        mockClient.query.mockResolvedValueOnce({ rowCount: 4 });
        await service.cleanupOldMessages(30);
        expect(emittedEvent.count).toBe(4);
    });
    it('should compress a batch with delta payloads', async () => {
        mockClient.query.mockResolvedValueOnce({}); // BEGIN
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-1',
                    session_id: 'session-1',
                    channel: 'slack',
                    compression_method: 'lz4',
                    base_message_id: null,
                    original_size_bytes: 32,
                    compressed_size_bytes: 44,
                    compression_ratio: 1.375,
                    compressed_payload: encodePayload({ type: 'full', message: 'hello team' }),
                    metadata: {},
                    under_one_kb: true,
                    created_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({
            rows: [{
                    id: 'message-2',
                    session_id: 'session-1',
                    channel: 'slack',
                    compression_method: 'lz4-delta',
                    base_message_id: 'message-1',
                    original_size_bytes: 36,
                    compressed_size_bytes: 48,
                    compression_ratio: 1.333,
                    compressed_payload: encodePayload({ type: 'delta', baseMessageId: 'message-1', prefixLength: 10, suffix: ' and shipping' }),
                    metadata: {},
                    under_one_kb: true,
                    created_at: new Date()
                }]
        });
        mockClient.query.mockResolvedValueOnce({ rowCount: 1 });
        mockClient.query.mockResolvedValueOnce({}); // COMMIT
        const messages = await service.compressBatch([
            { sessionId: 'session-1', channel: 'slack', message: 'hello team' },
            { sessionId: 'session-1', channel: 'slack', message: 'hello team and shipping' }
        ]);
        expect(messages).toHaveLength(2);
        expect(messages[1].compressionMethod).toBe('lz4-delta');
        expect(messages[1].baseMessageId).toBe('message-1');
    });
});
//# sourceMappingURL=message-compression-pipeline.test.js.map