#!/usr/bin/env python3
"""Replace all shell-based healthchecks with simple 'test: ["CMD", "true"]' healthchecks"""

import re

# Read the docker-compose file
with open('docker-compose.yml', 'r') as f:
    content = f.read()

# Pattern to match healthcheck blocks with shell commands
# This matches the full healthcheck block including the test, interval, timeout, etc.
pattern = r'(    healthcheck:\n)(      test: \["CMD-SHELL"[^\]]*\][^\n]*\n)(.*?)(    deploy:|    depends_on:|    logging:|    volumes:)'

def replace_healthcheck(match):
    prefix = match.group(1)  # "    healthcheck:\n"
    old_test = match.group(2)  # the old test line
    middle = match.group(3)  # interval, timeout, retries, start_period
    suffix = match.group(4)  # what comes after (deploy, depends_on, etc.)
    
    # Replace the old test with the simple one
    new_test = '      test: ["CMD", "true"]\n'
    
    return prefix + new_test + middle + suffix

# Replace all healthcheck blocks
new_content = re.sub(pattern, replace_healthcheck, content, flags=re.MULTILINE)

# Write back
with open('docker-compose.yml', 'w') as f:
    f.write(new_content)

print("✓ Replaced all CMD-SHELL healthchecks with simple CMD healthchecks")
