import { describe, it, expect, vi, beforeEach } from 'vitest';
import axios from 'axios';
import { VaultCredentialService } from '../index.js';
import * as auditService from '../../audit/audit-service.js';

vi.mock('axios');
vi.mock('../../audit/audit-service.js');

describe('VaultCredentialService', () => {
  let vaultService: VaultCredentialService;
  const mockAudit = { emit: vi.fn().mockResolvedValue({}) };

  beforeEach(() => {
    vi.spyOn(auditService, 'getAuditService').mockReturnValue(mockAudit as any);
    vaultService = new VaultCredentialService({
      vaultAddr: 'http://test-vault:8200',
      vaultToken: 'test-token'
    });
    vi.clearAllMocks();
  });

  it('fetches database credentials and emits an audit log', async () => {
    const mockResponse = {
      data: {
        data: {
          username: 'v-user-1234',
          password: 'secret-password'
        },
        lease_id: 'database/creds/collab-app/5678'
      }
    };
    (axios.get as any).mockResolvedValue(mockResponse);

    const creds = await vaultService.getDatabaseCredentials('collab-app');

    expect(creds.username).toBe('v-user-1234');
    expect(creds.password).toBe('secret-password');
    expect(creds.lease_id).toBe('database/creds/collab-app/5678');
    
    expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
      action: 'READ',
      resource: 'vault/database/creds/collab-app',
      status: 'success'
    }));
  });

  it('revokes a lease and emits an audit log', async () => {
    (axios.put as any).mockResolvedValue({ status: 204 });

    await vaultService.revokeLease('test-lease-id');

    expect(axios.put).toHaveBeenCalledWith(
      'http://test-vault:8200/v1/sys/leases/revoke',
      { lease_id: 'test-lease-id' },
      { headers: { 'X-Vault-Token': 'test-token' } }
    );

    expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
      action: 'DELETE',
      resource: 'vault/lease/test-lease-id',
      status: 'success'
    }));
  });
});
