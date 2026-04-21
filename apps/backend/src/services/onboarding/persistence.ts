// @file        apps/backend/src/services/onboarding/persistence.ts
// @module      services/onboarding
// @description Progress persistence utilities for onboarding sessions
//              Saves and loads session state to persistent storage
//

import * as fs from 'fs'
import * as path from 'path'
import { promisify } from 'util'
import { OnboardingSession } from './onboarding-service'
import { logger } from '../../lib/logger'

const writeFile = promisify(fs.writeFile)
const readFile = promisify(fs.readFile)
const mkdir = promisify(fs.mkdir)

/**
 * OnboardingPersistence - handles saving and loading session state
 */
export class OnboardingPersistence {
  private storageDir: string

  constructor(storageDir: string = './.onboarding-sessions') {
    this.storageDir = storageDir
  }

  /**
   * Initialize storage directory
   */
  async initialize(): Promise<void> {
    try {
      if (!fs.existsSync(this.storageDir)) {
        await mkdir(this.storageDir, { recursive: true })
        logger.info('Onboarding session storage directory created', { dir: this.storageDir })
      }
    } catch (error) {
      logger.error('Failed to initialize onboarding storage', error)
      throw error
    }
  }

  /**
   * Save session to persistent storage
   */
  async saveSession(session: OnboardingSession): Promise<void> {
    try {
      await this.initialize()

      const filePath = this.getSessionFilePath(session.sessionId)
      const data = JSON.stringify(session, null, 2)

      await writeFile(filePath, data, 'utf-8')

      logger.debug('Onboarding session saved', {
        sessionId: session.sessionId,
        filePath,
      })
    } catch (error) {
      logger.error('Failed to save onboarding session', error)
      throw error
    }
  }

  /**
   * Load session from persistent storage
   */
  async loadSession(sessionId: string): Promise<OnboardingSession | null> {
    try {
      const filePath = this.getSessionFilePath(sessionId)

      if (!fs.existsSync(filePath)) {
        return null
      }

      const data = await readFile(filePath, 'utf-8')
      const session = JSON.parse(data) as OnboardingSession

      logger.debug('Onboarding session loaded', {
        sessionId,
        filePath,
      })

      return session
    } catch (error) {
      logger.error('Failed to load onboarding session', error)
      throw error
    }
  }

  /**
   * Save session progress checkpoint
   */
  async saveCheckpoint(
    sessionId: string,
    checkpoint: {
      stepIndex: number
      completedSteps: string[]
      skippedSteps: string[]
      timestamp: number
    },
  ): Promise<void> {
    try {
      await this.initialize()

      const checkpointDir = path.join(this.storageDir, sessionId, 'checkpoints')
      if (!fs.existsSync(checkpointDir)) {
        await mkdir(checkpointDir, { recursive: true })
      }

      const filePath = path.join(checkpointDir, `checkpoint-${checkpoint.timestamp}.json`)
      const data = JSON.stringify(checkpoint, null, 2)

      await writeFile(filePath, data, 'utf-8')

      logger.debug('Onboarding checkpoint saved', {
        sessionId,
        checkpointTime: new Date(checkpoint.timestamp).toISOString(),
      })
    } catch (error) {
      logger.error('Failed to save onboarding checkpoint', error)
      throw error
    }
  }

  /**
   * Load latest checkpoint
   */
  async loadLatestCheckpoint(sessionId: string): Promise<any | null> {
    try {
      const checkpointDir = path.join(this.storageDir, sessionId, 'checkpoints')

      if (!fs.existsSync(checkpointDir)) {
        return null
      }

      const files = fs.readdirSync(checkpointDir).sort().reverse()

      if (files.length === 0) {
        return null
      }

      const latestFile = files[0]
      const filePath = path.join(checkpointDir, latestFile)
      const data = await readFile(filePath, 'utf-8')

      return JSON.parse(data)
    } catch (error) {
      logger.error('Failed to load latest checkpoint', error)
      throw error
    }
  }

  /**
   * List all checkpoints for a session
   */
  async listCheckpoints(sessionId: string): Promise<string[]> {
    try {
      const checkpointDir = path.join(this.storageDir, sessionId, 'checkpoints')

      if (!fs.existsSync(checkpointDir)) {
        return []
      }

      return fs.readdirSync(checkpointDir).sort()
    } catch (error) {
      logger.error('Failed to list checkpoints', error)
      throw error
    }
  }

  /**
   * Delete session data
   */
  async deleteSession(sessionId: string): Promise<void> {
    try {
      const sessionDir = path.join(this.storageDir, sessionId)

      if (fs.existsSync(sessionDir)) {
        fs.rmSync(sessionDir, { recursive: true, force: true })
        logger.info('Onboarding session deleted', { sessionId })
      }

      const filePath = this.getSessionFilePath(sessionId)
      if (fs.existsSync(filePath)) {
        fs.rmSync(filePath)
      }
    } catch (error) {
      logger.error('Failed to delete onboarding session', error)
      throw error
    }
  }

  /**
   * Get all sessions
   */
  async getAllSessions(): Promise<OnboardingSession[]> {
    try {
      await this.initialize()

      if (!fs.existsSync(this.storageDir)) {
        return []
      }

      const files = fs.readdirSync(this.storageDir).filter((f) => f.endsWith('.json'))
      const sessions: OnboardingSession[] = []

      for (const file of files) {
        const filePath = path.join(this.storageDir, file)
        const data = await readFile(filePath, 'utf-8')
        sessions.push(JSON.parse(data))
      }

      return sessions
    } catch (error) {
      logger.error('Failed to get all sessions', error)
      throw error
    }
  }

  /**
   * Get session statistics
   */
  async getSessionStats(): Promise<{
    totalSessions: number
    completedSessions: number
    averageDurationMs: number
    completionRate: number
  }> {
    try {
      const sessions = await this.getAllSessions()
      const completed = sessions.filter((s) => s.completedAt)

      const avgDuration =
        completed.length > 0
          ? completed.reduce((sum, s) => sum + (s.totalDurationMs || 0), 0) / completed.length
          : 0

      return {
        totalSessions: sessions.length,
        completedSessions: completed.length,
        averageDurationMs: avgDuration,
        completionRate: (completed.length / sessions.length) * 100 || 0,
      }
    } catch (error) {
      logger.error('Failed to get session stats', error)
      throw error
    }
  }

  /**
   * Export session as JSON
   */
  async exportSession(sessionId: string): Promise<string> {
    try {
      const session = await this.loadSession(sessionId)

      if (!session) {
        throw new Error(`Session not found: ${sessionId}`)
      }

      return JSON.stringify(session, null, 2)
    } catch (error) {
      logger.error('Failed to export session', error)
      throw error
    }
  }

  /**
   * Get session file path
   */
  private getSessionFilePath(sessionId: string): string {
    return path.join(this.storageDir, `${sessionId}.json`)
  }
}

/**
 * Export global persistence instance
 */
export const onboardingPersistence = new OnboardingPersistence()
