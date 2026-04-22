# Access Control Policy

**Document ID:** ACP-001  
**Version:** 1.0  
**Effective Date:** April 22, 2026  
**Classification:** Internal - Confidential

## 1. Purpose

Define procedures for provisioning, managing, and revoking user access to KC systems.

## 2. User Provisioning

### 2.1 Onboarding Process
1. **Request:** New hire / contractor requests system access via HR ticketing
2. **Approval:** Security owner approves based on role requirements
3. **Configuration:**
   - Create OIDC/GitHub account (for IDE access)
   - Add to appropriate RBAC role (admin/editor/viewer)
   - Enable MFA (Time-based One-Time Password)
   - Provide SSH key setup instructions
4. **Verification:** User confirms access works, MFA enabled
5. **Documentation:** Access logged in audit_access_log table

### 2.2 MFA Requirements
- **Mandatory for all accounts** (TOTP app: Google Authenticator, Authy, etc.)
- **Exception:** Service accounts use OIDC or asymmetric keys (no passwords)
- **Backup codes:** Provided and stored securely by user
- **Enforcement:** MFA checked at login, required for all SSH access

### 2.3 Initial Password Reset
- **Temporary password:** Generated, 24-hour validity
- **User action:** Must reset on first login
- **Minimum requirement:** 16 characters, mix of case/numbers/symbols
- **Storage:** Hashed in IdP database, never stored in plain text

## 3. SSH Key Management

### 3.1 Key Generation
- **User action:** User generates RSA 4096-bit key locally
- **Command:** `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa`
- **Private key:** Kept secure locally, never shared
- **Public key:** Submitted to system admin for approval

### 3.2 Key Registration
- **Admin approval:** Verify key ownership before adding
- **Registration:** Add public key to ~/.ssh/authorized_keys on target servers
- **Audit logging:** SSH key addition logged with timestamp and approver
- **Expiration:** Keys rotated annually or when employee leaves

### 3.3 Key Compromise
- **Immediate action:** Remove key from authorized_keys
- **Notification:** Contact user and security team
- **RCA:** Investigate how key was compromised
- **New key:** User generates replacement, repeats registration

## 4. VPN Access (if applicable)

### 4.1 VPN Provisioning
- Requires additional security approval for remote access
- VPN credentials issued separately from IDE access
- MFA required for VPN login

### 4.2 VPN Policy
- Split tunnel disabled (all traffic through VPN)
- Session timeout: 8 hours
- Audit logging of all VPN connections

## 5. Privileged Access Management (PAM)

### 5.1 Escalation Process
- Regular users: viewer role (read-only access to IDE)
- Developers: editor role (can modify code)
- Admins: admin role (full system access)
- Service accounts: system role (service-to-service only)

### 5.2 Admin Access
- **Usage:** Only when necessary for system maintenance
- **Approval:** Security owner authorization required
- **Duration:** Time-bounded (usually < 1 hour per session)
- **Audit:** All admin actions logged with username and timestamp
- **Approval record:** GitHub issue or ticket linked in audit log

### 5.3 Just-In-Time (JIT) Access
- Future enhancement: Temporary admin access via GSM ephemeral credentials
- Goal: Eliminate standing admin privileges
- Implementation: TBD in Q3 2026

## 6. Access Reviews

### 6.1 Quarterly Review Process
1. Security owner extracts current user list from RBAC
2. For each user:
   - [ ] Verify user still employed / active
   - [ ] Verify role matches current responsibilities
   - [ ] Verify no unauthorized permission escalation
3. Remove access for departed users
4. Update roles for changed responsibilities
5. Document review results in GitHub issue #1070

### 6.2 Approval Authority
- **Role changes:** Security owner + department head approval
- **New access:** Security owner approval
- **Revocation:** Security owner + HR notification

## 7. Deprovisioning

### 7.1 Offboarding Process
1. **Notification:** HR notifies security upon employee departure
2. **Access revocation timeline:**
   - Same day: Revoke IDE, SSH, VPN access
   - Same day: Delete OIDC account
   - Same day: Remove from all RBAC roles
3. **Credential cleanup:**
   - Invalidate MFA device
   - Remove SSH keys
   - Revoke any issued tokens
4. **Equipment:** Ensure all devices returned (keys, VPN tokens)
5. **Audit logging:** Deprovisioning logged with timestamp and reason

### 7.2 Contractor Deprovisioning
- Same process as employees
- Verify contract end date from HR
- Immediate revocation upon end date

## 8. Password Policy

### 8.1 Requirements
- Minimum length: 16 characters
- Character mix: Uppercase + lowercase + numbers + symbols
- No dictionary words or common patterns
- No reuse of previous 5 passwords

### 8.2 Password Reset
- Self-service via IdP password reset page
- Manual reset (admin) for forgotten passwords
- Reset link valid for 24 hours
- New password must be different from old

### 8.3 Service Account Secrets
- Never stored as plaintext passwords
- OAuth2 secrets: Issued by OAuth provider, stored in GSM
- Database passwords: Generated, stored in GSM
- Asymmetric keys: OIDC service accounts use public key auth

## 9. Role-Based Access Control (RBAC)

### 9.1 Roles and Permissions

| Role | IDE | Code | Workspace | Admin | Service |
|------|-----|------|-----------|-------|---------|
| viewer | ✅ Read | ✅ View | ✅ Access | ❌ No | ❌ No |
| editor | ✅ Read | ✅ RW | ✅ Manage | ❌ No | ❌ No |
| admin | ✅ RW | ✅ RW | ✅ Full | ✅ Yes | ❌ No |
| system | ❌ No | ❌ No | ❌ No | ❌ No | ✅ Yes |

### 9.2 Role Assignment Rules
- Default role for new users: viewer
- Escalation only upon explicit request + approval
- Principle of least privilege always applied
- Review quarterly for necessity

## 10. Appendix: Access Control Checklist

### Monthly
- [ ] New user access provisions complete (< 24 hours)
- [ ] Departed users removed within 1 day
- [ ] Unused SSH keys rotated

### Quarterly
- [ ] Access review completed (all users verified)
- [ ] Role appropriateness validated
- [ ] Unauthorized access attempts < 10 per month
- [ ] MFA compliance 100%

---

**Document Owner:** Security Team  
**Related Issues:** #1070, #388 (IAM Phase 3)  
**Next Review:** July 22, 2026
