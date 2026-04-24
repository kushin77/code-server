package authz

import future.keywords.in

default allow := false

# Allow if user has admin role
allow if {
    input.user.roles[_] == "admin"
}

# Allow read access to public resources
allow if {
    input.method == "GET"
    input.path[0] == "public"
}

# Allow authenticated users to access their own data
allow if {
    input.user.id == input.resource.owner_id
}

# Deny access to sensitive admin endpoints for non-admins
deny contains msg if {
    input.path[0] == "admin"
    not input.user.roles[_] == "admin"
    msg := "Access to admin resources requires admin role"
}
