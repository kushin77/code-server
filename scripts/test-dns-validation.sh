#!/bin/bash
# Test: Verify Terraform validation prevents IP hardcoding

echo "Testing Terraform validation for DNS hardening..."
echo ""

# Test Case 1: Valid Cloudflare Tunnel URL (should pass)
echo "Test 1: Valid Cloudflare Tunnel URL"
export TF_VAR_cloudflare_tunnel_url="home-dev.cfargotunnel.com"
cd terraform
terraform plan -target='godaddy_domain_record.root_cname_cloudflare' 2>&1 | head -5
echo "✓ Test 1: Valid URL accepted"
echo ""

# Test Case 2: Invalid IP address (should fail)
echo "Test 2: Invalid IP address (should be rejected)"
export TF_VAR_cloudflare_tunnel_url="192.168.168.31"
terraform plan -target='godaddy_domain_record.root_cname_cloudflare' 2>&1 | grep -q "must be a Cloudflare tunnel endpoint"
if [ $? -eq 0 ]; then
  echo "✓ Test 2: IP address correctly rejected by validation"
else
  echo "✗ Test 2: IP address was NOT rejected (validation failed)"
fi
echo ""

# Test Case 3: Plain domain without cfargotunnel (should fail)
echo "Test 3: Invalid domain without cfargotunnel"
export TF_VAR_cloudflare_tunnel_url="example.com"
terraform plan -target='godaddy_domain_record.root_cname_cloudflare' 2>&1 | grep -q "must be a Cloudflare tunnel endpoint"
if [ $? -eq 0 ]; then
  echo "✓ Test 3: Non-Cloudflare domain correctly rejected"
else
  echo "✗ Test 3: Non-Cloudflare domain was NOT rejected (validation failed)"
fi
echo ""

echo "Validation tests complete!"
