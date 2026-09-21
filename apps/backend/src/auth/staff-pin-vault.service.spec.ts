process.env.COOKIE_ENCRYPTION_KEY ??= 'staff-pin-vault-spec-key-0123456789';

import { StaffPinVault } from './staff-pin-vault.service';
import { PrismaService } from '../prisma.service';
import { BOOTSTRAP_VENUE_ID } from './legacy-pos-tenant.service';

/**
 * Which Venue's staff PINs an access reaches.
 *
 * The vault is stored one map per Venue, in that Venue's own `setting` row, and
 * its tenant used to be optional — an omitted one silently meant the bootstrap
 * Venue. The manager app omitted it on every call while POS staff sync passed
 * the real one, so for any Venue but the bootstrap the two were reading and
 * writing different rows for the same staff member. These state the property
 * that replaces that: an access reaches the Venue it was given, or it fails.
 *
 * Encryption is real here — the rows below are what actually lands in the
 * database — so "Venue B cannot see Venue A's PIN" is a fact about the stored
 * value, not about a mock.
 */

const VENUE_A = 'venue-aaaa-0001';
const VENUE_B = 'venue-bbbb-0002';
const PIN_MAP_KEY = 'staff:plain_pins';

/** A `setting` table with the real compound unique key, and nothing else. */
class FakeSettingStore {
  readonly rows = new Map<string, string>();

  private static id(venueId: string, key: string) {
    return `${venueId} ${key}`;
  }

  readonly setting = {
    findUnique: ({
      where,
    }: {
      where: { venueId_key: { venueId: string; key: string } };
    }) => {
      const { venueId, key } = where.venueId_key;
      const value = this.rows.get(FakeSettingStore.id(venueId, key));
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
      this.rows.set(FakeSettingStore.id(venueId, key), update.value);
      return Promise.resolve(null);
    },
  };

  /** The raw stored string for a Venue, as the database holds it. */
  stored(venueId: string): string | undefined {
    return this.rows.get(FakeSettingStore.id(venueId, PIN_MAP_KEY));
  }

  seedLegacyCleartext(venueId: string, map: Record<string, string>): void {
    this.rows.set(
      FakeSettingStore.id(venueId, PIN_MAP_KEY),
      JSON.stringify(map),
    );
  }

  venueIds(): string[] {
    return [...this.rows.keys()].map((id) => id.split(' ')[0]).sort();
  }
}

function makeVault() {
  const db = new FakeSettingStore();
  const vault = new StaffPinVault(db as unknown as PrismaService);
  return { db, vault };
}

describe('StaffPinVault - one namespace per Venue', () => {
  it('stores a map in the Venue row it was given', async () => {
    const { db, vault } = makeVault();

    await vault.write({ mary: '1234' }, { venueId: VENUE_A });

    expect(db.venueIds()).toEqual([VENUE_A]);
    await expect(vault.read({ venueId: VENUE_A })).resolves.toEqual({
      mary: '1234',
    });
  });

  it('gives Venue B its own namespace, with no sight of Venue A', async () => {
    const { db, vault } = makeVault();

    await vault.write({ mary: '1234' }, { venueId: VENUE_A });
    await vault.write({ nino: '5678' }, { venueId: VENUE_B });

    await expect(vault.read({ venueId: VENUE_A })).resolves.toEqual({
      mary: '1234',
    });
    await expect(vault.read({ venueId: VENUE_B })).resolves.toEqual({
      nino: '5678',
    });
    expect(db.venueIds()).toEqual([VENUE_A, VENUE_B]);
  });

  it('leaves Venue B untouched when the same username changes PIN in Venue A', async () => {
    const { db, vault } = makeVault();
    await vault.write({ mary: '1234' }, { venueId: VENUE_A });
    await vault.write({ mary: '1234' }, { venueId: VENUE_B });
    const venueBBefore = db.stored(VENUE_B);

    await vault.write({ mary: '9999' }, { venueId: VENUE_A });

    await expect(vault.read({ venueId: VENUE_A })).resolves.toEqual({
      mary: '9999',
    });
    await expect(vault.read({ venueId: VENUE_B })).resolves.toEqual({
      mary: '1234',
    });
    expect(db.stored(VENUE_B)).toBe(venueBBefore);
  });

  it('reads nothing for a Venue that has never been written', async () => {
    const { vault } = makeVault();
    await vault.write({ mary: '1234' }, { venueId: VENUE_A });

    await expect(vault.read({ venueId: VENUE_B })).resolves.toEqual({});
  });

  it('never leaves a PIN in the stored value', async () => {
    const { db, vault } = makeVault();

    await vault.write({ mary: '1234' }, { venueId: VENUE_A });

    expect(db.stored(VENUE_A)).toEqual(expect.stringContaining('v1:'));
    expect(db.stored(VENUE_A)).not.toContain('1234');
    expect(db.stored(VENUE_A)).not.toContain('mary');
  });
});

describe('StaffPinVault - a Venue nobody established', () => {
  it('refuses a blank Venue instead of serving the bootstrap one', async () => {
    const { db, vault } = makeVault();
    await vault.write({ mary: '1234' }, { venueId: BOOTSTRAP_VENUE_ID });

    await expect(vault.read({ venueId: '  ' })).rejects.toThrow(
      /requires an authenticated Venue/,
    );
    await expect(
      vault.write({ mary: '9999' }, { venueId: '' }),
    ).rejects.toThrow(/requires an authenticated Venue/);
    // The bootstrap Venue's map is exactly as it was; nothing fell through.
    await expect(vault.read({ venueId: BOOTSTRAP_VENUE_ID })).resolves.toEqual({
      mary: '1234',
    });
    expect(db.venueIds()).toEqual([BOOTSTRAP_VENUE_ID]);
  });
});

describe('StaffPinVault - the bootstrap Venue', () => {
  it('behaves as it always did when it is the authenticated Venue', async () => {
    const { db, vault } = makeVault();

    await vault.write(
      { mary: '1234', nino: '5678' },
      { venueId: BOOTSTRAP_VENUE_ID },
    );

    expect(db.venueIds()).toEqual([BOOTSTRAP_VENUE_ID]);
    await expect(vault.read({ venueId: BOOTSTRAP_VENUE_ID })).resolves.toEqual({
      mary: '1234',
      nino: '5678',
    });
  });

  it('still reads a legacy cleartext row, and re-encrypts it in place', async () => {
    const { db, vault } = makeVault();
    db.seedLegacyCleartext(BOOTSTRAP_VENUE_ID, { mary: '1234' });

    const map = await vault.read({ venueId: BOOTSTRAP_VENUE_ID });
    await vault.write(map, { venueId: BOOTSTRAP_VENUE_ID });

    expect(map).toEqual({ mary: '1234' });
    expect(db.stored(BOOTSTRAP_VENUE_ID)).toEqual(
      expect.stringContaining('v1:'),
    );
    expect(db.stored(BOOTSTRAP_VENUE_ID)).not.toContain('1234');
  });
});
