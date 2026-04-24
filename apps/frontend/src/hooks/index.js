import { useState } from 'react';
import { rbacAPI } from '@/api/rbac-client';
import { useAuthStore, useUserStore } from '@/store';
/**
 * NOTE: Many hooks show as unused by ts-prune but are actually:
 * - Used in page components via destructuring assignments
 * - Part of the public hook API for component integration
 * - Used internally within the monorepo
 *
 * @ts-prune-ignore (issue #1023)
 */
/**
 * useLogin Hook
 * Handles login flow with optional MFA verification
 * @ts-prune-ignore - Public hook API for component integration
 */
// @ts-prune-ignore
export const useLogin = () => {
    const { setToken, setUser, setOrg, setError } = useAuthStore();
    const [isLoading, setIsLoading] = useState(false);
    const [error, setLocalError] = useState(null);
    const [mfaRequired, setMfaRequired] = useState(false);
    const [mfaToken, setMfaToken] = useState();
    const login = async (request) => {
        setIsLoading(true);
        setLocalError(null);
        try {
            const response = await rbacAPI.login(request);
            if (response.requiresMfa && response.mfaToken) {
                setMfaRequired(true);
                setMfaToken(response.mfaToken);
                return {
                    requiresMfa: true,
                    mfaToken: response.mfaToken,
                };
            }
            else {
                // Login successful
                setToken(response.token);
                setUser(response.user);
                setOrg(response.org);
                setMfaRequired(false);
                return { requiresMfa: false };
            }
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Login failed';
            setLocalError(message);
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const verifyMFA = async (token, code) => {
        setIsLoading(true);
        setLocalError(null);
        try {
            const response = await rbacAPI.verifyMFA(token, code);
            setToken(response.token);
            setUser(response.user);
            setOrg(response.org);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'MFA verification failed';
            setLocalError(message);
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    return {
        login,
        verifyMFA,
        isLoading,
        error,
        mfaRequired,
        mfaToken,
    };
};
/**
 * useUserManagement Hook
 * Handles user CRUD operations
 * @ts-prune-ignore - Public hook API for component integration
 */
// @ts-prune-ignore
export const useUserManagement = () => {
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState(null);
    const { users, setUsers, addUser, removeUser } = useUserStore();
    const fetchUsers = async (filters) => {
        setIsLoading(true);
        setError(null);
        try {
            const result = await rbacAPI.getUsers(filters);
            setUsers(result.users);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to fetch users';
            setError(message);
        }
        finally {
            setIsLoading(false);
        }
    };
    const createUser = async (request) => {
        setIsLoading(true);
        setError(null);
        try {
            const newUser = await rbacAPI.createUser(request);
            addUser(newUser);
            return newUser;
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to create user';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const assignRole = async (userId, request) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.assignRole(userId, request);
            // Refresh user list to get updated roles
            await fetchUsers();
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to assign role';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const deleteUser = async (userId) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.deleteUser(userId);
            removeUser(userId);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to delete user';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    return {
        users,
        isLoading,
        error,
        fetchUsers,
        createUser,
        assignRole,
        deleteUser,
    };
};
/**
 * useRepositoryAccess Hook
 * Handles repository access control
 * @ts-prune-ignore - Public hook API for component integration
 */
// @ts-prune-ignore
export const useRepositoryAccess = () => {
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState(null);
    const grantAccess = async (request) => {
        setIsLoading(true);
        setError(null);
        try {
            const result = await rbacAPI.grantRepositoryAccess(request);
            return result;
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to grant access';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const revokeAccess = async (userId, repositoryId) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.revokeRepositoryAccess(userId, repositoryId);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to revoke access';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    return {
        isLoading,
        error,
        grantAccess,
        revokeAccess,
    };
};
/**
 * useAPITokens Hook
 * Handles API token lifecycle
 * @ts-prune-ignore - Public hook API for component integration
 */
// @ts-prune-ignore
export const useAPITokens = () => {
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState(null);
    const [tokens, setTokens] = useState([]);
    const createToken = async (request) => {
        setIsLoading(true);
        setError(null);
        try {
            const result = await rbacAPI.createToken(request);
            setTokens((tokens) => [
                ...tokens,
                {
                    id: result.id,
                    name: result.name,
                    scopes: result.scopes,
                    createdAt: result.createdAt,
                    expiresAt: result.expiresAt,
                },
            ]);
            return result;
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to create token';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const revokeToken = async (tokenId) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.revokeToken(tokenId);
            setTokens((tokens) => tokens.filter((t) => t.id !== tokenId));
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to revoke token';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    return {
        tokens,
        isLoading,
        error,
        createToken,
        revokeToken,
    };
};
/**
 * useSessions Hook
 * Handles active session management
 * @ts-prune-ignore - Public hook API for component integration
 */
// @ts-prune-ignore
export const useSessions = () => {
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState(null);
    const [sessions, setSessions] = useState([]);
    const fetchSessions = async () => {
        setIsLoading(true);
        setError(null);
        try {
            const result = await rbacAPI.getSessions();
            setSessions(result);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to fetch sessions';
            setError(message);
        }
        finally {
            setIsLoading(false);
        }
    };
    const revokeSession = async (sessionId) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.revokeSession(sessionId);
            setSessions((sessions) => sessions.filter((s) => s.id !== sessionId));
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to revoke session';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    return {
        sessions,
        isLoading,
        error,
        fetchSessions,
        revokeSession,
    };
};
/**
 * useEphemeralSessions Hook
 * Handles session-broker lifecycle actions for launch, status, cancel, and destroy
 * @ts-prune-ignore - Public hook API for component integration
 */
// @ts-prune-ignore
export const useEphemeralSessions = () => {
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState(null);
    const [session, setSession] = useState(null);
    const [status, setStatus] = useState(null);
    const launchSession = async (request) => {
        setIsLoading(true);
        setError(null);
        try {
            const result = await rbacAPI.launchSession(request);
            setSession(result);
            return result;
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to launch session';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const fetchSessionStatus = async (sessionId) => {
        setIsLoading(true);
        setError(null);
        try {
            const result = await rbacAPI.getSessionStatus(sessionId);
            setStatus(result);
            return result;
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to fetch session status';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const cancelSession = async (sessionId) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.cancelSession(sessionId);
            setStatus((current) => current && current.sessionId === sessionId
                ? { ...current, state: 'teardown_pending', active: false, terminal: false, nextActions: ['destroy'] }
                : current);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to cancel session';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    const destroySession = async (sessionId) => {
        setIsLoading(true);
        setError(null);
        try {
            await rbacAPI.destroySession(sessionId);
            setSession((current) => (current?.sessionId === sessionId ? null : current));
            setStatus((current) => current && current.sessionId === sessionId
                ? { ...current, state: 'destroyed', active: false, terminal: true, nextActions: [] }
                : current);
        }
        catch (err) {
            const message = err instanceof Error ? err.message : 'Failed to destroy session';
            setError(message);
            throw err;
        }
        finally {
            setIsLoading(false);
        }
    };
    return {
        session,
        status,
        isLoading,
        error,
        launchSession,
        fetchSessionStatus,
        cancelSession,
        destroySession,
    };
};
//# sourceMappingURL=index.js.map