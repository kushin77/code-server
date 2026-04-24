import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import express from 'express'
import request from 'supertest'
import { router } from '../workspace-map'

describe('Workspace Map Routes', () => {
  let app: express.Application
  let workspaceId: string

  beforeEach(() => {
    // Generate unique workspace ID for each test to avoid singleton conflicts
    workspaceId = `test-workspace-${Math.random().toString(36).substring(7)}`

    app = express()
    app.use(express.json())
    app.use('/api/workspace-map', router)
  })

  describe('POST /:workspaceId/init', () => {
    it('should initialize workspace map', async () => {
      const res = await request(app).post(`/api/workspace-map/${workspaceId}/init`)

      expect(res.status).toBe(200)
      expect(res.body.success).toBe(true)
      expect(res.body.workspaceId).toBe(workspaceId)
    })
  })

  describe('POST /:workspaceId/sessions', () => {
    it('should register a session', async () => {
      const res = await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })

      expect(res.status).toBe(200)
      expect(res.body.success).toBe(true)
      expect(res.body.session.userId).toBe('user-1')
      expect(res.body.session.status).toBe('online')
    })

    it('should return 400 if userId is missing', async () => {
      const res = await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions`)
        .send({
          userName: 'Alice',
        })

      expect(res.status).toBe(400)
      expect(res.body.error).toBeDefined()
    })

    it('should return 400 if userName is missing', async () => {
      const res = await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
      })

      expect(res.status).toBe(400)
      expect(res.body.error).toBeDefined()
    })
  })

  describe('POST /:workspaceId/sessions/:userId/activity', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })
    })

    it('should update user activity', async () => {
      const res = await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions/user-1/activity`)
        .send({
          currentFile: 'src/app.ts',
          cursorPosition: { line: 10, column: 5 },
        })

      expect(res.status).toBe(200)
      expect(res.body.success).toBe(true)
      expect(res.body.currentFile).toBe('src/app.ts')
    })

    it('should return 400 if currentFile is missing', async () => {
      const res = await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions/user-1/activity`)
        .send({})

      expect(res.status).toBe(400)
    })
  })

  describe('POST /:workspaceId/sessions/:userId/idle', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })
    })

    it('should mark user as idle', async () => {
      const res = await request(app).post(
        `/api/workspace-map/${workspaceId}/sessions/user-1/idle`
      )

      expect(res.status).toBe(200)
      expect(res.body.success).toBe(true)
      expect(res.body.status).toBe('idle')
    })
  })

  describe('POST /:workspaceId/sessions/:userId/unregister', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })
    })

    it('should unregister session', async () => {
      const res = await request(app).post(
        `/api/workspace-map/${workspaceId}/sessions/user-1/unregister`
      )

      expect(res.status).toBe(200)
      expect(res.body.success).toBe(true)
    })
  })

  describe('GET /:workspaceId/snapshot', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })

      await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions/user-1/activity`)
        .send({
          currentFile: 'src/app.ts',
        })
    })

    it('should get workspace snapshot', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/snapshot`)

      expect(res.status).toBe(200)
      expect(res.body.workspaceId).toBe(workspaceId)
      expect(res.body.totalActiveUsers).toBe(1)
      expect(res.body.activeSessions).toHaveLength(1)
    })

    it('should include metrics in snapshot', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/snapshot`)

      expect(res.body.metrics).toBeDefined()
      expect(res.body.metrics.peakConcurrentUsers).toBeGreaterThan(0)
    })
  })

  describe('GET /:workspaceId/files', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })

      await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions/user-1/activity`)
        .send({
          currentFile: 'src/app.ts',
        })
    })

    it('should get active files', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/files`)

      expect(res.status).toBe(200)
      expect(res.body.files).toHaveLength(1)
      expect(res.body.files[0].path).toBe('src/app.ts')
    })

    it('should filter files by pattern', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/files?pattern=app`)

      expect(res.status).toBe(200)
      expect(res.body.files).toHaveLength(1)
    })
  })

  describe('GET /:workspaceId/sessions', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })

      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-2',
        userName: 'Bob',
      })
    })

    it('should get active sessions', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/sessions`)

      expect(res.status).toBe(200)
      expect(res.body.sessions).toHaveLength(2)
      expect(res.body.totalSessions).toBe(2)
    })
  })

  describe('GET /:workspaceId/sessions/:userId', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })
    })

    it('should get session details', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/sessions/user-1`)

      expect(res.status).toBe(200)
      expect(res.body.userId).toBe('user-1')
      expect(res.body.userName).toBe('Alice')
    })

    it('should return 404 for non-existent session', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/sessions/non-existent`)

      expect(res.status).toBe(404)
      expect(res.body.error).toBeDefined()
    })
  })

  describe('GET /:workspaceId/files/:filePath/users', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })

      await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions/user-1/activity`)
        .send({
          currentFile: 'src/app.ts',
        })
    })

    it('should get users on file', async () => {
      const res = await request(app).get(
        `/api/workspace-map/${workspaceId}/files/user-1/users?filePath=src/app.ts`
      )

      expect(res.status).toBe(200)
      expect(res.body.users).toHaveLength(1)
      expect(res.body.totalUsers).toBe(1)
    })

    it('should return 400 if filePath is missing', async () => {
      const res = await request(app).get(
        `/api/workspace-map/${workspaceId}/files/user-1/users`
      )

      expect(res.status).toBe(400)
    })
  })

  describe('GET /:workspaceId/stats', () => {
    beforeEach(async () => {
      await request(app).post(`/api/workspace-map/${workspaceId}/sessions`).send({
        userId: 'user-1',
        userName: 'Alice',
      })

      await request(app)
        .post(`/api/workspace-map/${workspaceId}/sessions/user-1/activity`)
        .send({
          currentFile: 'src/app.ts',
        })
    })

    it('should get workspace statistics', async () => {
      const res = await request(app).get(`/api/workspace-map/${workspaceId}/stats`)

      expect(res.status).toBe(200)
      expect(res.body.workspaceId).toBe(workspaceId)
      expect(res.body.activeUsers).toBe(1)
      expect(res.body.activeFiles).toBe(1)
    })
  })
})
