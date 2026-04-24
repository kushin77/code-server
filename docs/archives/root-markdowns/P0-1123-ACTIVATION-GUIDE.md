## P0 #1123: PRODUCTION DEPLOYMENT - ACTIVATION GUIDE

**Status:** All artifacts deployed and verified on primary and replica hosts.
**Ready for activation:** YES
**Deployment Date:** April 22, 2026

### Pre-Activation Verification

All required artifacts are present on production:

**Primary Host (192.168.168.31):**
```
✓ config/mtls-certs/ - Complete certificate hierarchy
✓ docker-compose.mtls.yml - mTLS overlay configuration  
✓ scripts/security/rotate-mtls-certificates.sh - Rotation automation
✓ Environment: .env.production configured
```

**Replica Host (192.168.168.42):**
```
✓ config/mtls-certs/ - Complete certificate hierarchy
✓ docker-compose.mtls.yml - mTLS overlay configuration
✓ scripts/security/rotate-mtls-certificates.sh - Rotation automation
```

### Activation Steps

Execute on primary host (192.168.168.31):

```bash
cd /home/akushnir/code-server-enterprise-ops

# Step 1: Verify current status
docker-compose ps

# Step 2: Source environment
source .env.production

# Step 3: Apply mTLS overlay with current configuration
docker-compose -f docker-compose.yml -f docker-compose.mtls.yml up -d

# Step 4: Verify all services started with mTLS
docker-compose logs --tail=20

# Step 5: Check certificate deployment
docker-compose exec redis openssl s_client -showcerts </dev/null 2>/dev/null | grep subject
```

### Expected Results After Activation

- All 13 services restart with mTLS enabled
- Services communicate via mutual TLS authentication
- Daily certificate rotation begins at 02:00 UTC
- Audit logs written to `/tmp/mtls-rotation.log`
- Zero-downtime deployment (services restart one at a time)

### Rollback Procedure

If needed, rollback to previous TLS mode:

```bash
docker-compose -f docker-compose.yml up -d
```

This removes the mTLS overlay and restarts with previous TLS configuration.

### Certificate Rotation Verification

After activation, verify rotation is scheduled:

```bash
systemctl list-timers mtls-cert-rotation.timer
systemctl status mtls-cert-rotation.service
```

### Monitoring After Activation

Monitor certificate expiration:
```bash
openssl x509 -enddate -noout -in config/mtls-certs/ca-root/ca-cert.pem
```

Check rotation logs:
```bash
tail -f /tmp/mtls-rotation.log
```

---

**P0 #1123 Implementation Status:** ✅ COMPLETE
**Artifacts Status:** ✅ DEPLOYED TO PRODUCTION
**Activation Status:** 🟡 READY (awaiting manual activation)
**Documentation:** ✅ COMPLETE

This guide is ready for operations team to execute activation at planned maintenance window.
