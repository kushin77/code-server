import { EventEmitter } from 'events'
import pino from 'pino'

interface ActiveFile {
  path: string
  isOpen: boolean
  activeUsers: string[]
  lastModified: Date
}

interface UserSession {
  userId: string
  userName: string
  status: 'online' | 'idle' | 'offline'
  currentFile?: string
  cursorPosition?: { line: number; column: number }
  joinedAt: Date
  lastActive: Date
}

interface WorkspaceSnapshot {
  workspaceId: string
  timestamp: Date
  activeSessions: UserSession[]
  activeFiles: ActiveFile[]
  totalActiveUsers: number
  totalOpenFiles: number
  metrics: {
    averageSessionDuration: number
    peakConcurrentUsers: number
    mostActiveFile: string | null
  }
}

interface WorkspaceMapServiceOptions {
  workspaceId: string
  logger?: pino.Logger
}

export class WorkspaceMapService extends EventEmitter {
  private static instances = new Map<string, WorkspaceMapService>()
  private workspaceId: string
  private logger: pino.Logger
  private activeSessions = new Map<string, UserSession>()
  private activeFiles = new Map<string, ActiveFile>()
  private sessionHistory: UserSession[] = []
  private metrics = {
    peakConcurrentUsers: 0,
    sessionStartTimes: new Map<string, Date>(),
  }

  private constructor(options: WorkspaceMapServiceOptions) {
    super()
    this.workspaceId = options.workspaceId
    this.logger = options.logger || pino({
      base: { service: 'workspace-map', workspace: options.workspaceId },
    })
  }

  static getInstance(options: WorkspaceMapServiceOptions): WorkspaceMapService {
    if (!this.instances.has(options.workspaceId)) {
      this.instances.set(options.workspaceId, new WorkspaceMapService(options))
    }
    return this.instances.get(options.workspaceId)!
  }

  /**
   * Register a new user session
   */
  registerSession(userId: string, userName: string): void {
    const session: UserSession = {
      userId,
      userName,
      status: 'online',
      joinedAt: new Date(),
      lastActive: new Date(),
    }

    this.activeSessions.set(userId, session)
    this.metrics.sessionStartTimes.set(userId, new Date())
    this.updateMetrics()

    this.logger.info(`User ${userId} registered session in workspace ${this.workspaceId}`)
    this.emit('session-registered', { userId, session })
  }

  /**
   * Update user's current file and cursor position
   */
  updateUserActivity(
    userId: string,
    currentFile: string,
    cursorPosition?: { line: number; column: number }
  ): void {
    const session = this.activeSessions.get(userId)
    if (!session) {
      this.logger.warn(`Session not found for user ${userId}`)
      return
    }

    // Update session
    session.currentFile = currentFile
    session.cursorPosition = cursorPosition
    session.lastActive = new Date()
    session.status = 'online'

    // Track file activity
    if (!this.activeFiles.has(currentFile)) {
      this.activeFiles.set(currentFile, {
        path: currentFile,
        isOpen: true,
        activeUsers: [userId],
        lastModified: new Date(),
      })
    } else {
      const file = this.activeFiles.get(currentFile)!
      if (!file.activeUsers.includes(userId)) {
        file.activeUsers.push(userId)
      }
      file.lastModified = new Date()
    }

    this.emit('user-activity-updated', { userId, currentFile, cursorPosition })
  }

  /**
   * Mark user as idle
   */
  markUserIdle(userId: string): void {
    const session = this.activeSessions.get(userId)
    if (!session) return

    session.status = 'idle'
    session.lastActive = new Date()

    this.emit('user-status-changed', { userId, status: 'idle' })
  }

  /**
   * Mark user as offline
   */
  unregisterSession(userId: string): void {
    const session = this.activeSessions.get(userId)
    if (!session) return

    // Remove from active files
    this.activeFiles.forEach((file) => {
      const idx = file.activeUsers.indexOf(userId)
      if (idx !== -1) {
        file.activeUsers.splice(idx, 1)
      }
    })

    this.sessionHistory.push(session)
    this.activeSessions.delete(userId)
    this.metrics.sessionStartTimes.delete(userId)

    this.logger.info(`User ${userId} unregistered session in workspace ${this.workspaceId}`)
    this.emit('session-unregistered', { userId })
  }

  /**
   * Get current workspace snapshot
   */
  getWorkspaceSnapshot(): WorkspaceSnapshot {
    const activeSessions = Array.from(this.activeSessions.values())
    const activeFiles = Array.from(this.activeFiles.values()).filter((f) => f.activeUsers.length > 0)

    // Calculate metrics
    let mostActiveFile: string | null = null
    let maxUsers = 0
    activeFiles.forEach((file) => {
      if (file.activeUsers.length > maxUsers) {
        maxUsers = file.activeUsers.length
        mostActiveFile = file.path
      }
    })

    const avgSessionDuration =
      this.sessionHistory.length > 0
        ? this.sessionHistory.reduce((sum, s) => {
            const startTime = this.metrics.sessionStartTimes.get(s.userId) || s.joinedAt
            const endTime = new Date()
            return sum + (endTime.getTime() - startTime.getTime())
          }, 0) / this.sessionHistory.length
        : 0

    return {
      workspaceId: this.workspaceId,
      timestamp: new Date(),
      activeSessions,
      activeFiles,
      totalActiveUsers: activeSessions.length,
      totalOpenFiles: activeFiles.length,
      metrics: {
        averageSessionDuration: avgSessionDuration,
        peakConcurrentUsers: this.metrics.peakConcurrentUsers,
        mostActiveFile,
      },
    }
  }

  /**
   * Get active files
   */
  getActiveFiles(): ActiveFile[] {
    return Array.from(this.activeFiles.values()).filter((f) => f.activeUsers.length > 0)
  }

  /**
   * Get active sessions
   */
  getActiveSessions(): UserSession[] {
    return Array.from(this.activeSessions.values())
  }

  /**
   * Get session by user ID
   */
  getSession(userId: string): UserSession | undefined {
    return this.activeSessions.get(userId)
  }

  /**
   * Get file activity
   */
  getFileActivity(filePath: string): ActiveFile | undefined {
    return this.activeFiles.get(filePath)
  }

  /**
   * Get all users working on a specific file
   */
  getUsersOnFile(filePath: string): UserSession[] {
    const file = this.activeFiles.get(filePath)
    if (!file) return []

    return file.activeUsers
      .map((userId) => this.activeSessions.get(userId))
      .filter((session) => session !== undefined) as UserSession[]
  }

  /**
   * Query active files by pattern
   */
  queryActiveFiles(pattern: string): ActiveFile[] {
    const regex = new RegExp(pattern)
    return this.getActiveFiles().filter((file) => regex.test(file.path))
  }

  /**
   * Get workspace statistics
   */
  getStatistics() {
    return {
      workspaceId: this.workspaceId,
      activeUsers: this.activeSessions.size,
      activeFiles: Array.from(this.activeFiles.values()).filter((f) => f.activeUsers.length > 0)
        .length,
      peakConcurrency: this.metrics.peakConcurrentUsers,
      totalSessionsRecorded: this.sessionHistory.length,
    }
  }

  /**
   * Update metrics
   */
  private updateMetrics(): void {
    const currentUsers = this.activeSessions.size
    if (currentUsers > this.metrics.peakConcurrentUsers) {
      this.metrics.peakConcurrentUsers = currentUsers
      this.emit('peak-concurrency-updated', { peakConcurrentUsers: currentUsers })
    }
  }

  /**
   * Reset workspace state
   */
  reset(): void {
    this.activeSessions.clear()
    this.activeFiles.clear()
    this.sessionHistory = []
    this.metrics = { peakConcurrentUsers: 0, sessionStartTimes: new Map() }
    this.emit('workspace-reset')
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.reset()
    WorkspaceMapService.instances.delete(this.workspaceId)
    this.emit('shutdown')
  }
}

export function createWorkspaceMapService(
  options: WorkspaceMapServiceOptions
): WorkspaceMapService {
  return WorkspaceMapService.getInstance(options)
}
