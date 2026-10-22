import { isDevLanOrigin } from './dev-origins';

describe('local web origins', () => {
  it.each([
    'http://admin.localhost:5173',
    'http://admin.vynic.localhost:5173',
    'http://vynic.localhost:5173',
    'http://admin.localhost:4173',
    'http://localhost:5173',
    'http://127.0.0.1:5174',
    'http://localhost:5175',
    'http://admin.localhost:5176',
    'http://10.10.10.3:5174',
    'http://localhost:5273',
    'http://192.168.1.2:5173',
  ])('allows the development origin %s', (origin) => {
    expect(isDevLanOrigin(origin)).toBe(true);
  });
  it.each([
    'https://admin.vynic.ge',
    'http://admin.localhost.evil.test:5173',
    'http://admin.localhost:9999',
    'http://localhost:5172',
    'http://localhost:5274',
    'http://example.com:5174',
    'http://unknown.localhost:5173',
    'http://admin.localhost:5173/path',
    'http://admin.localhost:5173@evil.test',
  ])('does not implicitly allow %s', (origin) => {
    expect(isDevLanOrigin(origin)).toBe(false);
  });
});
