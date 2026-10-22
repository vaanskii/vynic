import { BadRequestException } from '@nestjs/common';
import {
  menuClientReport,
  menuCompatibility,
  minimumMenuBuild,
} from './menu-client-policy';

describe('Menu capability and deployment build policy', () => {
  afterEach(() => {
    delete process.env.MENU_CANONICAL_MIN_BUILD_WINDOWS;
  });
  const current = {
    version: 1 as const,
    capabilities: ['CANONICAL_MENU_V2'],
    appVersion: '9.99',
    buildNumber: null,
  };
  it('does not infer protocol support from a marketing version', () => {
    expect(
      menuCompatibility('CLOUD', 'WINDOWS', { ...current, capabilities: [] })
        .result,
    ).toBe('CAPABILITY_MISSING');
    expect(menuCompatibility('CLOUD', 'WINDOWS', current).result).toBe(
      'SUPPORTED',
    );
    expect(menuCompatibility('CLOUD', 'UNKNOWN', current).result).toBe(
      'MODE_UNSUPPORTED',
    );
  });
  it('requires an explicit integer build when a minimum is configured; legacy remains independent', () => {
    process.env.MENU_CANONICAL_MIN_BUILD_WINDOWS = '10';
    expect(menuCompatibility('CLOUD', 'WINDOWS', current).result).toBe(
      'UPDATE_REQUIRED',
    );
    expect(
      menuCompatibility('CLOUD', 'WINDOWS', { ...current, buildNumber: 9 })
        .result,
    ).toBe('UPDATE_REQUIRED');
    expect(
      menuCompatibility('CLOUD', 'WINDOWS', { ...current, buildNumber: 10 })
        .result,
    ).toBe('SUPPORTED');
    expect(menuCompatibility('POS', 'WINDOWS', null).result).toBe('SUPPORTED');
    process.env.MENU_CANONICAL_MIN_BUILD_WINDOWS = 'bad';
    expect(menuCompatibility('POS', 'WINDOWS', null).result).toBe('SUPPORTED');
  });
  it('rejects malformed policy rather than treating it as no minimum', () => {
    for (const value of ['-1', '1.0.0', '09', '9007199254740992']) {
      process.env.MENU_CANONICAL_MIN_BUILD_WINDOWS = value;
      expect(() => minimumMenuBuild('WINDOWS')).toThrow('Invalid');
    }
  });
  it('normalizes bounded reports and rejects invalid shapes', () => {
    expect(menuClientReport(null)).toBeNull();
    expect(
      menuClientReport({
        ...current,
        capabilities: ['CANONICAL_MENU_V2', 'CANONICAL_MENU_V2'],
      }),
    ).toEqual(current);
    for (const report of [
      { ...current, version: 2 },
      { ...current, buildNumber: 1.5 },
      { ...current, capabilities: ['x'] },
      '{broken',
    ])
      expect(() => menuClientReport(report)).toThrow(BadRequestException);
  });
});
