#!/usr/bin/env python3
# @file        validate_workflows.py
# @module      ci/workflow-validation
# @description Validate selected workflow YAML files and pinned actions
#
import yaml
import re

workflows = [
    '.github/workflows/policy-bundle-governance.yml',
    '.github/workflows/governance-waiver-audit.yml',
    '.github/workflows/policy-ssot-guard.yml'
]

all_valid = True

# Validate YAML syntax
for wf in workflows:
    try:
        with open(wf, 'r') as f:
            yaml.safe_load(f)
        print(f"✓ {wf} valid YAML")
    except Exception as e:
        print(f"✗ {wf} ERROR: {e}")
        all_valid = False

# Check for unpinned actions
print("\n--- Action Pin Status ---")
for wf in workflows:
    try:
        with open(wf, 'r') as f:
            content = f.read()
        # Look for action lines - version tags or SHAs
        actions = re.findall(r'uses: ([^\n]+)', content)
        unpinned = []
        for action in actions:
            action = action.split('#', 1)[0].strip()
            # Check if it has @ and either v<semver> or 40-char SHA
            if '@' in action:
                parts = action.split('@')
                if len(parts) == 2:
                    pin = parts[1].strip()
                    # Valid: v1.2.3, v4.2.2, or 40-char hex (SHA)
                    if re.match(r'v\d+\.\d+\.\d+$', pin) or re.match(r'[a-f0-9]{40}$', pin):
                        continue
                unpinned.append(action)
            else:
                unpinned.append(action)

        if unpinned:
            print(f"! {wf} unpinned actions: {unpinned}")
            all_valid = False
        else:
            print(f"✓ {wf} all actions properly pinned")
    except Exception as e:
        print(f"✗ {wf} error checking actions: {e}")
        all_valid = False

if all_valid:
    print("\n✓ All workflows valid and compliant")
else:
    print("\n✗ Issues found in workflows")
    exit(1)
