import os
import subprocess
import time
from pathlib import Path

replica = 'akushnir@192.168.168.42'
nas = Path('/mnt/nas-56')
pid = os.getpid()
results = []

# Network transfer benchmark: primary -> replica via SSH
mib = 100
start = time.perf_counter()
p1 = subprocess.Popen(
    ['dd', 'if=/dev/zero', 'bs=1M', f'count={mib}'],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
)
p2 = subprocess.Popen(
    ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', replica, 'cat'],
    stdin=p1.stdout,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
p1.stdout.close()
rc2 = p2.wait()
rc1 = p1.wait()
elapsed = time.perf_counter() - start
results.append(("network_ssh_transfer_mib_per_s", round(mib / elapsed, 2), "MiB/s"))
results.append(("network_ssh_transfer_mbps", round((mib * 8) / elapsed, 2), "Mb/s"))
results.append(("network_transfer_exit_codes", f"dd:{rc1} ssh:{rc2}", ""))

# NFS throughput benchmark on /mnt/nas-56
bench = nas / f'baseline-{pid}.bin'
small = nas / f'baseline-small-{pid}'
small.mkdir(exist_ok=True)

start = time.perf_counter()
subprocess.run(
    ['dd', 'if=/dev/zero', f'of={bench}', 'bs=1M', f'count={mib}', 'conv=fsync', 'status=none'],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=True,
)
write_elapsed = time.perf_counter() - start
results.append(("nfs_write_mib_per_s", round(mib / write_elapsed, 2), "MiB/s"))
results.append(("nfs_write_mbps", round((mib * 8) / write_elapsed, 2), "Mb/s"))

start = time.perf_counter()
subprocess.run(
    ['dd', f'if={bench}', 'of=/dev/null', 'bs=1M', 'status=none'],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=True,
)
read_elapsed = time.perf_counter() - start
results.append(("nfs_read_mib_per_s", round(mib / read_elapsed, 2), "MiB/s"))
results.append(("nfs_read_mbps", round((mib * 8) / read_elapsed, 2), "Mb/s"))

# Small-file latency benchmark
count = 1000
start = time.perf_counter()
for i in range(count):
    (small / f'file-{i:04d}.txt').touch()
create_elapsed = time.perf_counter() - start
results.append(("nfs_smallfile_create_avg_ms", round((create_elapsed * 1000) / count, 3), "ms/file"))

start = time.perf_counter()
for i in range(count):
    os.stat(small / f'file-{i:04d}.txt')
stat_elapsed = time.perf_counter() - start
results.append(("nfs_smallfile_stat_avg_ms", round((stat_elapsed * 1000) / count, 3), "ms/file"))

# Cleanup
bench.unlink(missing_ok=True)
for child in small.iterdir():
    child.unlink()
small.rmdir()

for key, value, unit in results:
    print(f"{key}={value} {unit}")
