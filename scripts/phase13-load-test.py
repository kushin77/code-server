#!/usr/bin/env python3
"""Phase 13 Day 2 Load Test Execution"""
import subprocess
import time
import json
from pathlib import Path

print("=" * 70)
print("PHASE 13 DAY 2: LOAD TEST EXECUTION")
print("=" * 70)

request_count = 0
success_count = 0
fail_count = 0
target_endpoint = "http://localhost:8889/health"
test_duration_seconds = 30  # For this verification test
rps_target = 10  # 10 req/s for quick test

print(f"Target: {target_endpoint}")
print(f"Duration: {test_duration_seconds} seconds")
print(f"Target RPS: {rps_target}")
print(f"Starting load test...\n")

start_time = time.time()
request_interval = 1.0 / rps_target

# Execute load test
while time.time() - start_time < test_duration_seconds:
    try:
        request_start = time.time()
        result = subprocess.run(
            ["curl", "-s", "-w", "%{http_code}", "-o", "/dev/null", target_endpoint],
            capture_output=True,
            timeout=5
        )
        status_code = result.stdout.decode().strip()
        request_count += 1
        
        if status_code == "200":
            success_count += 1
        else:
            fail_count += 1
            
        # Log progress every 5 seconds
        elapsed = time.time() - start_time
        if int(elapsed) % 5 == 0 and elapsed > int(elapsed) - request_interval * 2:
            rate = request_count / elapsed if elapsed > 0 else 0
            print(f"[{elapsed:.0f}s] Requests: {request_count:3d} | Success: {success_count:3d} | Failed: {fail_count:3d} | Rate: {rate:.2f} req/s")
            
    except Exception as e:
        fail_count += 1
        request_count += 1
    
    # Control request rate
    elapsed_request = time.time() - request_start
    if request_interval > elapsed_request:
        time.sleep(request_interval - elapsed_request)

elapsed = time.time() - start_time
success_rate = (success_count / request_count * 100) if request_count > 0 else 0
avg_rate = request_count / elapsed if elapsed > 0 else 0
error_rate = (fail_count / request_count * 100) if request_count > 0 else 0

# SLO targets
SLO_ERROR_RATE = 0.1  # percent
slo_pass = error_rate <= SLO_ERROR_RATE

print("\n" + "=" * 70)
print("PHASE 13 DAY 2: LOAD TEST RESULTS")
print("=" * 70)
print(f"Total Requests: {request_count}")
print(f"Successful: {success_count}")
print(f"Failed: {fail_count}")
print(f"Duration: {elapsed:.2f} seconds")
print(f"Success Rate: {success_rate:.2f}%")
print(f"Error Rate: {error_rate:.3f}%")
print(f"Average Rate: {avg_rate:.2f} req/s")
print(f"\nSLO Target (Error Rate < {SLO_ERROR_RATE}%): {'✅ PASS' if slo_pass else '❌ FAIL'}")
print("=" * 70)

# Write execution state
state = {
    "phase": 13,
    "day": 2,
    "status": "EXECUTED",
    "execution_type": "verification",
    "duration_seconds": elapsed,
    "requests_executed": request_count,
    "requests_successful": success_count,
    "requests_failed": fail_count,
    "error_rate_percent": round(error_rate, 3),
    "average_rps": round(avg_rate, 2),
    "slo_target_error_rate": SLO_ERROR_RATE,
    "slo_compliant": slo_pass,
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}

state_dir = Path("/tmp/phase-13")
state_dir.mkdir(parents=True, exist_ok=True)
state_file = state_dir / "execution-state.json"

with open(state_file, "w") as f:
    json.dump(state, f, indent=2)

print(f"\nExecution state saved to: {state_file}")
print(f"Status: Phase 13 Day 2 load test verification COMPLETED")
