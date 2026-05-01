#!/usr/bin/env python3
"""
scripts/ops/event-schema-registry.py
--------------------------------------
Lightweight schema registry for internal event bus (Redpanda/Kafka topics).
Manages Avro/JSON schema versions, validates producer schemas on publish,
and enforces backward-compatible evolution rules.

Usage:
  python3 scripts/ops/event-schema-registry.py --action <register|validate|list|diff> [options]
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


REGISTRY_DIR = Path(os.environ.get("SCHEMA_REGISTRY_DIR",
                                   Path(__file__).parent.parent / "configs" / "event-schemas"))
REGISTRY_INDEX = REGISTRY_DIR / "_index.json"


def parse_args():
    p = argparse.ArgumentParser(description="Event schema registry")
    p.add_argument("--action", required=True,
                   choices=["register", "validate", "list", "diff", "init"],
                   help="Action to perform")
    p.add_argument("--topic", help="Topic / schema name")
    p.add_argument("--schema-file", help="Path to schema JSON file")
    p.add_argument("--version", type=int, help="Schema version (for diff/validate)")
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args()


def load_index() -> dict:
    if REGISTRY_INDEX.exists():
        return json.loads(REGISTRY_INDEX.read_text())
    return {"schemas": {}, "updated_at": ""}


def save_index(index: dict):
    index["updated_at"] = datetime.now(timezone.utc).isoformat()
    REGISTRY_INDEX.write_text(json.dumps(index, indent=2))


def schema_fingerprint(schema: dict) -> str:
    canonical = json.dumps(schema, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode()).hexdigest()[:16]


def is_backward_compatible(old: dict, new: dict) -> tuple[bool, str]:
    """
    Basic backward compatibility check for JSON schemas:
    - New required fields not in old schema = BREAKING
    - Removed fields = BREAKING
    - Type changes = BREAKING
    - New optional fields = OK
    """
    old_props = old.get("properties", {})
    new_props = new.get("properties", {})
    old_required = set(old.get("required", []))
    new_required = set(new.get("required", []))

    # Check for new required fields
    new_required_fields = new_required - old_required
    if new_required_fields:
        return False, f"New required fields added: {new_required_fields}"

    # Check for removed fields
    removed = set(old_props.keys()) - set(new_props.keys())
    if removed:
        return False, f"Fields removed: {removed}"

    # Check for type changes
    for field in old_props:
        if field in new_props:
            old_type = old_props[field].get("type")
            new_type = new_props[field].get("type")
            if old_type != new_type:
                return False, f"Type changed for '{field}': {old_type} → {new_type}"

    return True, "backward compatible"


def action_init():
    REGISTRY_DIR.mkdir(parents=True, exist_ok=True)
    if not REGISTRY_INDEX.exists():
        save_index({"schemas": {}})
        print(f"Initialized schema registry at {REGISTRY_DIR}")
    else:
        print(f"Registry already exists at {REGISTRY_DIR}")


def action_register(args):
    if not args.topic:
        print("ERROR: --topic required for register", file=sys.stderr)
        sys.exit(1)
    if not args.schema_file:
        print("ERROR: --schema-file required for register", file=sys.stderr)
        sys.exit(1)

    schema_path = Path(args.schema_file)
    if not schema_path.exists():
        print(f"ERROR: schema file not found: {schema_path}", file=sys.stderr)
        sys.exit(1)

    new_schema = json.loads(schema_path.read_text())
    fingerprint = schema_fingerprint(new_schema)

    index = load_index()
    topic_schemas = index["schemas"].get(args.topic, [])

    # Check for duplicate
    if any(s["fingerprint"] == fingerprint for s in topic_schemas):
        print(f"Schema already registered (fingerprint={fingerprint})")
        return

    # Compatibility check against latest version
    if topic_schemas:
        latest = topic_schemas[-1]
        latest_schema_file = REGISTRY_DIR / args.topic / f"v{latest['version']}.json"
        if latest_schema_file.exists():
            old_schema = json.loads(latest_schema_file.read_text())
            compatible, reason = is_backward_compatible(old_schema, new_schema)
            if not compatible:
                print(f"BREAKING CHANGE: {reason}", file=sys.stderr)
                if not args.dry_run:
                    sys.exit(1)
                else:
                    print(f"[DRY-RUN] would fail: {reason}")

    version = len(topic_schemas) + 1
    topic_dir = REGISTRY_DIR / args.topic
    topic_dir.mkdir(parents=True, exist_ok=True)

    versioned_path = topic_dir / f"v{version}.json"
    if not args.dry_run:
        versioned_path.write_text(json.dumps(new_schema, indent=2))
        topic_schemas.append({
            "version": version,
            "fingerprint": fingerprint,
            "registered_at": datetime.now(timezone.utc).isoformat(),
            "file": str(versioned_path.relative_to(REGISTRY_DIR)),
        })
        index["schemas"][args.topic] = topic_schemas
        save_index(index)
        print(f"Registered: {args.topic} v{version} (fingerprint={fingerprint})")
    else:
        print(f"[DRY-RUN] would register: {args.topic} v{version} (fingerprint={fingerprint})")


def action_list(args):
    index = load_index()
    if not index["schemas"]:
        print("No schemas registered")
        return
    for topic, versions in index["schemas"].items():
        if args.topic and topic != args.topic:
            continue
        print(f"\nTopic: {topic} ({len(versions)} version(s))")
        for v in versions:
            print(f"  v{v['version']} — fp={v['fingerprint']} — {v['registered_at']}")


def action_validate(args):
    if not args.topic or not args.schema_file:
        print("ERROR: --topic and --schema-file required for validate", file=sys.stderr)
        sys.exit(1)

    candidate = json.loads(Path(args.schema_file).read_text())
    index = load_index()
    versions = index["schemas"].get(args.topic, [])

    if not versions:
        print(f"No registered schema for topic '{args.topic}' — first registration will pass")
        return

    latest = versions[-1]
    latest_path = REGISTRY_DIR / latest["file"]
    old_schema = json.loads(latest_path.read_text())
    compatible, reason = is_backward_compatible(old_schema, candidate)
    if compatible:
        print(f"✅ Schema is backward compatible: {reason}")
    else:
        print(f"❌ BREAKING CHANGE: {reason}", file=sys.stderr)
        sys.exit(1)


def action_diff(args):
    if not args.topic:
        print("ERROR: --topic required for diff", file=sys.stderr)
        sys.exit(1)
    index = load_index()
    versions = index["schemas"].get(args.topic, [])
    if len(versions) < 2:
        print("Need at least 2 versions to diff")
        return
    v_a = versions[-2]
    v_b = versions[-1]
    path_a = REGISTRY_DIR / v_a["file"]
    path_b = REGISTRY_DIR / v_b["file"]
    schema_a = json.loads(path_a.read_text())
    schema_b = json.loads(path_b.read_text())
    props_a = set(schema_a.get("properties", {}).keys())
    props_b = set(schema_b.get("properties", {}).keys())
    print(f"Diff: {args.topic} v{v_a['version']} → v{v_b['version']}")
    for f in props_b - props_a:
        print(f"  + {f} (added)")
    for f in props_a - props_b:
        print(f"  - {f} (removed)")
    for f in props_a & props_b:
        ta = schema_a["properties"][f].get("type")
        tb = schema_b["properties"][f].get("type")
        if ta != tb:
            print(f"  ~ {f}: {ta} → {tb}")


def main():
    args = parse_args()
    REGISTRY_DIR.mkdir(parents=True, exist_ok=True)

    dispatch = {
        "init":     action_init,
        "register": action_register,
        "list":     action_list,
        "validate": action_validate,
        "diff":     action_diff,
    }
    dispatch[args.action](args) if args.action != "init" else action_init()


if __name__ == "__main__":
    main()
