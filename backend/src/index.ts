import express, { Express, Request, Response, NextFunction } from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import jwt from 'jsonwebtoken'
import bcrypt from 'bcryptjs'
import speakeasy from 'speakeasy'
import QRCode from 'qrcode'
import { v4 as uuidv4 } from 'uuid'
import oauthRoutes from './oauth.js'

// Load environment variables
dotenv.config()

const app: Express = express()
const PORT = process.env.PORT || 3001
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production'
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '24h'

// Middleware
app.use(cors())
app.use(express.json())
app.use(express.urlencoded({ extended: true }))

// Request logging middleware
app.use((req: Request, res: Response, next: NextFunction) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`)
  next()
})

// Types
interface AuthPayload {
  userId: string
  email: string
  orgId: string
  orgSlug: string
  roles: string[]
}

interface User {
  id: string
  email: string
  fullName: string
  passwordHash: string
  status: 'active' | 'inactive'
  mfaEnabled: boolean
  mfaSecret?: string
  roles: UserRole[]
  createdAt: Date
  updatedAt: Date
}

interface UserRole {
  id: string
  roleId: string
  userId: string
  grantedAt: Date
  expiresAt?: Date
}

interface Role {
  id: string
  name: string
  description: string
  permissions: string[]
}

// In-memory data store (replace with database in production)
const users = new Map<string, User>()
const roles = new Map<string, Role>()
const organizations = new Map<string, { id: string; slug: string; name: string }>()

// Initialize with demo data
const initializeData = () => {
  // Create demo organization
  organizations.set('acme-corp', {
    id: 'org-1',
    slug: 'acme-corp',
    name: 'ACME Corporation',
  })

  // Create demo roles
  const adminRole: Role = {
    id: 'role-admin',
    name: 'Admin',
    description: 'Full administrative access',
    permissions: ['*'],
  }
  const userRole: Role = {
    id: 'role-user',
    name: 'User',
    description: 'Standard user access',
    permissions: ['read:users', 'read:repos'],
  }
  roles.set('role-admin', adminRole)
  roles.set('role-user', userRole)

  // Create demo user (password: password123)
  const hashedPassword = bcrypt.hashSync('password123', 10)
  const adminUser: User = {
    id: 'user-1',
    email: 'admin@example.com',
    fullName: 'Admin User',
    passwordHash: hashedPassword,
    status: 'active',
    mfaEnabled: false,
    roles: [
      {
        id: 'ur-1',
        roleId: 'role-admin',
        userId: 'user-1',
        grantedAt: new Date(),
      },
    ],
    createdAt: new Date(),
    updatedAt: new Date(),
  }
  users.set('user-1', adminUser)
}

initializeData()

// Utility functions
const generateToken = (payload: AuthPayload): string => {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN })
}

const verifyToken = (token: string): AuthPayload | null => {
  try {
    return jwt.verify(token, JWT_SECRET) as AuthPayload
  } catch (error) {
    return null
  }
}

const verifyTokenMiddleware = (req: Request, res: Response, next: NextFunction) => {
  const authHeader = req.headers.authorization
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid authorization header' })
  }

  const token = authHeader.substring(7)
  const payload = verifyToken(token)
  if (!payload) {
    return res.status(401).json({ error: 'Invalid or expired token' })
  }

  ;(req as any).user = payload
  next()
}

// Health check endpoint
app.get('/healthz', (req: Request, res: Response) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() })
})

// OAuth2/OpenID Connect endpoints for Appsmith and Backstage
app.use('/auth', oauthRoutes)

// Authentication endpoints
app.post('/auth/login', async (req: Request, res: Response) => {
  try {
    const { email, password, org_slug } = req.body

    // Validation
    if (!email || !password || !org_slug) {
      return res.status(400).json({ error: 'Email, password, and org_slug are required' })
    }

    // Check organization exists
    const org = organizations.get(org_slug)
    if (!org) {
      return res.status(404).json({ error: 'Organization not found' })
    }

    // Find user by email
    let user: User | null = null
    for (const u of users.values()) {
      if (u.email === email) {
        user = u
        break
      }
    }

    if (!user) {
      return res.status(401).json({ error: 'Invalid email or password' })
    }

    // Verify password
    const passwordMatch = await bcrypt.compare(password, user.passwordHash)
    if (!passwordMatch) {
      return res.status(401).json({ error: 'Invalid email or password' })
    }

    // Check if MFA is enabled
    if (user.mfaEnabled) {
      return res.status(200).json({
        status: 'mfa_required',
        requiresMfa: true,
        mfaToken: generateToken({ userId: user.id, email: user.email, orgId: org.id, orgSlug: org.slug, roles: [] }),
      })
    }

    // Generate JWT token
    const token = generateToken({
      userId: user.id,
      email: user.email,
      orgId: org.id,
      orgSlug: org.slug,
      roles: user.roles.map(r => r.roleId),
    })

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        mfaEnabled: user.mfaEnabled,
      },
      org: {
        id: org.id,
        slug: org.slug,
        name: org.name,
      },
    })
  } catch (error) {
    console.error('Login error:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

app.post('/auth/mfa-verify', (req: Request, res: Response) => {
  try {
    const { mfa_token, totp_code } = req.body

    if (!mfa_token || !totp_code) {
      return res.status(400).json({ error: 'MFA token and TOTP code are required' })
    }

    // Verify MFA token
    const mfaPayload = verifyToken(mfa_token)
    if (!mfaPayload) {
      return res.status(401).json({ error: 'Invalid or expired MFA token' })
    }

    // Find user
    const user = users.get(mfaPayload.userId)
    if (!user || !user.mfaEnabled || !user.mfaSecret) {
      return res.status(401).json({ error: 'MFA not configured for this user' })
    }

    // Verify TOTP code
    const verified = speakeasy.totp.verify({
      secret: user.mfaSecret,
      encoding: 'base32',
      token: totp_code,
      window: 2,
    })

    if (!verified) {
      return res.status(401).json({ error: 'Invalid TOTP code' })
    }

    // Generate JWT token
    const org = organizations.get(mfaPayload.orgSlug)
    if (!org) {
      return res.status(500).json({ error: 'Organization not found' })
    }

    const token = generateToken({
      userId: user.id,
      email: user.email,
      orgId: org.id,
      orgSlug: org.slug,
      roles: user.roles.map(r => r.roleId),
    })

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        mfaEnabled: user.mfaEnabled,
      },
    })
  } catch (error) {
    console.error('MFA verification error:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// MFA Setup endpoints
app.post('/mfa/setup', verifyTokenMiddleware, async (req: Request, res: Response) => {
  try {
    const user = users.get((req as any).user.userId)
    if (!user) {
      return res.status(404).json({ error: 'User not found' })
    }

    // Generate secret
    const secret = speakeasy.generateSecret({
      name: `RBAC Dashboard (${user.email})`,
      issuer: 'RBAC',
      length: 32,
    })

    if (!secret.otpauth_url) {
      return res.status(500).json({ error: 'Failed to generate secret' })
    }

    // Generate QR code
    const qrCode = await QRCode.toDataURL(secret.otpauth_url)

    res.json({
      secret: secret.base32,
      qrCode,
      manualEntryKey: secret.base32,
    })
  } catch (error) {
    console.error('MFA setup error:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

app.post('/mfa/confirm', verifyTokenMiddleware, (req: Request, res: Response) => {
  try {
    const { secret, totp_code } = req.body
    const userId = (req as any).user.userId

    if (!secret || !totp_code) {
      return res.status(400).json({ error: 'Secret and TOTP code are required' })
    }

    // Verify TOTP code with the secret
    const verified = speakeasy.totp.verify({
      secret,
      encoding: 'base32',
      token: totp_code,
      window: 2,
    })

    if (!verified) {
      return res.status(400).json({ error: 'Invalid TOTP code' })
    }

    // Update user to enable MFA
    const user = users.get(userId)
    if (!user) {
      return res.status(404).json({ error: 'User not found' })
    }

    user.mfaEnabled = true
    user.mfaSecret = secret
    user.updatedAt = new Date()

    res.json({
      success: true,
      message: 'MFA enabled successfully',
      backupCodes: Array.from({ length: 8 }, () => Math.random().toString(36).substring(2, 10).toUpperCase()),
    })
  } catch (error) {
    console.error('MFA confirm error:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// User management endpoints
app.get('/users', verifyTokenMiddleware, (req: Request, res: Response) => {
  try {
    const userList = Array.from(users.values()).map(u => ({
      id: u.id,
      email: u.email,
      fullName: u.fullName,
      status: u.status,
      mfaEnabled: u.mfaEnabled,
      roles: u.roles,
      createdAt: u.createdAt,
      updatedAt: u.updatedAt,
    }))

    res.json({ users: userList })
  } catch (error) {
    console.error('Error fetching users:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

app.get('/users/:id', verifyTokenMiddleware, (req: Request, res: Response) => {
  try {
    const user = users.get(req.params.id)
    if (!user) {
      return res.status(404).json({ error: 'User not found' })
    }

    res.json({
      id: user.id,
      email: user.email,
      fullName: user.fullName,
      status: user.status,
      mfaEnabled: user.mfaEnabled,
      roles: user.roles,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    })
  } catch (error) {
    console.error('Error fetching user:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

app.post('/users', verifyTokenMiddleware, async (req: Request, res: Response) => {
  try {
    const { email, fullName, password } = req.body

    if (!email || !fullName || !password) {
      return res.status(400).json({ error: 'Email, fullName, and password are required' })
    }

    // Check if user already exists
    for (const u of users.values()) {
      if (u.email === email) {
        return res.status(409).json({ error: 'User already exists' })
      }
    }

    const userId = `user-${uuidv4().substring(0, 8)}`
    const hashedPassword = await bcrypt.hash(password, 10)

    const newUser: User = {
      id: userId,
      email,
      fullName,
      passwordHash: hashedPassword,
      status: 'active',
      mfaEnabled: false,
      roles: [],
      createdAt: new Date(),
      updatedAt: new Date(),
    }

    users.set(userId, newUser)

    res.status(201).json({
      id: newUser.id,
      email: newUser.email,
      fullName: newUser.fullName,
      status: newUser.status,
      mfaEnabled: newUser.mfaEnabled,
    })
  } catch (error) {
    console.error('Error creating user:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

app.delete('/users/:id', verifyTokenMiddleware, (req: Request, res: Response) => {
  try {
    const user = users.get(req.params.id)
    if (!user) {
      return res.status(404).json({ error: 'User not found' })
    }

    users.delete(req.params.id)
    res.json({ success: true, message: 'User deleted successfully' })
  } catch (error) {
    console.error('Error deleting user:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// Role assignment endpoints
app.post('/users/:userId/roles/:roleId', verifyTokenMiddleware, (req: Request, res: Response) => {
  try {
    const user = users.get(req.params.userId)
    if (!user) {
      return res.status(404).json({ error: 'User not found' })
    }

    const role = roles.get(req.params.roleId)
    if (!role) {
      return res.status(404).json({ error: 'Role not found' })
    }

    // Check if user already has this role
    if (user.roles.some(r => r.roleId === req.params.roleId)) {
      return res.status(409).json({ error: 'User already has this role' })
    }

    const userRole: UserRole = {
      id: `ur-${uuidv4().substring(0, 8)}`,
      roleId: req.params.roleId,
      userId: req.params.userId,
      grantedAt: new Date(),
    }

    user.roles.push(userRole)
    user.updatedAt = new Date()

    res.json({ success: true, userRole })
  } catch (error) {
    console.error('Error assigning role:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// Roles endpoints
app.get('/roles', verifyTokenMiddleware, (req: Request, res: Response) => {
  try {
    const roleList = Array.from(roles.values())
    res.json({ roles: roleList })
  } catch (error) {
    console.error('Error fetching roles:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
})

// Error handling middleware
app.use((err: any, req: Request, res: Response, next: NextFunction) => {
  console.error('Error:', err)
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' })
})

// Start server
app.listen(PORT, () => {
  console.log(`✓ RBAC API server running on port ${PORT}`)
  console.log(`✓ Environment: ${process.env.NODE_ENV || 'development'}`)
  console.log(`✓ Health check: GET http://localhost:${PORT}/healthz`)
})

export default app
