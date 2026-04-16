#!/usr/bin/env python3
import yaml
import glob
import sys

# Read all individual rule files
rule_files = sorted(glob.glob('config/prometheus/rules/*.yml'))
all_groups = []

for rule_file in rule_files:
    if 'alert-rules' in rule_file or '_index' in rule_file:
        continue  # Skip consolidated or index files
    
    print(f"Reading {rule_file}...", file=sys.stderr)
    with open(rule_file, 'r') as f:
        data = yaml.safe_load(f)
        if data and 'groups' in data:
            all_groups.extend(data['groups'])
            print(f"  → {len(data['groups'])} groups, {sum(len(g.get('rules', [])) for g in data['groups'])} rules", file=sys.stderr)

# Create consolidated file with all groups
consolidated = {'groups': all_groups}

with open('config/prometheus/rules/alert-rules.yml', 'w') as f:
    yaml.dump(consolidated, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

print(f"\n✓ Consolidated {len(rule_files)-2} rule files into {len(all_groups)} groups", file=sys.stderr)
print(f"✓ Total alert rules: {sum(len(group.get('rules', [])) for group in all_groups)}", file=sys.stderr)
