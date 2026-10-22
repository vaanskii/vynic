import { BadRequestException, HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

export const MENU_CLIENT_CAPABILITY = 'CANONICAL_MENU_V2';
export const MENU_CLIENT_HEADER = 'x-vynic-menu-client';
export const MENU_REPORT_FRESH_MS = 15 * 60_000;

export interface MenuClientReport {
  version: 1;
  capabilities: string[];
  appVersion: string | null;
  buildNumber: number | null;
}

/** Self-report, bound by authenticated Device/code. Not binary attestation. */
export function menuClientReport(raw: unknown): MenuClientReport | null {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw === 'string') {
    if (raw.length > 2048)
      throw new BadRequestException('Menu client report too large');
    try {
      raw = JSON.parse(raw) as unknown;
    } catch {
      throw new BadRequestException('Invalid Menu client report');
    }
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    throw new BadRequestException('Invalid Menu client report');
  const r = raw as Record<string, unknown>;
  if (
    r.version !== 1 ||
    !Array.isArray(r.capabilities) ||
    r.capabilities.length > 16 ||
    r.capabilities.some(
      (c) => typeof c !== 'string' || !/^[A-Z0-9_]{1,64}$/.test(c),
    ) ||
    (r.appVersion != null &&
      (typeof r.appVersion !== 'string' || r.appVersion.length > 64)) ||
    (r.buildNumber != null &&
      (!Number.isSafeInteger(r.buildNumber) || (r.buildNumber as number) < 0))
  )
    throw new BadRequestException('Invalid Menu client report');
  return {
    version: 1,
    capabilities: [...new Set(r.capabilities as string[])].sort(),
    appVersion: (r.appVersion as string | null) ?? null,
    buildNumber: (r.buildNumber as number | null) ?? null,
  };
}

/** One deployment-owned integer policy; marketing SemVer is display only. */
export function minimumMenuBuild(platform: string): number | null {
  const key = `MENU_CANONICAL_MIN_BUILD_${platform.toUpperCase()}`;
  const raw = process.env[key];
  if (!raw) return null;
  if (!/^(0|[1-9][0-9]*)$/.test(raw) || !Number.isSafeInteger(Number(raw)))
    throw new Error(`Invalid ${key}`);
  return Number(raw);
}

export function menuCompatibility(
  authority: 'POS' | 'CLOUD',
  platform: string,
  report: MenuClientReport | null,
) {
  const minimumBuild =
    authority === 'CLOUD' ? minimumMenuBuild(platform) : null;
  const result =
    authority === 'POS'
      ? 'SUPPORTED'
      : !report?.capabilities.includes(MENU_CLIENT_CAPABILITY)
        ? 'CAPABILITY_MISSING'
        : !['WINDOWS', 'MACOS', 'LINUX'].includes(platform.toUpperCase())
          ? 'MODE_UNSUPPORTED'
          : minimumBuild !== null &&
              (report.buildNumber === null || report.buildNumber < minimumBuild)
            ? 'UPDATE_REQUIRED'
            : 'SUPPORTED';
  return {
    result,
    authority,
    requiredCapabilities: authority === 'CLOUD' ? [MENU_CLIENT_CAPABILITY] : [],
    minimumBuild: authority === 'CLOUD' ? minimumBuild : null,
  };
}

export function assertMenuCompatibility(
  authority: 'POS' | 'CLOUD',
  platform: string,
  report: MenuClientReport | null,
) {
  const compatibility = menuCompatibility(authority, platform, report);
  if (compatibility.result !== 'SUPPORTED')
    throw new HttpException(
      {
        code: 'MENU_UPDATE_REQUIRED',
        ...compatibility,
        message:
          'ამ POS ვერსიას ამ რესტორნის მენიუს რეჟიმი აღარ უჭერს მხარს. განაახლეთ Vynic POS. რესტორნის მონაცემები არ შეცვლილა.',
      },
      426,
    );
  return compatibility;
}

/** Call only at Menu boundaries, never per Order or safe recovery endpoint. */
export async function requireMenuClient(
  tx: Prisma.TransactionClient,
  venueId: string,
  deviceId: string | null,
  raw: unknown,
  enforce = true,
) {
  const venue = await tx.venue.findUniqueOrThrow({
    where: { id: venueId },
    select: { menuAuthority: true },
  });
  const report = menuClientReport(raw);
  const device = deviceId
    ? await tx.device.findFirstOrThrow({
        where: { id: deviceId, venueId, status: 'ACTIVE' },
      })
    : null;
  const compatibility = enforce
    ? assertMenuCompatibility(
        venue.menuAuthority,
        device?.platform ?? 'LEGACY',
        report,
      )
    : menuCompatibility(
        venue.menuAuthority,
        device?.platform ?? 'LEGACY',
        report,
      );
  if (device) {
    const now = new Date();
    // A missing report invalidates any previous self-report; credential polls
    // alone cannot keep an old binary's compatibility metadata fresh.
    if (
      JSON.stringify(menuClientReport(device.menuClientReport)) !==
        JSON.stringify(report) ||
      !device.menuClientObservedAt ||
      now.getTime() - device.menuClientObservedAt.getTime() >= 60_000
    ) {
      await tx.device.update({
        where: { id: device.id },
        data: {
          menuClientReport: report ? { ...report } : Prisma.JsonNull,
          menuClientObservedAt: now,
        },
      });
    }
  }
  return compatibility;
}
