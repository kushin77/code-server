#!/usr/bin/env python3
# @file        policies/policy_manager.py
# @module      policy-management
# @description Dynamic policy management with hot-reloading and versioning
#
# Supports loading, managing, and updating OPA policies without server restart
# Implements version control and rollback for policy changes

import json
import yaml
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime
import hashlib
from enum import Enum


class PolicyStatus(Enum):
    """Policy deployment status"""
    DRAFT = "draft"
    PUBLISHED = "published"
    DEPRECATED = "deprecated"
    DISABLED = "disabled"


@dataclass
class PolicyVersion:
    """Versioned policy snapshot"""
    policy_path: str
    version: int
    content: str
    content_hash: str
    created_at: float
    created_by: str
    comment: str
    test_coverage_percent: float
    status: PolicyStatus = PolicyStatus.DRAFT


class PolicyManager:
    """
    Manage OPA policies with versioning and hot-reload.
    
    Features:
    - Policy versioning (track all versions)
    - Hot-reload (update without restart)
    - Rollback (revert to previous version)
    - Validation (test policies before deployment)
    - Dependency tracking (track policy dependencies)
    """
    
    def __init__(self, policy_storage_path: str = "/policies"):
        self.storage_path = policy_storage_path
        self.policies: Dict[str, PolicyVersion] = {}
        self.policy_history: Dict[str, List[PolicyVersion]] = {}
        self.dependencies: Dict[str, List[str]] = {}  # Track policy dependencies
        self.active_versions: Dict[str, int] = {}  # Track active version per policy
    
    def create_policy(self,
                     policy_path: str,
                     content: str,
                     created_by: str,
                     comment: str = "",
                     test_coverage: float = 0.0) -> PolicyVersion:
        """
        Create new policy version.
        
        Args:
            policy_path: e.g., "ai/prompt-safety" or "core/secrets"
            content: Rego policy content
            created_by: User creating policy
            comment: Change description
            test_coverage: Percentage of code covered by tests
        """
        content_hash = hashlib.sha256(content.encode()).hexdigest()
        
        # Determine version number
        if policy_path not in self.policy_history:
            self.policy_history[policy_path] = []
        
        version_num = len(self.policy_history[policy_path]) + 1
        
        policy = PolicyVersion(
            policy_path=policy_path,
            version=version_num,
            content=content,
            content_hash=content_hash,
            created_at=datetime.utcnow().timestamp(),
            created_by=created_by,
            comment=comment,
            test_coverage_percent=test_coverage,
            status=PolicyStatus.DRAFT
        )
        
        self.policy_history[policy_path].append(policy)
        return policy
    
    def validate_policy(self, policy: PolicyVersion) -> Tuple[bool, List[str]]:
        """
        Validate policy syntax and test coverage.
        
        Returns:
            Tuple of (is_valid, list_of_errors)
        """
        errors = []
        
        # Check syntax (simplified)
        if not policy.content.strip():
            errors.append("Policy content is empty")
        
        if "package policy" not in policy.content:
            errors.append("Missing 'package policy' declaration")
        
        # Check test coverage
        if policy.test_coverage_percent < 50:
            errors.append(f"Test coverage {policy.test_coverage_percent}% below 50% threshold")
        
        # Check for forbidden patterns
        forbidden = ["exec", "eval", "system"]
        for pattern in forbidden:
            if pattern in policy.content.lower():
                errors.append(f"Forbidden pattern '{pattern}' found in policy")
        
        return (len(errors) == 0, errors)
    
    def publish_policy(self, policy_path: str, version: int) -> bool:
        """
        Publish policy version (make active).
        
        Process:
        1. Get version from history
        2. Validate policy
        3. Check for conflicts
        4. Publish (set as active)
        5. Notify OPA
        """
        if policy_path not in self.policy_history:
            return False
        
        versions = self.policy_history[policy_path]
        if version > len(versions) or version < 1:
            return False
        
        target_policy = versions[version - 1]
        
        # Validate
        is_valid, errors = self.validate_policy(target_policy)
        if not is_valid:
            return False
        
        # Check conflicts with active policies
        current_active = self.policies.get(policy_path)
        if current_active and current_active.status == PolicyStatus.PUBLISHED:
            # Check for breaking changes
            if self._has_breaking_changes(current_active, target_policy):
                return False
        
        # Publish
        target_policy.status = PolicyStatus.PUBLISHED
        self.policies[policy_path] = target_policy
        self.active_versions[policy_path] = version
        
        return True
    
    def rollback_policy(self, policy_path: str, target_version: int) -> bool:
        """
        Rollback policy to previous version.
        
        Safety checks:
        - Verify target version exists
        - Validate target version
        - Check for dependent policies
        - Execute rollback
        """
        if policy_path not in self.policy_history:
            return False
        
        versions = self.policy_history[policy_path]
        if target_version > len(versions) or target_version < 1:
            return False
        
        target_policy = versions[target_version - 1]
        
        # Validate target
        is_valid, _ = self.validate_policy(target_policy)
        if not is_valid:
            return False
        
        # Check dependents
        dependents = self.dependencies.get(policy_path, [])
        if dependents:
            # All dependents must also be reverted
            for dependent in dependents:
                if dependent in self.policies:
                    if not self._can_revert_dependent(dependent, policy_path):
                        return False
        
        # Execute rollback
        target_policy.status = PolicyStatus.PUBLISHED
        self.policies[policy_path] = target_policy
        self.active_versions[policy_path] = target_version
        
        return True
    
    def deprecate_policy(self, policy_path: str) -> bool:
        """Mark policy as deprecated (no longer used)"""
        if policy_path not in self.policies:
            return False
        
        self.policies[policy_path].status = PolicyStatus.DEPRECATED
        return True
    
    def disable_policy(self, policy_path: str) -> bool:
        """Disable policy (still exists, but not evaluated)"""
        if policy_path not in self.policies:
            return False
        
        self.policies[policy_path].status = PolicyStatus.DISABLED
        return True
    
    def get_policy_history(self, policy_path: str) -> List[PolicyVersion]:
        """Get all versions of policy"""
        return self.policy_history.get(policy_path, [])
    
    def get_active_policy(self, policy_path: str) -> Optional[PolicyVersion]:
        """Get currently active policy version"""
        return self.policies.get(policy_path)
    
    def set_policy_dependency(self, policy: str, depends_on: List[str]) -> None:
        """Register policy dependencies"""
        self.dependencies[policy] = depends_on
    
    def get_policy_graph(self) -> Dict:
        """Get dependency graph of all policies"""
        return {
            "policies": {
                policy_path: {
                    "version": self.active_versions.get(policy_path),
                    "status": self.policies[policy_path].status.value if policy_path in self.policies else "unknown",
                    "dependencies": self.dependencies.get(policy_path, [])
                }
                for policy_path in self.policies
            },
            "reverse_dependencies": self._compute_reverse_dependencies()
        }
    
    def export_policies(self, format: str = "json") -> str:
        """
        Export all active policies.
        
        Formats: json, yaml, rego
        """
        if format == "json":
            data = {
                policy_path: {
                    "version": self.active_versions.get(policy_path),
                    "content": policy.content,
                    "status": policy.status.value
                }
                for policy_path, policy in self.policies.items()
            }
            return json.dumps(data, indent=2)
        
        elif format == "yaml":
            data = {
                policy_path: {
                    "version": self.active_versions.get(policy_path),
                    "content": policy.content,
                    "status": policy.status.value
                }
                for policy_path, policy in self.policies.items()
            }
            return yaml.dump(data)
        
        else:  # rego
            rego_files = []
            for policy_path, policy in self.policies.items():
                if policy.status == PolicyStatus.PUBLISHED:
                    rego_files.append(f"# {policy_path} (v{self.active_versions[policy_path]})\n{policy.content}")
            return "\n\n".join(rego_files)
    
    # =====================================================================
    # Private helper methods
    # =====================================================================
    
    def _has_breaking_changes(self, old_policy: PolicyVersion, new_policy: PolicyVersion) -> bool:
        """Detect if new policy has breaking changes"""
        # Simplified check: compare decision changes
        # In production, would parse Rego and analyze semantically
        old_allow_rules = old_policy.content.count("allow")
        new_allow_rules = new_policy.content.count("allow")
        
        # Breaking if new version removes allow rules
        return new_allow_rules < old_allow_rules
    
    def _can_revert_dependent(self, dependent_policy: str, target_policy: str) -> bool:
        """Check if dependent policy can be reverted"""
        # Simplified: allow if dependent exists and is valid
        if dependent_policy not in self.policies:
            return False
        
        policy = self.policies[dependent_policy]
        is_valid, _ = self.validate_policy(policy)
        return is_valid
    
    def _compute_reverse_dependencies(self) -> Dict[str, List[str]]:
        """Compute reverse dependency graph"""
        reverse = {}
        for policy, deps in self.dependencies.items():
            for dep in deps:
                if dep not in reverse:
                    reverse[dep] = []
                reverse[dep].append(policy)
        return reverse
