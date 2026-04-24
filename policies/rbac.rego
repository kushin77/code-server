package system.rbac

default allow = false

# Role definitions
roles := {
    "admin": ["read", "write", "delete", "admin"],
    "operator": ["read", "write"],
    "viewer": ["read"]
}

# User to Role mapping (Example)
user_roles := {
    "admin_user": "admin",
    "ops_user": "operator",
    "guest": "viewer"
}

# Allow if user has required permission
allow {
    some role
    role := user_roles[input.user]
    permissions := roles[role]
    some p
    p := permissions[_]
    p == input.action
}
