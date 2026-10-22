import { generatedSlug, requestableSlug } from './hostname';
describe('generated server hostname', () => {
  it.each([
    ['Restaurant Vankisi', 'restaurantvankisi'],
    ['Café Shavi Lomi!', 'cafeshavilomi'],
    ['ხაჭაპური & ღვინო', 'khachapurighvino'],
    ['\t A  B\nC', 'abc'],
    ['---💥---', 'restaurant'],
    ['Admin', 'restaurant-admin'],
    ['Vynic', 'restaurant-vynic'],
    ['  Dashboard  ', 'restaurant-dashboard'],
    ['Wine-Bar 7', 'wine-bar7'],
    ['A'.repeat(60), 'a'.repeat(40)],
  ])('%s -> %s', (name, slug) => expect(generatedSlug(name)).toBe(slug));
});

describe('requestable hostname', () => {
  it('accepts a valid free-form label', () =>
    expect(requestableSlug('vankisi')).toBe('vankisi'));
  it.each(['vynic', 'www', 'dashboard', 'Vankisi', 'van kisi', '-x', ''])(
    'refuses %p',
    (value) => expect(() => requestableSlug(value)).toThrow(),
  );
});
