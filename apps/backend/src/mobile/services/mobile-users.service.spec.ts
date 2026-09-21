process.env.COOKIE_ENCRYPTION_KEY ??= 'mobile-users-spec-key-0123456789ab';

import * as bcrypt from 'bcrypt';
import { MobileUsersService } from './mobile-users.service';
import { StaffPinVault } from '../../auth/staff-pin-vault.service';
import { BOOTSTRAP_VENUE_ID } from '../../auth/legacy-pos-tenant.service';
import { PrismaService } from '../../prisma.service';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import type { TenantContext } from '../../tenancy/tenant-context';

/**
 * Which Venue a manager's staff-credential edit lands in.
 *
 * The manager app reached the PIN vault with no tenant at all, so a manager of
 * any Venue but the bootstrap one read and wrote the bootstrap Venue's PIN map
 * while POS staff sync used their real one. The two disagreed about the same
 * staff member's credential, and the vault is what the manager app shows and
 * what the POS is reconciled against.
 *
 * These drive the real service over a real vault — real AES, real bcrypt — so
 * what is asserted is the stored credential, not a call argument. Nothing here
 * supplies a Venue in a request body or parameter: the tenant is the one the
 * request authenticated into, which for a Manager is their own Staff row's
 * Venue (`ManagerTenantService`), and that is the only thing the writes are
 * addressed with.
 */

const VENUE_A: TenantContext = {
  venueId: 'venue-aaaa-0001',
  organizationId: 'org-aaaa',
};
const VENUE_B: TenantContext = {
  venueId: 'venue-bbbb-0002',
  organizationId: 'org-bbbb',
};
const BOOTSTRAP: TenantContext = {
  venueId: BOOTSTRAP_VENUE_ID,
  organizationId: 'org-bootstrap',
};

interface StaffRow {
  id: string;
  venueId: string;
  username: string;
  pinHash: string;
  role: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}

interface StaffKey {
  venueId_username: { venueId: string; username: string };
}

/** The `staff` and `setting` tables, with their real compound unique keys. */
class FakeDb {
  readonly rows: StaffRow[] = [];
  readonly settings = new Map<string, string>();
  private seq = 0;

  private find(where: StaffKey): StaffRow | undefined {
    const { venueId, username } = where.venueId_username;
    return this.rows.find(
      (row) => row.venueId === venueId && row.username === username,
    );
  }

  readonly staff = {
    findUnique: ({ where }: { where: StaffKey }) =>
      Promise.resolve(this.find(where) ?? null),
    findMany: ({ where }: { where: { venueId: string } }) =>
      Promise.resolve(this.rows.filter((row) => row.venueId === where.venueId)),
    create: ({
      data,
    }: {
      data: Omit<StaffRow, 'id' | 'createdAt' | 'updatedAt'>;
    }) => {
      const created: StaffRow = {
        ...data,
        id: `staff-${++this.seq}`,
        createdAt: new Date(0),
        updatedAt: new Date(0),
      };
      this.rows.push(created);
      return Promise.resolve(created);
    },
    update: ({ where, data }: { where: StaffKey; data: Partial<StaffRow> }) => {
      const row = this.find(where);
      if (row) Object.assign(row, data);
      return Promise.resolve(row ?? null);
    },
    count: ({ where }: { where: { venueId: string } }) =>
      Promise.resolve(
        this.rows.filter((row) => row.venueId === where.venueId).length,
      ),
    delete: ({ where }: { where: StaffKey }) => {
      const row = this.find(where);
      if (row) this.rows.splice(this.rows.indexOf(row), 1);
      return Promise.resolve(row ?? null);
    },
  };

  readonly setting = {
    findUnique: ({
      where,
    }: {
      where: { venueId_key: { venueId: string; key: string } };
    }) => {
      const { venueId, key } = where.venueId_key;
      const value = this.settings.get(`${venueId} ${key}`);
      return Promise.resolve(value === undefined ? null : { value });
    },
    upsert: ({
      where,
      update,
    }: {
      where: { venueId_key: { venueId: string; key: string } };
      update: { value: string };
    }) => {
      const { venueId, key } = where.venueId_key;
      this.settings.set(`${venueId} ${key}`, update.value);
      return Promise.resolve(null);
    },
  };

  /** Which Venues hold a stored PIN map. */
  vaultVenueIds(): string[] {
    return [...this.settings.keys()].map((id) => id.split(' ')[0]).sort();
  }

  hashFor(venueId: string, username: string): string | undefined {
    return this.rows.find(
      (row) => row.venueId === venueId && row.username === username,
    )?.pinHash;
  }
}

/** One member's PIN as the manager app would list it for that Venue. */
async function listedPin(
  users: MobileUsersService,
  tenant: TenantContext,
  username: string,
): Promise<string | undefined> {
  const listed = (await users.getUsers(tenant)) as Array<{
    username: string;
    pinCode: string;
  }>;
  return listed.find((member) => member.username === username)?.pinCode;
}

function makeService() {
  const db = new FakeDb();
  const dispatched: TenantContext[] = [];
  const dispatcher = {
    dispatch: (tenant: TenantContext) => {
      dispatched.push(tenant);
      return Promise.resolve({ delivered: false });
    },
  } as unknown as PosCommandDispatcher;
  const vault = new StaffPinVault(db as unknown as PrismaService);
  const users = new MobileUsersService(
    db as unknown as PrismaService,
    dispatcher,
    vault,
  );
  return { db, users, vault, dispatched };
}

jest.setTimeout(30000);

describe('MobileUsersService - staff credentials are Venue-local', () => {
  it('stores a created member under the Venue the manager authenticated into', async () => {
    const h = makeService();

    await h.users.createUser(VENUE_A, {
      username: 'mary',
      pinCode: '1234',
      role: 'WAITER',
    });

    expect(h.db.vaultVenueIds()).toEqual([VENUE_A.venueId]);
    await expect(h.vault.read(VENUE_A)).resolves.toEqual({ mary: '1234' });
    expect(h.db.rows[0].venueId).toBe(VENUE_A.venueId);
    // The POS command goes to the same Venue, not a defaulted one.
    expect(h.dispatched).toEqual([VENUE_A]);
  });

  it('does not show one Venue the PIN of a same-named member in another', async () => {
    const h = makeService();
    await h.users.createUser(VENUE_A, {
      username: 'mary',
      pinCode: '1234',
      role: 'WAITER',
    });
    await h.users.createUser(VENUE_B, {
      username: 'mary',
      pinCode: '5678',
      role: 'WAITER',
    });

    await expect(listedPin(h.users, VENUE_A, 'mary')).resolves.toBe('1234');
    await expect(listedPin(h.users, VENUE_B, 'mary')).resolves.toBe('5678');

    expect(h.db.vaultVenueIds()).toEqual([VENUE_A.venueId, VENUE_B.venueId]);
  });

  it('leaves the other Venue whole when a PIN is updated', async () => {
    const h = makeService();
    await h.users.createUser(VENUE_A, {
      username: 'mary',
      pinCode: '1234',
      role: 'WAITER',
    });
    await h.users.createUser(VENUE_B, {
      username: 'mary',
      pinCode: '1234',
      role: 'WAITER',
    });

    await h.users.updateUserPin(VENUE_A, 'mary', { pinCode: '9999' });

    await expect(h.vault.read(VENUE_A)).resolves.toEqual({ mary: '9999' });
    await expect(h.vault.read(VENUE_B)).resolves.toEqual({ mary: '1234' });
    // And the credential authentication verifies against, per Venue.
    const inA = h.db.hashFor(VENUE_A.venueId, 'mary') ?? '';
    const inB = h.db.hashFor(VENUE_B.venueId, 'mary') ?? '';
    await expect(bcrypt.compare('9999', inA)).resolves.toBe(true);
    await expect(bcrypt.compare('9999', inB)).resolves.toBe(false);
    await expect(bcrypt.compare('1234', inB)).resolves.toBe(true);
  });

  it('removes a deleted member from only its own Venue vault', async () => {
    const h = makeService();
    await h.users.createUser(VENUE_A, {
      username: 'mary',
      pinCode: '1234',
      role: 'MANAGER',
    });
    await h.users.createUser(VENUE_A, {
      username: 'nino',
      pinCode: '2222',
      role: 'MANAGER',
    });
    await h.users.createUser(VENUE_B, {
      username: 'mary',
      pinCode: '5678',
      role: 'WAITER',
    });

    await h.users.deleteUser(VENUE_A, 'mary');

    await expect(h.vault.read(VENUE_A)).resolves.toEqual({ nino: '2222' });
    await expect(h.vault.read(VENUE_B)).resolves.toEqual({ mary: '5678' });
  });

  it('renames inside one Venue without disturbing the other', async () => {
    const h = makeService();
    await h.users.createUser(VENUE_A, {
      username: 'mary',
      pinCode: '1234',
      role: 'WAITER',
    });
    await h.users.createUser(VENUE_B, {
      username: 'mary',
      pinCode: '5678',
      role: 'WAITER',
    });

    await h.users.renameUser(VENUE_A, 'mary', { username: 'maria' });

    await expect(h.vault.read(VENUE_A)).resolves.toEqual({ maria: '1234' });
    await expect(h.vault.read(VENUE_B)).resolves.toEqual({ mary: '5678' });
  });
});

describe('MobileUsersService - the tenant is not something a caller can send', () => {
  it('ignores a venueId smuggled in the request body', async () => {
    const h = makeService();
    await h.users.createUser(VENUE_B, {
      username: 'nino',
      pinCode: '5678',
      role: 'WAITER',
    });

    await h.users.createUser(VENUE_A, {
      username: 'mary',
      pinCode: '1234',
      role: 'WAITER',
      // Not part of the contract, and not consulted by anything below.
      venueId: VENUE_B.venueId,
      organizationId: VENUE_B.organizationId,
    } as Parameters<MobileUsersService['createUser']>[1]);

    await expect(h.vault.read(VENUE_A)).resolves.toEqual({ mary: '1234' });
    await expect(h.vault.read(VENUE_B)).resolves.toEqual({ nino: '5678' });
    expect(h.db.rows.map((row) => [row.venueId, row.username])).toEqual([
      [VENUE_B.venueId, 'nino'],
      [VENUE_A.venueId, 'mary'],
    ]);
  });

  it('cannot reach another Venue member through the username parameter', async () => {
    const h = makeService();
    await h.users.createUser(VENUE_B, {
      username: 'nino',
      pinCode: '5678',
      role: 'WAITER',
    });

    await expect(
      h.users.updateUserPin(VENUE_A, 'nino', { pinCode: '0000' }),
    ).rejects.toThrow(/not found/i);
    await expect(h.vault.read(VENUE_B)).resolves.toEqual({ nino: '5678' });
    await expect(
      bcrypt.compare('5678', h.db.hashFor(VENUE_B.venueId, 'nino') ?? ''),
    ).resolves.toBe(true);
  });
});

describe('MobileUsersService - the bootstrap Venue', () => {
  it('still reads and writes the bootstrap vault when that is the tenant', async () => {
    const h = makeService();

    await h.users.createUser(BOOTSTRAP, {
      username: 'mary',
      pinCode: '1234',
      role: 'MANAGER',
    });
    await h.users.updateUserPin(BOOTSTRAP, 'mary', { pinCode: '9999' });

    expect(h.db.vaultVenueIds()).toEqual([BOOTSTRAP_VENUE_ID]);
    await expect(h.vault.read(BOOTSTRAP)).resolves.toEqual({ mary: '9999' });
    await expect(listedPin(h.users, BOOTSTRAP, 'mary')).resolves.toBe('9999');
  });

  it('reads a vault an older build left at the bootstrap Venue', async () => {
    const h = makeService();
    // Written before this fix, when the manager app passed no tenant at all.
    await h.vault.write({ mary: '1234' }, BOOTSTRAP);
    await h.db.staff.create({
      data: {
        venueId: BOOTSTRAP_VENUE_ID,
        username: 'mary',
        pinHash: await bcrypt.hash('1234', 4),
        role: 'MANAGER',
        isActive: true,
      },
    });

    await expect(listedPin(h.users, BOOTSTRAP, 'mary')).resolves.toBe('1234');
  });
});
