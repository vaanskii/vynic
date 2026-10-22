import {
  emptyWebsiteContent,
  readWebsiteContent,
  websiteContent,
  websiteMapUrl,
  websiteWorkingHours,
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
  it('keeps map visibility in the page and rejects non-boolean visibility', () => {
    expect(websiteContent({ ...content, showMap: false })).toMatchObject({
      showMap: false,
    });
    expect(() => websiteContent({ ...content, showMap: 'false' })).toThrow();
    // The pin itself is Venue public information, validated on its own.
    expect(websiteMapUrl('https://maps.app.goo.gl/example')).toBe(
      'https://maps.app.goo.gl/example',
    );
  });
});

describe('Page document and Venue public information', () => {
  const content = {
    ...emptyWebsiteContent,
    slug: 'restaurant',
    heroTitle: 'Restaurant',
  };
  it('refuses Venue-level fields in a page save and drops them from stored pages', () => {
    for (const moved of [
      { workingHours: [] },
      { contactEmail: '' },
      { mapUrl: '' },
      { socials: [] },
      { gallery: [] },
    ])
      expect(() => websiteContent({ ...content, ...moved })).toThrow();
    // A page stored before the move still reads, without those fields.
    expect(
      readWebsiteContent({
        ...content,
        workingHours: [{ day: 1, opens: '10:00', closes: '22:00' }],
        gallery: [{ url: '/media/website-logos/a.webp', alt: '' }],
      }),
    ).toEqual(content);
  });
  it('validates opening hours once, for every renderer', () => {
    expect(
      websiteWorkingHours([{ day: 7, opens: '18:00', closes: '02:00' }]),
    ).toEqual([{ day: 7, opens: '18:00', closes: '02:00' }]);
    for (const bad of [
      [{ day: 8, opens: '10:00', closes: '22:00' }],
      [{ day: 1, opens: '10:00', closes: '10:00' }],
      [
        { day: 1, opens: '10:00', closes: '22:00' },
        { day: 1, opens: '11:00', closes: '23:00' },
      ],
    ])
      expect(() => websiteWorkingHours(bad)).toThrow();
  });
});
