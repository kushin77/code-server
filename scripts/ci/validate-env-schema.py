#!/usr/bin/env python3
# @file        scripts/ci/validate-env-schema.py
# @module      ci/governance
# @description Validate environment variables against .env.schema.json
#

import json
import os
import sys
import re

def load_json(file_path):
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading {file_path}: {e}")
        return None

def parse_env(file_path):
    env_vars = {}
    if not os.path.exists(file_path):
        return env_vars
    try:
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.strip()] = value.strip()
    except Exception as e:
        print(f"Error parsing {file_path}: {e}")
    return env_vars

def validate():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
    schema_path = os.path.join(root_dir, ".env.schema.json")
    
    # Try multiple .env variants
    env_paths = [
        os.path.join(root_dir, ".env"),
        os.path.join(root_dir, ".env.production"),
        os.path.join(root_dir, ".env.defaults")
    ]
    
    env_path = next((p for p in env_paths if os.path.exists(p) and os.path.getsize(p) > 0), None)
    
    schema = load_json(schema_path)
    if not schema:
        sys.exit(1)
        
    if not env_path:
        print(f"⚠️  No non-empty .env file found. Skipping validation.")
        return 0
        
    actual_vars = parse_env(env_path)
    print(f"🔍 Validating {os.path.basename(env_path)} against {schema_path}")

    errors = 0
    warnings = 0
    
    # Get properties from schema (handle nested "properties" if exists)
    properties = schema.get("properties", schema)
    
    for key, spec in properties.items():
        if not isinstance(spec, dict):
            continue
            
        is_required = spec.get("required", False)
        
        if key not in actual_vars:
            if is_required:
                print(f"❌ ERROR: Missing required variable: {key}")
                errors += 1
            else:
                # Optional variable missing
                pass
        else:
            value = actual_vars[key]
            v_type = spec.get("type", "string")
            
            # Basic type check
            if v_type == "boolean":
                if value.lower() not in ["true", "false", "1", "0"]:
                    print(f"❌ ERROR: Variable {key} should be boolean, got '{value}'")
                    errors += 1
            elif v_type == "integer":
                if not value.isdigit():
                    print(f"❌ ERROR: Variable {key} should be integer, got '{value}'")
                    errors += 1
            
            # Value restriction/pattern check (e.g. image pinning)
            description = spec.get("description", "").lower()
            if "pinned" in description or "digest" in description:
                if "@sha256:" not in value and "codercom/code-server" in value:
                     print(f"⚠️  WARNING: Variable {key} should use pinned digest: {value}")
                     warnings += 1

    if errors > 0:
        print(f"\n❌ Validation FAILED: {errors} errors, {warnings} warnings")
        return 1
    else:
        print(f"\n✅ Validation PASSED: {warnings} warnings")
        return 0

if __name__ == "__main__":
    sys.exit(validate())
