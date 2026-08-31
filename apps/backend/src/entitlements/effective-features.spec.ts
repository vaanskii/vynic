import { FeatureOverrideEffect } from '@prisma/client';
import { resolveEffectiveFeatures } from './effective-features';
import { FeatureKeys } from './feature-keys';

const { POS, WEBSITE, MANAGER_APP } = FeatureKeys;

describe('resolveEffectiveFeatures', () => {
  it('gives a Venue exactly what its plan includes when nothing is overridden', () => {
    expect(resolveEffectiveFeatures([POS, WEBSITE], [])).toEqual([
      POS,
      WEBSITE,
    ]);
  });

  it('represents every package the business sells today', () => {
    expect(resolveEffectiveFeatures([POS], [])).toEqual([POS]);
    expect(resolveEffectiveFeatures([POS, WEBSITE], [])).toEqual([
      POS,
      WEBSITE,
    ]);
    expect(resolveEffectiveFeatures([POS, MANAGER_APP], [])).toEqual([
      MANAGER_APP,
      POS,
    ]);
    expect(resolveEffectiveFeatures([POS, WEBSITE, MANAGER_APP], [])).toEqual([
      MANAGER_APP,
      POS,
      WEBSITE,
    ]);
  });

  it('grants a feature the plan lacks when the override enables it', () => {
    expect(
      resolveEffectiveFeatures(
        [POS, WEBSITE],
        [{ key: MANAGER_APP, effect: FeatureOverrideEffect.ENABLED }],
      ),
    ).toEqual([MANAGER_APP, POS, WEBSITE]);
  });

  it('withholds a feature the plan includes when the override disables it', () => {
    expect(
      resolveEffectiveFeatures(
        [POS, WEBSITE, MANAGER_APP],
        [{ key: WEBSITE, effect: FeatureOverrideEffect.DISABLED }],
      ),
    ).toEqual([MANAGER_APP, POS]);
  });

  it('lets an override stand in for a plan entirely', () => {
    expect(
      resolveEffectiveFeatures(
        [],
        [{ key: POS, effect: FeatureOverrideEffect.ENABLED }],
      ),
    ).toEqual([POS]);
  });

  it('leaves a Venue with no plan and no overrides entitled to nothing', () => {
    expect(resolveEffectiveFeatures([], [])).toEqual([]);
  });

  it('ignores a DISABLED override for a feature the plan never granted', () => {
    expect(
      resolveEffectiveFeatures(
        [POS],
        [{ key: WEBSITE, effect: FeatureOverrideEffect.DISABLED }],
      ),
    ).toEqual([POS]);
  });

  it('resolves a feature key it has never heard of, so new features need no code change', () => {
    expect(
      resolveEffectiveFeatures(
        ['RESERVATIONS'],
        [{ key: 'ADVANCED_REPORTS', effect: FeatureOverrideEffect.ENABLED }],
      ),
    ).toEqual(['ADVANCED_REPORTS', 'RESERVATIONS']);
  });
});
