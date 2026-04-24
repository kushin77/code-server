#!/bin/bash
# Execute GPU driver upgrade in unprivileged mode first to test, then with docker

echo "[$(date +'%H:%M:%S')] Attempting GPU driver upgrade..."

# Try with docker run --privileged (akushnir is in docker group, so no sudo needed)
docker run --rm \
  --privileged \
  --network host \
  -v /tmp:/tmp \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --pid=host \
  ubuntu:22.04 \
  bash -x /tmp/gpu-driver-ubuntu-drivers.sh

echo "[$(date +'%H:%M:%S')] GPU driver installation via Docker completed"
