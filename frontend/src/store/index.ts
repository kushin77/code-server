import { create } from 'zustand'
import * as types from '@/types'

/**
 * Authentication Store
 * Manages global auth state (token, user, org)
 */
export const useAuthStore = create<types.AuthState>((set) => ({
  token: localStorage.getItem('auth_token'),
  user: null,
  org: null,
  isAuthenticated: !!localStorage.getItem('auth_token'),
  isLoading: false,
  error: null,
  
  setToken: (token) => {
    if (token) {
      localStorage.setItem('auth_token', token)
      set({ token, isAuthenticated: true })
    } else {
      localStorage.removeItem('auth_token')
      set({ token: null, isAuthenticated: false })
    }
  },
  
  setUser: (user) => set({ user }),
  
  setOrg: (org) => set({ org }),
  
  setError: (error) => set({ error }),
  
  clearAuth: () => {
    localStorage.removeItem('auth_token')
    set({ token: null, user: null, org: null, isAuthenticated: false })
  },
}))

/**
 * User Management Store
 * Manages user list state and operations
 */
export const useUserStore = create<types.UserState>((set) => ({
  users: [],
  selectedUser: null,
  filters: {},
  isLoading: false,
  
  setUsers: (users) => set({ users }),
  
  addUser: (user) => set((state) => ({ users: [user, ...state.users] })),
  
  updateUser: (user) => {
    set((state) => ({
      users: state.users.map((u) => (u.id === user.id ? user : u)),
      selectedUser: state.selectedUser?.id === user.id ? user : state.selectedUser,
    }))
  },
  
  removeUser: (userId) => {
    set((state) => ({
      users: state.users.filter((u) => u.id !== userId),
      selectedUser: state.selectedUser?.id === userId ? null : state.selectedUser,
    }))
  },
  
  setSelectedUser: (user) => set({ selectedUser: user }),
  
  setLoading: (loading) => set({ isLoading: loading }),
  
  fetchUsers: async () => {
    // Placeholder: will be called by hooks
  },
}))

/**
 * Role Store
 * Manages role definitions (read-only)
 */
export const useRoleStore = create<types.RoleState>((set) => ({
  roles: [
    {
      id: 'admin',
      name: 'Administrator',
      description: 'Full access to all resources',
      permissions: [],
    },
    {
      id: 'developer',
      name: 'Developer',
      description: 'Read/write access to repositories',
      permissions: [],
    },
    {
      id: 'reviewer',
      name: 'Code Reviewer',
      description: 'Read access and code review permissions',
      permissions: [],
    },
    {
      id: 'viewer',
      name: 'Viewer',
      description: 'Read-only access',
      permissions: [],
    },
    {
      id: 'auditor',
      name: 'Auditor',
      description: 'Audit log access only',
      permissions: [],
    },
  ],
  
  setRoles: (roles) => set({ roles }),
  
  addRole: (role) => set((state) => ({ roles: [...state.roles, role] })),
  
  removeRole: (roleId) => set((state) => ({ roles: state.roles.filter((r) => r.id !== roleId) })),
}))
