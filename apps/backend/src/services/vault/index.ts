import axios from 'axios';
import { getAuditService } from '../audit/audit-service.js';

/**
 * Service for managing ephemeral credentials via HashiCorp Vault.
 * Provides dynamic DB credentials and session-scoped secrets.
 */
export class VaultCredentialService {
  private readonly vaultAddr: string;
  private readonly vaultToken: string;
  private readonly audit = getAuditService();

  constructor(options: { vaultAddr?: string; vaultToken?: string } = {}) {
    this.vaultAddr = options.vaultAddr || process.env.VAULT_ADDR || 'http://localhost:8200';
    this.vaultToken = options.vaultToken || process.env.VAULT_TOKEN || 'dev-root-token-change-me';
  }

  /**
   * Generates dynamic PostgreSQL credentials with a specified TTL.
   */
  async getDatabaseCredentials(role: string = 'collab-app'): Promise<{ username: string; password: string; lease_id: string }> {
    try {
      const response = await axios.get(`${this.vaultAddr}/v1/database/creds/${role}`, {
        headers: { 'X-Vault-Token': this.vaultToken }
      });

      const { username, password } = response.data.data;
      const { lease_id } = response.data;

      await this.audit.emit({
        action: 'READ',
        resource: `vault/database/creds/${role}`,
        status: 'success',
        metadata: { username, lease_id }
      });

      return { username, password, lease_id };
    } catch (error) {
      await this.audit.emit({
        action: 'READ',
        resource: `vault/database/creds/${role}`,
        status: 'failure',
        metadata: { error: error instanceof Error ? error.message : String(error) }
      });
      throw error;
    }
  }

  /**
   * Revokes a lease (e.g., when a session ends).
   */
  async revokeLease(leaseId: string): Promise<void> {
    try {
      await axios.put(`${this.vaultAddr}/v1/sys/leases/revoke`, {
        lease_id: leaseId
      }, {
        headers: { 'X-Vault-Token': this.vaultToken }
      });

      await this.audit.emit({
        action: 'DELETE',
        resource: `vault/lease/${leaseId}`,
        status: 'success'
      });
    } catch (error) {
      console.error(`Failed to revoke lease ${leaseId}:`, error);
    }
  }
}

let instance: VaultCredentialService | null = null;

export function getVaultService(): VaultCredentialService {
  if (!instance) {
    instance = new VaultCredentialService();
  }
  return instance;
}
