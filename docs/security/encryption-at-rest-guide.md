# Encryption at Rest Guide (P1 Priority 7)

## Overview
This document outlines the encryption at rest strategy used to protect persistent data for the Code Server Enterprise environment.

## Hard Disk Encryption (LUKS)
For on-premises or block-device-based storage, we use Linux Unified Key Setup (LUKS).
- **Tool**: \cryptsetup- **Standard**: AES-256-XTS
- **Key Management**: Use Passphrase or External Key Management System (KMS).

## Cloud-native Encryption
When deploying to cloud providers (AWS, Azure, GCP):
- **AWS**: Use KMS-managed keys for EBS and S3.
- **Azure**: Use Azure Disk Encryption and Storage Service Encryption.
- **GCP**: Use Cloud KMS for persistent disks.

## Automation
A configuration checklist is generated via:
\\ash
bash scripts/ops/setup-encryption-at-rest.sh
\
## Compliance
This implementation ensures compliance with GOV-002 and industry-standard security frameworks for data-at-rest protection.
