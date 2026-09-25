import { PlatformCommercialService } from './platform-commercial.service';
import * as argon2 from 'argon2';

describe('Admin password length', () => {
  const actor = { platformUserId: 'admin', role: 'SUPER_ADMIN' } as const;
  const body = { email: 'new@test.invalid', displayName: 'Test admin', role: 'SUPER_ADMIN' };
  function fixture() {
    const create = jest.fn().mockImplementation(async ({ data }) => ({ id: 'new-admin', ...data }));
    const tx = { platformUser: { create }, platformAuditEvent: { create: jest.fn() } };
    const db = { $transaction: jest.fn().mockImplementation(fn => fn(tx)) };
    return { service: new PlatformCommercialService(db as any, {} as any), db, create };
  }
  it.each(['eight123', 'a longer existing password'])('accepts and hashes %s', async password => {
    const { service, create } = fixture();
    await service.createUser(actor, { ...body, password });
    const hash = create.mock.calls[0][0].data.passwordHash;
    expect(await argon2.verify(hash, password)).toBe(true);
  });
  it('rejects seven characters before creating an account', async () => {
    const { service, db } = fixture();
    await expect(service.createUser(actor, { ...body, password: 'short12' })).rejects.toThrow();
    expect(db.$transaction).not.toHaveBeenCalled();
  });
});
