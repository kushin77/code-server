## Production Baseline Evidence for #895

Captured on 2026-04-20 from the production host at 192.168.168.31.

### Network Transfer Benchmark
- Primary -> replica SSH transfer: 68.22 MiB/s
- Equivalent throughput: 545.79 Mb/s
- Exit codes: dd:0 ssh:0

### Transport-Neutral iperf3 Benchmark
- Primary -> replica: 935 Mb/s
- Replica -> primary: 935 Mb/s
- Test method: temporary `networkstatic/iperf3` container on both hosts with host networking

### NAS / NFS Benchmark
- NFS write throughput: 91.02 MiB/s
- NFS read throughput: 3726.32 MiB/s
- Small-file create latency: 4.224 ms/file
- Small-file stat latency: 0.094 ms/file

### PostgreSQL Cache-Hit Check
- Cache hit ratio: 99.88%

### Assessment
- The production host baseline is now captured.
- NAS read/write and cache-hit behavior look healthy.
- Bidirectional iperf3 throughput now clears the 900 Mb/s target.
- #895 is ready to close with the captured baseline evidence.
