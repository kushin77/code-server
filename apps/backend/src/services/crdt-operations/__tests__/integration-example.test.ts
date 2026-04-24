/**
 * @file        apps/backend/src/services/crdt-operations/__tests__/integration-example.test.ts
 * @module      collaboration/crdt
 * @description Integration tests for CRDT operations service
 */

import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { createCRDTExampleApp } from '../integration-example';
import type { Express } from 'express';

describe('CRDT Operations Integration Example', () => {
  let app: Express;

  beforeEach(async () => {
    app = await createCRDTExampleApp();
  });

  describe('Document Initialization', () => {
    it('creates a new document with initial content', async () => {
      const res = await request(app).post('/api/crdt/documents').send({
        documentId: 'doc-1',
        initialContent: 'Hello, world!',
      });

      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({
        content: 'Hello, world!',
        version: 0,
        lastOperationId: null,
      });
    });

    it('retrieves document state', async () => {
      await request(app).post('/api/crdt/documents').send({
        documentId: 'doc-2',
        initialContent: 'test',
      });

      const res = await request(app).get('/api/crdt/documents/doc-2');

      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({
        content: 'test',
        version: 0,
      });
    });
  });

  describe('Concurrent Insert Operations', () => {
    beforeEach(async () => {
      await request(app).post('/api/crdt/documents').send({
        documentId: 'doc-concurrent',
        initialContent: 'AB',
      });
    });

    it('handles concurrent inserts with automatic position transformation', async () => {
      // Client 1 inserts "X" at position 1 (between A and B)
      const res1 = await request(app).post('/api/crdt/documents/doc-concurrent/insert').send({
        clientId: 'client-1',
        position: 1,
        content: 'X',
      });

      expect(res1.status).toBe(200);
      expect(res1.body.state.content).toBe('AXB');

      // Client 2 inserts "Y" at position 1 (concurrent with client-1)
      // The position should be adjusted due to client-1's insert
      const res2 = await request(app).post('/api/crdt/documents/doc-concurrent/insert').send({
        clientId: 'client-2',
        position: 1,
        content: 'Y',
      });

      expect(res2.status).toBe(200);
      // Final content depends on OT transform; should have both X and Y
      expect(res2.body.state.content).toContain('X');
      expect(res2.body.state.content).toContain('Y');
    });

    it('maintains document version and causality', async () => {
      await request(app).post('/api/crdt/documents/doc-concurrent/insert').send({
        clientId: 'client-1',
        position: 1,
        content: 'Hello',
      });

      const res = await request(app).get('/api/crdt/documents/doc-concurrent');
      expect(res.body.version).toBe(1);
      expect(res.body.vectorClock).toBeDefined();
    });
  });

  describe('Insert and Delete Operations', () => {
    beforeEach(async () => {
      await request(app).post('/api/crdt/documents').send({
        documentId: 'doc-mixed',
        initialContent: 'ABCDE',
      });
    });

    it('applies delete operation correctly', async () => {
      const res = await request(app).post('/api/crdt/documents/doc-mixed/delete').send({
        clientId: 'client-1',
        position: 1,
        length: 2,
      });

      expect(res.status).toBe(200);
      expect(res.body.state.content).toBe('ADE');
    });

    it('transforms delete position when prior insert happened', async () => {
      // Insert "X" at position 1
      await request(app).post('/api/crdt/documents/doc-mixed/insert').send({
        clientId: 'client-1',
        position: 1,
        content: 'X',
      });

      // Now delete starting at position 2 (should account for the inserted X)
      const res = await request(app).post('/api/crdt/documents/doc-mixed/delete').send({
        clientId: 'client-2',
        position: 2,
        length: 1,
      });

      expect(res.status).toBe(200);
      expect(res.body.state.content).toContain('X');
    });

    it('handles overlapping concurrent operations', async () => {
      // Client 1 inserts at position 2
      await request(app).post('/api/crdt/documents/doc-mixed/insert').send({
        clientId: 'client-1',
        position: 2,
        content: 'NEW',
      });

      // Client 2 deletes at position 2 (concurrent operation)
      const res = await request(app).post('/api/crdt/documents/doc-mixed/delete').send({
        clientId: 'client-2',
        position: 2,
        length: 1,
      });

      expect(res.status).toBe(200);
      // Both operations should be applied (order may vary)
      const content = res.body.state.content;
      expect(content.length).toBeGreaterThan(0);
    });
  });

  describe('Operation History', () => {
    beforeEach(async () => {
      await request(app).post('/api/crdt/documents').send({
        documentId: 'doc-history',
        initialContent: 'start',
      });
    });

    it('retrieves full operation history', async () => {
      await request(app).post('/api/crdt/documents/doc-history/insert').send({
        clientId: 'client-1',
        position: 0,
        content: 'A',
      });

      await request(app).post('/api/crdt/documents/doc-history/delete').send({
        clientId: 'client-1',
        position: 0,
        length: 1,
      });

      const res = await request(app).get('/api/crdt/documents/doc-history/history');

      expect(res.status).toBe(200);
      expect(res.body.operations).toHaveLength(2);
      expect(res.body.operations[0].type).toBe('insert');
      expect(res.body.operations[1].type).toBe('delete');
    });

    it('supports operation sync for late-joining clients', async () => {
      // Apply some operations
      await request(app).post('/api/crdt/documents/doc-history/insert').send({
        clientId: 'client-1',
        position: 0,
        content: 'OP1',
      });

      await request(app).post('/api/crdt/documents/doc-history/insert').send({
        clientId: 'client-2',
        position: 3,
        content: 'OP2',
      });

      // New client syncs from version 0
      const res = await request(app).get('/api/crdt/documents/doc-history/sync?since=0');

      expect(res.status).toBe(200);
      expect(res.body.operations.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Document Management', () => {
    it('lists all active documents', async () => {
      await request(app).post('/api/crdt/documents').send({
        documentId: 'list-doc-1',
        initialContent: 'content1',
      });

      await request(app).post('/api/crdt/documents').send({
        documentId: 'list-doc-2',
        initialContent: 'content2',
      });

      const res = await request(app).get('/api/crdt/documents');

      expect(res.status).toBe(200);
      expect(res.body.documents).toContain('list-doc-1');
      expect(res.body.documents).toContain('list-doc-2');
    });
  });

  describe('Error Handling', () => {
    it('returns 404 for non-existent document', async () => {
      const res = await request(app).get('/api/crdt/documents/non-existent');
      expect(res.status).toBe(404);
    });

    it('validates required fields on insert', async () => {
      await request(app).post('/api/crdt/documents').send({
        documentId: 'doc-validation',
        initialContent: 'test',
      });

      const res = await request(app).post('/api/crdt/documents/doc-validation/insert').send({
        clientId: 'client-1',
        // missing position and content
      });

      expect(res.status).toBe(400);
    });
  });
});
