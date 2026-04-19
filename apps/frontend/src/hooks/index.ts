import { useState } from 'react'
import * as types from '@/types'
import { rbacAPI } from '@/api/rbac-client'
import { useAuthStore, useUserStore } from '@/store'

/**
 * useLogin Hook
 * Handles login flow with optional MFA verification
 */
export const useLogin = () => {
  const { setToken, setUser, setOrg, setError } = useAuthStore()
  const [isLoading, setIsLoading] = useState(false)
  const [error, setLocalError] = useState<string | null>(null)
  const [mfaRequired, setMfaRequired] = useState(false)
  const [mfaToken, setMfaToken] = useState<string | undefined>()

  const login = async (request: types.LoginRequest) => {
    setIsLoading(true)
    setLocalError(null)

    try {
      const response = await rbacAPI.login(request)

      if (response.requiresMfa && response.mfaToken) {
        setMfaRequired(true)
        setMfaToken(response.mfaToken)
        return {
          requiresMfa: true,
          mfaToken: response.mfaToken,
        }
      } else {
        // Login successful
        setToken(response.token)
        setUser(response.user)
        setOrg(response.org)
        setMfaRequired(false)
        return { requiresMfa: false }
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Login failed'
      setLocalError(message)
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const verifyMFA = async (token: string, code: string) => {
    setIsLoading(true)
    setLocalError(null)

    try {
      const response = await rbacAPI.verifyMFA(token, code)
      setToken(response.token)
      setUser(response.user)
      setOrg(response.org)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'MFA verification failed'
      setLocalError(message)
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  return {
    login,
    verifyMFA,
    isLoading,
    error,
    mfaRequired,
    mfaToken,
  }
}

/**
 * useUserManagement Hook
 * Handles user CRUD operations
 */
export const useUserManagement = () => {
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { users, setUsers, addUser, updateUser: updateUserInStore, removeUser, setSelectedUser } = useUserStore()

  const fetchUsers = async (filters?: types.FilterConfig) => {
    setIsLoading(true)
    setError(null)

    try {
      const result = await rbacAPI.getUsers(filters)
      setUsers(result.users)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch users'
      setError(message)
    } finally {
      setIsLoading(false)
    }
  }

  const createUser = async (request: types.CreateUserRequest) => {
    setIsLoading(true)
    setError(null)

    try {
      const newUser = await rbacAPI.createUser(request)
      addUser(newUser)
      return newUser
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create user'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const assignRole = async (userId: string, request: types.AssignRoleRequest) => {
    setIsLoading(true)
    setError(null)

    try {
      await rbacAPI.assignRole(userId, request)
      // Refresh user list to get updated roles
      await fetchUsers()
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to assign role'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const deleteUser = async (userId: string) => {
    setIsLoading(true)
    setError(null)

    try {
      await rbacAPI.deleteUser(userId)
      removeUser(userId)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to delete user'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  return {
    users,
    isLoading,
    error,
    fetchUsers,
    createUser,
    assignRole,
    deleteUser,
  }
}

/**
 * useRepositoryAccess Hook
 * Handles repository access control
 */
export const useRepositoryAccess = () => {
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const grantAccess = async (request: types.GrantRepoAccessRequest) => {
    setIsLoading(true)
    setError(null)

    try {
      const result = await rbacAPI.grantRepositoryAccess(request)
      return result
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to grant access'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const revokeAccess = async (userId: string, repositoryId: string) => {
    setIsLoading(true)
    setError(null)

    try {
      await rbacAPI.revokeRepositoryAccess(userId, repositoryId)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to revoke access'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  return {
    isLoading,
    error,
    grantAccess,
    revokeAccess,
  }
}

/**
 * useAPITokens Hook
 * Handles API token lifecycle
 */
export const useAPITokens = () => {
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [tokens, setTokens] = useState<types.APIToken[]>([])

  const createToken = async (request: types.CreateTokenRequest) => {
    setIsLoading(true)
    setError(null)

    try {
      const result = await rbacAPI.createToken(request)
      setTokens((tokens) => [
        ...tokens,
        {
          id: result.id,
          name: result.name,
          scopes: result.scopes,
          createdAt: result.createdAt,
          expiresAt: result.expiresAt,
        },
      ])
      return result
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create token'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const revokeToken = async (tokenId: string) => {
    setIsLoading(true)
    setError(null)

    try {
      await rbacAPI.revokeToken(tokenId)
      setTokens((tokens) => tokens.filter((t) => t.id !== tokenId))
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to revoke token'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  return {
    tokens,
    isLoading,
    error,
    createToken,
    revokeToken,
  }
}

/**
 * useSessions Hook
 * Handles active session management
 */
export const useSessions = () => {
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [sessions, setSessions] = useState<types.Session[]>([])

  const fetchSessions = async () => {
    setIsLoading(true)
    setError(null)

    try {
      const result = await rbacAPI.getSessions()
      setSessions(result)
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to fetch sessions'
      setError(message)
    } finally {
      setIsLoading(false)
    }
  }

  const revokeSession = async (sessionId: string) => {
    setIsLoading(true)
    setError(null)

    try {
      await rbacAPI.revokeSession(sessionId)
      setSessions((sessions) => sessions.filter((s) => s.id !== sessionId))
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to revoke session'
      setError(message)
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  return {
    sessions,
    isLoading,
    error,
    fetchSessions,
    revokeSession,
  }
}
