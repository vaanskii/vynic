import {
  isLocalDevelopmentHost,
  normalizeHostname,
  requestHostnames,
} from './website-host';

describe('normalizeHostname', () => {
  it('lowercases and strips the port', () => {
    expect(normalizeHostname('Vankisi.Example:5173')).toBe('vankisi.example');
  });

  it('strips the root dot', () => {
    expect(normalizeHostname('a.test.')).toBe('a.test');
  });

  it('keeps an IPv6 literal without its port', () => {
    expect(normalizeHostname('[::1]:3000')).toBe('[::1]');
  });

  it('refuses anything that is not a bare host', () => {
    for (const raw of [
      'https://a.test',
      'a.test/menu',
      'a.test?x=1',
      'a.test#f',
      'user@a.test',
      'a.test b.test',
      'a..test',
      '-a.test',
      '',
      '   ',
    ]) {
      expect(normalizeHostname(raw)).toBeNull();
    }
  });

  it('refuses an over-long host', () => {
    expect(normalizeHostname(`${'a'.repeat(254)}.test`)).toBeNull();
  });
});

describe('requestHostnames', () => {
  it('reads the Host header', () => {
    expect(
      requestHostnames({ host: 'A.test:443' }, { trustForwardedHost: false }),
    ).toEqual(['a.test']);
  });

  it('ignores X-Forwarded-Host unless a proxy is trusted', () => {
    const headers = { host: 'a.test', 'x-forwarded-host': 'b.test' };
    expect(requestHostnames(headers, { trustForwardedHost: false })).toEqual([
      'a.test',
    ]);
    expect(requestHostnames(headers, { trustForwardedHost: true })).toEqual([
      'b.test',
      'a.test',
    ]);
  });

  it('takes only the first entry of a forwarded chain', () => {
    expect(
      requestHostnames(
        { 'x-forwarded-host': 'b.test, evil.test', host: 'a.test' },
        { trustForwardedHost: true },
      ),
    ).toEqual(['b.test', 'a.test']);
  });

  it('drops malformed candidates instead of guessing', () => {
    expect(
      requestHostnames(
        { host: 'https://a.test' },
        { trustForwardedHost: false },
      ),
    ).toEqual([]);
  });
});

describe('isLocalDevelopmentHost', () => {
  it('recognises loopback, LAN and reserved development names', () => {
    for (const host of [
      'localhost',
      'vankisi.localhost',
      '127.0.0.1',
      '[::1]',
      '10.10.10.4',
      '192.168.1.20',
      '172.20.0.5',
    ]) {
      expect(isLocalDevelopmentHost(host)).toBe(true);
    }
  });

  it('does not treat a public name as local', () => {
    for (const host of ['a.test', 'example.com', '8.8.8.8', '172.15.0.1']) {
      expect(isLocalDevelopmentHost(host)).toBe(false);
    }
  });
});
