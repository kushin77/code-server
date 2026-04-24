/**
 * @file apps/frontend/src/pages/UserManagement.tsx
 * @module pages/user-management
 * @description User management interface for administrative controls
 */
import React, { useEffect, useMemo, useState } from 'react';
import { useAuthStore } from '@/store';
import { Button, Input, Alert, Card, Spinner } from '@/components/Common';
/**
 * UserManagementPage - Admin interface for user management
 */
export const UserManagementPage = () => {
    const { user: currentUser } = useAuthStore();
    const [state, setState] = useState({
        users: [],
        isLoading: false,
        error: null,
        searchQuery: '',
        selectedUserId: null,
    });
    // Load users on mount
    useEffect(() => {
        const loadUsers = async () => {
            setState((prev) => ({ ...prev, isLoading: true, error: null }));
            try {
                // TODO: Implement user loading from API
                // const response = await fetch('/api/admin/users')
                // const users = await response.json()
                // setState((prev) => ({ ...prev, users }))
                setState((prev) => ({ ...prev, users: [] }));
            }
            catch (err) {
                setState((prev) => ({
                    ...prev,
                    error: err instanceof Error ? err.message : 'Failed to load users',
                }));
            }
            finally {
                setState((prev) => ({ ...prev, isLoading: false }));
            }
        };
        loadUsers();
    }, []);
    const filteredUsers = useMemo(() => {
        return state.users.filter((user) => user.username.toLowerCase().includes(state.searchQuery.toLowerCase()) ||
            user.email.toLowerCase().includes(state.searchQuery.toLowerCase()));
    }, [state.users, state.searchQuery]);
    const handleSearch = (query) => {
        setState((prev) => ({ ...prev, searchQuery: query }));
    };
    const handleSelectUser = (userId) => {
        setState((prev) => ({ ...prev, selectedUserId: userId }));
    };
    const handleRemoveUser = async (userId) => {
        try {
            // TODO: Implement user removal from API
            // await fetch(`/api/admin/users/${userId}`, { method: 'DELETE' })
            setState((prev) => ({
                ...prev,
                users: prev.users.filter((u) => u.id !== userId),
            }));
        }
        catch (err) {
            setState((prev) => ({
                ...prev,
                error: err instanceof Error ? err.message : 'Failed to remove user',
            }));
        }
    };
    return (<div className="space-y-4 p-4">
      <Card title="User Management">
        <div className="space-y-4">
          {!currentUser ? (<Alert type="error">Not authenticated</Alert>) : (<>
              <Input label="Search users" placeholder="Search by username or email..." value={state.searchQuery} onChange={(e) => handleSearch(e.currentTarget.value)}/>

              {state.error && <Alert type="error">{state.error}</Alert>}

              {state.isLoading ? (<div className="flex justify-center">
                  <Spinner size="md"/>
                </div>) : filteredUsers.length > 0 ? (<div className="space-y-2 border border-gray-200 rounded-lg overflow-hidden">
                  {filteredUsers.map((user) => (<div key={user.id} className={`p-4 border-b border-gray-200 cursor-pointer hover:bg-gray-50 transition ${state.selectedUserId === user.id ? 'bg-blue-50' : ''}`} onClick={() => handleSelectUser(user.id)}>
                      <div className="flex justify-between items-start">
                        <div>
                          <p className="font-semibold text-gray-900">{user.username}</p>
                          <p className="text-sm text-gray-600">{user.email}</p>
                          <div className="mt-2 flex gap-1 flex-wrap">
                            {user.roles.map((role) => (<span key={role} className="inline-block bg-blue-100 text-blue-800 text-xs px-2 py-1 rounded">
                                {role}
                              </span>))}
                          </div>
                        </div>
                        <Button label="Remove" variant="danger" size="sm" onClick={(e) => {
                        e.stopPropagation();
                        handleRemoveUser(user.id);
                    }}/>
                      </div>
                    </div>))}
                </div>) : (<p className="text-gray-500 text-center py-8">No users found</p>)}
            </>)}
        </div>
      </Card>
    </div>);
};
export default UserManagementPage;
//# sourceMappingURL=UserManagement.js.map