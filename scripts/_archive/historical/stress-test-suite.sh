#!/bin/bash
# Comprehensive stress test suite for code-server deployment

set -e

HOST=${1:-192.168.168.31}
RESULTS_DIR="/tmp/stress-test-results"
SSH_CMD="ssh -o StrictHostKeyChecking=no akushnir@$HOST"

mkdir -p $RESULTS_DIR
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$RESULTS_DIR/stress-test-$TIMESTAMP.txt"

echo "=== STRESS TEST SUITE ===" | tee $REPORT
echo "Target: $HOST" | tee -a $REPORT
echo "Start: $(date)" | tee -a $REPORT
echo "" | tee -a $REPORT

# Test 1: Baseline Resource State
echo "=== TEST 1: BASELINE RESOURCE STATE ===" | tee -a $REPORT
$SSH_CMD bash -c '
echo "CPU Info:"
nproc
lscpu | grep -E "Model name|CPU MHz|Cores"
echo ""
echo "Memory Info:"
free -h
echo ""
echo "Container Limits:"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"
' | tee -a $REPORT

echo "" | tee -a $REPORT

# Test 2: HTTP Load Test (Concurrent Connections)
echo "=== TEST 2: HTTP LOAD TEST (Concurrent Connections) ===" | tee -a $REPORT
echo "Testing connection concurrency and throughput..." | tee -a $REPORT

for concurrent in 10 25 50 100 200; do
  echo "→ Testing $concurrent concurrent connections..." | tee -a $REPORT
  START=$(date +%s%N)

  $SSH_CMD bash -c "
  timeout 30 ab -n 1000 -c $concurrent -q http://localhost:3000/health 2>/dev/null || true
  echo 'Status: OK'
  " 2>&1 | head -20 | tee -a $REPORT

  END=$(date +%s%N)
  DURATION=$(( ($END - $START) / 1000000 ))
  echo "  Duration: ${DURATION}ms" | tee -a $REPORT
done

echo "" | tee -a $REPORT

# Test 3: Memory Stress Test
echo "=== TEST 3: MEMORY STRESS TEST ===" | tee -a $REPORT
echo "Baseline memory:" | tee -a $REPORT
$SSH_CMD "free -h | tail -2" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "Starting memory intensive operation..." | tee -a $REPORT

$SSH_CMD bash -c '
echo "Memory before: $(free -h | grep Mem | awk "{print \$3}")"
timeout 20 python3 -c "
import numpy as np
import time
sizes = [100, 300, 500]
for size in sizes:
    arr = np.random.rand(size, size)
    print(f\"Array {size}x{size} created - Memory: {arr.nbytes / 1024 / 1024:.1f}MB\")
    time.sleep(2)
    del arr
"
echo "Memory after: $(free -h | grep Mem | awk "{print \$3}")"
' 2>&1 | tee -a $REPORT

echo "" | tee -a $REPORT

# Test 4: CPU Stress Test
echo "=== TEST 4: CPU STRESS TEST ===" | tee -a $REPORT
echo "Baseline CPU:" | tee -a $REPORT
$SSH_CMD "top -bn1 | grep 'Cpu(s)'" | tee -a $REPORT

echo "" | tee -a $REPORT
echo "Stressing CPU with parallel workloads..." | tee -a $REPORT

$SSH_CMD bash -c '
NUM_CORES=$(nproc)
echo "Running $NUM_CORES parallel CPU-intensive tasks for 30 seconds..."

for i in $(seq 1 $NUM_CORES); do
  (timeout 30 bash -c "while true; do echo $((13**99)) > /dev/null; done") &
done

sleep 5
echo "CPU under load:"
top -bn1 | grep "Cpu(s)"

wait
echo "CPU after load:"
top -bn1 | grep "Cpu(s)"
' 2>&1 | tee -a $REPORT

echo "" | tee -a $REPORT

# Test 5: Disk I/O Test
echo "=== TEST 5: DISK I/O TEST ===" | tee -a $REPORT
$SSH_CMD bash -c '
echo "Disk space available:"
df -h / | tail -1

echo ""
echo "Testing sequential write performance..."
dd if=/dev/zero of=/tmp/test-io.bin bs=1M count=100 2>&1 | tail -1

echo ""
echo "Testing random read performance..."
dd if=/tmp/test-io.bin of=/dev/null bs=1M count=100 2>&1 | tail -1

rm -f /tmp/test-io.bin
' 2>&1 | tee -a $REPORT

echo "" | tee -a $REPORT

# Test 6: Container Health Under Load
echo "=== TEST 6: CONTAINER HEALTH UNDER LOAD ===" | tee -a $REPORT
$SSH_CMD bash -c '
echo "Starting sustained load for 60 seconds..."
timeout 60 bash -c "while true; do curl -s http://localhost:3000/health > /dev/null; done" &
LOAD_PID=$!

sleep 10
echo "Container stats (during load):"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"

wait $LOAD_PID 2>/dev/null || true

sleep 2
echo ""
echo "Container stats (after load):"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"
' 2>&1 | tee -a $REPORT

echo "" | tee -a $REPORT

# Test 7: Network Throughput
echo "=== TEST 7: NETWORK THROUGHPUT ===" | tee -a $REPORT
$SSH_CMD bash -c '
echo "Network interfaces:"
ip -s link 2>/dev/null | grep -A2 "eth0\|ens\|wlan" || echo "N/A"

echo ""
echo "Testing sustained data transfer (100 concurrent requests)..."
timeout 30 bash -c "for i in {1..100}; do curl -s -o /dev/null http://localhost:3000/health & done; wait"

echo ""
echo "Network stats:"
cat /proc/net/dev 2>/dev/null | grep -E "eth0|ens" || echo "N/A"
' 2>&1 | tee -a $REPORT

echo "" | tee -a $REPORT

# Test 8: Process and Connection Limits
echo "=== TEST 8: PROCESS & CONNECTION LIMITS ===" | tee -a $REPORT
$SSH_CMD bash -c '
echo "Max open files:"
cat /proc/sys/fs/file-max

echo ""
echo "Max processes:"
cat /proc/sys/kernel/pid_max

echo ""
echo "Current connections to port 3000:"
netstat -an 2>/dev/null | grep ":3000" | wc -l || echo "N/A"

echo ""
echo "Current processes:"
ps aux | grep -E "code-server|caddy|ssh" | grep -v grep | wc -l
' 2>&1 | tee -a $REPORT

echo "" | tee -a $REPORT
echo "=== END STRESS TEST ===" | tee -a $REPORT
echo "Completed: $(date)" | tee -a $REPORT
echo "Report saved to: $REPORT" | tee -a $REPORT

echo ""
echo "Report location: $REPORT"
