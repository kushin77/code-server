import React, { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import QRCode from 'qrcode.react'
import { Button, Input, Alert, Card, Spinner } from '@/components/Common'
import { rbacAPI } from '@/api/rbac-client'

interface MFASetupState {
  step: 'initial' | 'generating' | 'scanned' | 'verified' | 'complete'
  secret?: string
  qrCode?: string
  backupCodes: string[]
  totpCode: string
  isLoading: boolean
  error: string | null
  success: string | null
}

/**
 * MFASetup Component
 * Complete TOTP MFA setup flow with QR code, secret, and backup codes
 *
 * Flow:
 * 1. User clicks "Setup TOTP"
 * 2. Backend generates secret + QR code
 * 3. Display QR code (for scanning)
 * 4. Show secret (for manual entry)
 * 5. Generate backup codes
 * 6. User enters 6-digit TOTP to verify
 * 7. Call confirmMFA() to enable
 * 8. Show success message + download codes
 * 9. Back to dashboard
 */
export const MFASetup: React.FC = () => {
  const navigate = useNavigate()
  const [state, setState] = useState<MFASetupState>({
    step: 'initial',
    backupCodes: [],
    totpCode: '',
    isLoading: false,
    error: null,
    success: null,
  })

  const [secretCopied, setSecretCopied] = useState(false)
  const [codesCopied, setCodesCopied] = useState(false)

  /**
   * Step 1: Initiate MFA setup
   * Generate secret and QR code
   */
  const handleStartSetup = async () => {
    setState((prev) => ({ ...prev, isLoading: true, error: null }))

    try {
      // Call backend to generate MFA secret
      const response = await rbacAPI.setupMFA()

      // Generate backup codes locally (8 random codes)
      const codes = Array.from({ length: 8 }, () =>
        Math.random().toString(36).substring(2, 10).toUpperCase()
      )

      setState((prev) => ({
        ...prev,
        step: 'scanned',
        secret: response.secret,
        qrCode: response.qrCode,
        backupCodes: codes,
        isLoading: false,
      }))
    } catch (err) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: `Failed to generate MFA secret: ${err instanceof Error ? err.message : 'Unknown error'}`,
      }))
    }
  }

  /**
   * Step 2: Verify TOTP code and confirm MFA
   */
  const handleVerifyTOTP = async (e: React.FormEvent) => {
    e.preventDefault()
    setState((prev) => ({ ...prev, error: null }))

    // Validation
    if (!state.secret) {
      setState((prev) => ({ ...prev, error: 'Secret not generated' }))
      return
    }

    if (!state.totpCode) {
      setState((prev) => ({ ...prev, error: 'TOTP code is required' }))
      return
    }

    if (state.totpCode.length !== 6) {
      setState((prev) => ({ ...prev, error: 'TOTP code must be 6 digits' }))
      return
    }

    setState((prev) => ({ ...prev, isLoading: true }))

    try {
      // Verify TOTP code with backend
      const response = await rbacAPI.confirmMFA(state.secret, state.totpCode)

      if (response.success) {
        setState((prev) => ({
          ...prev,
          step: 'verified',
          isLoading: false,
          success: 'TOTP code verified! MFA is now enabled.',
          totpCode: '',
        }))

        // Auto-navigate after 3 seconds
        setTimeout(() => {
          navigate('/')
        }, 3000)
      } else {
        setState((prev) => ({
          ...prev,
          isLoading: false,
          error: 'Failed to verify TOTP code',
        }))
      }
    } catch (err) {
      setState((prev) => ({
        ...prev,
        isLoading: false,
        error: `Invalid TOTP code: ${err instanceof Error ? err.message : 'Please try again'}`,
      }))
    }
  }

  /**
   * Copy secret to clipboard
   */
  const copySecretToClipboard = () => {
    if (state.secret) {
      navigator.clipboard.writeText(state.secret)
      setSecretCopied(true)
      setTimeout(() => setSecretCopied(false), 2000)
    }
  }

  /**
   * Copy backup codes to clipboard
   */
  const copyBackupCodes = () => {
    const codesText = state.backupCodes.join('\n')
    navigator.clipboard.writeText(codesText)
    setCodesCopied(true)
    setTimeout(() => setCodesCopied(false), 2000)
  }

  /**
   * Download backup codes as text file
   */
  const downloadBackupCodes = () => {
    const codesText = `RBAC Dashboard Backup Codes
Generated: ${new Date().toISOString()}
Keep these codes safe. Each code can only be used once.

${state.backupCodes.map((code, i) => `${i + 1}. ${code}`).join('\n')}`

    const element = document.createElement('a')
    element.setAttribute('href', `data:text/plain;charset=utf-8,${encodeURIComponent(codesText)}`)
    element.setAttribute('download', 'rbac-backup-codes.txt')
    element.style.display = 'none'
    document.body.appendChild(element)
    element.click()
    document.body.removeChild(element)
  }

  /**
   * Cancel setup and go back
   */
  const handleCancel = () => {
    navigate('/')
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-blue-50 py-12 px-4">
      <div className="max-w-2xl mx-auto">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-sky-900 mb-2">🔐 Set Up Two-Factor Authentication</h1>
          <p className="text-gray-600">Secure your account with TOTP (Time-based One-Time Password)</p>
        </div>

        {/* Step Indicator */}
        <div className="flex justify-center items-center gap-2 mb-8">
          {['Setup', 'Scan', 'Verify', 'Done'].map((label, idx) => (
            <React.Fragment key={label}>
              <div
                className={`w-10 h-10 rounded-full flex items-center justify-center font-semibold transition-all ${
                  state.step === ['initial', 'generating', 'scanned', 'verified'][idx]
                    ? 'bg-sky-600 text-white'
                    : ['initial', 'generating'].includes(state.step)
                      ? 'bg-gray-200 text-gray-600'
                      : 'bg-green-600 text-white'
                }`}
              >
                {idx + 1}
              </div>
              {idx < 3 && <div className="w-12 h-1 bg-gray-300" />}
            </React.Fragment>
          ))}
        </div>

        {/* Main Content */}
        <div className="bg-white rounded-lg shadow-lg p-8">
          {/* STEP 1: Initial Setup */}
          {state.step === 'initial' && (
            <>
              <h2 className="text-2xl font-semibold text-gray-900 mb-4">Ready to set up MFA?</h2>

              <div className="space-y-4 mb-6">
                <Card>
                  <div className="font-semibold text-gray-900 mb-2">What is TOTP?</div>
                  <p className="text-sm text-gray-600">
                    Time-based One-Time Password (TOTP) is a type of two-factor authentication that generates a unique 6-digit code every 30 seconds.
                  </p>
                </Card>

                <Card>
                  <div className="font-semibold text-gray-900 mb-2">Required Apps</div>
                  <p className="text-sm text-gray-600">
                    You'll need an authenticator app on your phone:
                  </p>
                  <ul className="text-sm text-gray-600 mt-2 space-y-1 ml-4">
                    <li>• Google Authenticator</li>
                    <li>• Microsoft Authenticator</li>
                    <li>• Authy</li>
                    <li>• 1Password</li>
                    <li>• Any TOTP-compatible app</li>
                  </ul>
                </Card>

                <Card>
                  <div className="font-semibold text-gray-900 mb-2">What You'll Get</div>
                  <p className="text-sm text-gray-600">
                    After setup, you'll receive 8 backup codes. Save these in a safe place - you can use them if you lose access to your phone.
                  </p>
                </Card>
              </div>

              {error && <Alert type="error">{error}</Alert>}

              <div className="flex gap-4">
                <Button
                  label="Start Setup"
                  variant="primary"
                  fullWidth
                  onClick={handleStartSetup}
                  loading={state.isLoading}
                  disabled={state.isLoading}
                />
                <Button
                  label="Cancel"
                  variant="secondary"
                  fullWidth
                  onClick={handleCancel}
                  disabled={state.isLoading}
                />
              </div>
            </>
          )}

          {/* STEP 2: QR Code & Secret */}
          {(state.step === 'generating' || state.step === 'scanned') && (
            <>
              {state.isLoading ? (
                <div className="flex flex-col items-center justify-center py-12">
                  <Spinner size="lg" />
                  <p className="text-gray-600 mt-4">Generating QR code...</p>
                </div>
              ) : state.qrCode && state.secret ? (
                <>
                  <h2 className="text-2xl font-semibold text-gray-900 mb-6">Scan QR Code</h2>

                  <div className="space-y-6">
                    {/* QR Code Display */}
                    <Card>
                      <div className="flex flex-col items-center">
                        <p className="text-sm text-gray-600 mb-4">Scan this code with your authenticator app:</p>
                        <div className="bg-white p-4 border-2 border-gray-200 rounded-lg">
                          <QRCode value={state.qrCode} size={200} level="H" includeMargin={true} />
                        </div>
                      </div>
                    </Card>

                    {/* Secret Key Display */}
                    <Card>
                      <p className="text-sm text-gray-600 mb-3">
                        Can't scan? Enter this key manually in your authenticator app:
                      </p>
                      <div className="flex gap-2">
                        <code className="flex-1 bg-gray-100 p-3 rounded-lg font-mono text-lg text-gray-900 break-all">
                          {state.secret}
                        </code>
                        <Button
                          label={secretCopied ? '✓' : 'Copy'}
                          variant="secondary"
                          size="sm"
                          onClick={copySecretToClipboard}
                        />
                      </div>
                    </Card>

                    {/* Important Note */}
                    <Alert type="warning">
                      Save this secret in a safe place. You'll need it if you lose your phone.
                    </Alert>

                    {/* Next Button */}
                    <Button
                      label="I've scanned the code"
                      variant="primary"
                      fullWidth
                      onClick={() => setState((prev) => ({ ...prev, step: 'verified' }))}
                    />
                  </div>
                </>
              ) : null}
            </>
          )}

          {/* STEP 3: Verify TOTP Code */}
          {(state.step === 'verified' || state.step === 'scanned') && (
            <>
              <h2 className="text-2xl font-semibold text-gray-900 mb-6">Verify TOTP Code</h2>

              <p className="text-gray-600 mb-6">
                Enter the 6-digit code from your authenticator app to verify the setup:
              </p>

              {error && <Alert type="error">{error}</Alert>}

              <form onSubmit={handleVerifyTOTP} className="space-y-4">
                <Input
                  label="6-Digit Code"
                  type="text"
                  placeholder="000000"
                  maxLength={6}
                  value={state.totpCode}
                  onChange={(e) => {
                    const value = e.target.value.replace(/\D/g, '').slice(0, 6)
                    setState((prev) => ({ ...prev, totpCode: value, error: null }))
                  }}
                  disabled={state.isLoading}
                  inputMode="numeric"
                />

                <Button
                  type="submit"
                  label={state.isLoading ? 'Verifying...' : 'Verify & Enable MFA'}
                  variant="primary"
                  fullWidth
                  loading={state.isLoading}
                  disabled={state.isLoading || state.totpCode.length !== 6}
                />
              </form>
            </>
          )}

          {/* STEP 4: Success & Backup Codes */}
          {state.step === 'verified' && state.success && (
            <>
              <div className="mb-6">
                <Alert type="success">{state.success}</Alert>
              </div>

              <h2 className="text-2xl font-semibold text-gray-900 mb-6">Save Your Backup Codes</h2>

              <p className="text-gray-600 mb-4">
                Save these codes in a safe place. Each code can only be used once if you lose access to your authenticator:
              </p>

              {/* Backup Codes Display */}
              <Card>
                <div className="bg-gray-50 p-4 rounded-lg font-mono text-sm space-y-1 mb-4">
                  {state.backupCodes.map((code, idx) => (
                    <div key={idx} className="text-gray-700">
                      {idx + 1}. {code}
                    </div>
                  ))}
                </div>

                <div className="flex gap-2">
                  <Button
                    label={codesCopied ? '✓ Copied' : 'Copy All'}
                    variant="secondary"
                    flex
                    onClick={copyBackupCodes}
                  />
                  <Button
                    label="Download"
                    variant="secondary"
                    flex
                    onClick={downloadBackupCodes}
                  />
                </div>
              </Card>

              <Alert type="warning" className="mt-6">
                Store these codes securely. Anyone with these codes can access your account.
              </Alert>

              <Button
                label="Done - Go to Dashboard"
                variant="primary"
                fullWidth
                className="mt-6"
                onClick={() => navigate('/')}
              />
            </>
          )}
        </div>

        {/* Help Text */}
        <div className="mt-8 text-center text-sm text-gray-600">
          <p>Need help? <span className="text-sky-600 hover:text-sky-700 cursor-pointer">Contact support</span></p>
        </div>
      </div>
    </div>
  )
}
