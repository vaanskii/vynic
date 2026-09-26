import {
  CapabilityFacts,
  publicCapabilities,
  readCapabilityKey,
  websiteCapabilities,
} from './website-capabilities';

const facts = (patch: Partial<CapabilityFacts> = {}): CapabilityFacts => ({
  features: ['WEBSITE'],
  policy: {},
  menuItems: 3,
  hours: 7,
  galleryPhotos: 2,
  bookableTables: 4,
  payment: null,
  ...patch,
});
const byKey = (states: ReturnType<typeof websiteCapabilities>) =>
  Object.fromEntries(states.map((s) => [s.key, s]));

describe('shared website capabilities', () => {
  it('gives SAAS and CUSTOM the same backend answer; only the renderer column differs', () => {
    for (const f of [
      facts(),
      facts({
        features: ['WEBSITE', 'ONLINE_PAYMENTS'],
        payment: { enabled: true },
      }),
      facts({ policy: { HOURS: false, GALLERY: false } }),
    ]) {
      const strip = (mode: 'SAAS' | 'CUSTOM') =>
        websiteCapabilities(f, mode).map((s) => ({
          ...s,
          usedByFrontend: 'renderer-specific',
        }));
      expect(strip('CUSTOM')).toEqual(strip('SAAS'));
    }
    const saas = byKey(websiteCapabilities(facts(), 'SAAS'));
    const custom = byKey(websiteCapabilities(facts(), 'CUSTOM'));
    expect(saas.MENU.usedByFrontend).toBe(true);
    expect(saas.RESERVATIONS.usedByFrontend).toBe(false);
    expect(custom.MENU.usedByFrontend).toBeNull();
  });

  it('describes a Website-only Venue: menu, hours, gallery and accounts live; payments impossible', () => {
    const s = byKey(websiteCapabilities(facts(), 'CUSTOM'));
    for (const key of ['MENU', 'HOURS', 'GALLERY', 'CUSTOMER_ACCOUNTS'])
      expect(s[key]).toMatchObject({ available: true, live: true });
    expect(s.ONLINE_PAYMENTS).toMatchObject({
      commercial: false,
      canEnable: false,
      available: false,
    });
    // The current booking flow takes a BOG deposit, so tables alone are not enough.
    expect(s.RESERVATIONS).toMatchObject({
      available: true,
      ready: false,
      live: false,
      readyDetail: 'Bookings are paid online, and online payments are not live',
    });
  });

  it('makes reservations live once payments are included, configured and enabled', () => {
    const s = byKey(
      websiteCapabilities(
        facts({
          features: ['WEBSITE', 'ONLINE_PAYMENTS'],
          payment: { enabled: true },
        }),
        'SAAS',
      ),
    );
    expect(s.ONLINE_PAYMENTS.live).toBe(true);
    expect(s.RESERVATIONS.live).toBe(true);
    const off = byKey(
      websiteCapabilities(
        facts({
          features: ['WEBSITE', 'ONLINE_PAYMENTS'],
          payment: { enabled: true },
          policy: { ONLINE_PAYMENTS: false },
        }),
        'SAAS',
      ),
    );
    expect(off.ONLINE_PAYMENTS).toMatchObject({ enabled: false, live: false });
    expect(off.RESERVATIONS.live).toBe(false);
  });

  it('turns an operator-disabled capability off without touching the others', () => {
    const s = byKey(
      websiteCapabilities(facts({ policy: { HOURS: false } }), 'SAAS'),
    );
    expect(s.HOURS).toMatchObject({
      commercial: true,
      enabled: false,
      canEnable: true,
      available: false,
      live: false,
    });
    expect(s.MENU.live).toBe(true);
  });

  it('offers no switch for capabilities that are not built', () => {
    const s = byKey(websiteCapabilities(facts(), 'SAAS'));
    for (const key of ['EVENTS', 'BANQUETS', 'ONLINE_ORDERING']) {
      expect(s[key]).toMatchObject({
        built: false,
        commercial: false,
        enabled: false,
        canEnable: false,
        live: false,
      });
      expect(readCapabilityKey(key)).toBeNull();
    }
    expect(readCapabilityKey('HOURS')).toBe('HOURS');
  });

  it('publishes only what a frontend can use', () => {
    expect(
      publicCapabilities(websiteCapabilities(facts({ hours: 0 }), 'CUSTOM')),
    ).toEqual({
      profile: true,
      menu: true,
      hours: false,
      gallery: true,
      reservations: false,
      customerAccounts: true,
      onlinePayments: false,
    });
  });
});
