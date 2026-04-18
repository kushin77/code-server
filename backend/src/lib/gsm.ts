// @file        backend/src/lib/gsm.ts
// @module      secrets
// @description Google Secret Manager integration with env-driven config,
//              lazy client initialization, and strongly typed error handling.

import { SecretManagerServiceClient } from '@google-cloud/secret-manager'

export interface GSMConfig {
  projectId: string
  enabled: boolean
}

export const ErrGSMDisabled = new Error('google secret manager is disabled')
export const ErrGSMNotConfigured = new Error('google secret manager is not configured')

/** Build GSM config from environment variables. */
export const getGSMConfigFromEnv = (): GSMConfig => ({
  projectId: process.env['OLLAMA_GSM_PROJECT_ID'] || '',
  enabled: (process.env['OLLAMA_GSM_ENABLED'] || '').toLowerCase() === 'true',
})

/**
 * GSM client wrapper with lazy initialization.
 * Mirrors the behavior used in Ollama's Go implementation.
 */
export class GSMClient {
  private readonly config: GSMConfig
  private client: SecretManagerServiceClient | null

  constructor(config: GSMConfig) {
    this.config = config
    this.client = null
  }

  static create(config: GSMConfig): GSMClient {
    if (!config.enabled) {
      throw ErrGSMDisabled
    }
    if (!config.projectId) {
      throw ErrGSMNotConfigured
    }
    return new GSMClient(config)
  }

  private ensureClient(): SecretManagerServiceClient {
    if (!this.client) {
      this.client = new SecretManagerServiceClient()
    }
    return this.client
  }

  /** Get latest version for a secret id. */
  async getSecret(secretName: string): Promise<string> {
    if (!this.config.enabled) {
      throw ErrGSMDisabled
    }

    const client = this.ensureClient()
    const name = `projects/${this.config.projectId}/secrets/${secretName}/versions/latest`

    const [result] = await client.accessSecretVersion({ name })
    const data = result.payload?.data
    return data ? data.toString('utf8') : ''
  }

  /** Get a specific secret version by version id (e.g. "1"). */
  async getSecretVersion(secretName: string, version: string): Promise<string> {
    if (!this.config.enabled) {
      throw ErrGSMDisabled
    }

    const client = this.ensureClient()
    const name = `projects/${this.config.projectId}/secrets/${secretName}/versions/${version}`

    const [result] = await client.accessSecretVersion({ name })
    const data = result.payload?.data
    return data ? data.toString('utf8') : ''
  }

  async close(): Promise<void> {
    if (this.client) {
      await this.client.close()
      this.client = null
    }
  }
}

/**
 * Resolve GitHub token using GSM first (if enabled), then env fallback.
 * This keeps existing script behavior while offering typed backend usage.
 */
export const resolveGitHubToken = async (): Promise<string> => {
  const envToken = process.env['GITHUB_TOKEN'] || process.env['GH_TOKEN'] || ''
  const cfg = getGSMConfigFromEnv()

  if (!cfg.enabled) {
    return envToken
  }

  const secretName = process.env['GSM_GITHUB_TOKEN_SECRET'] || 'prod-github-token'

  try {
    const gsm = GSMClient.create(cfg)
    const token = await gsm.getSecret(secretName)
    await gsm.close()
    return token || envToken
  } catch {
    return envToken
  }
}
