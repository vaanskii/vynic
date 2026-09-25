import { generatedSlug } from './hostname';
describe('generated server hostname', () => {
  it.each([
    ['Restaurant Vankisi', 'restaurantvankisi'],
    ['Café Shavi Lomi!', 'cafeshavilomi'],
    ['ხაჭაპური & ღვინო', 'khachapurighvino'],
    ['\t A  B\nC', 'abc'],
    ['---💥---', 'restaurant'],
    ['Admin', 'restaurant-admin'],
  ])('%s -> %s', (name, slug) => expect(generatedSlug(name)).toBe(slug));
});
