import { useEffect } from 'react'
import { useUserManagement } from '@/hooks'

export function UserManagementPage() {
  const { users, isLoading, error, fetchUsers } = useUserManagement()

  useEffect(() => {
    void fetchUsers()
  }, [fetchUsers])

  return (
    <main style={{ padding: '2rem' }}>
      <h1>User Management</h1>
      {error ? <p>{error}</p> : null}
      {isLoading ? <p>Loading users...</p> : null}
      <ul>
        {users.map((user) => (
          <li key={user.id}>{user.email ?? user.id}</li>
        ))}
      </ul>
    </main>
  )
}
