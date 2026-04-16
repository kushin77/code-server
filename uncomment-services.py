#!/usr/bin/env python3
"""Uncomment code-server, oauth2-proxy, and caddy services from docker-compose.yml"""

import sys

with open('docker-compose.yml', 'r') as f:
    lines = f.readlines()

# Track if we're in a commented service
in_disabled_section = False
service_name = None

new_lines = []
for i, line in enumerate(lines):
    # Check if this line marks a disabled service
    if 'DISABLED FOR PHASE 7a' in line:
        in_disabled_section = True
        # Look ahead to find the service name
        if i + 1 < len(lines):
            next_line = lines[i + 1]
            if '# ' in next_line and ':' in next_line:
                service_name = next_line.split(':')[0].replace('#', '').strip()
        new_lines.append(line)
        continue
    
    # If we're in a disabled section, uncomment lines
    if in_disabled_section:
        # Check if we've reached the next service
        if line.strip() and not line.startswith(' ' * 4) and ':' in line and not line.startswith('  #'):
            in_disabled_section = False
            service_name = None
            new_lines.append(line)
        # Uncomment the line if it starts with "  # "
        elif line.startswith('  # '):
            new_lines.append(line[4:])
        elif line.startswith('  #   '):
            new_lines.append(line[4:])
        elif line.startswith('  #     '):
            new_lines.append(line[4:])
        else:
            new_lines.append(line)
    else:
        new_lines.append(line)

with open('docker-compose.yml', 'w') as f:
    f.writelines(new_lines)

print("✓ code-server, oauth2-proxy, and caddy services uncommented")
sys.exit(0)
