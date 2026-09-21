jest.mock('bcrypt', () => ({
  hash: jest.fn((value: string) => Promise.resolve(`hashed:${value}`)),
  compare: jest.fn((value: string, hash: string) =>
    Promise.resolve(hash === `hashed:${value}`),
  ),
}));

import * as bcrypt from 'bcrypt';
import { StaffSyncService } from './staff-sync.service';
import { StaffPinVault } from '../../../auth/staff-pin-vault.service';
import { PrismaService } from '../../../prisma.service';
import { StaffSync } from '../sync-payload';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * What a POS snapshot costs the staff credential store.
 *
 * The behaviour these replace re-derived a bcrypt cost-12 hash for every staff
 * member on every snapshot — about 2.7 seconds for fourteen members — because
 * the POS sent every PIN and the server had no way to tell an unchanged
 * credential from a new one. The properties that have to hold instead are
 * stated directly: a routine snapshot hashes nothing and changes no
 * credential, and everything that genuinely sets a PIN still does.
 *
 * bcrypt is replaced with a visible `hashed:<pin>` so the tests can say what
 * was derived and how often, rather than waiting seconds to observe it.
 */
const hashMock = bcrypt.hash as unknown as jest.Mock;

const TENANT: TenantContext = {
  venueId: 'venue-a',
  organizationId: 'organization-a',
};

interface StaffRow {
  venueId: string;
  username: string;
  pinHash: string;
  role: string;
  isActive: boolean;
}

/** The compound key the service addresses a member by. */
interface StaffIdentity {
  venueId_username: { venueId: string; username: string };
}

/** An in-memory `staff` table, so a credential can be read back after a sync. */
class FakeStaffDb {
  async $transaction<T>(fn: (db: this) => Promise<T>) {
    return fn(this);
  }
  async $queryRaw() {
    return [];
  }
  readonly rows: StaffRow[] = [];

  private rowFor(where: StaffIdentity): StaffRow | undefined {
    const { venueId, username } = where.venueId_username;
    return this.rows.find(
      (row) => row.venueId === venueId && row.username === username,
    );
  }

  readonly staff = {
    findUnique: ({ where }: { where: StaffIdentity }) =>
      Promise.resolve(this.rowFor(where) ?? null),
    upsert: ({
      where,
      update,
      create,
    }: {
      where: StaffIdentity;
      update: Partial<StaffRow>;
      create: StaffRow;
    }) => {
      const row = this.rowFor(where);
      if (row) {
        Object.assign(row, update);
        return Promise.resolve(row);
      }
      const created: StaffRow = { ...create };
      this.rows.push(created);
      return Promise.resolve(created);
    },
    update: ({
      where,
      data,
    }: {
      where: StaffIdentity;
      data: Partial<StaffRow>;
    }) => {
      const row = this.rowFor(where);
      if (row) Object.assign(row, data);
      return Promise.resolve(row ?? null);
    },
    findMany: ({ where }: { where: { venueId: string } }) =>
      Promise.resolve(
        this.rows
          .filter((row) => row.venueId === where.venueId)
          .map((row) => ({ username: row.username })),
      ),
    deleteMany: ({
      where,
    }: {
      where: { venueId: string; username: { in: string[] } };
    }) => {
      const names = where.username.in;
      for (let i = this.rows.length - 1; i >= 0; i--) {
        if (
          this.rows[i].venueId === where.venueId &&
          names.includes(this.rows[i].username)
        ) {
          this.rows.splice(i, 1);
        }
      }
      return Promise.resolve({ count: names.length });
    },
  };

  readonly posCallbackOutbox = { findMany: () => Promise.resolve([]) };
}

/** The plain-PIN vault, backed by a map instead of an encrypted setting row. */
class FakeVault {
  constructor(public map: Record<string, string> = {}) {}
  readonly read = jest.fn(() => Promise.resolve({ ...this.map }));
  readonly write = jest.fn((next: Record<string, string>) => {
    this.map = { ...next };
    return Promise.resolve();
  });
}

function makeService(vaultMap: Record<string, string> = {}) {
  const db = new FakeStaffDb();
  const vault = new FakeVault(vaultMap);
  const service = new StaffSyncService(
    db as unknown as PrismaService,
    vault as unknown as StaffPinVault,
  );
  return {
    db,
    vault,
    sync: (staff: StaffSync[]) => service.sync(TENANT, staff),
  };
}

/** The staff list a POS that has already been acknowledged sends: no PINs. */
function routine(...members: Array<[string, StaffSync['role']]>): StaffSync[] {
  return members.map(([username, role]) => ({ username, role }));
}

beforeEach(() => hashMock.mockClear());

describe('StaffSyncService — a routine snapshot', () => {
  it('hashes nothing for an unchanged staff list', async () => {
    const h = makeService({ mary: '1234', nino: '5678' });
    h.db.rows.push(
      row('mary', 'hashed:1234', 'WAITER'),
      row('nino', 'hashed:5678', 'MANAGER'),
    );

    const result = await h.sync(
      routine(['mary', 'WAITER'], ['nino', 'MANAGER']),
    );

    expect(hashMock).not.toHaveBeenCalled();
    expect(result.pinsHashed).toBe(0);
    expect(result.needsPin).toEqual([]);
    expect(h.vault.write).not.toHaveBeenCalled();
  });

  it('leaves every existing credential exactly as it was, sync after sync', async () => {
    const h = makeService({ mary: '1234' });
    h.db.rows.push(row('mary', 'hashed:1234', 'WAITER'));

    for (let i = 0; i < 5; i++) {
      await h.sync(routine(['mary', 'WAITER']));
    }

    expect(hashMock).not.toHaveBeenCalled();
    expect(h.db.rows).toHaveLength(1);
    expect(h.db.rows[0].pinHash).toBe('hashed:1234');
    await expect(bcrypt.compare('1234', h.db.rows[0].pinHash)).resolves.toBe(
      true,
    );
  });

  it('still applies a role change without touching the credential', async () => {
    const h = makeService({ mary: '1234' });
    h.db.rows.push(row('mary', 'hashed:1234', 'WAITER'));

    await h.sync(routine(['mary', 'SUPERVISOR']));

    expect(hashMock).not.toHaveBeenCalled();
    expect(h.db.rows[0].role).toBe('SUPERVISOR');
    expect(h.db.rows[0].pinHash).toBe('hashed:1234');
  });

  it('reports a member it holds no credential for instead of inventing one', async () => {
    const h = makeService();

    const result = await h.sync(routine(['ghost', 'WAITER']));

    expect(result.needsPin).toEqual(['ghost']);
    expect(h.db.rows).toHaveLength(0);
    expect(hashMock).not.toHaveBeenCalled();
  });
});

describe('StaffSyncService — credentials that genuinely change', () => {
  it('creates a member the POS sends with a PIN', async () => {
    const h = makeService();

    const result = await h.sync([
      { username: 'mary', role: 'WAITER', pin: '1234' },
    ]);

    expect(result.pinsHashed).toBe(1);
    expect(h.db.rows).toHaveLength(1);
    expect(h.db.rows[0].pinHash).toBe('hashed:1234');
    expect(h.db.rows[0].pinHash).not.toBe('1234');
    await expect(bcrypt.compare('1234', h.db.rows[0].pinHash)).resolves.toBe(
      true,
    );
    expect(h.vault.write).toHaveBeenCalledWith(
      { mary: '1234' },
      expect.objectContaining({ venueId: 'venue-a' }),
      h.db,
    );
  });

  it('re-hashes when the PIN actually changed, and the old one stops matching', async () => {
    const h = makeService({ mary: '1234' });
    h.db.rows.push(row('mary', 'hashed:1234', 'WAITER'));

    const result = await h.sync([
      { username: 'mary', role: 'WAITER', pin: '9999' },
    ]);

    expect(result.pinsHashed).toBe(1);
    expect(hashMock).toHaveBeenCalledWith('9999', 12);
    expect(h.db.rows[0].pinHash).toBe('hashed:9999');
    await expect(bcrypt.compare('9999', h.db.rows[0].pinHash)).resolves.toBe(
      true,
    );
    await expect(bcrypt.compare('1234', h.db.rows[0].pinHash)).resolves.toBe(
      false,
    );
    expect(h.vault.map).toEqual({ mary: '9999' });
  });

  it('hashes for a member whose PIN the vault does not know, rather than trusting the row', async () => {
    const h = makeService();
    h.db.rows.push(row('mary', 'hashed:1234', 'WAITER'));

    const result = await h.sync([
      { username: 'mary', role: 'WAITER', pin: '1234' },
    ]);

    expect(result.pinsHashed).toBe(1);
    expect(h.db.rows[0].pinHash).toBe('hashed:1234');
  });
});

describe('StaffSyncService — an older POS that sends every PIN', () => {
  it('costs no hashing when the PINs are the ones already stored', async () => {
    const h = makeService({ mary: '1234', nino: '5678' });
    h.db.rows.push(
      row('mary', 'hashed:1234', 'WAITER'),
      row('nino', 'hashed:5678', 'MANAGER'),
    );

    const result = await h.sync([
      { username: 'mary', role: 'SUPERVISOR', pin: '1234' },
      { username: 'nino', role: 'MANAGER', pin: '5678' },
    ]);

    expect(hashMock).not.toHaveBeenCalled();
    expect(result.pinsHashed).toBe(0);
    // The identity half of the snapshot is still applied.
    expect(h.db.rows[0].role).toBe('SUPERVISOR');
  });

  it('still creates members from the PINs it carries', async () => {
    const h = makeService();

    const result = await h.sync([
      { username: 'mary', role: 'WAITER', pin: '1234' },
      { username: 'nino', role: 'MANAGER', pin: '5678' },
    ]);

    expect(result.pinsHashed).toBe(2);
    expect(result.needsPin).toEqual([]);
    expect(h.db.rows.map((r) => r.username)).toEqual(['mary', 'nino']);
  });
});

describe('StaffSyncService — reconcile', () => {
  it('deletes a member the snapshot no longer names', async () => {
    const h = makeService({ mary: '1234', nino: '5678' });
    h.db.rows.push(
      row('mary', 'hashed:1234', 'WAITER'),
      row('nino', 'hashed:5678', 'MANAGER'),
    );

    await h.sync(routine(['mary', 'WAITER']));

    expect(h.db.rows.map((r) => r.username)).toEqual(['mary']);
  });
});

function row(username: string, pinHash: string, role: string): StaffRow {
  return { venueId: 'venue-a', username, pinHash, role, isActive: true };
}
