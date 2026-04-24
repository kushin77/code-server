// @file        apps/backend/src/services/auth/__tests__/role-mapper.test.ts
// @module      auth/role-mapping
// @description Unit tests for RoleMapper service
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { RoleMapper } from '../role-mapper';
describe('RoleMapper', () => {
    let mapper;
    let mockAuditService;
    beforeEach(() => {
        mockAuditService = {
            emit: vi.fn(),
        };
        mapper = new RoleMapper(mockAuditService);
    });
    describe('mapClaimsToRoles', () => {
        it('should assign user role to everyone', () => {
            const claims = {
                sub: 'user-123',
                email: 'user@example.com',
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('user');
        });
        it('should add admin role when admin flag is true', () => {
            const claims = {
                sub: 'admin-123',
                email: 'admin@example.com',
                admin: true,
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('admin');
            expect(roles).toContain('user');
        });
        it('should map Google groups to roles', () => {
            const claims = {
                sub: 'dev-123',
                email: 'dev@example.com',
                groups: ['developers@company.com'],
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('developer');
            expect(roles).toContain('user');
        });
        it('should handle multiple groups', () => {
            const claims = {
                sub: 'multi-123',
                email: 'user@example.com',
                groups: ['developers@company.com', 'support@company.com'],
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('developer');
            expect(roles).toContain('support');
            expect(roles).toContain('user');
        });
        it('should detect service accounts by email pattern', () => {
            const claims = {
                sub: 'svc-admin-123',
                email: 'service-admin.svc.internal@company.com',
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('service-admin');
        });
        it('should detect backend service accounts', () => {
            const claims = {
                sub: 'svc-backend-123',
                email: 'backend.svc.internal@company.com',
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('backend-service');
        });
        it('should detect session service accounts', () => {
            const claims = {
                sub: 'svc-session-123',
                email: 'session.svc.internal@company.com',
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('session-service');
        });
        it('should ignore invalid groups', () => {
            const claims = {
                sub: 'user-123',
                email: 'user@example.com',
                groups: ['invalid-group@company.com', 'developers@company.com'],
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('developer');
            expect(roles).not.toContain('invalid-group');
        });
        it('should combine multiple role sources', () => {
            const claims = {
                sub: 'multi-123',
                email: 'service-admin.svc.internal@company.com',
                admin: true,
                groups: ['developers@company.com'],
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('admin');
            expect(roles).toContain('service-admin');
            expect(roles).toContain('developer');
            expect(roles).toContain('user');
        });
    });
    describe('registerGroupMapping', () => {
        it('should register custom group mappings', () => {
            mapper.registerGroupMapping('custom-group@company.com', [
                'custom-role',
            ]);
            const claims = {
                sub: 'user-123',
                email: 'user@example.com',
                groups: ['custom-group@company.com'],
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('custom-role');
        });
        it('should support multiple roles per group', () => {
            mapper.registerGroupMapping('management@company.com', [
                'manager',
                'developer',
            ]);
            const claims = {
                sub: 'user-123',
                email: 'user@example.com',
                groups: ['management@company.com'],
            };
            const roles = mapper.mapClaimsToRoles(claims);
            expect(roles).toContain('manager');
            expect(roles).toContain('developer');
        });
    });
    describe('getGroupMappings', () => {
        it('should return all registered mappings', () => {
            mapper.registerGroupMapping('test@company.com', ['test-role']);
            const mappings = mapper.getGroupMappings();
            expect(mappings['admin@company.com']).toEqual(['admin']);
            expect(mappings['developers@company.com']).toEqual(['developer']);
            expect(mappings['test@company.com']).toEqual(['test-role']);
        });
        it('should return empty object if no custom mappings', () => {
            const mapper2 = new RoleMapper();
            const mappings = mapper2.getGroupMappings();
            expect(mappings).toHaveProperty('admin@company.com');
            expect(mappings).toHaveProperty('developers@company.com');
        });
    });
    describe('Audit Logging', () => {
        it('should emit audit event when mapping claims', () => {
            const mockAudit = { emit: vi.fn() };
            const testMapper = new RoleMapper(mockAudit);
            const claims = {
                sub: 'user-123',
                email: 'user@example.com',
                groups: ['developers@company.com'],
                admin: false,
            };
            testMapper.mapClaimsToRoles(claims);
            expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
                userId: 'user@example.com',
                action: 'read',
                resourceType: 'oauth-claims',
                resource: 'oauth:user-123',
                metadata: expect.objectContaining({
                    email: 'user@example.com',
                    mappedRoles: expect.arrayContaining(['user', 'developer']),
                }),
            }));
        });
        it('should emit audit event when registering group mapping', () => {
            const mockAudit = { emit: vi.fn() };
            const testMapper = new RoleMapper(mockAudit);
            testMapper.registerGroupMapping('analytics@company.com', ['analyst']);
            expect(mockAudit.emit).toHaveBeenCalledWith(expect.objectContaining({
                userId: 'system',
                action: 'update',
                resourceType: 'role-mapping-config',
                resource: 'role-mapping:analytics@company.com',
                metadata: expect.objectContaining({
                    group: 'analytics@company.com',
                    roles: ['analyst'],
                }),
            }));
        });
        it('should work without audit service', () => {
            const mapperNoAudit = new RoleMapper();
            const claims = {
                sub: 'user-123',
                email: 'user@example.com',
            };
            const roles = mapperNoAudit.mapClaimsToRoles(claims);
            expect(roles).toContain('user');
        });
    });
});
//# sourceMappingURL=role-mapper.test.js.map