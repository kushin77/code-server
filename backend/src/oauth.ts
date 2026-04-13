// OAuth2 and OpenID Connect endpoints for Appsmith and Backstage
// Implements standard OAuth2 flows for third-party integrations

import express, { Request, Response } from 'express'
import jwt from 'jsonwebtoken'

const router = express.Router()

// JWT configuration
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key'
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '24h'

/**
 * OpenID Connect Discovery Endpoint
 * Required by Backstage for OIDC provider discovery
 * GET /.well-known/openid-configuration
 */
router.get('/.well-known/openid-configuration', (req: Request, res: Response) => {
  const baseUrl = process.env.BASE_URL || 'https://ide.kushnir.cloud'
  
  res.json({
    issuer: baseUrl,
    authorization_endpoint: `${baseUrl}/auth/authorize`,
    token_endpoint: `${baseUrl}/auth/token`,
    userinfo_endpoint: `${baseUrl}/auth/userinfo`,
    jwks_uri: `${baseUrl}/auth/jwks`,
    
    // Supported flows
    response_types_supported: ['code', 'token'],
    grant_types_supported: ['authorization_code', 'implicit', 'refresh_token'],
    token_endpoint_auth_methods_supported: ['client_secret_basic', 'client_secret_post'],
    
    // Claims
    subject_types_supported: ['public'],
    id_token_signing_alg_values_supported: ['HS256', 'RS256'],
    userinfo_signing_alg_values_supported: ['RS256'],
    
    // Scopes
    scopes_supported: ['openid', 'profile', 'email', 'roles'],
    claims_supported: [
      'sub',
      'iss',
      'aud',
      'exp',
      'iat',
      'email',
      'email_verified',
      'name',
      'roles',
    ],
  })
})

/**
 * OAuth2 Authorization Endpoint
 * POST /auth/authorize
 * Called by Backstage/Appsmith to request authorization
 */
router.post('/authorize', (req: Request, res: Response) => {
  try {
    const { client_id, redirect_uri, response_type, state, scope } = req.body

    // Validate client_id (in production, check against registered clients)
    const validClients = ['backstage', 'appsmith', 'rbac-dashboard']
    if (!validClients.includes(client_id)) {
      return res.status(400).json({ error: 'invalid_client' })
    }

    // Generate authorization code (in production, store with expiry)
    const authCode = Buffer.from(
      JSON.stringify({
        client_id,
        timestamp: Date.now(),
      })
    ).toString('base64')

    // Return authorization code for exchange with token endpoint
    res.json({
      code: authCode,
      state: state || null,
    })
  } catch (error) {
    res.status(500).json({ error: 'server_error' })
  }
})

/**
 * OAuth2 Token Endpoint
 * POST /auth/token
 * Called by Backstage/Appsmith to exchange code for JWT token
 */
router.post('/token', (req: Request, res: Response) => {
  try {
    const { grant_type, code, client_id, client_secret, username, password } =
      req.body

    // Validate client credentials
    if (!client_id) {
      return res.status(400).json({ error: 'invalid_client' })
    }

    let userId: string
    let email: string
    let roles: string[] = []

    // Handle different grant types
    if (grant_type === 'authorization_code') {
      // Exchange authorization code for token
      // In production, validate code hasn't expired and matches client
      userId = 'user-temp'
      email = 'user@example.com'
    } else if (grant_type === 'password') {
      // Resource owner password credentials flow (simplified)
      // In production, validate against user database
      userId = 'user-1'
      email = username || 'admin@example.com'
      roles = ['admin']
    } else {
      return res.status(400).json({ error: 'unsupported_grant_type' })
    }

    // Generate JWT token for the client
    const token = jwt.sign(
      {
        userId,
        email,
        sub: userId,
        aud: client_id,
        roles,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    )

    res.json({
      access_token: token,
      token_type: 'Bearer',
      expires_in: 86400, // 24 hours in seconds
      scope: 'openid profile email roles',
    })
  } catch (error) {
    console.error('Token endpoint error:', error)
    res.status(500).json({ error: 'server_error' })
  }
})

/**
 * OpenID Connect UserInfo Endpoint
 * GET /auth/userinfo (with Authorization header)
 * Called by Backstage/AppSmith to get authenticated user profile
 */
router.get('/userinfo', (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'invalid_token' })
    }

    const token = authHeader.substring(7)
    const payload = jwt.verify(token, JWT_SECRET) as any

    res.json({
      sub: payload.userId,
      email: payload.email,
      email_verified: true,
      name: payload.email.split('@')[0],
      roles: payload.roles || [],
      org_id: payload.orgId,
    })
  } catch (error) {
    res.status(401).json({ error: 'invalid_token' })
  }
})

/**
 * JWT Validation Endpoint (custom)
 * POST /auth/validate
 * Appsmith can call this to validate JWT tokens
 */
router.post('/validate', (req: Request, res: Response) => {
  try {
    const { token } = req.body
    if (!token) {
      return res.status(400).json({ valid: false, error: 'Missing token' })
    }

    const payload = jwt.verify(token, JWT_SECRET)
    res.json({
      valid: true,
      payload,
    })
  } catch (error) {
    res.status(401).json({
      valid: false,
      error: 'Invalid or expired token',
    })
  }
})

/**
 * Token Refresh Endpoint (custom)
 * POST /auth/refresh
 * Allows clients to refresh expired tokens
 */
router.post('/refresh', (req: Request, res: Response) => {
  try {
    const { refresh_token } = req.body
    if (!refresh_token) {
      return res.status(400).json({ error: 'Missing refresh_token' })
    }

    // In production: verify refresh_token, check against database
    // For now: validate JWT structure
    const payload = jwt.verify(refresh_token, JWT_SECRET) as any

    // Generate new access token
    const newToken = jwt.sign(
      {
        userId: payload.userId,
        email: payload.email,
        roles: payload.roles,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRES_IN }
    )

    res.json({
      access_token: newToken,
      token_type: 'Bearer',
      expires_in: 86400,
    })
  } catch (error) {
    res.status(401).json({ error: 'invalid_refresh_token' })
  }
})

/**
 * JWKS (JSON Web Key Set) Endpoint
 * GET /auth/jwks
 * Used by Backstage to validate JWT signatures
 */
router.get('/jwks', (req: Request, res: Response) => {
  // In production, return actual public keys for JWT verification
  // For HS256 (symmetric), public key isn't available
  // For RS256 (asymmetric), return the public key
  
  res.json({
    keys: [
      {
        kty: 'oct',
        kid: 'default',
        alg: 'HS256',
        use: 'sig',
        // Note: For HS256 with symmetric keys, this endpoint would typically
        // not include the secret. In production with RS256, include public key.
      },
    ],
  })
})

/**
 * Logout Endpoint
 * POST /auth/logout
 * Revoke tokens for Appsmith/Backstage
 */
router.post('/logout', (req: Request, res: Response) => {
  try {
    // In production: invalidate refresh tokens in database
    res.json({
      success: true,
      message: 'Logged out successfully',
    })
  } catch (error) {
    res.status(500).json({ error: 'logout_failed' })
  }
})

export default router
