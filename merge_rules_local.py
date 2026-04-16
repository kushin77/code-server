#!/usr/bin/env python3
import yaml
import sys
import glob

# Get all individual rule files from the rules directory
rule_files = sorted([
    f for f in glob.glob('config/prometheus/rules/*.yml')
    if 'alert-rules' not in f and '_index' not in f
])

all_groups = []

for fname in rule_files:
    try:
        with open(fname, 'r') as f:
            content = yaml.safe_load(f)
            if content and isinstance(content, dict) and 'groups' in content:
                all_groups.extend(content['groups'])
                print(f'✓ {fname}: {len(content["groups"])} group(s)', file=sys.stderr)
            else:
                print(f'⚠ {fname}: no groups found', file=sys.stderr)
    except Exception as e:
        print(f'✗ {fname}: {e}', file=sys.stderr)
        sys.exit(1)

# Write consolidated file
output = {'groups': all_groups}
with open('config/prometheus/alert-rules.yml', 'w') as f:
    yaml.dump(output, f, default_flow_style=False, allow_unicode=True)

print(f'\n✓ Consolidated {len(rule_files)} files into alert-rules.yml', file=sys.stderr)
print(f'✓ Total groups: {len(all_groups)}', file=sys.stderr)
print(f'✓ Total rules: {sum(len(g.get("rules", [])) for g in all_groups)}', file=sys.stderr)
