// @file        apps/backend/src/services/onboarding/__tests__/persistence.test.ts
// @module      services/onboarding
// @description Tests for onboarding persistence file operations and audit emission
//

import * as fs from 'fs'
import * as os from 'os'
import * as path from 'path'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AuditService } from '../../audit/audit-service'
import { OnboardingPersistence } from '../persistence'

describe('OnboardingPersistence', () => {
  let tempDir: string
  let mockAuditService: any

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'onboarding-persistence-'))
    mockAuditService = { emit: vi.fn() }
  })

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true })
  })

  it('audits session writes and deletes', async () => {
    const persistence = new OnboardingPersistence(tempDir, mockAuditService as AuditService)
    const session = {
      sessionId: 'session-1',
      userId: 'user-1',
      workspaceId: 'workspace-1',
      teamId: 'team-1',
      startedAt: Date.now(),
      steps: [],
      currentStepIndex: 0,
      completionPercentage: 0,
      skipped: [],
      status: 'active'
    }

    await persistence.saveSession(session as any)
    
    expect(mockAuditService.emit).toHaveBeenCalled()
    expect(mockAuditService.emit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'update',
        resourceType: 'session',
        resource: `onboarding-session:${session.sessionId}`
      })
    )

    await persistence.deleteSession(session.sessionId)

    expect(mockAuditService.emit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'delete',
        resourceType: 'session',
        resource: `onboarding-session:${session.sessionId}`
      })
    )
  })

  it('initializes storage directory', async () => {
    const storageDir = path.join(tempDir, 'sessions')
    const persistence = new OnboardingPersistence(storageDir)
    
    await persistence.initialize()
    expect(fs.existsSync(storageDir)).toBe(true)
  })
})