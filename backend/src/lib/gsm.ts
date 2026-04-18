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

  /**
   * Fetch a secret from Google Secret Manager.
   * @param secretId The secret identifier (name without version)
   * @param version The secret version ("latest" by default)
   * @returns The secret value (plaintext)
   */
  async getSecret(secretId: string, version = 'latest'): Promise<string> {
    const client = this.ensureClient()
    const name = client.secretVersionPath(
      this.config.projectId,
      secretId,
      version,
    )

    const [response] = await client.accessSecretVersion({
      name,
    })

    return response.payload?.data?.toString('utf8') || ''
  }

  /**
   * List all secrets in the project.
   * @returns Array of secret names
   */
  async listSecrets(): Promise<string[]> {
    const client = this.ensureClient()
    const parent = client.projectPath(this.config.projectId)

    const [secrets] = await client.listSecrets({
      parent,
    })

    return secrets.map((s) => s.name || '').filter(Boolean)
  }
}
