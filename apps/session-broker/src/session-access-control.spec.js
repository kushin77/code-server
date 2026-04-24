import { describe, expect, it } from 'vitest';
import { authorizeBreakGlassTermination, authorizeSessionApproval, authorizeSessionLaunch, authorizeSessionTermination, evaluateSessionPublication, buildSessionBrokerPrincipal, } from './session-access-control.js';
describe('session access control helpers', () => {
    const requester = buildSessionBrokerPrincipal({
        userId: 'user-1',
        username: 'alice',
        email: 'alice@example.com',
        groups: ['developers'],
    });
    const operator = buildSessionBrokerPrincipal({
        userId: 'user-2',
        username: 'ops',
        email: 'ops@example.com',
        groups: ['operator'],
    });
    const auditor = buildSessionBrokerPrincipal({
        userId: 'user-3',
        username: 'audit',
        email: 'audit@example.com',
        groups: ['auditor'],
    });
    it('allows self launch and blocks launches for other users without elevated roles', () => {
        expect(authorizeSessionLaunch(requester, 'user-1').allowed).toBe(true);
        expect(authorizeSessionLaunch(requester, 'user-9').allowed).toBe(false);
        expect(authorizeSessionLaunch(operator, 'user-9').allowed).toBe(true);
    });
    it('requires an elevated role for approval', () => {
        expect(authorizeSessionApproval(requester).allowed).toBe(false);
        expect(authorizeSessionApproval(operator).allowed).toBe(true);
    });
    it('treats approval pending sessions as unpublished', () => {
        expect(evaluateSessionPublication('testing', true).allowed).toBe(false);
        expect(evaluateSessionPublication('ready', true).allowed).toBe(true);
    });
    it('requires a break-glass reason code and elevated role', () => {
        expect(authorizeBreakGlassTermination(requester, 'user-9', 'urgent').allowed).toBe(false);
        expect(authorizeBreakGlassTermination(operator, 'user-9', '').allowed).toBe(false);
        expect(authorizeBreakGlassTermination(operator, 'user-9', 'urgent').allowed).toBe(true);
    });
    it('allows owners and elevated principals to terminate sessions', () => {
        expect(authorizeSessionTermination(requester, 'user-1').allowed).toBe(true);
        expect(authorizeSessionTermination(auditor, 'user-1').allowed).toBe(false);
        expect(authorizeSessionTermination(operator, 'user-1').allowed).toBe(true);
    });
});
//# sourceMappingURL=session-access-control.spec.js.map