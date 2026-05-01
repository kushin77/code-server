#!/usr/bin/env python3
"""Direct GitHub phase issues closure with real-time status."""

import os, json, urllib.request, urllib.error, re, time, sys
from datetime import datetime as dt

token = os.environ.get('GITHUB_TOKEN') or os.popen(
    'gcloud secrets versions access latest --secret=github-token 2>/dev/null'
).read().strip()

if not token:
    print("ERROR: No GitHub token")
    sys.exit(1)

repo = "kushin77/code-server"
api = f"https://api.github.com/repos/{repo}"

print(f"🚀 DIRECT GITHUB PHASE ISSUES CLOSURE")
print(f"Repository: {repo}\n")
print(f"Starting: {dt.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

# Quick fetch of open issues
print("📊 Fetching open phase issues...")
issues = []
try:
    page = 1
    while True:
        url = f"{api}/issues?state=open&per_page=100&page={page}"
        req = urllib.request.Request(url, headers={
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
        })
        resp = urllib.request.urlopen(req, timeout=10)
        batch = json.loads(resp.read().decode())
        if not batch:
            break
        for issue in batch:
            match = re.search(r'Phase (\d+)', issue['title'])
            if match:
                issues.append((issue['number'], int(match.group(1))))
        page += 1
        time.sleep(0.5)
except Exception as e:
    print(f"ERROR fetching: {e}")
    sys.exit(1)

issues.sort()
total = len(issues)
print(f"✅ Found {total} phase issues\n")

if total == 0:
    print("No phase issues to close")
    sys.exit(0)

print(f"📋 CLOSING ISSUES (REAL-TIME STATUS):\n")

closed = 0
failed = 0
for idx, (issue_num, phase_num) in enumerate(issues, 1):
    try:
        # Close the issue directly
        close_req = urllib.request.Request(
            f"{api}/issues/{issue_num}",
            data=json.dumps({'state': 'closed'}).encode(),
            headers={
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.github+json',
                'Content-Type': 'application/json'
            },
            method='PATCH'
        )
        
        resp = urllib.request.urlopen(close_req, timeout=15)
        result = json.loads(resp.read().decode())
        
        if result.get('state') == 'closed':
            closed += 1
            if idx % 25 == 0:
                print(f"  ✅ [{idx}/{total}] Closed #{issue_num} (Phase {phase_num})")
        else:
            failed += 1
    
    except urllib.error.HTTPError as e:
        if e.code == 403:
            print(f"  ⏸️  Rate limit (403) - sleeping 60s...")
            time.sleep(60)
        else:
            failed += 1
    except Exception as e:
        failed += 1
    
    time.sleep(1)

print(f"\n✅ CLOSURE COMPLETE")
print(f"  Total found: {total}")
print(f"  Closed: {closed}")
print(f"  Failed: {failed}")
print(f"  Success rate: {100*closed//total if total else 0}%")
print(f"  Completed: {dt.now().strftime('%Y-%m-%d %H:%M:%S')}")
