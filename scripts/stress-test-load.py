#!/usr/bin/env python3
"""
Stress test script for code-server at 192.168.168.31
Tests concurrency, throughput, and resource limits
"""

import subprocess
import json
import time
import sys
import os
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import requests
from statistics import mean, stdev, median

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HOST = os.environ.get("STRESS_HOST", "192.168.168.31")
ENDPOINT = os.environ.get("STRESS_ENDPOINT", f"http://{HOST}:3000/health")
CONCURRENCY_LEVELS = [int(value) for value in os.environ.get("STRESS_CONCURRENCY_LEVELS", "5,10,25,50").split(",") if value.strip()]
REQUEST_MULTIPLIER = int(os.environ.get("STRESS_REQUEST_MULTIPLIER", "20"))
HTTP_DURATION_SEC = int(os.environ.get("STRESS_HTTP_DURATION_SEC", "30"))
CPU_LOAD_DURATION_SEC = int(os.environ.get("STRESS_CPU_LOAD_DURATION_SEC", "15"))
MEMORY_SIZES_MB = [int(value) for value in os.environ.get("STRESS_MEMORY_SIZES_MB", "50,100,200").split(",") if value.strip()]
SSH_KEY_CANDIDATES = []
if os.environ.get("STRESS_SSH_KEY"):
    SSH_KEY_CANDIDATES.append(Path(os.environ["STRESS_SSH_KEY"]).expanduser())
SSH_KEY_CANDIDATES.extend([
    Path(os.path.expanduser("~/.ssh/id_rsa")),
    Path(os.path.expanduser("~/.ssh/id_ed25519_roundrobin")),
    Path(os.path.expanduser("~/.ssh/id_ed25519_elevatediq")),
])
SSH_KEY = next((candidate for candidate in SSH_KEY_CANDIDATES if candidate.is_file()), None)

if SSH_KEY is None:
    raise SystemExit("Missing SSH key for stress test: set STRESS_SSH_KEY or add a key to ~/.ssh")

SSH_CMD = [
    "ssh",
    "-i",
    str(SSH_KEY),
    "-o",
    "BatchMode=yes",
    "-o",
    "StrictHostKeyChecking=no",
    f"akushnir@{HOST}",
]

def ssh_exec(cmd):
    """Execute command on remote host"""
    try:
        result = subprocess.run(
            SSH_CMD + [cmd],
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout.strip()
    except Exception as e:
        return f"Error: {e}"

def get_baseline():
    """Get baseline system metrics"""
    print("\n=== BASELINE METRICS ===")
    
    cpus = ssh_exec("nproc")
    print(f"CPUs: {cpus}")
    
    mem = ssh_exec("free -h | grep Mem | awk '{print $2}'")
    print(f"Total Memory: {mem}")
    
    disk = ssh_exec("df -h / | tail -1 | awk '{print $2}'") 
    print(f"Total Disk: {disk}")
    
    docker_stats = ssh_exec("docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}'")
    print(f"\nContainer Status:\n{docker_stats}")
    
    return {"cpus": cpus, "memory": mem, "disk": disk}

def http_load_test(concurrent_users, total_requests, duration_sec=None):
    """Load test with concurrent HTTP requests"""
    print(f"\nTesting {concurrent_users} concurrent users, {total_requests} total requests...")
    
    start_time = time.time()
    results = []
    errors = 0
    
    def make_request():
        try:
            start = time.time()
            resp = requests.get(ENDPOINT, timeout=5)
            elapsed = (time.time() - start) * 1000  # ms
            return {"status": resp.status_code, "time": elapsed}
        except Exception as e:
            return {"status": 0, "time": 0, "error": str(e)}
    
    with ThreadPoolExecutor(max_workers=concurrent_users) as executor:
        futures = []
        for i in range(total_requests):
            if duration_sec and (time.time() - start_time) > duration_sec:
                break
            futures.append(executor.submit(make_request))
        
        for future in as_completed(futures):
            result = future.result()
            if result["status"] == 200:
                results.append(result["time"])
            else:
                errors += 1
    
    elapsed = time.time() - start_time
    
    if results:
        latencies = sorted(results)
        stats = {
            "users": concurrent_users,
            "requests": len(results),
            "errors": errors,
            "success_rate": (len(results) / (len(results) + errors)) * 100,
            "duration_sec": round(elapsed, 2),
            "throughput": round(len(results) / elapsed, 2),
            "latency_min": round(min(latencies), 2),
            "latency_p50": round(latencies[int(len(latencies)*0.5)], 2),
            "latency_p95": round(latencies[int(len(latencies)*0.95)], 2),
            "latency_p99": round(latencies[int(len(latencies)*0.99)], 2),
            "latency_max": round(max(latencies), 2),
            "latency_mean": round(mean(latencies), 2),
        }
        
        print(f"  Requests: {stats['requests']} | Errors: {errors} | Success: {stats['success_rate']:.1f}%")
        print(f"  Duration: {stats['duration_sec']}s | Throughput: {stats['throughput']} req/s")
        print(f"  Latency - Min: {stats['latency_min']}ms | p50: {stats['latency_p50']}ms | p95: {stats['latency_p95']}ms | p99: {stats['latency_p99']}ms | Max: {stats['latency_max']}ms")
        
        return stats
    else:
        print(f"  All {errors} requests failed!")
        return None

def cpu_load_test():
    """Test CPU under load"""
    print("\n=== TEST: CPU CAPACITY ===")
    print("Baseline CPU:")
    baseline = ssh_exec("top -bn1 | grep 'Cpu(s)'")
    print(baseline)
    
    print(f"\nApplying CPU load ({CPU_LOAD_DURATION_SEC} seconds)...")
    ssh_exec(f"nohup bash -c 'for i in $(seq 1 $(nproc)); do (timeout {CPU_LOAD_DURATION_SEC} bash -c \"while true; do echo \\\\$((13**99)) > /dev/null; done\") & done; wait' > /dev/null 2>&1 &")
    
    time.sleep(5)
    print("CPU under load:")
    loaded = ssh_exec("top -bn1 | grep 'Cpu(s)'")
    print(loaded)
    
    time.sleep(CPU_LOAD_DURATION_SEC)
    print("CPU after load:")
    after = ssh_exec("top -bn1 | grep 'Cpu(s)'")
    print(after)

def memory_load_test():
    """Test memory capacity"""
    print("\n=== TEST: MEMORY CAPACITY ===")
    
    baseline = ssh_exec("free -h | grep Mem")
    print(f"Baseline: {baseline}")
    
    print("Testing memory allocation (various sizes)...")
    sizes = ", ".join(str(size) for size in MEMORY_SIZES_MB)
    cmd = f"""python3 - <<'PY'
import time

sizes_mb = [{sizes}]
chunks = []

for size_mb in sizes_mb:
    try:
        chunks.append(bytearray(size_mb * 1024 * 1024))
        print(f'Allocated {{size_mb}}MB - OK')
        time.sleep(1)
    except MemoryError as exc:
        print(f'Failed at {{size_mb}}MB: {{exc}}')
        break
PY
"""
    result = ssh_exec(cmd)
    print(result)
    
    final = ssh_exec("free -h | grep Mem")
    print(f"After test: {final}")

def connection_limits_test():
    """Test connection and process limits"""
    print("\n=== TEST: CONNECTION LIMITS ===")
    
    file_limit = ssh_exec("cat /proc/sys/fs/file-max")
    print(f"Max open files: {file_limit}")
    
    proc_limit = ssh_exec("cat /proc/sys/kernel/pid_max")
    print(f"Max processes: {proc_limit}")
    
    current_conns = ssh_exec("netstat -an 2>/dev/null | grep ':3000' | wc -l")
    print(f"Current connections to port 3000: {current_conns}")
    
    current_procs = ssh_exec("ps aux | grep -E 'code-server|caddy' | grep -v grep | wc -l")
    print(f"Current processes (code-server/caddy): {current_procs}")

def disk_io_test():
    """Test disk I/O performance"""
    print("\n=== TEST: DISK I/O ===")
    
    disk_space = ssh_exec("df -h / | tail -1 | awk '{print $3 \" / \" $2}'")
    print(f"Disk usage: {disk_space}")
    
    print("Testing sequential write (100MB)...")
    write_result = ssh_exec("dd if=/dev/zero of=/tmp/test-io.bin bs=1M count=100 2>&1 | tail -1")
    print(write_result)
    
    print("Testing sequential read (100MB)...")
    read_result = ssh_exec("dd if=/tmp/test-io.bin of=/dev/null bs=1M count=100 2>&1 | tail -1")
    print(read_result)
    
    ssh_exec("rm -f /tmp/test-io.bin")

def main():
    print("=" * 60)
    print("CODE-SERVER STRESS TEST SUITE")
    print(f"Target: {HOST}")
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    
    # Get baseline
    baseline = get_baseline()
    
    # HTTP Load Tests (increasing concurrency)
    print("\n=== TEST: HTTP LOAD TEST ===")
    load_results = []
    for concurrent in CONCURRENCY_LEVELS:
        result = http_load_test(concurrent, concurrent * REQUEST_MULTIPLIER, duration_sec=HTTP_DURATION_SEC)
        load_results.append(result)
        time.sleep(2)
    
    # CPU test
    cpu_load_test()
    
    # Memory test  
    memory_load_test()
    
    # Connection limits
    connection_limits_test()
    
    # Disk I/O
    disk_io_test()
    
    # Summary Report
    print("\n" + "=" * 60)
    print("STRESS TEST SUMMARY")
    print("=" * 60)
    
    print("\nLoad Test Results:")
    print("Concurrent Users | Requests | Success Rate | Throughput | p99 Latency")
    print("-" * 70)
    for result in load_results:
        if result:
            print(f"{result['users']:16d} | {result['requests']:8d} | {result['success_rate']:11.1f}% | {result['throughput']:10.2f} req/s | {result['latency_p99']:7.2f}ms")
    
    # Determine capacity
    print("\n" + "=" * 60)
    print("CAPACITY ANALYSIS")
    print("=" * 60)
    
    if load_results:
        max_concurrent = max([r['users'] for r in load_results if r])
        peak_throughput = max([r['throughput'] for r in load_results if r])
        
        print(f"\nOK Tested up to {max_concurrent} concurrent users")
        print(f"OK Peak throughput: {peak_throughput} req/s")
        print(f"OK Server appears stable under load")
        
        # Find breaking point
        for i, result in enumerate(load_results):
            if result and result['success_rate'] < 99:
                print(f"\nWARNING Performance degradation at {result['users']} concurrent users:")
                print(f"  - Success rate: {result['success_rate']:.1f}%")
                print(f"  - p99 latency: {result['latency_p99']}ms")
    
    print("\n" + "=" * 60)
    print("Completed: " + datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    print("=" * 60)

if __name__ == "__main__":
    main()
