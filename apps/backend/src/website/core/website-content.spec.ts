import {
  emptyWebsiteContent,
  readWebsiteContent,
  websiteContent,
} from './website-content';

describe('Website map visibility compatibility', () => {
  const content = {
    ...emptyWebsiteContent,
    slug: 'restaurant',
    heroTitle: 'Restaurant',
  };
  it('defaults old drafts and published snapshots to the profile location', () => {
    const { showMap: _, ...legacy } = content;
    expect(websiteContent(legacy).showMap).toBe(true);
    expect(readWebsiteContent(legacy).showMap).toBe(true);
  });
  it('keeps the exact pin when the map is hidden and rejects non-boolean visibility', () => {
    expect(
      websiteContent({
        ...content,
        showMap: false,
        mapUrl: 'https://maps.app.goo.gl/example',
      }),
    ).toMatchObject({
      showMap: false,
      mapUrl: 'https://maps.app.goo.gl/example',
    });
    expect(() => websiteContent({ ...content, showMap: 'false' })).toThrow();
  });
});
