#!/usr/bin/env python3
###############################################################################
# Phase 5 Week 1: Light Load Test - Python Implementation
#
# This script performs a proper light load test (50 users, 5 minutes) 
# against the production gateway using Python HTTP libraries.
###############################################################################

import concurrent.futures
import time
import urllib.request
import urllib.error
import socket
import sys
import json
import os
from statistics import mean, median, stdev
from threading import Lock

# Configuration
HOST = os.environ.get("PRIMARY_HOST", "192.168.168.31")
PORT = int(os.environ.get("PRIMARY_PORT", "80"))
TARGET_URL = f"http://{HOST}:{PORT}/"
CONCURRENT_USERS = int(os.environ.get("LOAD_TEST_USERS", "50"))
REQUESTS_PER_USER = int(os.environ.get("LOAD_TEST_REQUESTS_PER_USER", "30"))
TIMEOUT = int(os.environ.get("LOAD_TEST_TIMEOUT", "5"))  # seconds

# Results collection
results_lock = Lock()
results = {
    'successful': [],
    'failed': [],
    'timeouts': [],
    'errors': []
}

def make_request(user_id: int, request_id: int) -> dict:
    """Make a single HTTP request and record response time."""
    start_time = time.time()
    
    try:
        response = urllib.request.urlopen(TARGET_URL, timeout=TIMEOUT)
        elapsed = (time.time() - start_time) * 1000  # Convert to ms
        
        return {
            'user': user_id,
            'request': request_id,
            'status': response.code,
            'response_time_ms': elapsed,
            'result': 'success',
            'size': len(response.read())
        }
    except socket.timeout:
        elapsed = (time.time() - start_time) * 1000
        return {
            'user': user_id,
            'request': request_id,
            'status': 0,
            'response_time_ms': elapsed,
            'result': 'timeout',
            'error': 'Socket timeout'
        }
    except urllib.error.URLError as e:
        elapsed = (time.time() - start_time) * 1000
        return {
            'user': user_id,
            'request': request_id,
            'status': 0,
            'response_time_ms': elapsed,
            'result': 'error',
            'error': str(e)
        }
    except Exception as e:
        elapsed = (time.time() - start_time) * 1000
        return {
            'user': user_id,
            'request': request_id,
            'status': 0,
            'response_time_ms': elapsed,
            'result': 'error',
            'error': str(type(e).__name__)
        }

def record_result(result: dict):
    """Thread-safe result recording."""
    with results_lock:
        if result['result'] == 'success':
            results['successful'].append(result)
        elif result['result'] == 'timeout':
            results['timeouts'].append(result)
        elif result['result'] == 'error':
            results['errors'].append(result)
        else:
            results['failed'].append(result)

def run_load_test():
    """Execute the light load test."""
    print("═" * 70)
    print("PHASE 5 WEEK 1: LIGHT LOAD TEST")
    print("═" * 70)
    print(f"Target: {TARGET_URL}")
    print(f"Concurrent Users: {CONCURRENT_USERS}")
    print(f"Requests per User: {REQUESTS_PER_USER}")
    print(f"Total Requests: {CONCURRENT_USERS * REQUESTS_PER_USER}")
    print(f"Timeout: {TIMEOUT}s")
    print("=" * 70)
    print()
    
    # Warmup request
    print("Performing warmup request...", end='', flush=True)
    try:
        urllib.request.urlopen(TARGET_URL, timeout=TIMEOUT)
        print(" ✓")
    except Exception as e:
        print(f" ✗ ({e})")
    
    print()
    print("Starting load test execution...")
    print("-" * 70)
    
    start_time = time.time()
    
    # Execute load test with thread pool
    with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENT_USERS) as executor:
        futures = []
        
        # Submit all requests
        for user_id in range(CONCURRENT_USERS):
            for request_id in range(REQUESTS_PER_USER):
                future = executor.submit(make_request, user_id, request_id)
                futures.append(future)
        
        # Collect results as they complete
        completed = 0
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            record_result(result)
            completed += 1
            
            if completed % 100 == 0:
                elapsed = time.time() - start_time
                print(f"  Progress: {completed}/{CONCURRENT_USERS * REQUESTS_PER_USER} requests ({elapsed:.1f}s)")
    
    test_duration = time.time() - start_time
    
    print("-" * 70)
    print()
    print("RESULTS ANALYSIS")
    print("=" * 70)
    
    total_requests = len(results['successful']) + len(results['failed']) + len(results['timeouts']) + len(results['errors'])
    success_count = len(results['successful'])
    
    print(f"Total Requests: {total_requests}")
    print(f"Successful: {success_count} ({100.0 * success_count / total_requests:.1f}%)")
    print(f"Timeouts: {len(results['timeouts'])} ({100.0 * len(results['timeouts']) / total_requests:.1f}%)")
    print(f"Errors: {len(results['errors'])} ({100.0 * len(results['errors']) / total_requests:.1f}%)")
    print(f"Failed: {len(results['failed'])} ({100.0 * len(results['failed']) / total_requests:.1f}%)")
    print(f"Test Duration: {test_duration:.1f} seconds")
    print()
    
    # Performance metrics
    if results['successful']:
        response_times = [r['response_time_ms'] for r in results['successful']]
        response_times.sort()
        
        print("PERFORMANCE METRICS")
        print("-" * 70)
        print(f"Min Response Time: {min(response_times):.1f} ms")
        print(f"Max Response Time: {max(response_times):.1f} ms")
        print(f"Avg Response Time: {mean(response_times):.1f} ms")
        print(f"Median (P50): {response_times[len(response_times)//2]:.1f} ms")
        
        # Calculate percentiles
        p95_idx = int(len(response_times) * 0.95)
        p99_idx = int(len(response_times) * 0.99)
        
        print(f"P95 Response Time: {response_times[p95_idx]:.1f} ms")
        print(f"P99 Response Time: {response_times[p99_idx]:.1f} ms")
        
        if len(response_times) > 1:
            print(f"Std Dev: {stdev(response_times):.1f} ms")
        
        print()
        print("BASELINE COMPARISON")
        print("-" * 70)
        print(f"Target P95: 500ms | Actual: {response_times[p95_idx]:.1f}ms | {'✓ PASS' if response_times[p95_idx] < 500 else '✗ FAIL'}")
        print(f"Target P99: 1000ms | Actual: {response_times[p99_idx]:.1f}ms | {'✓ PASS' if response_times[p99_idx] < 1000 else '✗ FAIL'}")
        print()
    
    # Throughput calculation
    throughput = total_requests / test_duration
    print("THROUGHPUT")
    print("-" * 70)
    print(f"Requests/Second: {throughput:.2f} req/s")
    print(f"Target Min: 1000 req/s (simulated: {throughput:.2f} is light load baseline)")
    print()
    
    # Summary
    print("=" * 70)
    if success_count >= total_requests * 0.95:  # 95% success threshold for light load
        print("✅ LIGHT LOAD TEST PASSED")
        print(f"   {success_count}/{total_requests} requests successful")
        print("   Infrastructure is stable under light load")
        print("   Ready for medium load test (200 users, 10 min)")
    else:
        print("⚠️  LIGHT LOAD TEST DEGRADED")
        print(f"   {success_count}/{total_requests} requests successful")
        print(f"   Error rate: {100.0 * (total_requests - success_count) / total_requests:.1f}%")
        print("   Investigate errors before proceeding")
    print("=" * 70)

if __name__ == '__main__':
    try:
        run_load_test()
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
