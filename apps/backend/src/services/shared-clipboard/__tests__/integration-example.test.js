// @file        apps/backend/src/services/shared-clipboard/__tests__/integration-example.test.ts
// @module      collaboration/shared-clipboard/tests
// @description Tests for shared clipboard session integration example
import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createSharedClipboardExampleApp } from '../integration-example.js';
describe('shared clipboard integration example', () => {
    it('creates a shared clipboard session and synchronizes copied text', async () => {
        const app = await createSharedClipboardExampleApp();
        const createResponse = await request(app).post('/api/shared-clipboard/sessions').send({
            workspaceId: 'workspace-1',
            userId: 'user-1',
            userName: 'Alice',
        });
        expect(createResponse.status).toBe(201);
        const sessionId = createResponse.body.session.sessionId;
        const joinResponse = await request(app).post(`/api/shared-clipboard/sessions/${sessionId}/join`).send({
            userId: 'user-2',
            userName: 'Bob',
        });
        expect(joinResponse.status).toBe(200);
        expect(joinResponse.body.session.participants).toHaveLength(2);
        const copyResponse = await request(app).post(`/api/shared-clipboard/sessions/${sessionId}/copy`).send({
            userId: 'user-2',
            userName: 'Bob',
            text: 'console.log("shared clipboard")',
        });
        expect(copyResponse.status).toBe(201);
        expect(copyResponse.body.entry.text).toBe('console.log("shared clipboard")');
        const historyResponse = await request(app).get(`/api/shared-clipboard/sessions/${sessionId}/history`);
        expect(historyResponse.status).toBe(200);
        expect(historyResponse.body.history).toHaveLength(1);
        expect(historyResponse.body.history[0].text).toBe('console.log("shared clipboard")');
    });
    it('blocks credential-like clipboard content', async () => {
        const app = await createSharedClipboardExampleApp();
        const createResponse = await request(app).post('/api/shared-clipboard/sessions').send({
            workspaceId: 'workspace-1',
            userId: 'user-1',
            userName: 'Alice',
        });
        const sessionId = createResponse.body.session.sessionId;
        const blockedResponse = await request(app).post(`/api/shared-clipboard/sessions/${sessionId}/copy`).send({
            userId: 'user-1',
            userName: 'Alice',
            text: 'ghp_abcdefghijklmnopqrstuvwxyz1234567890',
        });
        expect(blockedResponse.status).toBe(400);
        expect(blockedResponse.body.error).toContain('blocked');
        const historyResponse = await request(app).get(`/api/shared-clipboard/sessions/${sessionId}/history`);
        expect(historyResponse.body.history).toHaveLength(0);
    });
    it('caps clipboard history at 20 entries', async () => {
        const app = await createSharedClipboardExampleApp();
        const createResponse = await request(app).post('/api/shared-clipboard/sessions').send({
            workspaceId: 'workspace-1',
            userId: 'user-1',
            userName: 'Alice',
        });
        const sessionId = createResponse.body.session.sessionId;
        for (let index = 1; index <= 21; index += 1) {
            const copyResponse = await request(app).post(`/api/shared-clipboard/sessions/${sessionId}/copy`).send({
                userId: 'user-1',
                userName: 'Alice',
                text: `clipboard-${index}`,
            });
            expect(copyResponse.status).toBe(201);
        }
        const historyResponse = await request(app).get(`/api/shared-clipboard/sessions/${sessionId}/history`);
        expect(historyResponse.status).toBe(200);
        expect(historyResponse.body.history).toHaveLength(20);
        expect(historyResponse.body.history[0].text).toBe('clipboard-2');
        expect(historyResponse.body.history[19].text).toBe('clipboard-21');
    });
});
//# sourceMappingURL=integration-example.test.js.map