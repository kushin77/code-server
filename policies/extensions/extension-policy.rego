package extensions

# OPA Extension Policy - Fail-Closed Extension Security
# Enforces capability declarations and isolation for third-party extensions

# Extension type: agent | model | panel | tool
extension_type := input.type

# Declared capabilities must be in allowed_by_type list
allowed_capabilities_by_type := {
    "agent": [
        "read_files",
        "create_comments",
        "memory_read",
        "event_subscribe",
        "event_publish",
        "ide_panel",
    ],
    "model": [
        "model_inference",
        "gpu_access",
        "batch_processing",
    ],
    "panel": [
        "ide_webview",
        "event_publish",
        "memory_read",
    ],
    "tool": [
        "cli_command",
        "subprocess",
    ],
}

# Permission types
allowed_permissions := [
    "event_bus",
    "ide_panel",
    "filesystem",
    "network",
    "subprocess",
]

# RULE 1: Extension type must be declared
deny[msg] {
    not input.type
    msg := "Extension type must be declared (agent|model|panel|tool)"
}

# RULE 2: Capabilities must be in allowed list
deny[msg] {
    cap := input.capabilities[_]
    not cap in allowed_capabilities_by_type[extension_type]
    msg := sprintf(
        "Capability '%s' not allowed for type '%s'",
        [cap, extension_type]
    )
}

# RULE 3: Cannot declare memory_write (read-only for extensions)
deny[msg] {
    cap := input.capabilities[_]
    cap == "memory_write"
    msg := "Extensions cannot declare memory_write capability (read-only enforced)"
}

# RULE 4: Permission scopes must match capability declarations
deny[msg] {
    perm := input.permissions[_]
    perm_type := perm.type
    
    # event_bus requires event_subscribe or event_publish capability
    perm_type == "event_bus"
    not "event_subscribe" in input.capabilities
    not "event_publish" in input.capabilities
    msg := "event_bus permission requires event_subscribe or event_publish capability"
}

# RULE 5: IDE panel requires ide_panel capability and permission
deny[msg] {
    perm := input.permissions[_]
    perm.type == "ide_panel"
    not "ide_panel" in input.capabilities
    msg := "ide_panel permission requires ide_panel capability declaration"
}

# RULE 6: Filesystem access requires capability
deny[msg] {
    perm := input.permissions[_]
    perm.type == "filesystem"
    access := perm.access
    
    access == "read"
    not "read_files" in input.capabilities
    msg := "Filesystem read access requires read_files capability"
}

deny[msg] {
    perm := input.permissions[_]
    perm.type == "filesystem"
    access := perm.access
    
    access == "write"
    not "write_files" in input.capabilities
    msg := "Filesystem write access not allowed (extensions are read-only)"
}

# RULE 7: Network access requires declaration
deny[msg] {
    perm := input.permissions[_]
    perm.type == "network"
    not perm.allowed_hosts
    msg := "Network permission must explicitly list allowed_hosts"
}

# RULE 8: Marketplace signature must be present for installation
deny[msg] {
    not input.signatures.marketplace_signature
    msg := "Extension must be signed by marketplace for installation"
}

# RULE 9: Author must be declared
deny[msg] {
    not input.author
    msg := "Extension author must be declared"
}

# RULE 10: Version must be semantic
deny[msg] {
    version := input.version
    not regex.match(`^[0-9]+\.[0-9]+\.[0-9]+`, version)
    msg := sprintf("Version must be semantic (major.minor.patch), got: %s", [version])
}

# ALLOW: If no deny rules matched, extension is approved
allow {
    count(deny) == 0
}

# Decision: Default deny (fail-closed)
default allow = false
