Loaded Prisma config from prisma.config.ts.

-- RenameForeignKey
ALTER TABLE "pos"."DevicePrinterRuntimeRequest" RENAME CONSTRAINT "DevicePrinterRuntimeRequest_device_fkey" TO "DevicePrinterRuntimeRequest_deviceId_fkey";

-- RenameForeignKey
ALTER TABLE "pos"."DevicePrinterRuntimeRequest" RENAME CONSTRAINT "DevicePrinterRuntimeRequest_venue_fkey" TO "DevicePrinterRuntimeRequest_venueId_fkey";

