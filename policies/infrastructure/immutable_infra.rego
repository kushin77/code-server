# @file immutable_infra.rego
# @module policies/infrastructure
# @description Enforce immutable infrastructure patterns - no manual mutations outside IaC
# @governance GOV-003 - Infrastructure Immutability

package infrastructure.immutable_infra

import future.keywords.if
import future.keywords.contains

mutable_command_types := {"file_modify", "config_change", "package_install"}
deployment_actions := {"docker_pull", "deploy_container"}
apply_actions := {"apply_terraform", "apply_docker_compose"}
mutable_image_tags := {"latest", "main", "stable"}

prod_target(target) {
    contains(lower(target), "prod")
}

modifies_container {
    input.modify_filesystem
} {
    input.modify_config
}

# Deny manual SSH modifications to production hosts
deny[msg] {
    input.action == "ssh_command"
    input.target_host
    prod_target(input.target_host)
    mutable_command_types[input.command_type]
    msg := "Production infrastructure is immutable: all changes must go through IaC (Terraform/Docker Compose)"
}

# Deny direct Docker container modifications on managed hosts
deny[msg] {
    input.action == "docker_command"
    input.command == "exec"
    input.target_container
    prod_target(input.target_container)
    modifies_container
    msg := "Direct container modification denied: use docker-compose and Terraform instead"
}

# Deny untracked image modifications
deny[msg] {
    input.action == "docker_build"
    not input.dockerfile_path
    msg := "Image build must reference Dockerfile path for audit trail"
}

# Deny floating/mutable image tags in production
deny[msg] {
    deployment_actions[input.action]
    input.target_env == "production"
    input.image_tag
    mutable_image_tags[input.image_tag]
    msg := sprintf("Production deployments require immutable image digests, not tags like '%s'", [input.image_tag])
}

# Deny manual secrets modifications in production
deny[msg] {
    input.action == "modify_secret"
    input.target_env == "production"
    msg := "Secrets in production must be updated through GSM (Google Secret Manager), not manual entry"
}

# Deny uncommitted infrastructure changes
deny[msg] {
    apply_actions[input.action]
    input.target_env == "production"
    not input.from_git_commit
    msg := "Production infrastructure changes must originate from Git commit (GitOps requirement)"
}

# Allow changes that go through proper IaC channels
allow[msg] {
    apply_actions[input.action]
    input.from_git_commit
    input.commit_sha
    msg := sprintf("Infrastructure change approved: tracked in Git commit %s", 
        [substring(input.commit_sha, 0, 7)])
}

# Allow image pulls with immutable digests
allow[msg] {
    deployment_actions[input.action]
    input.image_digest
    msg := sprintf("Immutable image deployment approved: digest %s", 
        [substring(input.image_digest, 0, 12)])
}

# Audit all infrastructure changes
audit_event[event] {
    apply_actions[input.action]
    event := {
        "action": input.action,
        "timestamp": input.timestamp,
        "actor": input.actor_id,
        "git_commit": input.commit_sha,
        "environment": input.target_env
    }
}
