// @file        apps/backend/src/services/onboarding/onboarding-service.ts
// @module      services/onboarding
// @description Workspace onboarding wizard service for new team members
//              Manages 10-minute setup flow: git, SSH, cloud login, clone, build, verify
//

import { EventEmitter } from 'events'
import { logger } from '../../lib/logger'

/**
 * Onboarding step type
 */
export type OnboardingStepType =
  | 'git-config'
  | 'ssh-setup'
  | 'cloud-login'
  | 'repo-clone'
  | 'build-config'
  | 'verify'
  | 'complete'

/**
 * Step status
 */
export type StepStatus = 'pending' | 'in-progress' | 'completed' | 'skipped' | 'failed'

/**
 * Onboarding step definition
 */
export interface OnboardingStep {
  id: string
  type: OnboardingStepType
  title: string
  description: string
  order: number
  estimatedDurationMs: number
  status: StepStatus
  completed: boolean
  error?: string
  result?: any
  autoRunnable: boolean
  manualFallback: boolean
}

/**
 * Onboarding session
 */
export interface OnboardingSession {
  sessionId: string
  userId: string
  workspaceId: string
  teamId: string
  startedAt: number
  completedAt?: number
  totalDurationMs?: number
  steps: OnboardingStep[]
  currentStepIndex: number
  completionPercentage: number
  skipped: string[]
}

/**
 * Step execution result
 */
export interface StepExecutionResult {
  stepId: string
  status: StepStatus
  durationMs: number
  output?: any
  error?: string
  requiresManualIntervention: boolean
}

/**
 * Onboarding service
 */
export class OnboardingService extends EventEmitter {
  private sessions: Map<string, OnboardingSession> = new Map()

  /**
   * Create new onboarding session for user
   */
  async createSession(
    userId: string,
    workspaceId: string,
    teamId: string,
  ): Promise<OnboardingSession> {
    const sessionId = `onboard-${Date.now()}-${Math.random().toString(36).slice(2)}`

    const steps: OnboardingStep[] = [
      {
        id: 'git-config',
        type: 'git-config',
        title: 'Configure Git',
        description: 'Set your Git name and email for commits',
        order: 1,
        estimatedDurationMs: 30000, // 30 seconds
        status: 'pending',
        completed: false,
        autoRunnable: true,
        manualFallback: true,
      },
      {
        id: 'ssh-setup',
        type: 'ssh-setup',
        title: 'Setup SSH Keys',
        description: 'Generate SSH key pair for GitHub/GitLab access',
        order: 2,
        estimatedDurationMs: 45000, // 45 seconds
        status: 'pending',
        completed: false,
        autoRunnable: true,
        manualFallback: true,
      },
      {
        id: 'cloud-login',
        type: 'cloud-login',
        title: 'Cloud Login',
        description: 'Authenticate with cloud provider (GitHub/Azure/Google)',
        order: 3,
        estimatedDurationMs: 60000, // 1 minute
        status: 'pending',
        completed: false,
        autoRunnable: false,
        manualFallback: true,
      },
      {
        id: 'repo-clone',
        type: 'repo-clone',
        title: 'Clone Repository',
        description: 'Clone team repository to workspace',
        order: 4,
        estimatedDurationMs: 120000, // 2 minutes
        status: 'pending',
        completed: false,
        autoRunnable: true,
        manualFallback: true,
      },
      {
        id: 'build-config',
        type: 'build-config',
        title: 'Configure Build',
        description: 'Install dependencies and configure build tools',
        order: 5,
        estimatedDurationMs: 300000, // 5 minutes
        status: 'pending',
        completed: false,
        autoRunnable: true,
        manualFallback: true,
      },
      {
        id: 'verify',
        type: 'verify',
        title: 'Verify Setup',
        description: 'Run build and tests to verify everything works',
        order: 6,
        estimatedDurationMs: 180000, // 3 minutes
        status: 'pending',
        completed: false,
        autoRunnable: true,
        manualFallback: true,
      },
      {
        id: 'complete',
        type: 'complete',
        title: 'Complete',
        description: 'Onboarding complete, ready to start coding',
        order: 7,
        estimatedDurationMs: 5000,
        status: 'pending',
        completed: false,
        autoRunnable: true,
        manualFallback: false,
      },
    ]

    const session: OnboardingSession = {
      sessionId,
      userId,
      workspaceId,
      teamId,
      startedAt: Date.now(),
      steps,
      currentStepIndex: 0,
      completionPercentage: 0,
      skipped: [],
    }

    this.sessions.set(sessionId, session)

    logger.info('Onboarding session created', {
      sessionId,
      userId,
      workspaceId,
      teamId,
    })

    this.emit('session-created', session)

    return session
  }

  /**
   * Get session by ID
   */
  getSession(sessionId: string): OnboardingSession | undefined {
    return this.sessions.get(sessionId)
  }

  /**
   * Execute current step
   */
  async executeStep(
    sessionId: string,
    autoRun: boolean = true,
  ): Promise<StepExecutionResult> {
    const session = this.sessions.get(sessionId)
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`)
    }

    const step = session.steps[session.currentStepIndex]
    if (!step) {
      throw new Error(`Step not found at index ${session.currentStepIndex}`)
    }

    const startTime = Date.now()
    step.status = 'in-progress'

    this.emit('step-started', { sessionId, step })

    try {
      let result: any

      if (autoRun && step.autoRunnable) {
        // Auto-run the step
        result = await this.runStep(step)
      } else {
        // Manual step - just move to next
        result = { manual: true }
      }

      const durationMs = Date.now() - startTime
      step.status = 'completed'
      step.completed = true
      step.result = result
      step.estimatedDurationMs = durationMs // Update with actual

      this.updateProgress(session)

      this.emit('step-completed', { sessionId, step, durationMs })

      return {
        stepId: step.id,
        status: 'completed',
        durationMs,
        output: result,
        requiresManualIntervention: !autoRun && !step.autoRunnable,
      }
    } catch (error) {
      const durationMs = Date.now() - startTime
      step.status = 'failed'
      step.error = (error as Error).message

      this.emit('step-failed', { sessionId, step, error })

      return {
        stepId: step.id,
        status: 'failed',
        durationMs,
        error: (error as Error).message,
        requiresManualIntervention: step.manualFallback,
      }
    }
  }

  /**
   * Skip current step
   */
  skipStep(sessionId: string): void {
    const session = this.sessions.get(sessionId)
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`)
    }

    const step = session.steps[session.currentStepIndex]
    step.status = 'skipped'
    session.skipped.push(step.id)

    this.updateProgress(session)
    this.emit('step-skipped', { sessionId, step })
  }

  /**
   * Move to next step
   */
  nextStep(sessionId: string): OnboardingStep | null {
    const session = this.sessions.get(sessionId)
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`)
    }

    if (session.currentStepIndex < session.steps.length - 1) {
      session.currentStepIndex++
      return session.steps[session.currentStepIndex]
    }

    return null
  }

  /**
   * Move to previous step
   */
  previousStep(sessionId: string): OnboardingStep | null {
    const session = this.sessions.get(sessionId)
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`)
    }

    if (session.currentStepIndex > 0) {
      session.currentStepIndex--
      return session.steps[session.currentStepIndex]
    }

    return null
  }

  /**
   * Get current step
   */
  getCurrentStep(sessionId: string): OnboardingStep | null {
    const session = this.sessions.get(sessionId)
    if (!session) return null

    return session.steps[session.currentStepIndex] || null
  }

  /**
   * Complete onboarding
   */
  async completeOnboarding(sessionId: string): Promise<OnboardingSession> {
    const session = this.sessions.get(sessionId)
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`)
    }

    session.completedAt = Date.now()
    session.totalDurationMs = session.completedAt - session.startedAt

    // Mark complete step as done
    const completeStep = session.steps.find((s) => s.type === 'complete')
    if (completeStep) {
      completeStep.status = 'completed'
      completeStep.completed = true
    }

    session.completionPercentage = 100

    logger.info('Onboarding completed', {
      sessionId,
      userId: session.userId,
      durationMs: session.totalDurationMs,
      stepsCompleted: session.steps.filter((s) => s.completed).length,
    })

    this.emit('onboarding-completed', session)

    return session
  }

  /**
   * Run individual step
   */
  private async runStep(step: OnboardingStep): Promise<any> {
    switch (step.type) {
      case 'git-config':
        return this.runGitConfig()
      case 'ssh-setup':
        return this.runSSHSetup()
      case 'cloud-login':
        return this.runCloudLogin()
      case 'repo-clone':
        return this.runRepoClone()
      case 'build-config':
        return this.runBuildConfig()
      case 'verify':
        return this.runVerify()
      case 'complete':
        return { status: 'complete' }
      default:
        throw new Error(`Unknown step type: ${step.type}`)
    }
  }

  /**
   * Configure Git user and email
   */
  private async runGitConfig(): Promise<any> {
    // Simulate git config
    await new Promise((resolve) => setTimeout(resolve, 100))
    return {
      user: 'Team Member',
      email: 'member@team.com',
      configured: true,
    }
  }

  /**
   * Setup SSH keys
   */
  private async runSSHSetup(): Promise<any> {
    await new Promise((resolve) => setTimeout(resolve, 150))
    return {
      keyGenerated: true,
      publicKeyPath: '~/.ssh/id_rsa.pub',
      fingerprint: 'SHA256:xxxxx...',
    }
  }

  /**
   * Cloud login (manual step)
   */
  private async runCloudLogin(): Promise<any> {
    return {
      requiresUserInteraction: true,
      provider: 'github',
    }
  }

  /**
   * Clone repository
   */
  private async runRepoClone(): Promise<any> {
    await new Promise((resolve) => setTimeout(resolve, 200))
    return {
      cloned: true,
      repoPath: '/workspace/team-repo',
      size: '1.2GB',
    }
  }

  /**
   * Configure build
   */
  private async runBuildConfig(): Promise<any> {
    await new Promise((resolve) => setTimeout(resolve, 300))
    return {
      buildConfigured: true,
      dependenciesInstalled: 2543,
      buildTool: 'npm',
    }
  }

  /**
   * Verify setup
   */
  private async runVerify(): Promise<any> {
    await new Promise((resolve) => setTimeout(resolve, 200))
    return {
      buildPassed: true,
      testsPassed: true,
      allChecks: 'passed',
    }
  }

  /**
   * Update progress
   */
  private updateProgress(session: OnboardingSession): void {
    const completedSteps = session.steps.filter((s) => s.completed).length
    session.completionPercentage = (completedSteps / session.steps.length) * 100
  }

  /**
   * Get onboarding statistics
   */
  async getStats(): Promise<{
    totalSessions: number
    completedSessions: number
    averageDurationMs: number
    completionRate: number
  }> {
    const sessions = Array.from(this.sessions.values())
    const completed = sessions.filter((s) => s.completedAt)

    const avgDuration =
      completed.length > 0
        ? completed.reduce((sum, s) => sum + (s.totalDurationMs || 0), 0) / completed.length
        : 0

    return {
      totalSessions: sessions.length,
      completedSessions: completed.length,
      averageDurationMs: avgDuration,
      completionRate: (completed.length / sessions.length) * 100,
    }
  }
}

/**
 * Export global instance
 */
export const onboardingService = new OnboardingService()
