# Cloudflare Tunnel Setup (P1 #351)

This document provides instructions for setting up and managing a Cloudflare Tunnel for secure, on-premises connectivity to `ide.kushnir.cloud`.

---

## Architecture Overview

- **Hostname**: `ide.kushnir.cloud`
- **Internal Host**: `192.168.168.31`
- **Internal Service**: `http://caddy:80`
- **Tunnel Service**: `cloudflared` (Systemd)

---

## 1. Prerequisites

- ✅ Cloudflare account with a valid zone for `kushnir.cloud`.
- ✅ Cloudflare API Token (Zone:Edit, DNS:Edit permissions).
- ✅ Cloudflare Account ID and Zone ID.
- ✅ Terraform installed (local or on-prem).
- ✅ `CLOUDFLARE_TUNNEL_TOKEN` stored in a secure location (Vault or GitHub Secrets).

---

## 2. Infrastructure Setup (Terraform)

Infrastructure is managed via Terraform in `terraform/modules/dns/main.tf`.

To provision the tunnel and DNS records:
```bash
cd terraform
# Ensure vars are set in terraform.tfvars or as ENV variables
terraform plan
terraform apply -auto-approve
```

---

## 3. On-Prem Implementation

Run the setup script on the primary host (`192.168.168.31`):

```bash
# SSH to the host
ssh akushnir@192.168.168.31

# Run the setup script (ensure token is set)
export CLOUDFLARE_TUNNEL_TOKEN="your-token-here"
sudo bash scripts/setup-cloudflare-tunnel.sh
```

---

## 4. Monitoring & Health Checks

- **Prometheus Metrics**: `localhost:7878/metrics` relative to the `cloudflared` service.
- **Log Location**: `journalctl -u cloudflared`
- **Status Dashboard**: [Zero Trust Dashboard](https://one.dash.cloudflare.com/) -> Access -> Tunnels

---

## 5. Troubleshooting & Rollback

### Common Issues
- **Authentication**: Ensure the `CLOUDFLARE_TUNNEL_TOKEN` is correct.
- **Connectivity**: Verify outgoing HTTPS access patterns (TCP port 443, 7878).
- **DNS**: Confirm the CNAME record points to `<tunnel-id>.cfargotunnel.com`.

### Rollback (Manual)
If the tunnel fails and you need to restore direct access:
1. Update DNS record in Cloudflare or via Terraform to point directly to the host IP.
2. Disable the `cloudflared` service:
   ```bash
   sudo systemctl stop cloudflared
   sudo systemctl disable cloudflared
   ```

---

**Last Updated**: April 16, 2026 | **Owner**: Alex Kushnir | **Reference**: #351
