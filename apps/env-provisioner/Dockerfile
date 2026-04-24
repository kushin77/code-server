# @file        apps/env-provisioner/Dockerfile
# @module      infrastructure/parity
# @description Dockerfile for Env Provisioner service

FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir pyyaml

COPY main.py .

ENTRYPOINT ["python", "main.py"]
