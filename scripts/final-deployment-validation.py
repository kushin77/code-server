#!/usr/bin/env python3
###############################################################################
# Final Deployment Validation - Complete System Verification
#
# Validates entire deployment is functional end-to-end
###############################################################################

import urllib.request
import subprocess
import json
import sys

HOST = __import__("os").environ.get("PRIMARY_HOST", "192.168.168.31")

print("═" * 70)
print("FINAL DEPLOYMENT VALIDATION - COMPLETE SYSTEM CHECK")
print("═" * 70)
print()

checks = []

# Check 1: Primary host reachable
print("[1/10] Primary Host Connectivity...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", "echo OK"],
        capture_output=True,
        timeout=5
    )
    if result.returncode == 0:
        print(" ✓")
        checks.append(("Primary Host SSH", True))
    else:
        print(" ✗")
        checks.append(("Primary Host SSH", False))
except:
    print(" ✗")
    checks.append(("Primary Host SSH", False))

# Check 2: Docker running
print("[2/10] Docker Daemon Running...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", "docker version"],
        capture_output=True,
        timeout=5
    )
    if result.returncode == 0:
        print(" ✓")
        checks.append(("Docker Daemon", True))
    else:
        print(" ✗")
        checks.append(("Docker Daemon", False))
except:
    print(" ✗")
    checks.append(("Docker Daemon", False))

# Check 3: Services running
print("[3/10] Services Running...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", "docker ps | wc -l"],
        capture_output=True,
        timeout=5,
        text=True
    )
    count = int(result.stdout.strip()) - 1  # Exclude header
    if count >= 35:
        print(f" ✓ ({count} services)")
        checks.append(("Services Running", True))
    else:
        print(f" ⚠ ({count} services)")
        checks.append(("Services Running", False))
except:
    print(" ✗")
    checks.append(("Services Running", False))

# Check 4: HTTP Gateway
print("[4/10] HTTP Gateway (Caddy)...", end='', flush=True)
try:
    response = urllib.request.urlopen(f"http://{HOST}/", timeout=5)
    if response.code == 200:
        print(" ✓")
        checks.append(("HTTP Gateway", True))
    else:
        print(f" ⚠ (HTTP {response.code})")
        checks.append(("HTTP Gateway", False))
except:
    print(" ✗")
    checks.append(("HTTP Gateway", False))

# Check 5: Database
print("[5/10] Database (PostgreSQL)...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", 
         "docker exec code-server-postgres pg_isready -h localhost"],
        capture_output=True,
        timeout=5,
        text=True
    )
    if "accepting" in result.stdout:
        print(" ✓")
        checks.append(("PostgreSQL", True))
    else:
        print(" ✗")
        checks.append(("PostgreSQL", False))
except:
    print(" ✗")
    checks.append(("PostgreSQL", False))

# Check 6: Cache
print("[6/10] Cache (Redis)...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", 
         "docker exec code-server-redis redis-cli ping"],
        capture_output=True,
        timeout=5,
        text=True
    )
    if "PONG" in result.stdout or "NOAUTH" in result.stdout:
        print(" ✓")
        checks.append(("Redis", True))
    else:
        print(" ✗")
        checks.append(("Redis", False))
except:
    print(" ✗")
    checks.append(("Redis", False))

# Check 7: Message Broker
print("[7/10] Message Broker (Kafka)...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", 
         "docker exec code-server-redpanda rpk broker info"],
        capture_output=True,
        timeout=5,
        text=True
    )
    if result.returncode == 0 or "Brokers" in result.stdout:
        print(" ✓")
        checks.append(("Kafka", True))
    else:
        print(" ✗")
        checks.append(("Kafka", False))
except:
    print(" ✗")
    checks.append(("Kafka", False))

# Check 8: Monitoring (Prometheus)
print("[8/10] Monitoring (Prometheus)...", end='', flush=True)
try:
    response = urllib.request.urlopen(f"http://{HOST}:9090/api/v1/query?query=up", timeout=5)
    data = json.loads(response.read())
    if data.get("status") == "success":
        print(" ✓")
        checks.append(("Prometheus", True))
    else:
        print(" ✗")
        checks.append(("Prometheus", False))
except:
    print(" ✗")
    checks.append(("Prometheus", False))

# Check 9: Visualization (Grafana)
print("[9/10] Visualization (Grafana)...", end='', flush=True)
try:
    response = urllib.request.urlopen(f"http://{HOST}:3000/api/health", timeout=5)
    if response.code == 200:
        print(" ✓")
        checks.append(("Grafana", True))
    else:
        print(" ✗")
        checks.append(("Grafana", False))
except:
    print(" ✗")
    checks.append(("Grafana", False))

# Check 10: System Health
print("[10/10] System Health...", end='', flush=True)
try:
    result = subprocess.run(
        ["ssh", f"akushnir@{HOST}", "uptime"],
        capture_output=True,
        timeout=5,
        text=True
    )
    if result.returncode == 0:
        print(" ✓")
        checks.append(("System Health", True))
    else:
        print(" ✗")
        checks.append(("System Health", False))
except:
    print(" ✗")
    checks.append(("System Health", False))

# Summary
print()
print("=" * 70)
print("VALIDATION SUMMARY")
print("=" * 70)
print()

passed = sum(1 for _, status in checks if status)
total = len(checks)

for check, status in checks:
    symbol = "✓" if status else "✗"
    print(f"{symbol} {check}")

print()
print(f"Overall: {passed}/{total} checks passed ({100*passed/total:.0f}%)")
print()

if passed == total:
    print("✅ COMPLETE DEPLOYMENT VALIDATION PASSED")
    print("   All systems operational and responding")
    print("   Infrastructure is production-ready")
    print()
    print("DEPLOYMENT COMPLETE")
else:
    print("⚠️  SOME SYSTEMS NOT FULLY RESPONSIVE")
    print(f"   {total-passed} checks failed or degraded")
    print("   Review logs for details")

print("=" * 70)
