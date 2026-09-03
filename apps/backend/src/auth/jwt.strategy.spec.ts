import { UnauthorizedException } from '@nestjs/common';
import type { ManagerAuthContext } from './manager-auth-context';
import { JwtStrategy } from './jwt.strategy';
import { ManagerTenantService } from './manager-tenant.service';

const RESOLVED: ManagerAuthContext = {
  staffId: 'staff-1',
  username: 'real-manager',
  role: 'MANAGER',
  venueId: 'venue-a',
  organizationId: 'org-1',
};

function makeStrategy(resolved: ManagerAuthContext | null) {
  const resolveByStaffId = jest.fn(() => Promise.resolve(resolved));
  const managerTenant = {
    resolveByStaffId,
  } as unknown as ManagerTenantService;
  return { strategy: new JwtStrategy(managerTenant), resolveByStaffId };
}

describe('JwtStrategy', () => {
  const originalSecret = process.env.JWT_SECRET;
  beforeAll(() => {
    process.env.JWT_SECRET = 'test-secret';
  });
  afterAll(() => {
    process.env.JWT_SECRET = originalSecret;
  });

  it('puts the server-resolved tenant on the request', async () => {
    const { strategy } = makeStrategy(RESOLVED);

    await expect(
      strategy.validate({
        sub: 'staff-1',
        username: 'real-manager',
        role: 'MANAGER',
      }),
    ).resolves.toEqual({ userId: 'staff-1', ...RESOLVED });
  });

  it('ignores the username and role carried in the token', async () => {
    const { strategy, resolveByStaffId } = makeStrategy(RESOLVED);

    // A token minted before a rename and a demotion. Only `sub` is used.
    const user = await strategy.validate({
      sub: 'staff-1',
      username: 'stale-name',
      role: 'ADMIN',
    });

    expect(user.username).toBe('real-manager');
    expect(user.role).toBe('MANAGER');
    expect(resolveByStaffId).toHaveBeenCalledWith('staff-1');
  });

  it('rejects a token whose staff member no longer resolves', async () => {
    const { strategy } = makeStrategy(null);

    await expect(
      strategy.validate({ sub: 'staff-1', username: 'gone', role: 'MANAGER' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
