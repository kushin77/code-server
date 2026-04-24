import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { WorkspaceMapService, createWorkspaceMapService } from '../workspace-map-service'

describe('WorkspaceMapService', () => {
  let service: WorkspaceMapService

  beforeEach(() => {
    service = createWorkspaceMapService({ workspaceId: 'test-workspace' })
  })

  afterEach(() => {
    service.shutdown()
  })

  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined()
      expect(service.getActiveSessions()).toHaveLength(0)
      expect(service.getActiveFiles()).toHaveLength(0)
    })

    it('should return same instance on subsequent calls', () => {
      const service2 = createWorkspaceMapService({ workspaceId: 'test-workspace' })
      expect(service).toBe(service2)
    })
  })

  describe('Session Registration', () => {
    it('should register a new session', () => {
      service.registerSession('user-1', 'Alice')
      const sessions = service.getActiveSessions()
      expect(sessions).toHaveLength(1)
      expect(sessions[0].userId).toBe('user-1')
      expect(sessions[0].userName).toBe('Alice')
      expect(sessions[0].status).toBe('online')
    })

    it('should emit session-registered event', () => {
      let emitted = false
      service.on('session-registered', () => {
        emitted = true
      })

      service.registerSession('user-1', 'Alice')
      expect(emitted).toBe(true)
    })

    it('should register multiple sessions', () => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
      expect(service.getActiveSessions()).toHaveLength(2)
    })
  })

  describe('User Activity', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
    })

    it('should update user activity with file', () => {
      service.updateUserActivity('user-1', 'src/app.ts', { line: 10, column: 5 })
      const session = service.getSession('user-1')
      expect(session?.currentFile).toBe('src/app.ts')
      expect(session?.cursorPosition).toEqual({ line: 10, column: 5 })
    })

    it('should track active files', () => {
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/utils.ts')

      const files = service.getActiveFiles()
      expect(files).toHaveLength(2)
    })

    it('should track multiple users on same file', () => {
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/app.ts')

      const users = service.getUsersOnFile('src/app.ts')
      expect(users).toHaveLength(2)
    })

    it('should emit user-activity-updated event', () => {
      let emitted = false
      service.on('user-activity-updated', () => {
        emitted = true
      })

      service.updateUserActivity('user-1', 'src/app.ts')
      expect(emitted).toBe(true)
    })

    it('should not update activity for non-existent session', () => {
      service.updateUserActivity('non-existent', 'src/app.ts')
      expect(service.getActiveFiles()).toHaveLength(0)
    })
  })

  describe('User Status', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
    })

    it('should mark user as idle', () => {
      service.markUserIdle('user-1')
      const session = service.getSession('user-1')
      expect(session?.status).toBe('idle')
    })

    it('should emit user-status-changed event', () => {
      let emitted = false
      service.on('user-status-changed', () => {
        emitted = true
      })

      service.markUserIdle('user-1')
      expect(emitted).toBe(true)
    })
  })

  describe('Session Unregistration', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/app.ts')
    })

    it('should unregister a session', () => {
      service.unregisterSession('user-1')
      expect(service.getActiveSessions()).toHaveLength(1)
      expect(service.getSession('user-1')).toBeUndefined()
    })

    it('should emit session-unregistered event', () => {
      let emitted = false
      service.on('session-unregistered', () => {
        emitted = true
      })

      service.unregisterSession('user-1')
      expect(emitted).toBe(true)
    })

    it('should remove user from active files', () => {
      service.unregisterSession('user-1')
      const users = service.getUsersOnFile('src/app.ts')
      expect(users).toHaveLength(1)
      expect(users[0].userId).toBe('user-2')
    })
  })

  describe('Workspace Snapshot', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/utils.ts')
    })

    it('should get workspace snapshot', () => {
      const snapshot = service.getWorkspaceSnapshot()
      expect(snapshot.workspaceId).toBe('test-workspace')
      expect(snapshot.totalActiveUsers).toBe(2)
      expect(snapshot.totalOpenFiles).toBe(2)
      expect(snapshot.activeSessions).toHaveLength(2)
      expect(snapshot.activeFiles).toHaveLength(2)
    })

    it('should include metrics in snapshot', () => {
      const snapshot = service.getWorkspaceSnapshot()
      expect(snapshot.metrics).toBeDefined()
      expect(snapshot.metrics.peakConcurrentUsers).toBeGreaterThan(0)
      expect(snapshot.metrics.averageSessionDuration).toBeGreaterThanOrEqual(0)
    })

    it('should identify most active file', () => {
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/app.ts')
      service.unregisterSession('user-1')

      const snapshot = service.getWorkspaceSnapshot()
      expect(snapshot.metrics.mostActiveFile).toBe('src/app.ts')
    })
  })

  describe('File Activity', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/utils.ts')
    })

    it('should get active files', () => {
      const files = service.getActiveFiles()
      expect(files).toHaveLength(2)
      expect(files.map((f) => f.path)).toContain('src/app.ts')
      expect(files.map((f) => f.path)).toContain('src/utils.ts')
    })

    it('should get file activity', () => {
      const file = service.getFileActivity('src/app.ts')
      expect(file).toBeDefined()
      expect(file?.path).toBe('src/app.ts')
      expect(file?.activeUsers).toContain('user-1')
    })

    it('should query active files by pattern', () => {
      const files = service.queryActiveFiles('app')
      expect(files).toHaveLength(1)
      expect(files[0].path).toBe('src/app.ts')
    })
  })

  describe('Statistics', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
      service.updateUserActivity('user-1', 'src/app.ts')
      service.updateUserActivity('user-2', 'src/utils.ts')
    })

    it('should get workspace statistics', () => {
      const stats = service.getStatistics()
      expect(stats.workspaceId).toBe('test-workspace')
      expect(stats.activeUsers).toBe(2)
      expect(stats.activeFiles).toBe(2)
      expect(stats.peakConcurrency).toBeGreaterThan(0)
    })

    it('should track peak concurrency', () => {
      service.registerSession('user-3', 'Charlie')
      const stats1 = service.getStatistics()
      expect(stats1.peakConcurrency).toBe(3)

      service.unregisterSession('user-3')
      const stats2 = service.getStatistics()
      expect(stats2.peakConcurrency).toBe(3) // Peak is recorded
    })
  })

  describe('Reset', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
      service.updateUserActivity('user-1', 'src/app.ts')
    })

    it('should reset workspace state', () => {
      service.reset()
      expect(service.getActiveSessions()).toHaveLength(0)
      expect(service.getActiveFiles()).toHaveLength(0)
      expect(service.getStatistics().activeUsers).toBe(0)
    })

    it('should emit workspace-reset event', () => {
      let emitted = false
      service.on('workspace-reset', () => {
        emitted = true
      })

      service.reset()
      expect(emitted).toBe(true)
    })
  })

  describe('Shutdown', () => {
    beforeEach(() => {
      service.registerSession('user-1', 'Alice')
    })

    it('should shutdown service', () => {
      service.shutdown()
      expect(service.getActiveSessions()).toHaveLength(0)
    })

    it('should emit shutdown event', () => {
      let emitted = false
      service.on('shutdown', () => {
        emitted = true
      })

      service.shutdown()
      expect(emitted).toBe(true)
    })

    it('should remove instance after shutdown', () => {
      const service2 = createWorkspaceMapService({ workspaceId: 'test-workspace' })
      service.shutdown()
      const service3 = createWorkspaceMapService({ workspaceId: 'test-workspace' })
      expect(service2).not.toBe(service3)
    })
  })

  describe('Peak Concurrency', () => {
    it('should emit peak-concurrency-updated event', () => {
      let emitted = false
      let peakValue = 0
      service.on('peak-concurrency-updated', (data) => {
        emitted = true
        peakValue = data.peakConcurrentUsers
      })

      service.registerSession('user-1', 'Alice')
      expect(emitted).toBe(true)
      expect(peakValue).toBe(1)
    })

    it('should track increasing peak concurrency', () => {
      service.registerSession('user-1', 'Alice')
      service.registerSession('user-2', 'Bob')
      service.registerSession('user-3', 'Charlie')

      const stats = service.getStatistics()
      expect(stats.peakConcurrency).toBe(3)
    })
  })

  describe('Get Session', () => {
    it('should return undefined for non-existent session', () => {
      const session = service.getSession('non-existent')
      expect(session).toBeUndefined()
    })

    it('should return session details', () => {
      service.registerSession('user-1', 'Alice')
      const session = service.getSession('user-1')
      expect(session?.userId).toBe('user-1')
      expect(session?.userName).toBe('Alice')
    })
  })
})
