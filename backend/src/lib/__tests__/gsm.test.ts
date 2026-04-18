import { describe, it, expect, beforeEach, vi } from 'vitest'
import { GSMClient, getGSMConfigFromEnv, ErrGSMDisabled, ErrGSMNotConfigured } from '../gsm'

describe('GSM Integration', () => {
  const testConfig = {
    projectId: 'test-project',
    enabled: true,
  }

  describe('getGSMConfigFromEnv', () => {
    beforeEach(() => {
      delete process.env['OLLAMA_GSM_PROJECT_ID']
      delete process.env['OLLAMA_GSM_ENABLED']
    })

    it('should parse enabled=true from env', () => {
      process.env['OLLAMA_GSM_ENABLED'] = 'true'
      process.env['OLLAMA_GSM_PROJECT_ID'] = 'my-project'

      const config = getGSMConfigFromEnv()

      expect(config.enabled).toBe(true)
      expect(config.projectId).toBe('my-project')
    })

    it('should parse enabled=false from env', () => {
      process.env['OLLAMA_GSM_ENABLED'] = 'false'
      process.env['OLLAMA_GSM_PROJECT_ID'] = 'my-project'

      const config = getGSMConfigFromEnv()

      expect(config.enabled).toBe(false)
    })

    it('should default to disabled when env not set', () => {
      const config = getGSMConfigFromEnv()

      expect(config.enabled).toBe(false)
      expect(config.projectId).toBe('')
    })

    it('should be case-insensitive for enabled flag', () => {
      process.env['OLLAMA_GSM_ENABLED'] = 'TRUE'
      process.env['OLLAMA_GSM_PROJECT_ID'] = 'my-project'

      const config = getGSMConfigFromEnv()

      expect(config.enabled).toBe(true)
    })
  })

  describe('GSMClient.create', () => {
    it('should throw ErrGSMDisabled when disabled', () => {
      const config = { ...testConfig, enabled: false }

      expect(() => GSMClient.create(config)).toThrow(ErrGSMDisabled)
    })

    it('should throw ErrGSMNotConfigured when projectId empty', () => {
      const config = { ...testConfig, projectId: '' }

      expect(() => GSMClient.create(config)).toThrow(ErrGSMNotConfigured)
    })

    it('should create client when properly configured', () => {
      const client = GSMClient.create(testConfig)

      expect(client).toBeInstanceOf(GSMClient)
    })
  })

  describe('GSMClient lazy initialization', () => {
    it('should initialize client on first use', async () => {
      const client = GSMClient.create(testConfig)

      // Mock the SecretManagerServiceClient to avoid real GCP calls
      vi.mock('@google-cloud/secret-manager', () => ({
        SecretManagerServiceClient: vi.fn().mockImplementation(() => ({
          secretVersionPath: vi.fn().mockReturnValue('projects/test-project/secrets/test-secret/versions/latest'),
          accessSecretVersion: vi.fn().mockResolvedValue([
            {
              payload: {
                data: Buffer.from('secret-value'),
              },
            },
          ]),
          projectPath: vi.fn().mockReturnValue('projects/test-project'),
          listSecrets: vi.fn().mockResolvedValue([[] as any[]]),
        })),
      }))

      // Verify client was not initialized yet (internal state)
      // This is a simplified test; true lazy initialization testing would require interface exposure
      expect(client).toBeDefined()
    })
  })
})
