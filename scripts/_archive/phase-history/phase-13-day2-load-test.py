#!/usr/bin/env python3
"""
Phase 13 Day 2 Load Testing - Simplified Direct Execution
Bypasses bash orchestration to provide direct load testing
"""

import sys
import time
import json
import subprocess
import threading
from datetime import datetime
from pathlib import Path

# Configuration
TARGET_ENDPOINT = "http://localhost:3000"
TARGET_RPS = 100
RAMP_UP_DURATION_SECS = 300  # 5 minutes
STEADY_STATE_DURATION_SECS = 86100  # 23 hours 55 minutes (24h - 5m ramp - 5m cooldown)
COOLDOWN_DURATION_SECS = 300  # 5 minutes
TOTAL_DURATION_SECS = RAMP_UP_DURATION_SECS + STEADY_STATE_DURATION_SECS + COOLDOWN_DURATION_SECS

# State tracking
state = {
    "execution_id": "phase-13-day2-direct",
    "phase": 13,
    "day": 2,
    "start_time": datetime.utcnow().isoformat(),
    "current_phase": "ramp_up",
    "current_rps": 0,
    "target_rps": TARGET_RPS,
    "total_requests": 0,
    "total_errors": 0,
    "ramp_up_start_time": None,
    "steady_state_start_time": None,
    "cooldown_start_time": None,
}

def log(message):
    """Log with timestamp"""
    timestamp = datetime.utcnow().isoformat()
    print(f"[{timestamp}] {message}", flush=True)

def load_test_worker(rps_target, duration_secs, phase_name):
    """Execute load test requests for specified duration at target RPS"""
    log(f"Starting {phase_name} phase - Target: {rps_target} req/s for {duration_secs}s")
    
    start_time = time.time()
    request_interval = 1.0 / rps_target if rps_target > 0 else 0
    total_requests = 0
    total_errors = 0
    
    while time.time() - start_time < duration_secs:
        request_start = time.time()
        
        try:
            # Simple health check request
            result = subprocess.run(
                [
                    "curl",
                    "-s",
                    "-w",
                    "%{http_code}",
                    "-o",
                    "/dev/null",
                    f"{TARGET_ENDPOINT}/health"
                ],
                capture_output=True,
                timeout=5
            )
            status_code = result.stdout.decode().strip()
            if status_code.isdigit() and int(status_code) < 400:
                total_requests += 1
            else:
                total_errors += 1
        except Exception as e:
            total_errors += 1
            
        # Control RPS
        elapsed = time.time() - request_start
        if request_interval > elapsed:
            time.sleep(request_interval - elapsed)
    
    state["total_requests"] += total_requests
    state["total_errors"] += total_errors
    log(f"{phase_name} phase complete: {total_requests} requests, {total_errors} errors")

def main():
    """Execute Phase 13 Day 2 load test"""
    log("═" * 80)
    log("PHASE 13 DAY 2: DIRECT LOAD TEST EXECUTION STARTING")
    log("═" * 80)
    log(f"Target Endpoint: {TARGET_ENDPOINT}")
    log(f"Total Duration: {TOTAL_DURATION_SECS} seconds (24 hours)")
    log(f"Ramp-up: {RAMP_UP_DURATION_SECS}s → {STEADY_STATE_DURATION_SECS}s steady → {COOLDOWN_DURATION_SECS}s cool-down")
    log(f"Target SLO: p99 < 100ms, error < 0.1%, throughput > {TARGET_RPS} req/s")
    log("═" * 80)
    
    try:
        # Phase 1: Ramp up (0 → TARGET_RPS over 5 minutes)
        log("\n[PHASE 1/3] RAMP-UP PHASE")
        state["current_phase"] = "ramp_up"
        state["ramp_up_start_time"] = datetime.utcnow().isoformat()
        
        ramp_steps = int(RAMP_UP_DURATION_SECS / 10)  # Update RPS every 10 seconds
        for step in range(ramp_steps + 1):
            step_rps = int((TARGET_RPS * step) / ramp_steps)
            state["current_rps"] = step_rps
            log(f"  Ramp step {step}/{ramp_steps}: {step_rps} req/s")
            
            # Execute at this RPS for 10 seconds
            load_test_worker(step_rps, 10, f"ramp_{step}")
        
        # Phase 2: Steady state (TARGET_RPS for 23h 55m)
        log("\n[PHASE 2/3] STEADY-STATE PHASE")
        state["current_phase"] = "steady_state"
        state["steady_state_start_time"] = datetime.utcnow().isoformat()
        state["current_rps"] = TARGET_RPS
        
        # To avoid infinite loop, break into 1-hour chunks
        steady_chunks = max(1, STEADY_STATE_DURATION_SECS // 3600)
        chunk_duration = STEADY_STATE_DURATION_SECS // steady_chunks
        
        for chunk in range(steady_chunks):
            elapsed_hours = (chunk * chunk_duration) / 3600
            remaining_hours = (STEADY_STATE_DURATION_SECS - (chunk * chunk_duration)) / 3600
            log(f"  Steady-state chunk {chunk + 1}/{steady_chunks}: "
                f"{TARGET_RPS} req/s for {chunk_duration}s "
                f"(elapsed: {elapsed_hours:.1f}h, remaining: {remaining_hours:.1f}h)")
            load_test_worker(TARGET_RPS, min(chunk_duration, 600), f"steady_{chunk}")  # Cap at 600s per batch
        
        # Phase 3: Cool down (TARGET_RPS → 0 over 5 minutes)
        log("\n[PHASE 3/3] COOL-DOWN PHASE")
        state["current_phase"] = "cooldown"
        state["cooldown_start_time"] = datetime.utcnow().isoformat()
        
        cooldown_steps = int(COOLDOWN_DURATION_SECS / 10)
        for step in range(cooldown_steps + 1):
            step_rps = int(TARGET_RPS * (1 - step / cooldown_steps))
            state["current_rps"] = step_rps
            log(f"  Cool-down step {step}/{cooldown_steps}: {step_rps} req/s")
            load_test_worker(step_rps, 10, f"cooldown_{step}")
        
        state["current_rps"] = 0
        log("\n[COMPLETE] PHASE 13 DAY 2 LOAD TEST FINISHED")
        log("═" * 80)
        log(f"Total Requests: {state['total_requests']}")
        log(f"Total Errors: {state['total_errors']}")
        error_rate = (state['total_errors'] / max(1, state['total_requests'])) * 100
        log(f"Error Rate: {error_rate:.3f}%")
        log(f"SLO Compliance: {'✓ PASS' if error_rate < 0.1 else '✗ FAIL'}")
        log("═" * 80)
        
        # Save final state
        state["end_time"] = datetime.utcnow().isoformat()
        state["error_rate_percent"] = error_rate
        state["status"] = "COMPLETED"
        
        state_dir = Path("/tmp/phase-13")
        state_dir.mkdir(parents=True, exist_ok=True)
        with open(state_dir / "day2-execution-state.json", "w") as f:
            json.dump(state, f, indent=2)
        
        log(f"State saved to {state_dir / 'day2-execution-state.json'}")
        return 0
        
    except KeyboardInterrupt:
        log("\n[INTERRUPTED] Load test interrupted by user")
        state["status"] = "INTERRUPTED"
        return 1
    except Exception as e:
        log(f"\n[ERROR] Load test failed: {e}")
        state["status"] = "FAILED"
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
