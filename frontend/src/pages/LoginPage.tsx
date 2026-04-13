import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Input, Alert } from '@/components/Common'
import { useLogin } from '@/hooks'

interface LoginFormData {
  email: string
  password: string
  org_slug: string
}

interface MFAState {
  mfaRequired: boolean
  mfaToken?: string
  totpCode: string
}

/**
 * LoginPage Component
 * Handles user authentication with optional MFA verification
 *
 * Flow:
 * 1. User enters email/password/org_slug
 * 2. POST /auth/login
 * 3. If MFA required: show TOTP input
 * 4. User enters 6-digit code from authenticator
 * 5. POST /auth/mfa-verify
 * 6. Token stored in localStorage + Zustand
 * 7. Redirect to /dashboard
 */
export const LoginPage: React.FC = () => {
  const navigate = useNavigate()
  const { login, verifyMFA, isLoading, error: hookError } = useLogin()

  // Form state
  const [formData, setFormData] = useState<LoginFormData>({
    email: 'admin@example.com', // Demo email
    password: '',
    org_slug: 'acme-corp',
  })

  // MFA state
  const [mfaState, setMfaState] = useState<MFAState>({
    mfaRequired: false,
    mfaToken: undefined,
    totpCode: '',
  })

  // Local error (form validation)
  const [localError, setLocalError] = useState<string | null>(null)

  // Combine hook error with local error
  const error = localError || hookError

  /**
   * Validate email format
   */
  const isValidEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  }

  /**
   * Handle primary login form submission
   */
  const handleLoginSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLocalError(null)

    // Validation
    if (!formData.email) {
      setLocalError('Email is required')
      return
    }

    if (!isValidEmail(formData.email)) {
      setLocalError('Invalid email format')
      return
    }

    if (!formData.password) {
      setLocalError('Password is required')
      return
    }

    if (!formData.org_slug) {
      setLocalError('Organization is required')
      return
    }

    try {
      // Step 1: Attempt login
      const result = await login({
        email: formData.email,
        password: formData.password,
        org_slug: formData.org_slug,
      })

      // Check if MFA is required
      if (result?.requiresMfa && result?.mfaToken) {
        // MFA required: show TOTP input
        setMfaState({
          mfaRequired: true,
          mfaToken: result.mfaToken,
          totpCode: '',
        })
      } else {
        // MFA not required: login successful
        // Token already stored in Zustand by useLogin hook
        navigate('/')
      }
    } catch (err) {
      // Error already set in hook
      // User will see error message from hookError
      console.error('Login failed:', err)
    }
  }

  /**
   * Handle MFA verification (TOTP code)
   */
  const handleMFASubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLocalError(null)

    if (!mfaState.totpCode) {
      setLocalError('TOTP code is required')
      return
    }

    if (mfaState.totpCode.length !== 6) {
      setLocalError('TOTP code must be 6 digits')
      return
    }

    if (!mfaState.mfaToken) {
      setLocalError('MFA session expired. Please login again.')
      return
    }

    try {
      // Step 2: Verify TOTP code
      await verifyMFA(mfaState.mfaToken, mfaState.totpCode)

      // Token stored by hook: navigate to dashboard
      navigate('/')
    } catch (err) {
      setLocalError('Invalid TOTP code. Please try again.')
      console.error('MFA verification failed:', err)
    }
  }

  /**
   * Handle back from MFA (restart login)
   */
  const handleBackFromMFA = () => {
    setMfaState({
      mfaRequired: false,
      mfaToken: undefined,
      totpCode: '',
    })
    setFormData({ ...formData, password: '' })
    setLocalError(null)
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-sky-50 to-blue-50 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold text-sky-900 mb-2">🔐 RBAC Dashboard</h1>
          <p className="text-gray-600">Enterprise Access Control</p>
        </div>

        {/* Main Container */}
        <div className="bg-white rounded-lg shadow-lg p-8">
          {!mfaState.mfaRequired ? (
            // ===== PRIMARY LOGIN FORM =====
            <>
              <h2 className="text-2xl font-semibold text-gray-900 mb-6">Sign In</h2>

              {error && <Alert type="error">{error}</Alert>}

              <form onSubmit={handleLoginSubmit} className="space-y-4">
                {/* Email Input */}
                <Input
                  label="Email"
                  type="email"
                  placeholder="admin@example.com"
                  value={formData.email}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                    setFormData({ ...formData, email: e.target.value })
                    setLocalError(null)
                  }}
                  disabled={isLoading}
                />

                {/* Password Input */}
                <Input
                  label="Password"
                  type="password"
                  placeholder="••••••••"
                  value={formData.password}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                    setFormData({ ...formData, password: e.target.value })
                    setLocalError(null)
                  }}
                  disabled={isLoading}
                />

                {/* Organization Input */}
                <Input
                  label="Organization"
                  type="text"
                  placeholder="acme-corp"
                  value={formData.org_slug}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                    setFormData({ ...formData, org_slug: e.target.value })
                    setLocalError(null)
                  }}
                  disabled={isLoading}
                />

                {/* Submit Button */}
                <Button
                  type="submit"
                  label={isLoading ? 'Signing in...' : 'Sign In'}
                  variant="primary"
                  fullWidth
                  loading={isLoading}
                  disabled={isLoading}
                />
              </form>

              {/* Demo Credentials Note */}
              <div className="mt-6 p-4 bg-blue-50 rounded-lg border border-blue-200">
                <p className="text-sm text-gray-700">
                  <span className="font-semibold">Demo Credentials:</span>
                </p>
                <ul className="text-sm text-gray-600 mt-2 space-y-1">
                  <li>Email: <code className="bg-white px-2 py-1 rounded">admin@example.com</code></li>
                  <li>Password: <code className="bg-white px-2 py-1 rounded">password123</code></li>
                  <li>Org: <code className="bg-white px-2 py-1 rounded">acme-corp</code></li>
                </ul>
              </div>

              {/* Help Text */}
              <div className="mt-6 text-center text-sm text-gray-600">
                <p>Having trouble signing in?</p>
                <p className="text-sky-600 hover:text-sky-700 cursor-pointer">Contact support</p>
              </div>
            </>
          ) : (
            // ===== MFA VERIFICATION FORM =====
            <>
              <h2 className="text-2xl font-semibold text-gray-900 mb-6">Two-Factor Authentication</h2>

              {error && <Alert type="error">{error}</Alert>}

              <div className="mb-6 p-4 bg-blue-50 rounded-lg border border-blue-200">
                <p className="text-sm text-gray-700">
                  Enter the 6-digit code from your authenticator app (Google Authenticator, Authy, Microsoft Authenticator, etc.)
                </p>
              </div>

              <form onSubmit={handleMFASubmit} className="space-y-4">
                {/* TOTP Code Input */}
                <Input
                  label="Authenticator Code"
                  type="text"
                  placeholder="000000"
                  maxLength={6}
                  value={mfaState.totpCode}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => {
                    // Only allow digits
                    const value = e.target.value.replace(/\D/g, '').slice(0, 6)
                    setMfaState({ ...mfaState, totpCode: value })
                    setLocalError(null)
                  }}
                  disabled={isLoading}
                  inputMode="numeric"
                />

                {/* Submit Button */}
                <Button
                  type="submit"
                  label={isLoading ? 'Verifying...' : 'Verify'}
                  variant="primary"
                  fullWidth
                  loading={isLoading}
                  disabled={isLoading || mfaState.totpCode.length !== 6}
                />

                {/* Back Button */}
                <Button
                  type="button"
                  label="Back"
                  variant="secondary"
                  fullWidth
                  onClick={handleBackFromMFA}
                  disabled={isLoading}
                />
              </form>

              {/* Don't Have Code? */}
              <div className="mt-6 p-4 bg-amber-50 rounded-lg border border-amber-200">
                <p className="text-sm text-gray-700">
                  <span className="font-semibold">Don't have your code?</span>
                </p>
                <p className="text-sm text-gray-600 mt-2">
                  If you don't have access to your authenticator, contact your administrator.
                </p>
              </div>
            </>
          )}

          {/* Footer */}
          <div className="mt-8 pt-6 border-t border-gray-200 text-center text-xs text-gray-500">
            <p>🔒 Secure connection | Passwords encrypted | No data stored</p>
          </div>
        </div>
      </div>
    </div>
  )
}
