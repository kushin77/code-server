import { afterEach, describe, expect, it, vi } from 'vitest'

vi.mock('@google-cloud/secret-manager', () => {
  class MockSecretManagerServiceClient {
    async accessSecretVersion(): Promise<Array<{ payload?: { data?: Buffer } }>> {
      return [{ payload: { data: Buffer.from('mock-secret') } }]
    }

    async close(): Promise<void> {
      return
    }
  }

  return { SecretManagerServiceClient: MockSecretManagerServiceClient }
})

import {
  ErrGSMDisabled,
  ErrGSMNotConfigured,
  GSMClient,
  getGSMConfigFromEnv,
  resolveGitHubToken,
} from '../gsm'

describe('gsm config', () => {
  afterEach(() => {
    delete process.env['OLLAMA_GSM_PROJECT_ID']
    delete process.env['OLLAMA_GSM_ENABLED']
    delete process.env['GITHUB_TOKEN']
    delete process.env['GH_TOKEN']
    delete process.env['GSM_GITHUB_TOKEN_SECRET']
  })

  it('reads config from env', () => {
    process.env['OLLAMA_GSM_PROJECT_ID'] = 'proj-1'
    process.env['OLLAMA_GSM_ENABLED'] = 'true'
    const cfg = getGSMConfigFromEnv()
    expect(cfg.projectId).toBe('proj-1')
    expect(cfg.enabled).toBe(true)
  })

  it('fails create when disabled', () => {
    expect(() => GSMClient.create({ projectId: 'proj-1', enabled: false })).toThrow(
      ErrGSMDisabled,
    )
  })

  it('fails create when project id missing', () => {
    expect(() => GSMClient.create({ projectId: '', enabled: true })).toThrow(
      ErrGSMNotConfigured,
    )
  })
})

describe('gsm client', () => {
  it('gets latest secret value', async () => {
    const client = GSMClient.create({ projectId: 'proj-1', enabled: true })
    await expect(client.getSecret('github-token')).resolves.toBe('mock-secret')
    await client.close()
  })

  it('gets specific secret version', async () => {
    const client = GSMClient.create({ projectId: 'proj-1', enabled: true })
    await expect(client.getSecretVersion('github-token', '1')).resolves.toBe('mock-secret')
    await client.close()
  })

  it('throws disabled error on getSecret if disabled', async () => {
    const client = new GSMClient({ projectId: 'proj-1', enabled: false })
    await expect(client.getSecret('x')).rejects.toThrow(ErrGSMDisabled)
  })
})

describe('resolveGitHubToken', () => {
  afterEach(() => {
    delete process.env['OLLAMA_GSM_PROJECT_ID']
    delete process.env['OLLAMA_GSM_ENABLED']
    delete process.env['GITHUB_TOKEN']
    delete process.env['GH_TOKEN']
    delete process.env['GSM_GITHUB_TOKEN_SECRET']
  })

  it('returns env token when GSM disabled', async () => {
    process.env['GITHUB_TOKEN'] = 'env-token'
    process.env['OLLAMA_GSM_ENABLED'] = 'false'
    await expect(resolveGitHubToken()).resolves.toBe('env-token')
  })

  it('prefers GSM token when enabled', async () => {
    process.env['GITHUB_TOKEN'] = 'env-token'
    process.env['OLLAMA_GSM_ENABLED'] = 'true'
    process.env['OLLAMA_GSM_PROJECT_ID'] = 'proj-1'
    await expect(resolveGitHubToken()).resolves.toBe('mock-secret')
  })
})
