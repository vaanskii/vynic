// Explicit fixture for one disposable database. Never reads a production env URL.
//
// Creates the four Venues the generic SaaS website is proved against:
//   restaurant-a  SAAS, entitled, published, own menu and media
//   restaurant-b  SAAS, entitled, published, different menu and media
//   vankisi       CUSTOM, entitled  (the custom frontend's Venue shape)
//   restaurant-d  NONE, not entitled
async function seedWebsiteW3() {
  const raw = process.env.W3_TEST_DATABASE_URL;
  if (!raw || process.argv[2] !== '--confirm-local')
    throw Error('Explicit local URL and --confirm-local required');
  const u = new URL(raw);
  if (
    u.hostname !== '127.0.0.1' ||
    u.port !== '55439' ||
    u.pathname !== '/vynic_w3_disposable'
  )
    throw Error('Only the disposable website database is permitted');
  process.env.DATABASE_URL = raw;
  const { PrismaService } = require('../src/prisma.service');
  const { ConfigService } = require('@nestjs/config');
  const {
    VenueEntitlementsService,
  } = require('../src/entitlements/venue-entitlements.service');
  const {
    WebsiteTenantService,
  } = require('../src/website/tenancy/website-tenant.service');
  const {
    WebsiteCoreService,
  } = require('../src/website/core/website-core.service');
  const {
    WebsiteMenuService,
  } = require('../src/website/core/website-menu.service');
  const {
    emptyWebsiteContent,
  } = require('../src/website/core/website-content');
  const argon2 = require('argon2');
  const db = new PrismaService({ datasourceUrl: raw });
  const config = new ConfigService({ SAAS_WEBSITE_BASE_DOMAIN: 'vynic.local' });
  const menus = new WebsiteMenuService(db);
  const core = new WebsiteCoreService(
    db,
    new VenueEntitlementsService(db),
    new WebsiteTenantService(db, config),
    config,
    menus,
  );

  // Media are references the frontend serves from its own origin. The fixture
  // deliberately stores no image bytes in the database.
  const fixtures: Record<string, any> = {
    'restaurant-a': {
      entitled: true,
      mode: 'SAAS',
      name: 'Tabla',
      address: '12 Rustaveli Avenue, Tbilisi',
      phone: '+995 322 000 111',
      content: {
        heroTitle: 'ტაბლა · Tabla',
        heroSubtitle:
          'ქართული სამზარეულო ძველ თბილისში. Georgian cooking in old Tbilisi.',
        about:
          'ტაბლა ოჯახური რესტორანია, სადაც ყოველი კერძი ხელით მზადდება.\n\nTabla is a family kitchen where every dish is made by hand, from the bread to the last glass of wine.',
        menuHeading: 'მენიუ',
        menuIntro: 'ფასები დღიურად განახლდება POS-იდან.',
        seoTitle: 'Tabla — Georgian restaurant in Tbilisi',
        seoDescription:
          'Family-run Georgian kitchen in old Tbilisi. Khinkali, khachapuri and local wine.',
        contactEmail: 'hello@tabla.test.invalid',
        footerNote: 'ყოველდღე · Open every day',
        logoUrl: '/media/sample/logo-a.svg',
        heroImageUrl: '/media/sample/hero-a.svg',
        aboutImageUrl: '/media/sample/about-a.svg',
        gallery: [
          { url: '/media/sample/gallery-a-1.svg', alt: 'Dining room' },
          { url: '/media/sample/gallery-a-2.svg', alt: 'Bread oven' },
        ],
        socials: [
          { label: 'Instagram', url: 'https://instagram.com/example-tabla' },
        ],
        workingHours: [1, 2, 3, 4, 5, 6, 7].map((day) => ({
          day,
          opens: day >= 5 ? '11:00' : '12:00',
          closes: day >= 5 ? '01:00' : '23:00',
        })),
      },
      menu: [
        {
          slug: 'starters',
          nameKa: 'ცივი კერძები',
          nameEn: 'Starters',
          items: [
            ['ფხალი', 'Pkhali', 12],
            ['ბადრიჯანი', 'Badrijani', 14],
          ],
        },
        {
          slug: 'khinkali',
          nameKa: 'ხინკალი',
          nameEn: 'Khinkali',
          items: [
            ['ხორცის ხინკალი', 'Meat khinkali', 2.5],
            ['სოკოს ხინკალი', 'Mushroom khinkali', 2.5],
          ],
        },
        {
          slug: 'wine',
          nameKa: 'ღვინო',
          nameEn: 'Wine',
          subcategories: [
            {
              slug: 'white',
              nameKa: 'თეთრი',
              nameEn: 'White',
              items: [['რქაწითელი', 'Rkatsiteli', 9, [0.15, 0.75]]],
            },
            {
              slug: 'red',
              nameKa: 'წითელი',
              nameEn: 'Red',
              items: [['საფერავი', 'Saperavi', 11, [0.15, 0.75]]],
            },
          ],
        },
      ],
      hidden: ['Staff meal'],
    },
    'restaurant-b': {
      entitled: true,
      mode: 'SAAS',
      name: 'Zghva',
      address: '4 Seaside Road, Batumi',
      phone: '+995 322 000 222',
      content: {
        heroTitle: 'ზღვა · Zghva',
        heroSubtitle: 'ზღვის პროდუქტები ბათუმში. Seafood in Batumi.',
        about:
          'ზღვა ყოველდღე იღებს ახალ თევზს ბათუმის ნავსადგურიდან.\n\nZghva takes its fish from the Batumi harbour every morning.',
        menuHeading: 'Menu',
        seoTitle: 'Zghva — seafood in Batumi',
        seoDescription: 'Fresh Black Sea fish, grilled daily in Batumi.',
        footerNote: 'სამშაბათი დაკეტილია · Closed Tuesday',
        logoUrl: '/media/sample/logo-b.svg',
        heroImageUrl: '/media/sample/hero-b.svg',
        gallery: [{ url: '/media/sample/gallery-b-1.svg', alt: 'Harbour' }],
        socials: [
          { label: 'Facebook', url: 'https://facebook.com/example-zghva' },
        ],
        workingHours: [1, 3, 4, 5, 6, 7].map((day) => ({
          day,
          opens: '12:00',
          closes: '23:00',
        })),
      },
      menu: [
        {
          slug: 'fish',
          nameKa: 'თევზი',
          nameEn: 'Fish',
          items: [
            ['კეფალი', 'Mullet', 28],
            ['ქარცი', 'Turbot', 42],
          ],
        },
      ],
      hidden: [],
    },
    vankisi: { entitled: true, mode: 'CUSTOM', name: 'Vankisi local stand-in' },
    'restaurant-d': { entitled: false, mode: 'NONE', name: 'Unentitled local' },
  };

  try {
    const feature = await db.feature.findUniqueOrThrow({
      where: { key: 'WEBSITE' },
    });
    for (const [slug, fixture] of Object.entries(fixtures)) {
      const email = `${slug}@w3.test.invalid`;
      let account = await db.customerAccount.findUnique({ where: { email } });
      if (!account) {
        const passwordHash = await argon2.hash('Local W3 owner password!', {
          type: argon2.argon2id,
        });
        account = await db.customerAccount.create({
          data: {
            email,
            passwordHash,
            displayName: 'Local W3 owner',
            organization: { create: { name: `W3 local ${slug}` } },
          },
        });
      }
      await db.organizationMembership.upsert({
        where: { customerAccountId_organizationId: { customerAccountId: account.id, organizationId: account.organizationId! } },
        create: { customerAccountId: account.id, organizationId: account.organizationId!, role: 'OWNER' }, update: {},
      });
      let venue = await db.venue.findFirst({
        where: { organizationId: account.organizationId },
      });
      if (!venue)
        venue = await db.venue.create({
          data: {
            organizationId: account.organizationId!,
            name: fixture.name,
            address: fixture.address ?? null,
            phone: fixture.phone ?? null,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            websiteConfig: { create: { mode: fixture.mode } },
            // `.localhost` is reserved (RFC 6761) and resolves to the loopback
            // in browsers with no /etc/hosts entry, so the fixture is browsable
            // immediately; `.vynic.local` matches the deployment suffix that
            // publication actually claims. Both are ordinary aliases of the
            // same Venue — neither is a second tenancy path — and the
            // `vynic.` label keeps them clear of `vankisi.localhost`, which the
            // tenancy migration already owns.
            domains: {
              create: [
                { hostname: `${slug}.vynic.local` },
                { hostname: `${slug}.vynic.localhost` },
              ],
            },
            featureOverrides: {
              create: {
                featureId: feature.id,
                effect: fixture.entitled ? 'ENABLED' : 'DISABLED',
              },
            },
          },
        });
      if (fixture.menu) await seedMenu(db, venue.id, fixture);
      const state = await core.settings(venue.id);
      if (fixture.content && state.revision === 0) {
        await core.save(
          venue.id,
          {
            expectedRevision: 0,
            content: { ...emptyWebsiteContent, ...fixture.content, slug },
          },
          account.id,
        );
        await core.publish(venue.id, { expectedRevision: 1 }, account.id);
      }
      console.log(
        JSON.stringify({
          email,
          venueId: venue.id,
          hosts: [`${slug}.vynic.local`, `${slug}.vynic.localhost`],
          mode: fixture.mode,
          entitled: fixture.entitled,
        }),
      );
    }
  } finally {
    await db.$disconnect();
  }
}

/**
 * Operational menu rows, as a POS snapshot would have left them.
 *
 * The fixture writes MenuItem/MenuItemVariant directly because that is the
 * operational authority the website only *presents*; it then hides one item
 * through the presentation table rather than deleting or renaming anything.
 */
async function seedMenu(db: any, venueId: string, fixture: any) {
  if (await db.menuCategory.count({ where: { venueId } })) return;
  let categoryOrder = 0;
  for (const category of fixture.menu) {
    const row = await db.menuCategory.create({
      data: {
        venueId,
        slug: category.slug,
        nameKa: category.nameKa,
        nameEn: category.nameEn,
        sortOrder: categoryOrder++,
      },
    });
    let itemOrder = 0;
    for (const [nameKa, nameEn, price, sizes] of category.items ?? [])
      await createItem(db, venueId, row.id, null, {
        nameKa,
        nameEn,
        price,
        sizes,
        sortOrder: itemOrder++,
      });
    let subOrder = 0;
    for (const sub of category.subcategories ?? []) {
      const subRow = await db.menuSubcategory.create({
        data: {
          categoryId: row.id,
          slug: sub.slug,
          nameKa: sub.nameKa,
          nameEn: sub.nameEn,
          sortOrder: subOrder++,
        },
      });
      let order = 0;
      for (const [nameKa, nameEn, price, sizes] of sub.items)
        await createItem(db, venueId, row.id, subRow.id, {
          nameKa,
          nameEn,
          price,
          sizes,
          sortOrder: order++,
        });
    }
  }
  for (const nameEn of fixture.hidden ?? []) {
    const first = await db.menuCategory.findFirstOrThrow({
      where: { venueId },
      orderBy: { sortOrder: 'asc' },
    });
    const item = await createItem(db, venueId, first.id, null, {
      nameKa: nameEn,
      nameEn,
      price: 0,
      sortOrder: 999,
    });
    await db.menuItemWebsitePresentation.create({
      data: { menuItemId: item.id, venueId, visibleOnWebsite: false },
    });
  }
}

function createItem(
  db: any,
  venueId: string,
  categoryId: string,
  subcategoryId: string | null,
  item: any,
) {
  return db.menuItem.create({
    data: {
      venueId,
      categoryId,
      subcategoryId,
      nameKa: item.nameKa,
      nameEn: item.nameEn,
      price: item.price,
      sortOrder: item.sortOrder,
      variants: item.sizes
        ? {
            create: item.sizes.map((size: number) => ({
              size,
              price: Number((item.price * size * 4).toFixed(2)),
            })),
          }
        : undefined,
    },
  });
}

seedWebsiteW3().catch((error) => {
  console.error(
    'W3 local fixture failed; check the disposable database and explicit arguments.',
    error,
  );
  process.exitCode = 1;
});
