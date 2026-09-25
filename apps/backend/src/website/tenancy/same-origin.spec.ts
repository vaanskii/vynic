import { isSameOriginRequest } from './same-origin';

const direct = { trustForwardedHost: false };
const proxied = { trustForwardedHost: true };

describe('isSameOriginRequest', () => {
  it('accepts a page posting to its own host through a host-preserving proxy', () => {
    expect(
      isSameOriginRequest(
        'https://restaurantx.ge',
        { host: 'restaurantx.ge' },
        direct,
      ),
    ).toBe(true);
    expect(
      isSameOriginRequest(
        'http://custom-a.vynic.localhost:5176',
        { host: 'custom-a.vynic.localhost:5176' },
        direct,
      ),
    ).toBe(true);
    expect(
      isSameOriginRequest(
        'https://Vankisi.GE',
        { host: 'vankisi.ge:443' },
        direct,
      ),
    ).toBe(true);
  });

  it('refuses a different host, port or scheme default', () => {
    expect(
      isSameOriginRequest(
        'https://evil.test',
        { host: 'restaurantx.ge' },
        direct,
      ),
    ).toBe(false);
    expect(
      isSameOriginRequest(
        'http://custom-a.vynic.localhost:5177',
        { host: 'custom-a.vynic.localhost:5176' },
        direct,
      ),
    ).toBe(false);
    expect(
      isSameOriginRequest(
        'http://restaurantx.ge',
        { host: 'restaurantx.ge:443' },
        direct,
      ),
    ).toBe(false);
  });

  it('refuses opaque, malformed and path-carrying origins', () => {
    expect(isSameOriginRequest('null', { host: 'null' }, direct)).toBe(false);
    expect(
      isSameOriginRequest('https://a.ge/path', { host: 'a.ge' }, direct),
    ).toBe(false);
    expect(
      isSameOriginRequest('https://a.ge', { host: 'a.ge/x' }, direct),
    ).toBe(false);
    expect(isSameOriginRequest('https://a.ge', {}, direct)).toBe(false);
  });

  it('reads the forwarded host only behind a trusted proxy', () => {
    const headers = {
      host: 'backend:3000',
      'x-forwarded-host': 'restaurantx.ge',
    };
    expect(isSameOriginRequest('https://restaurantx.ge', headers, direct)).toBe(
      false,
    );
    expect(
      isSameOriginRequest('https://restaurantx.ge', headers, proxied),
    ).toBe(true);
    // A spoofed forwarded host cannot make a foreign origin same-origin.
    expect(
      isSameOriginRequest(
        'https://evil.test',
        { host: 'restaurantx.ge', 'x-forwarded-host': 'evil.test' },
        direct,
      ),
    ).toBe(false);
  });
});
