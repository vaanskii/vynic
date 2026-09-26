/** Explicit fixtures only in the Compose-owned DB. Re-running preserves edits. */
import { PrismaService } from '../src/prisma.service';
import { emptyWebsiteContent } from '../src/website/core/website-content';

async function main() {
  const url = new URL(process.env.DATABASE_URL || '');
  if (
    process.argv[2] !== '--confirm-local' ||
    url.hostname !== 'postgres' ||
    url.pathname !== '/vynic_local_prod' ||
    process.env.VYNIC_LOCAL_DOCKER !== 'true' ||
    process.env.SAAS_WEBSITE_BASE_DOMAIN !== 'vynic.localhost'
  )
    throw new Error(
      'Seed accepts only --confirm-local in the isolated local Docker deployment',
    );
  const db = new PrismaService();
  try {
    const plan = await db.plan.findUniqueOrThrow({
      where: { key: 'WEBSITE_ONLY' },
    });
    for (const [slug, name, mode, dish, price] of [
      ['tabla', 'Tabla', 'SAAS', 'Tabla khachapuri', 18],
      ['vankisi', 'Vankisi', 'CUSTOM', 'Vankisi mtsvadi', 25],
    ] as const) {
      const id =
        slug === 'tabla'
          ? '10000000-0000-4000-8000-000000000001'
          : '10000000-0000-4000-8000-000000000002';
      await db.$transaction(async (tx) => {
        if (await tx.venue.findUnique({ where: { id } })) return;
        const content = {
          ...emptyWebsiteContent,
          slug,
          heroTitle: name,
          heroSubtitle: 'Local demonstration restaurant',
          about: `${name} — isolated Docker sample data.`,
          menuHeading: 'Menu',
          seoTitle: `${name} · Vynic`,
        };
        await tx.organization.create({
          data: { id, name: `${name} local sample` },
        });
        await tx.venue.create({
          data: {
            id,
            organizationId: id,
            name,
            address: `${slug === 'tabla' ? 12 : 24} Sample Street, Tbilisi`,
            phone: '+995 555 000 000',
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
            menuAuthority: 'CLOUD',
            cloudMenuEditingEnabled: true,
            planAssignment: { create: { planId: plan.id } },
            // Explicit local manual commercial grant; never a fake provider payment.
            subscription: {
              create: {
                status: 'ACTIVE',
                startedAt: new Date(),
                billingManaged: false,
                note: 'Isolated Docker demonstration grant',
              },
            },
            websiteConfig: {
              create: {
                mode,
                ...(mode === 'SAAS'
                  ? {
                      assignedSlug: slug,
                      slug,
                      status: 'PUBLISHED',
                      draft: content,
                      published: content,
                      revision: 1,
                      publishedRevision: 1,
                      publishedAt: new Date(),
                    }
                  : {}),
              },
            },
            domains: { create: { hostname: `${slug}.vynic.localhost` } },
            ...(mode === 'CUSTOM'
              ? {
                  customWebsite: {
                    create: {
                      siteKey: 'vankisi-web',
                      status: 'ACTIVE',
                      statusNote: 'Local Docker sample',
                    },
                  },
                }
              : {}),
            publicProfile: {
              create: {
                workingHours: [1, 2, 3, 4, 5, 6, 7].map((day) => ({
                  day,
                  opens: mode === 'SAAS' ? '10:00' : '12:00',
                  closes: '23:00',
                })),
              },
            },
            menuCategories: {
              create: { id, slug: 'menu', nameKa: 'მენიუ', nameEn: 'Menu' },
            },
          },
        });
        await tx.menuItem.create({
          data: {
            id,
            venueId: id,
            categoryId: id,
            nameKa: dish,
            nameEn: dish,
            price,
          },
        });
      });
      console.log(
        `${name}: http://${slug}.vynic.localhost (${mode}; existing records preserved)`,
      );
    }
    console.log(
      'No BOG credentials created. Payments and paid reservations remain unavailable until configured.',
    );
  } finally {
    await db.$disconnect();
  }
}
main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
