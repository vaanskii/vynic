import {
  LOCAL_FRONTENDS_ENV,
  isLocalHostname,
  localFrontend,
  parseLocalFrontends,
} from './custom-website-local';

describe('CUSTOM website local frontends', () => {
  it('maps each frontend identity to its own port', () => {
    const registry = parseLocalFrontends(
      ' vankisi-web=5174, custom-b-web = 5176 ,hotel-y-web=5177,',
    );
    expect([...registry.ports]).toEqual([
      ['vankisi-web', 5174],
      ['custom-b-web', 5176],
      ['hotel-y-web', 5177],
    ]);
    expect(registry.problems).toEqual([]);
  });

  it('has no default: nothing configured means no ports', () => {
    for (const raw of [undefined, '', ' , ']) {
      const registry = parseLocalFrontends(raw);
      expect(registry.ports.size).toBe(0);
      expect(registry.problems).toEqual([]);
    }
  });

  it('drops and reports malformed, out-of-range, duplicated and clashing entries', () => {
    const registry = parseLocalFrontends(
      [
        'vankisi-web=5174',
        '5176',
        'Bad Key=5176',
        'http://x.localhost:5176',
        'low-web=80',
        'high-web=70000',
        'dup-web=5180',
        'dup-web=5181',
        'one-web=5190',
        'two-web=5190',
      ].join(','),
    );
    // Only the one unambiguous entry survives; nothing is guessed.
    expect([...registry.ports]).toEqual([['vankisi-web', 5174]]);
    expect(registry.problems).toEqual([
      '"5176" is not <frontend identity>=<port>',
      '"Bad Key=5176" is not <frontend identity>=<port>',
      '"http://x.localhost:5176" is not <frontend identity>=<port>',
      'low-web: port must be 1024-65535',
      'high-web: port must be 1024-65535',
      'dup-web is listed more than once',
      'one-web and two-web both claim port 5190',
    ]);
  });

  it('builds the local URL from the Venue domain and the mapped port', () => {
    const registry = parseLocalFrontends('vankisi-web=5174,custom-b-web=5176');
    expect(
      localFrontend(
        { siteKey: 'vankisi-web', hostname: 'vankisi.localhost' },
        registry,
      ),
    ).toEqual({
      state: 'CONFIGURED',
      siteKey: 'vankisi-web',
      hostname: 'vankisi.localhost',
      port: 5174,
      url: 'http://vankisi.localhost:5174/',
      source: LOCAL_FRONTENDS_ENV,
      detail: `vankisi-web=5174 in ${LOCAL_FRONTENDS_ENV}`,
      problems: [],
    });
    expect(
      localFrontend(
        { siteKey: 'custom-b-web', hostname: 'custom-b.localhost' },
        registry,
      ).url,
    ).toBe('http://custom-b.localhost:5176/');
  });

  it('reports what is missing instead of producing a URL', () => {
    const registry = parseLocalFrontends('vankisi-web=5174');
    const missing = localFrontend(
      { siteKey: 'restaurant-x-web', hostname: 'restaurant-x.localhost' },
      registry,
    );
    expect(missing).toMatchObject({
      state: 'NOT_CONFIGURED',
      port: null,
      url: null,
    });
    expect(missing.detail).toContain(
      `add restaurant-x-web=<port> to ${LOCAL_FRONTENDS_ENV}`,
    );
    expect(
      localFrontend({ siteKey: null, hostname: 'x.localhost' }, registry),
    ).toMatchObject({ state: 'NO_SITE_KEY', url: null });
    expect(
      localFrontend({ siteKey: 'vankisi-web', hostname: null }, registry),
    ).toMatchObject({ state: 'NO_LOCAL_DOMAIN', port: 5174, url: null });
  });

  it('treats only .localhost names as local', () => {
    expect(isLocalHostname('vankisi.localhost')).toBe(true);
    expect(isLocalHostname('custom-a.vynic.localhost')).toBe(true);
    expect(isLocalHostname('vankisi.ge')).toBe(false);
    expect(isLocalHostname('localhost.evil.test')).toBe(false);
  });
});
