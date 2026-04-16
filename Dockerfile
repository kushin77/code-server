# @file        Dockerfile
# @description CI pre-commit runner — linting, shellcheck, and governance hooks
# @module      ci-runner

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="code-server-enterprise-ci-runner"
LABEL org.opencontainers.image.description="CI pre-commit runner for linting, shellcheck, and governance hooks"
LABEL org.opencontainers.image.source="https://github.com/kushin77/code-server"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates python3 python3-pip gnupg2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir pre-commit

WORKDIR /workspace

CMD ["/bin/bash"]
