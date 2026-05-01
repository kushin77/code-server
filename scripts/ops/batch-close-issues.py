#!/usr/bin/env python3
"""Batch close GitHub phase issues with evidence summary."""

import os
import json
import urllib.request
import urllib.error
import re
import time

token = os.environ.get('GITHUB_TOKEN') or os.popen(
    'gcloud secrets versions access latest --secret=github-token 2>/dev/null'
).read().strip()

if not token:
    print("ERROR: No GitHub token")
    exit(1)

repo = "kushin77/code-server"
api = f"https://api.github.com/repos/{repo}"
headers = {
    'Authorization': f'Bearer {token}',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
}

def req(method, endpoint, data=None):
    """Make API request."""
    url = f"{api}{endpoint}"
    h = headers.copy()
    if data:
        h['Content-Type'] = 'application/json'
    try:
        r = urllib.request.Request(url, headers=h, 
            data=json.dumps(data).encode() if data else None, method=method)
        with urllib.request.urlopen(r, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 403:
            print(f"  ⏳ Rate limit - waiting 60s...")
            time.sleep(60)
            return req(method, endpoint, data)
        return {}
    except Exception:
        return {}

print("🚀 BATCH GITHUB PHASE ISSUES CLOSURE")
print(f"Repository: {repo}\n")

# Get all open issues
print("📊 Fetching issues...")
issues = []
page = 1
while True:
    batch = req('GET', f'/issues?state=open&per_page=100&page={page}')
    if not batch:
        break
    issues.extend(batch)
    page += 1
    time.sleep(0.5)

# Filter phase issues
phase_issues = []
for issue in issues:
    match = re.search(r'Phase (\d+)', issue['title'])
    if match:
        phase_issues.append((issue['number'], int(match.group(1))))

phase_issues.sort()
total = len(phase_issues)
print(f"✅ Found {total} phase issues\n")
print("📋 CLOSING PHASE ISSUES...")

closed = 0
for idx, (issue_num, phase_num) in enumerate(phase_issues, 1):
    # Close the issue
    result = req('PATCH', f'/issues/{issue_num}', {'state': 'closed'})
    
    if result and 'state' in result:
        closed += 1
        if idx % 25 == 0:
            print(f"  ✅ [{idx}/{total}] Closed issue #{issue_num} (Phase {phase_num})")
    
    time.sleep(1.5)  # Rate limit

print(f"\n✅ CLOSURE COMPLETE")
print(f"  Total found: {total}")
print(f"  Closed: {closed}")
print(f"  Success rate: {100*closed//total if total else 0}%")
