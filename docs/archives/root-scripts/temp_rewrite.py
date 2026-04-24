import sys
path = '/home/akushnir/code-server-enterprise/docker-compose.yml'
with open(path, 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if 'error-triage-engine:' in line:
        new_lines.append('  error-triage-engine:\n')
        new_lines.append('    image: alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e\n')
        new_lines.append('    container_name: error-triage-engine\n')
        new_lines.append('    restart: unless-stopped\n')
        new_lines.append('    profiles: ["observability"]\n')
        new_lines.append('    networks:\n')
        new_lines.append('      - net-management\n')
        new_lines.append('      - net-app\n')
        new_lines.append('    environment:\n')
        new_lines.append('      - LOKI_ENDPOINT=http://loki:3100\n')
        new_lines.append('      - GITHUB_REPO=${GITHUB_REPO:-kushin77/code-server}\n')
        new_lines.append('      - GITHUB_TOKEN=${GITHUB_TOKEN}\n')
        new_lines.append('      - ERROR_TRIAGE_INTERVAL=${ERROR_TRIAGE_INTERVAL:-300}\n')
        new_lines.append('      - ERROR_TRIAGE_THRESHOLD=${ERROR_TRIAGE_THRESHOLD:-3}\n')
        new_lines.append('      - ERROR_TRIAGE_WINDOW=${ERROR_TRIAGE_WINDOW:-3600}\n')
        new_lines.append('    volumes:\n')
        new_lines.append('      - ./scripts/error-triage-engine.sh:/usr/local/bin/error-triage-engine:ro\n')
        new_lines.append('      - ./scripts/_common:/usr/local/bin/_common:ro\n')
        new_lines.append('      - error-triage-db:/var/lib/error-triage\n')
        new_lines.append('    entrypoint: ["bash", "-c", "apk add --no-cache bash curl sqlite jq github-cli && exec bash /usr/local/bin/error-triage-engine"]\n')
        skip = True
        continue
    
    if skip:
        ls = line.strip()
        if (ls and not line.startswith(' ')) or ls in ['networks:', 'volumes:', 'services:']:
            skip = False
        else:
            continue
    
    new_lines.append(line)

with open(path, 'w') as f:
    f.writelines(new_lines)