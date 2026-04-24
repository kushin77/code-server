// @file        apps/backend/src/services/debug-session-collaboration/__tests__/integration-example.test.ts
// @module      backend/services/debug-session-collaboration
// @description Integration coverage for the collaborative debugging example app
// @owner       backend

import request from 'supertest'
import { describe, expect, it } from 'vitest'

import { createDebugSessionCollaborationExampleApp } from '../integration-example'

describe('Debug session collaboration integration example', () => {
  it('exposes debug session routes and health checks', async () => {
    const app = await createDebugSessionCollaborationExampleApp()

    await request(app)
      .get('/health')
      .expect(200)
      .expect(({ body }) => {
        expect(body.services).toContain('debug-session-collaboration')
      })

    const created = await request(app)
      .post('/api/debug-sessions')
      .send({
        workspaceId: 'portal-main',
        actor: 'Portal main',
        debuggerName: 'Portal debugger',
        debuggerProgram: 'src/main.ts',
        debuggerCwd: '/workspace/portal',
      })
      .expect(201)

    expect(created.body.sessionId).toBeTruthy()
    expect(created.body.participants).toHaveLength(1)

    await request(app)
      .get(`/api/debug-sessions/${created.body.sessionId}`)
      .expect(200)
      .expect(({ body }) => {
        expect(body.sessionId).toBe(created.body.sessionId)
        expect(body.owner).toBe('Portal main')
      })

    await request(app)
      .get(`/api/debug-sessions/${created.body.sessionId}/relay/messages`)
      .query({ actor: 'Portal main', since: 0 })
      .expect(200)
      .expect(({ body }) => {
        expect(body.sessionId).toBe(created.body.sessionId)
        expect(body.latestSequence).toBe(0)
        expect(body.messages).toEqual([])
      })
  })
})