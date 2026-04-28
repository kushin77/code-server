# Terraform SSL/TLS Module - Let's Encrypt ACME Automation

**Date**: April 28, 2026  
**Phase**: 3 - Infrastructure as Code Hardening  
**Status**: Phase 1 Complete - Certificate Provisioning & Automation  
**Owner**: Infrastructure Team

---

## Overview

This module automates SSL/TLS certificate lifecycle management using Let's Encrypt ACME with AWS Certificate Manager (ACM).

**Key Features**:
- ✅ Let's Encrypt certificate provisioning (free, automatic renewal)
- ✅ Route53 DNS-01 validation (no downtime, wildcard support)
- ✅ Automatic certificate renewal 30 days before expiry
- ✅ CloudWatch monitoring and SNS alerting
- ✅ Caddy integration for reverse proxy TLS
- ✅ Multi-environment support (dev, staging, production)

---

## Architecture

```
Let's Encrypt           AWS ACM              Route53
   (ACME)  -------->  (Certificates)  <---- (DNS)
              |             |
              v             v
        Certificate    CloudWatch
        Validation     Monitoring
              |             |
              v             v
          Lambda         EventBridge
       (Auto Renewal)   (Scheduling)
              |             |
              v             v
          Caddy      SNS Alerts
        (TLS Proxy)  (Email/Slack)
```

---

## Certificate Lifecycle

### Phases

**1. Issuance** (~5 minutes):
```
Terraform → ACM → Let's Encrypt → DNS Validation → Certificate Ready
```

**2. Deployment** (~2 minutes):
```
Certificate → Caddy Config → Reload → HTTPS Active
```

**3. Monitoring** (Continuous):
```
CloudWatch Lambda → Daily Check → 30-day Alert → Automatic Renewal
```

**4. Renewal** (~5 minutes, automatic):
```
30 days before expiry → New Certificate → Deploy → Old Cert Revoked
```

---

## Configuration

### Module Variables

```hcl
module "ssl_tls" {
  source = "./modules/ssl-tls"

  # Domain configuration
  environment          = "production"
  apex_domain          = "example.com"
  subdomain_prefixes   = ["api", "admin", "dashboard", "monitoring"]
  enable_wildcard_certificate = true

  # Let's Encrypt configuration
  letsencrypt_email            = "admin@example.com"
  letsencrypt_environment      = "production"
  certificate_renewal_days_before_expiry = 30

  # Monitoring
  enable_certificate_monitoring = true
  certificate_expiration_alarm_days = 14
  renewal_check_frequency = "0 2 * * *"  # Daily at 02:00 UTC

  # AWS Resources
  route53_zone_id  = aws_route53_zone.example.zone_id
  sns_topic_arn    = aws_sns_topic.ops_alerts.arn

  common_tags = {
    Project     = "infrastructure-modernization"
    Environment = "production"
    Phase       = "3"
  }
}
```

### Environment-Specific Configuration

**Development** (`dev-certificate.tfvars`):
```hcl
environment          = "dev"
apex_domain          = "dev.example.local"
letsencrypt_environment = "staging"  # Use LE staging to avoid rate limits
enable_certificate_monitoring = false
```

**Staging** (`staging-certificate.tfvars`):
```hcl
environment          = "staging"
apex_domain          = "staging.example.com"
letsencrypt_environment = "production"
enable_certificate_monitoring = true
certificate_expiration_alarm_days = 21
```

**Production** (`prod-certificate.tfvars`):
```hcl
environment          = "production"
apex_domain          = "example.com"
letsencrypt_environment = "production"
enable_certificate_monitoring = true
certificate_expiration_alarm_days = 14
enable_wildcard_certificate = true
```

---

## Deployment

### Step 1: Create DNS Zone

Ensure Route53 zone exists and is delegated:
```bash
aws route53 list-hosted-zones-by-name --dns-name example.com
```

### Step 2: Deploy Module

```bash
# Initialize
terraform init

# Plan
terraform plan -var-file=environments/prod-certificate.tfvars

# Apply (creates certificate + validation records)
terraform apply -var-file=environments/prod-certificate.tfvars
```

### Step 3: Verify Certificate

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn $(terraform output certificate_arn) \
  --query 'Certificate.{Status:Status,NotAfter:NotAfter,DomainNames:DomainNames}'

# Expected output (after validation):
# {
#   "Status": "ISSUED",
#   "NotAfter": "2027-04-28T23:59:59+00:00",
#   "DomainNames": ["example.com", "*.example.com", "api.example.com", ...]
# }
```

### Step 4: Update Caddy Configuration

```bash
# Copy generated Caddy config
cp config/caddy-certificate.conf /etc/caddy/

# Update main Caddyfile
echo "import caddy-certificate.conf" >> /etc/caddy/Caddyfile

# Reload Caddy
systemctl reload caddy

# Verify HTTPS
curl -v https://example.com/health
```

---

## Monitoring & Alerts

### CloudWatch Dashboard

Automatically created with:
- Certificate expiration timeline
- Renewal success rate
- DNS validation status
- Lambda execution metrics

Access via AWS Console:
```
CloudWatch → Dashboards → ${environment}-certificate-monitoring
```

### Alerts

**Certificate Expiration** (14 days before expiry):
```
Alert: Production certificate example.com expires in 14 days
Action: Manual: Check renewal Lambda logs
        Auto: Lambda should auto-renew 30 days before
```

**Renewal Failure**:
```
Alert: Certificate renewal failed for example.com
Action: Check Lambda logs at /aws/lambda/${environment}-certificate-renewal
        Manual renewal: aws acm-pca issue-certificate ...
```

**Validation Timeout** (> 5 minutes):
```
Alert: Certificate validation timeout for example.com
Action: Check Route53 DNS records
        Verify DNS propagation: dig example.com
```

---

## Certificate Domains

### Development
```
dev.kushnir.local
*.kushnir.local
```

### Staging  
```
staging.example.com
api.staging.example.com
admin.staging.example.com
dashboard.staging.example.com
monitoring.staging.example.com
*.staging.example.com (wildcard)
```

### Production
```
example.com
api.example.com
admin.example.com
dashboard.example.com
monitoring.example.com
*.example.com (wildcard)
```

---

## Renewal Process (Automated)

### Daily Check (02:00 UTC)

Lambda function runs:
```python
# Check certificate expiration
if days_until_expiry <= 30:
    # Request new certificate from Let's Encrypt
    new_cert = acm.request_certificate(
        domain_name=apex_domain,
        subject_alt_names=subdomain_list,
        validation_method='DNS'
    )
    # Update Route53 DNS records for validation
    # Wait for validation
    acm.wait_certificate_issued(new_cert_arn)
    # Update Caddy configuration
    # Reload Caddy
    # Send SNS notification: "Certificate renewed successfully"
```

### Manual Renewal

```bash
# If automatic renewal fails:
terraform taint aws_acm_certificate.main
terraform apply -var-file=prod-certificate.tfvars

# Or explicitly:
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" "api.example.com" \
  --validation-method DNS
```

---

## Troubleshooting

### Certificate Not Issued (stuck in "Pending Validation")

```bash
# Check Route53 records
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output route53_zone_id) \
  --query 'ResourceRecordSets[?contains(Name, "_")]'

# Should see: _xxxxx.example.com TXT "acme-challenge=..."

# Verify DNS propagation
dig _xxxxx.example.com TXT +short

# If not propagated, wait 5 minutes then:
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --query 'Certificate.DomainValidationOptions'
```

### Certificate Renewal Failed

```bash
# Check Lambda logs
aws logs tail /aws/lambda/production-certificate-renewal --follow

# Common issues:
# 1. DNS propagation delay
#    Solution: Wait 5 minutes and retry
# 2. Let's Encrypt rate limit
#    Solution: Use staging endpoint during testing
# 3. Subdomain DNS misconfigured
#    Solution: Verify CNAME/A records for all subdomains
```

### Caddy Not Using New Certificate

```bash
# Verify Caddy loaded config
curl http://localhost:2019/config | jq '.storage'

# Check certificate file permissions
ls -la /etc/caddy/certificates/

# Reload Caddy
systemctl reload caddy

# Verify with curl
curl -v https://example.com/ 2>&1 | grep -i "subject:"
```

---

## Cost & Limits

### Pricing

- **Let's Encrypt Certificates**: FREE
- **AWS Route53**: $0.40/month per hosted zone
- **AWS Lambda**: < $1/month (minimal execution)
- **CloudWatch**: < $5/month (logs + alarms)

**Total Monthly Cost**: ~$5-6 (Route53 + CloudWatch)

### Limits

- **Let's Encrypt**: 50 certificates per domain per week
- **Certificates per ACM**: Unlimited
- **Renewal frequency**: Max 1x per 7 days per domain
- **SANs per certificate**: Up to 10 subdomains

---

## Integration with Caddy

### Current Caddy Setup (Development)

```
Caddyfile (existing):
├── kushnir.local → internal certificates
├── API handlers
├── Admin handlers
└── Health checks
```

### Post-Deployment (Production)

```
Caddyfile (updated):
├── import caddy-certificate.conf  ← AUTO-GENERATED
│   ├── Let's Encrypt ACME
│   ├── Auto renewal
│   └── Security headers
└── Service routes
```

---

## Security Considerations

### Certificate Validation

- ✅ DNS-01 validation (secure, no public endpoint needed)
- ✅ Automatic DNS record cleanup (after validation)
- ✅ No domain control shared externally

### Secrets Management

- ✅ Let's Encrypt email in Terraform (configurable)
- ✅ Cloudflare API token via environment variable
- ✅ No private keys stored in git

### Compliance

- ✅ Certificates signed by Let's Encrypt (browser-trusted)
- ✅ TLS 1.2+ enforced (Caddy config)
- ✅ Certificate transparency logs (Let's Encrypt requirement)

---

## Phase 3 Week 2 Roadmap

✅ **Week 1 (Apr 28 - Done)**: Module created  
⏳ **Week 2 (May 5-11)**: Deploy to staging  
- [ ] Deploy SSL/TLS module to staging environment
- [ ] Verify certificate issuance
- [ ] Test auto-renewal flow
- [ ] Configure Caddy with production settings
- [ ] Monitor certificate lifecycle

⏳ **Week 3 (May 12-18)**: Production rollout  
- [ ] Production certificate provisioning
- [ ] Caddy configuration deployment
- [ ] Switch DNS to prod certificates
- [ ] Decommission manual certificate processes

---

## Support & Documentation

- Caddy TLS: https://caddyserver.com/docs/caddyfile/directives/tls
- Let's Encrypt: https://letsencrypt.org/docs/
- ACME Protocol: https://tools.ietf.org/html/rfc8555
- AWS ACM: https://docs.aws.amazon.com/acm/

---

**Status**: Module ready for staging deployment (Week 2)  
**Next**: Coordinate with database module for integrated deployment
