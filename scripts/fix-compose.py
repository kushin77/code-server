#!/usr/bin/env python3

import yaml
import sys

FILE = "/home/akushnir/code-server-phase13/docker-compose.yml"

# Read the broken file
with open(FILE, 'r') as f:
    lines = f.readlines()

# Correct structure:
# - Lines 0-368 (349-368 in sed): redis service definition end + volumes: section start
# - Lines 369-385: volume definitions
# - Lines 386-388: blank lines before networks
# - Lines 389-396: networks section (lines 37-44 of above = sed lines 386-393)

# Count actual line numbers from the output above:
# Sed lines 350-398 = actual file lines 350-398
# In that output, volumes: is at line 21 of output = line 370 of file
# networks: is at line 37 of output = line 386 of file
# enterprise network ends at line 42 of output = line 391 of file
# redis-cache (wrong) starts at line 44 of output = line 393 of file

print(f"Total lines in file: {len(lines)}")
print(f"Keeping lines 0-391 (lines 1-392 in sed)")
print(f"Adding redis-cache-data to volumes")

with open(FILE + '.new', 'w') as f:
    # Write all lines up to and including the correct networks section
    for i in range(min(392, len(lines))):
        f.write(lines[i])

    # Now add redis-cache-data volume if it wasn't added yet
    # Check if redis-data was in the volumes section
    volumes_section = ''.join(lines[:392])
    if 'redis-cache-data:' not in volumes_section and 'redis-data:' in volumes_section:
        # Find where to insert it (right after redis-data definition)
        output = ''.join(lines[:392])
        # Insert redis-cache-data before the networks: section
        # Find "redis-data:" and add redis-cache-data after it
        if '  redis-data:\n    driver: local\n' in output:
            output = output.replace(
                '  redis-data:\n    driver: local\n',
                '  redis-data:\n    driver: local\n  redis-cache-data:\n    driver: local\n'
            )
            f.seek(0)
            f.write(output)
        else:
            f.write(''.join(lines[:392]))
    f.flush()

print("Fixed file written")

# Test YAML validity
try:
    with open(FILE + '.new', 'r') as f:
        yaml.safe_load(f)
    print("✓ YAML is valid!")

    # Replace original
    import shutil
    shutil.copy(FILE, FILE + '.broken')
    shutil.copy(FILE + '.new', FILE)
    print("✓ docker-compose.yml fixed!")

except yaml.YAMLError as e:
    print(f"✗ YAML error: {e}")
    # Show what we generated
    with open(FILE + '.new', 'r') as f:
        content = f.read()
        lines_out = content.split('\n')
        print(f"Generated {len(lines_out)} lines")
        print("Last 20 lines:")
        for line in lines_out[-20:]:
            print(repr(line))
    sys.exit(1)
