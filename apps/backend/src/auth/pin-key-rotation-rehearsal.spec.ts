import { StaffPinVault } from './staff-pin-vault.service';
import { CryptoService } from '../website/common/crypto.service';
import { PrismaService } from '../prisma.service';
import { rehearsePinRekey } from '../../test/pin-key-rotation-rehearsal';

const oldKey = 'synthetic-old-cookie-vault-key-only-for-tests';
const newKey = 'synthetic-new-cookie-vault-key-only-for-tests';

describe('PIN rekey/recovery design with synthetic rows only', () => {
  const prior = process.env.COOKIE_ENCRYPTION_KEY;
  afterEach(() => {
    if (prior === undefined) delete process.env.COOKIE_ENCRYPTION_KEY;
    else process.env.COOKIE_ENCRYPTION_KEY = prior;
  });
  function fixture(key: string, rows = new Map<string, string>()) {
    process.env.COOKIE_ENCRYPTION_KEY = key;
    type Where = { venueId_key: { venueId: string; key: string } };
    const db = {
      setting: {
        findUnique: ({ where }: { where: Where }) =>
          Promise.resolve(
            rows.has(where.venueId_key.venueId)
              ? { value: rows.get(where.venueId_key.venueId) }
              : null,
          ),
        upsert: ({
          where,
          update,
        }: {
          where: Where;
          update: { value: string };
        }) => {
          rows.set(where.venueId_key.venueId, update.value);
          return Promise.resolve(null);
        },
      },
    };
    return { rows, vault: new StaffPinVault(db as unknown as PrismaService) };
  }
  async function seeded() {
    const f = fixture(oldKey);
    await f.vault.write({ alice: '1234' }, { venueId: 'synthetic-a' });
    await f.vault.write({ bob: '5678' }, { venueId: 'synthetic-b' });
    return f;
  }
  const inventory = (rows: Map<string, string>) =>
    [...rows].map(([venueId, ciphertext]) => ({ venueId, ciphertext }));
  it('round-trips actual vault format, preserves each Venue, and recovers pre-cutover ciphertext', async () => {
    const { rows } = await seeded();
    const backup = new Map(rows); // Synthetic memory-only backup, never a production export.
    const plan = rehearsePinRekey(inventory(rows), oldKey, newKey);
    expect(rows).toEqual(backup); // Planning does not mutate its input.
    for (const item of plan) rows.set(item.venueId, item.replacement);
    const rotated = fixture(newKey, rows).vault;
    await expect(rotated.read({ venueId: 'synthetic-a' })).resolves.toEqual({
      alice: '1234',
    });
    await expect(rotated.read({ venueId: 'synthetic-b' })).resolves.toEqual({
      bob: '5678',
    });
    const recovered = fixture(oldKey, backup).vault;
    await expect(recovered.read({ venueId: 'synthetic-a' })).resolves.toEqual({
      alice: '1234',
    });
    expect(plan.every((p) => p.ciphertext !== p.replacement)).toBe(true);
  });
  it('rejects wrong keys and corrupt/legacy rows before returning any replacement plan', async () => {
    const { rows } = await seeded();
    const original = new Map(rows);
    expect(() => rehearsePinRekey(inventory(rows), newKey, oldKey)).toThrow(
      'validation failed',
    );
    for (const invalid of [
      '{}',
      'v1:bad',
      'v1:' + '0'.repeat(24) + ':' + '0'.repeat(32) + ':00',
    ]) {
      expect(() =>
        rehearsePinRekey(
          [...inventory(rows), { venueId: 'synthetic-c', ciphertext: invalid }],
          oldKey,
          newKey,
        ),
      ).toThrow();
    }
    expect(rows).toEqual(original);
  });
  it('refuses duplicate row ownership and identical keys', async () => {
    const { rows } = await seeded();
    const list = inventory(rows);
    expect(() => rehearsePinRekey([...list, list[0]], oldKey, newKey)).toThrow(
      'duplicate',
    );
    expect(() => rehearsePinRekey(list, oldKey, oldKey)).toThrow('distinct');
  });
  it('requires compare-and-swap of the complete plan before committing a concurrent change', async () => {
    const { rows, vault } = await seeded();
    const plan = rehearsePinRekey(inventory(rows), oldKey, newKey);
    await vault.write({ alice: '9999' }, { venueId: 'synthetic-a' });
    const before = new Map(rows);
    const canCommit = plan.every((p) => rows.get(p.venueId) === p.ciphertext);
    expect(canCommit).toBe(false);
    expect(rows).toEqual(before);
    // This models an abort; a real DB transaction/lock is a separate release gate.
  });
  it('shows cookies require fresh login after rotation, while retained PIN rows need migration', () => {
    process.env.COOKIE_ENCRYPTION_KEY = oldKey;
    const oldCookies = new CryptoService();
    const cookie = oldCookies.encrypt('synthetic-session-token');
    process.env.COOKIE_ENCRYPTION_KEY = newKey;
    const newCookies = new CryptoService();
    expect(() => newCookies.decrypt(cookie)).toThrow('Failed to decrypt token');
    expect(oldCookies.decrypt(cookie)).toBe('synthetic-session-token');
  });
});
