import React, { useState, useEffect } from 'react'
import { Button, Input, Alert, Spinner, Card } from '@/components/Common'
import { useUserManagement } from '@/hooks'
import type { User } from '@/types'

/**
 * UserManagementPage Component
 * Admin interface for user CRUD, role assignment, and permission management
 */
export const UserManagementPage: React.FC = () => {
  const { users, isLoading, error, deleteUser, fetchUsers } = useUserManagement()
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [selectedUser, setSelectedUser] = useState<User | null>(null)

  useEffect(() => {
    fetchUsers()
  }, [])

  const filteredUsers = users.filter(
    user =>
      user.email.toLowerCase().includes(searchQuery.toLowerCase()) ||
      user.fullName.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const handleDeleteUser = async (userId: string) => {
    if (confirm('Are you sure you want to delete this user?')) {
      try {
        await deleteUser(userId)
        await fetchUsers()
      } catch (err) {
        console.error('Failed to delete user:', err)
      }
    }
  }

  if (isLoading && users.length === 0) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <Spinner size="lg" label="Loading users..." />
      </div>
    )
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">User Management</h1>
        <p className="text-gray-600">Manage organization users, roles, and permissions</p>
      </div>

      {/* Error Alert */}
      {error && <Alert type="error">{error}</Alert>}

      {/* Search and Create */}
      <div className="mb-6 flex gap-4">
        <Input
          type="text"
          placeholder="Search users by email or name..."
          value={searchQuery}
          onChange={(e: React.ChangeEvent<HTMLInputElement>) => setSearchQuery(e.target.value)}
          className="flex-1"
        />
        <Button onClick={() => setShowCreateModal(true)} variant="primary" label="+ New User" />
      </div>

      {/* Users Table */}
      <Card>
        {filteredUsers.length === 0 ? (
          <div className="text-center py-8">
            <p className="text-gray-500">No users found</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b">
                  <th className="text-left py-3 px-4 font-semibold">Email</th>
                  <th className="text-left py-3 px-4 font-semibold">Name</th>
                  <th className="text-left py-3 px-4 font-semibold">Status</th>
                  <th className="text-left py-3 px-4 font-semibold">MFA</th>
                  <th className="text-left py-3 px-4 font-semibold">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredUsers.map(user => (
                  <tr key={user.id} className="border-b hover:bg-gray-50">
                    <td className="py-3 px-4">{user.email}</td>
                    <td className="py-3 px-4">{user.fullName}</td>
                    <td className="py-3 px-4">
                      <span
                        className={`inline-flex px-2 py-1 rounded text-xs font-medium ${
                          user.status === 'active'
                            ? 'bg-green-100 text-green-800'
                            : 'bg-gray-100 text-gray-800'
                        }`}
                      >
                        {user.status}
                      </span>
                    </td>
                    <td className="py-3 px-4">
                      {user.mfaEnabled ? (
                        <span className="text-green-600 font-medium">✓ Enabled</span>
                      ) : (
                        <span className="text-gray-400">Disabled</span>
                      )}
                    </td>
                    <td className="py-3 px-4">
                      <div className="flex gap-2">
                        <Button
                          size="sm"
                          variant="secondary"
                          label="Edit"
                          onClick={() => setSelectedUser(user)}
                        />
                        <Button
                          size="sm"
                          variant="danger"
                          label="Delete"
                          onClick={() => handleDeleteUser(user.id)}
                        />
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {/* Create User Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center">
          <Card className="w-full max-w-md">
            <h2 className="text-xl font-bold mb-4">Create New User</h2>
            <div className="space-y-4">
              <Input label="Email" type="email" placeholder="user@example.com" />
              <Input label="Full Name" type="text" placeholder="John Doe" />
              <div className="flex gap-2">
                <Button
                  variant="secondary"
                  fullWidth
                  label="Cancel"
                  onClick={() => setShowCreateModal(false)}
                />
                <Button variant="primary" fullWidth label="Create" />
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* User Detail Modal */}
      {selectedUser && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center">
          <Card className="w-full max-w-md">
            <h2 className="text-xl font-bold mb-4">User Details</h2>
            <div className="space-y-3 mb-4">
              <p>
                <span className="font-medium">Email:</span> {selectedUser.email}
              </p>
              <p>
                <span className="font-medium">Name:</span> {selectedUser.fullName}
              </p>
              <p>
                <span className="font-medium">Status:</span> {selectedUser.status}
              </p>
              <p>
                <span className="font-medium">MFA:</span> {selectedUser.mfaEnabled ? 'Enabled' : 'Disabled'}
              </p>
            </div>
            <Button
              variant="secondary"
              fullWidth
              label="Close"
              onClick={() => setSelectedUser(null)}
            />
          </Card>
        </div>
      )}
    </div>
  )
}
