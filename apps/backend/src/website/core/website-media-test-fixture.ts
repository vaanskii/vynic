/** Explicit ACTIVE Website fixture for raster/HTTP transport tests. DB quota races have PostgreSQL coverage. */
export function mediaDatabaseFixture() {
  const tx: any = {
    venue: {
      findUnique: async () => ({
        subscription: { status: 'ACTIVE' },
        planAssignment: {
          plan: {
            features: [{ feature: { key: 'WEBSITE' } }],
            mediaQuotaFiles: 50,
            mediaQuotaBytes: 52428800,
          },
        },
        featureOverrides: [],
      }),
    },
    websiteMediaAsset: {
      aggregate: async () => ({ _count: 0, _sum: { byteSize: 0 } }),
      create: async () => ({}),
    },
    venueWebsiteConfig: { findUnique: async () => null },
    menuItemWebsitePresentation: { findMany: async () => [] },
    $queryRaw: async () => [],
  };
  tx.$transaction = (run: any) => run(tx);
  return tx;
}
