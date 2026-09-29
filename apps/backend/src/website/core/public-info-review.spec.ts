import {
  EMPTY_PUBLIC_INFO,
  differingFields,
  inferProvenance,
  storedInfo,
  type StoredPublicInfo,
} from './public-info-review';

const migratedAt = new Date('2026-10-10T12:00:00Z');
const before = new Date('2026-10-09T12:00:00Z');
const after = new Date('2026-10-11T12:00:00Z');
const live: StoredPublicInfo = {
  workingHours: [{ day: 1, opens: '09:00', closes: '18:00' }],
  contactEmail: 'owner@example.test',
  mapUrl: null,
  socials: [],
  gallery: [{ url: '/media/website-logos/x.webp', alt: 'x' }],
};
const config = (patch: Record<string, unknown> = {}) => ({
  published: { slug: 'x' },
  revision: 3,
  publishedRevision: 3,
  updatedAt: before,
  ...patch,
});

describe('WEB-02 public information provenance', () => {
  it('compares values structurally, ignoring object key order', () => {
    const a = storedInfo({
      ...live,
      workingHours: [{ closes: '18:00', opens: '09:00', day: 1 }],
    });
    expect(differingFields(a, live)).toEqual([]);
    expect(differingFields(live, EMPTY_PUBLIC_INFO)).toEqual([
      'workingHours',
      'contactEmail',
      'gallery',
    ]);
    // Empty text is "no value", exactly like the foundation's NULLIF.
    expect(storedInfo({ contactEmail: '', mapUrl: '' })).toEqual(
      EMPTY_PUBLIC_INFO,
    );
    expect(storedInfo(null)).toEqual(EMPTY_PUBLIC_INFO);
  });

  it('proves published only while draft and published were the same revision and nothing changed since', () => {
    const result = inferProvenance({
      live,
      ownerEditedFields: [],
      config: config(),
      migratedAt,
    });
    expect(result).toMatchObject({ provenance: 'PUBLISHED', action: 'NONE' });
    expect(result.migratedFields).toEqual([
      'workingHours',
      'contactEmail',
      'gallery',
    ]);
  });

  it('proves an unpublished draft when nothing was ever published', () => {
    expect(
      inferProvenance({
        live,
        ownerEditedFields: [],
        config: config({ published: null, publishedRevision: null }),
        migratedAt,
      }),
    ).toMatchObject({
      provenance: 'DRAFT_ONLY',
      action: 'WITHHOLD_RECOMMENDED',
    });
  });

  it('refuses to guess when unpublished changes existed or settings changed afterwards', () => {
    const diverged = inferProvenance({
      live,
      ownerEditedFields: [],
      config: config({ revision: 4 }),
      migratedAt,
    });
    expect(diverged).toMatchObject({
      provenance: 'AMBIGUOUS',
      action: 'CONFIRM_OR_WITHHOLD',
    });
    expect(diverged.reasons.join(' ')).toContain('unpublished changes');
    expect(
      inferProvenance({
        live,
        ownerEditedFields: [],
        config: config({ updatedAt: after }),
        migratedAt,
      }).provenance,
    ).toBe('AMBIGUOUS');
    expect(
      inferProvenance({
        live,
        ownerEditedFields: [],
        config: config(),
        migratedAt: null,
      }).provenance,
    ).toBe('AMBIGUOUS');
    expect(
      inferProvenance({ live, ownerEditedFields: [], config: null, migratedAt })
        .provenance,
    ).toBe('AMBIGUOUS');
  });

  it('never treats an audited owner edit as a migration artifact', () => {
    const partly = inferProvenance({
      live,
      ownerEditedFields: ['workingHours', 'gallery'],
      config: config({ revision: 4 }),
      migratedAt,
    });
    expect(partly.migratedFields).toEqual(['contactEmail']);
    expect(
      inferProvenance({
        live,
        ownerEditedFields: ['workingHours', 'contactEmail', 'gallery'],
        config: config({ revision: 4 }),
        migratedAt,
      }),
    ).toMatchObject({
      provenance: 'NOT_AFFECTED',
      action: 'NONE',
      migratedFields: [],
    });
    expect(
      inferProvenance({
        live: EMPTY_PUBLIC_INFO,
        ownerEditedFields: [],
        config: config(),
        migratedAt,
      }).provenance,
    ).toBe('NOT_AFFECTED');
  });
});
