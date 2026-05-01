# SSL/TLS Hardening Guide (P1 Priority 2)

## Overview
This document outlines the SSL/TLS hardening measures implemented to secure internal and external communications for the Code Server Enterprise environment.

## Internal PKI
A custom Internal Certificate Authority (CA) is used for service-to-service communication.
- **CA Certificate**: \certs/ssl/ca.crt- **Server Certificates**: Generated with SANs for \localhost\, \opa\, and \caddy\.
- **Strength**: RSA 4096-bit for CA, 2048-bit for leaf certificates.

## TLS Standards
We enforce **TLS 1.3** for all edge communications via Caddy.
- Older protocols (TLS 1.0, 1.1, 1.2) are disabled to prevent downgrade attacks.
- Perfect Forward Secrecy (PFS) is required.

## Automation
The hardening can be applied or refreshed using:
\\ash
bash scripts/ops/harden-ssl-tls.sh
\
## Verification
To verify the certificate chain and protocol support:
\\ash
openssl x509 -in certs/ssl/server.crt -text -noout
# Or use tools like testssl.sh against the endpoint
\
## Compliance
This implementation meets GOV-002 requirements for cryptographically secure internal communication.
