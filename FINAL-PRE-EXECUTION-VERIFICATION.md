# FINAL PRE-EXECUTION VERIFICATION - APRIL 14-15
**Phase 12: Multi-Region Federation | Execution Starts: Monday April 15, 08:00 UTC**

---

## CRITICAL: Complete This Checklist Before War Room Opens (By 07:45 UTC Monday)

This document is the **final gate** before Phase 12.1 execution begins. All items below MUST be checked, verified, and signed before proceeding.

---

## 1. CODE & GIT STATUS (Verify by 07:00 UTC Monday)

**All team members should run**:

```bash
# 1. Verify Phase 9-11-12 are on main branch
git status
git branch -v

# 2. Verify commit history shows Phases 9, 10, 11 merged
git log --oneline --graph | head -30

# 3. Verify no uncommitted changes
git status --porcelain
# Expected: Empty output (no changes)

# 4. Fetch latest from remote
git fetch origin main
git log --oneline origin/main | head -5

# 5. Verify terraform/phase-12/ is present and complete
ls -la terraform/phase-12/
# Expected files:
#   - main.tf
#   - variables.tf
#   - vpc-peering.tf
#   - regional-network.tf
#   - load-balancer.tf
#   - dns-failover.tf
#   - terraform.tfvars (or terraform.tfvars.example)
#   - phase-12-execute.sh
#   - phase-12-execute.ps1

# 6. Verify kubernetes/phase-12/ is present
ls -la kubernetes/phase-12/
# Expected directories:
#   - data-layer/
#   - routing/
#   - api/
```

**Infrastructure Lead ONLY - Run Complete Pre-Flight Check**:

```bash
# Full pre-flight validation
cd terraform/phase-12

# 1. Terraform version (must be >= 1.5.0)
terraform version
# Should show: Terraform v1.5.0 or higher

# 2. Initialize Terraform (if not already done)
terraform init
# Should complete without errors

# 3. Validate Terraform syntax
terraform validate
# Should show: Success! The configuration is valid.

# 4. Check if AWS credentials work
aws sts get-caller-identity
# Should show: Account ID, ARN, UserId

# 5. List existing VPCs (to populate terraform.tfvars if needed)
aws ec2 describe-vpcs --region us-east-1 \
  --query 'Vpcs[?Tags[?Key==`Name`]].{ID:VpcId,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

# 6. Terraform plan (without applying)
terraform plan -out=/tmp/phase12.tfplan
# Should complete and show:
#   - 5 VPC resources to create
#   - 10 VPC peering connections to create
#   - Security groups, route tables, etc.
#   - Total: 50-80 resources to create
```

**Sign-Off**:
- [ ] All code verified on main
- [ ] No uncommitted changes
- [ ] terraform/phase-12/ directory complete
- [ ] kubernetes/phase-12/ directory complete
- [ ] Terraform syntax valid
- [ ] AWS credentials working
- [ ] Terraform plan successful (Infrastructure Lead)

---

## 2. TEAM READINESS (Verify by 07:15 UTC Monday)

**All team members verify**:

```bash
# 1. Verify you have printed/digital MONDAY-START-HERE.md
[ ] File printed or available on screen
[ ] All sections read (especially your role assignment)

# 2. Verify you have shell access to bastion host
ssh bastion hostname
# Expected: Bastion hostname printed

# 3. Verify AWS CLI works
aws --version
# Expected: AWS CLI 2.x.x

# 4. Verify kubectl installed (if K8s role)
kubectl version --client
# Expected: Client version output

# 5. Verify ssh-key for bastion configured
cat ~/.ssh/id_rsa
# Expected: Private key content (if file exists)

# 6. Test Slack connectivity
# Join #phase-12-execution channel and send test message

# 7. Test Zoom/Meet connectivity
# Test audio/video in war room meeting before 08:00
```

**Infrastructure Lead ONLY - Verify Team Assignments**:

```bash
# Confirm all 8-10 team members have:
# 1. Notification channel access (#phase-12-execution)
# 2. PagerDuty on-call setup
# 3. CloudWatch dashboard access (Grafana/AWS)
# 4. Slack integration for alerts

# Send final confirmation email:
# TO: All team members
# SUBJECT: Phase 12 Execution - Final Confirmation
# Content: Role assignments, start time, war room link, RSVP
```

**Sign-Off**:
- [ ] All 8-10 team members confirmed attending
- [ ] All team members have Slack/email notifications working
- [ ] All AWS credentials verified
- [ ] All CLI tools installed (terraform, aws, kubectl)
- [ ] War room Zoom/Meet link tested by all
- [ ] One backup assigned for each role

---

## 3. AWS & INFRASTRUCTURE READINESS (Verify by 07:30 UTC Monday)

**Cloud Admin/Infrastructure Lead**:

```bash
# 1. Verify AWS account quota (must be sufficient for 5 regions)
# Check key quotas:
aws service-quotas list-service-quotas \
  --service-code ec2 \
  --region us-east-1 \
  --query 'Quotas[?QuotaName==`VPCs per Region`]'

# Expected output: Quota >= 5 (we need 1 new VPC per region)

# 2. Verify AWS account has sufficient credit/budget
aws ce get-cost-and-usage \
  --time-period Start=2026-04-13,End=2026-04-14 \
  --granularity DAILY \
  --metrics BlendedCost

# Note: Phase 12 will cost ~$5,000/day × 5 days = $25,000 total

# 3. Verify no VPC limit hits
for region in us-east-1 us-west-2 eu-west-1 ap-southeast-1 ca-central-1; do
  echo "=== $region ==="
  aws ec2 describe-vpcs --region $region --query 'length(Vpcs)'
done

# Expected: 1-3 existing VPCs per region (plenty of room for Phase 12)

# 4. Verify Route 53 hosted zone exists (or will be created)
aws route53 list-hosted-zones-by-name --query 'HostedZones[?Name==`api.code-server.com.`]'

# Expected: Empty (Phase 12 will create it), or existing zone with ID

# 5. Verify S3 bucket for Terraform state (if using remote state)
aws s3 ls s3://investigations-api-terraform-state/ 2>/dev/null
# Expected: Bucket exists and is readable

# 6. Verify DynamoDB lock table exists (if using Terraform locking)
aws dynamodb describe-table \
  --table-name terraform-locks \
  --region us-east-1 2>/dev/null
# Expected: Table exists in ACTIVE state
```

**Sign-Off**:
- [ ] AWS quotas sufficient for 5-region deployment
- [ ] AWS budget verified ($25K+ available)
- [ ] No VPC limit issues in any region
- [ ] Route 53 zone ready or creation plan clear
- [ ] Terraform state backend (S3/remote) accessible
- [ ] DynamoDB lock table ready

---

## 4. MONITORING & OBSERVABILITY READINESS (Verify by 07:30 UTC Monday)

**Observability/Ops Lead**:

```bash
# 1. Verify CloudWatch dashboard exists
aws cloudwatch describe-dashboards \
  --query 'DashboardEntries[?contains(DashboardName, `phase-12`)]'

# Expected: At least 1 Phase 12 dashboard listed

# 2. Verify CloudWatch log groups configured
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/phase-12/"

# Expected: Log groups exist for each component

# 3. Verify SNS topics for alerts
aws sns list-topics --query 'Topics[?contains(TopicArn, `phase-12`)]'

# Expected: Alert topic exists (e.g., investigations-api-alerts)

# 4. Verify Grafana dashboard access
curl -s https://grafana.internal/api/liveness
# Expected: Status 200 (or similar health check)

# 5. Verify alert rules exist
aws cloudwatch describe-alarms \
  --query 'MetricAlarms[?contains(AlarmName, `phase-12`)]'

# Expected: At least 10-20 alarms configured

# 6. Send test alert
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:investigations-api-alerts \
  --subject "Phase 12 Test Alert" \
  --message "This is a test alert - Phase 12 execution starting soon"

# Verify: Everyone on team receives SNS email/Slack notification within 1 minute
```

**Sign-Off**:
- [ ] CloudWatch dashboards accessible by all team members
- [ ] SNS alerts working (test alert received)
- [ ] Grafana login/access verified
- [ ] Log groups configured for Terraform, API, Database
- [ ] Alert rules enabled (not muted)
- [ ] CloudWatch metrics flowing

---

## 5. RUNBOOK & DOCUMENTATION READINESS (Verify by 07:45 UTC Monday)

**All team members**:

```bash
# 1. Verify you have access to Phase 12 documentation
[ ] MONDAY-START-HERE.md ✓
[ ] PHASE-12-EXECUTION-START-GUIDE.md ✓
[ ] PHASE-12-PRE-EXECUTION-CHECKLIST.md ✓
[ ] PHASE-12-QUICK-REFERENCE-CARD.md ✓
[ ] PHASE-12-DETAILED-EXECUTION-PLAN.md ✓
[ ] PHASE-12-DAILY-STATUS-TEMPLATE.md ✓

# 2. Verify you have role-specific runbook
# Infrastructure Lead: TERRAFORM_RUNBOOK.md
# Database Lead: DATABASE_REPLICATION_RUNBOOK.md
# Network Lead: VPC_PEERING_RUNBOOK.md
# Platform Engineer: KUBERNETES_DEPLOYMENT_RUNBOOK.md
# Ops Lead: MONITORING_& ALERTING_RUNBOOK.md

# 3. Verify quick reference card is printed
[ ] Printed and at desk
[ ] Has essential commands
[ ] Has contact information
[ ] Has war room link

# 4. Verify you know your role & responsibilities
[ ] Have read MONDAY-START-HERE.md section for your role
[ ] Know your start time (some roles start later, not all at 08:00)
[ ] Know your success criteria for the day
[ ] Know who to escalate to if something goes wrong
```

**Infrastructure Lead - Verify Documentation**:

```bash
# 1. Print out complete runbook set
# Should include: All 14 PHASE-12*.md documents
# Total: 500+ pages (recommend printing in office before Monday)

# 2. Distribute to team
# Method: Printed copies + digital PDF + Slack pinned
# Deadline: Monday 07:30 UTC (before war room opens)

# 3. Verify no documentation gaps
# Check that we have explicit procedures for:
# [ ] VPC Creation steps
# [ ] VPC Peering connection steps  
# [ ] Route 53 zone creation steps
# [ ] Database replication setup steps
# [ ] Load balancer configuration steps
# [ ] Kubernetes manifest deployment steps
# [ ] Monitoring dashboard setup steps
# [ ] Failover testing steps
# [ ] Rollback procedures (all 5 phases)
```

**Sign-Off**:
- [ ] All documentation printed/available
- [ ] All team members have role-specific runbooks
- [ ] Quick reference cards distributed
- [ ] No documentation gaps identified
- [ ] Everyone has read their role section

---

## 6. EXECUTION SCRIPT READINESS (Verify by 07:30 UTC Monday)

**Infrastructure Lead**:

```bash
cd terraform/phase-12

# 1. Verify execution scripts are executable
chmod +x phase-12-execute.sh
ls -la phase-12-execute.sh
# Expected: -rwxr-xr-x (executable)

# 2. Test script with 'validate' command (dry-run, no changes)
./phase-12-execute.sh validate
# Expected: All checks pass, no errors, shows resources detected

# 3. Verify script generates execution log
# Expected: Script creates logs/phase-12-YYYY-MM-DD.log file

# 4. Verify script has error handling
# Test: Pass bad AWS region to script, verify it errors gracefully
# Expected: Error message, exit code 1 (non-zero)

# 5. Inspect actual commands that will be run
# View: ./phase-12-execute.sh (read first 100 lines)
# Confirm: Commands match terraform plan output

# 6. Establish rollback readiness
# Ensure: phase-12-execute.sh destroy command works
./phase-12-execute.sh --help
# Expected: Shows options including 'destroy'

# 7. Brief team on script usage (Monday 08:15)
# Show: terraform/phase-12/phase-12-execute.sh --help
# Explain: Each option and expected output
# Demo: Walk through one manual terraform plan (not apply)
```

**Sign-Off**:
- [ ] Execution scripts present and executable
- [ ] Validate command runs successfully
- [ ] Error handling verified
- [ ] Destroy/rollback tested
- [ ] Logging working
- [ ] Script help text reviewed with team

---

## 7. FINAL GO/NO-GO VERIFICATION (Monday 08:00-08:15 UTC War Room)

**Before pressing 'apply', verify all of the following**:

### Infrastructure Check
- [ ] All 5 regions accessible from bastion host
- [ ] AWS CLI shows no errors for quota queries
- [ ] terraform plan output shows exactly 5 VPC resources
- [ ] terraform plan output shows exactly 10 peering connections
- [ ] No destructive changes in terraform plan (no deletes)

### Team Check
- [ ] All 8-10 team members present in war room (Zoom + Slack)
- [ ] All team members have roles assigned
- [ ] All team members have quick reference card visible
- [ ] No critical team members unavailable
- [ ] On-call rotation confirmed (who's primary, who's backup)

### Documentation Check
- [ ] Runbooks printed and distributed
- [ ] Daily status template ready for filling in
- [ ] Communication plan confirmed (Slack, PagerDuty, email)
- [ ] Escalation contacts listed and accessible
- [ ] Success criteria clearly understood by all

### Monitoring Check
- [ ] CloudWatch dashboard displayed on screen
- [ ] SNS alerts tested and working
- [ ] Grafana accessible from team laptops
- [ ] Log aggregation working (ELK/CloudWatch Logs)
- [ ] Alert rules enabled (not in maintenance mode)

### Code Check
- [ ] Phase 9, 10, 11 all merged to main (verified via `git log`)
- [ ] No uncommitted changes in workspace
- [ ] terraform/phase-12/ all files present
- [ ] kubernetes/phase-12/ all files present
- [ ] .git/config points to correct remote

### Budget & Risk Check
- [ ] AWS budget verified ($25K available)
- [ ] Risk mitigation table reviewed
- [ ] Rollback procedures understood by all
- [ ] Incident response escalation chain clear
- [ ] Emergency contact information posted in war room

### Final Sign-Off

```
=== MONDAY APRIL 15, 08:30 UTC ===
GO/NO-GO DECISION POINT

[ ] Infrastructure Lead: GO / NO-GO _______
[ ] Project Manager: GO / NO-GO _______
[ ] CTO / Tech Lead: GO / NO-GO _______

If ALL three are GO:
  → Execute: terraform apply phase12.tfplan
  → Monitor: CloudWatch dashboard + Slack updates
  
If ANY are NO-GO:
  → STOP: Do not proceed with terraform apply
  → Investigate: Address blocking issue immediately
  → Reschedule: Determine new execution time
  → Communicate: Notify stakeholders of delay
```

---

## CONTINGENCIES (If Issues Arise Before War Room)

### Issue: Phase 9 PR Not Merged to Main
- **Impact**: BLOCKING - Cannot execute Phase 12
- **Action**: 
  1. Contact PR reviewer immediately (by 06:00 UTC Monday)
  2. If blocked by review: CTO executes emergency override (requires 2 approvals)
  3. If CI failed: Tech lead investigates and fixes (document in ticket)
  4. **Worst case**: Delay execution to Tuesday, notify stakeholders

### Issue: AWS Quota Error or Limit Hit
- **Impact**: BLOCKING - Cannot create resources
- **Action**:
  1. Check which quota is hit: `aws service-quotas describe-service-quotas ...`
  2. Request quota increase: Use AWS service quota dashboard
  3. If quota unavailable immediately: Contact AWS TAM
  4. **Worst case**: Use fewer regions (deploy 3 instead of 5), validate feasibility with team

### Issue: Team Member Critically Unavailable Monday
- **Impact**: Medium (depends on role)
- **Action**:
  1. If Infrastructure Lead: CTO or Tech Lead steps in
  2. If Database Lead: Senior DB engineer from backup pool
  3. For other roles: Cross-trained backup takes over
  4. Communicate role change to team (send email + Slack announcement)

### Issue: Terraform Validation Fails Sunday Night
- **Impact**: BLOCKING - Cannot execute
- **Action**:
  1. Infrastructure Lead investigates immediately (Sunday PM)
  2. Check for: Syntax errors, provider issues, state lock
  3. Fix and commit to fix branch: `feature/phase-12-fix`
  4. Create quick PR + merge with emergency approval
  5. Re-run validate Monday 07:00 UTC
  6. **Worst case**: Delay to Tuesday

### Issue: AWS Credentials Expire or Invalid Monday Morning
- **Impact**: BLOCKING - No AWS access
- **Action**:
  1. Verify credentials: `aws sts get-caller-identity`
  2. If expired: Refresh AWS credentials (STS token refresh)
  3. If permissions wrong: Cloud admin grants required IAM role
  4. **Worst case**: Use pre-generated temporary credentials from vault

---

## SIGN-OFF CHECKLIST (Final)

**All team members** - Check the box for each item:

```
MONDAY APRIL 15, 2026 - PHASE 12 EXECUTION READINESS

Pre-Execution Verification (Complete by 07:45 UTC):

CODE & GIT:
[ ] Phase 9, 10, 11 on main branch
[ ] No uncommitted changes
[ ] terraform/phase-12/ files all present
[ ] kubernetes/phase-12/ files all present
[ ] terraform validate passes

TEAM:
[ ] All 8-10 team members attending
[ ] All roles assigned and confirmed
[ ] All team members in war room (Zoom + Slack)
[ ] Backup assignments confirmed

INFRASTRUCTURE:
[ ] AWS credentials working
[ ] AWS quotas sufficient
[ ] AWS budget verified ($25K+)
[ ] No regional issues or outages

MONITORING:
[ ] CloudWatch dashboards accessible
[ ] SNS alerts tested and working
[ ] Grafana login verified
[ ] Log aggregation operational

DOCUMENTATION:
[ ] Runbooks printed and available
[ ] Quick reference cards distributed
[ ] Role assignments understood
[ ] Communication plan confirmed

EXECUTION READINESS:
[ ] terraform plan output reviewed
[ ] All 5 VPCs shown in plan
[ ] All 10 peering connections shown
[ ] No unexpected deletions in plan
[ ] Rollback plan reviewed (everyone)

FINAL GO/NO-GO:
[ ] Infrastructure Lead: GO / NO-GO
[ ] Project Manager: GO / NO-GO
[ ] CTO / Tech Lead: GO / NO-GO

If ALL three marked GO -> Proceed to terraform apply
```

---

## FINAL REMINDERS

1. **NO CHANGES TO CODE** between Sunday EOD and Friday EOD
   - All code freeze during Phase 12 execution
   - Any critical fix: Emergency PRs only, requires 3 approvals

2. **REAL-TIME COMMUNICATION MANDATORY**
   - Check Slack #phase-12-execution every 10 minutes
   - Respond to status requests within 5 minutes
   - Report blockers immediately (within 2 minutes)

3. **DAILY STANDUPS AT 08:00 UTC**
   - 15 minutes, leads only
   - Fill in PHASE-12-DAILY-STATUS-TEMPLATE.md
   - Report on three things: Completed, In Progress, Blockers

4. **COST TRACKING**
   - Daily cost report: Monday-Friday 17:00 UTC
   - Alert threshold: > $7,500/day
   - If exceeded: Immediate CTO notification + cost reduction actions

5. **SAFETY FIRST**
   - Data loss is NEVER acceptable (even test data)
   - Failover testing must be scheduled 24 hours in advance
   - No production traffic reroute without lead approval
   - When in doubt: Ask first, implement second

---

**Document Version**: 1.0  
**Created**: April 13, 2026, 18:00 UTC  
**Valid Until**: April 15, 08:45 UTC (then superseded by Phase 12.1 Execution Log)  
**Next Update**: Monday 18:00 UTC (Phase 12.1 debrief)

**Print this document. Check every item. Sign your name. Keep at desk. Execute flawlessly.**
