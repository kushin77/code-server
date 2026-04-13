#!/bin/bash
# Stress test suite - executes on remote .31 host

echo "=== CODE-SERVER STRESS TEST ==="
echo "Time: $(date)"
echo ""

# Test 1: Baseline
echo "=== TEST 1: BASELINE SYSTEM METRICS ==="
echo "CPUs: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2 " (Used: " $3 ")"}')"
echo "Disk: $(df -h / | tail -1 | awk '{print $2 " (Used: " $3 ")"}')"
echo ""

# Test 2: Container status
echo "=== TEST 2: CONTAINER STATUS ==="
echo "Count: $(docker ps -q | wc -l) containers running"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}" | head -8
echo ""

# Test 3: HTTP Concurrency Test
echo "=== TEST 3: HTTP CONCURRENCY TEST ==="
for concurrent in 10 25 50 100; do
  echo -n "Testing $concurrent concurrent requests... "
  
  START=$(date +%s%N)
  SUCCESS=0
  FAIL=0
  
  # Use ApacheBench if available
  if command -v ab &> /dev/null; then
    RESULT=$(timeout 30 ab -n 500 -c $concurrent -q http://localhost:3000/health 2>/dev/null | grep "Requests per second")
    echo "$RESULT"
  else
    # Fallback: concurrent curl
    for i in $(seq 1 $((500/concurrent))); do
      for j in $(seq 1 $concurrent); do
        if timeout 5 curl -s http://localhost:3000/health > /dev/null 2>&1; then
          ((SUCCESS++))
        else
          ((FAIL++))
        fi &
      done
      wait
    done
    
    END=$(date +%s%N)
    DURATION=$(( ($END - $START) / 1000000000 ))
    RPS=$(( ($SUCCESS + $FAIL) / $DURATION ))
    
    echo "Success: $SUCCESS | Fail: $FAIL | RPS: $RPS"
  fi
done
echo ""

# Test 4: Memory under load
echo "=== TEST 4: MEMORY STRESS ==="
echo "Before: $(free -h | grep Mem | awk '{print $3}')"

if command -v python3 &> /dev/null; then
  timeout 20 python3 -c "
import numpy as np
import time
for size in [100, 200, 300]:
    try:
        arr = np.random.rand(size, size)
        print(f'  Created {size}x{size} array')
        time.sleep(2)
        del arr
    except:
        print(f'  Failed at size {size}')
        break
" 2>/dev/null
fi

echo "After: $(free -h | grep Mem | awk '{print $3}')"
echo ""

# Test 5: CPU Load
echo "=== TEST 5: CPU STRESS ==="
echo "Baseline: $(top -bn1 | grep 'Cpu(s)' | sed 's/^[^,]*,//')"

NUM_CORES=$(nproc)
echo "Running $NUM_CORES parallel CPU tasks (30 sec)..."

for i in $(seq 1 $NUM_CORES); do
  (timeout 30 bash -c 'while true; do echo $((13**99)) > /dev/null; done') &
done

sleep 5
echo "Under load: $(top -bn1 | grep 'Cpu(s)' | sed 's/^[^,]*,//')"

wait 2>/dev/null || true
sleep 2

echo "After load: $(top -bn1 | grep 'Cpu(s)' | sed 's/^[^,]*,//')"
echo ""

# Test 6: Disk I/O
echo "=== TEST 6: DISK I/O ==="
echo "Write speed (100MB):"
dd if=/dev/zero of=/tmp/test-io.bin bs=1M count=100 2>&1 | grep -oE '[0-9.]+.*s'

echo "Read speed (100MB):"
dd if=/tmp/test-io.bin of=/dev/null bs=1M count=100 2>&1 | grep -oE '[0-9.]+.*s'

rm -f /tmp/test-io.bin
echo ""

# Test 7: Process/Connection limits
echo "=== TEST 7: SYSTEM LIMITS ==="
echo "Max file descriptors: $(cat /proc/sys/fs/file-max)"
echo "Max processes: $(cat /proc/sys/kernel/pid_max)"
echo "Current connections (port 3000): $(netstat -an 2>/dev/null | grep ':3000' | wc -l)"
echo "Current relevant processes: $(ps aux | grep -E 'code-server|caddy|node' | grep -v grep | wc -l)"
echo ""

# Test 8: Sustained load
echo "=== TEST 8: SUSTAINED LOAD TEST (60 sec) ==="
echo "Generating ~100 req/s for 60 seconds..."

START=$(date +%s)
SUCCESS=0
FAIL=0

timeout 60 bash -c '
while true; do
  for i in {1..100}; do
    curl -s http://localhost:3000/health > /dev/null 2>&1 || true &
  done
  wait
done
' 2>/dev/null

sleep 2
END=$(date +%s)
DURATION=$((END - START))

echo "Total duration: ${DURATION}s"
echo "Container stats (after load):"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"

echo ""
echo "=== STRESS TEST COMPLETE ==="
echo "End time: $(date)"
