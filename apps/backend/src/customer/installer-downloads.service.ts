import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import type { Request, Response } from 'express';
import { PrismaService } from '../prisma.service';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import type { CustomerPrincipal } from './customer-auth';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { admit, secretHash } from './security-admission';

type Issuer =
  | { customerAccountId: string; venueId: string; platformUserId?: never }
  | { platformUserId: string; customerAccountId?: never; venueId?: never };
const fields = {
  id: true,
  venueId: true,
  customerAccountId: true,
  platformUserId: true,
  createdAt: true,
  expiresAt: true,
  revokedAt: true,
  requestCount: true,
} as const;

@Injectable()
export class InstallerDownloadsService {
  private readonly logger = new Logger(InstallerDownloadsService.name);
  constructor(private readonly db: PrismaService) {}
  configuration() {
    const {
      VYNIC_RELEASE_GITHUB_TOKEN: token,
      VYNIC_INSTALLER_ASSET_ID: assetId,
      VYNIC_INSTALLER_BYTES: bytes,
      VYNIC_INSTALLER_SHA256: sha256,
    } = process.env;
    const ready =
      !!token &&
      /^\d+$/.test(assetId ?? '') &&
      /^\d+$/.test(bytes ?? '') &&
      Number(bytes) > 0 &&
      Number(bytes) < 256 * 1024 * 1024 &&
      /^[a-f0-9]{64}$/.test(sha256 ?? '');
    return { ready, token, assetId, bytes: Number(bytes), sha256 };
  }
  status() {
    const c = this.configuration();
    return {
      available: c.ready,
      expiresInSeconds: 900,
      filename: 'Vynic-Windows-beta-offline.zip',
      ...(c.ready
        ? { sha256: c.sha256, bytes: c.bytes }
        : {
            message: 'Protected installer storage is awaiting configuration.',
          }),
    };
  }
  private async authorize(
    db: any,
    issuer: {
      customerAccountId?: string | null;
      venueId?: string | null;
      platformUserId?: string | null;
    },
  ) {
    if (issuer.customerAccountId) {
      const account = await db.customerAccount.findFirst({
        where: {
          id: issuer.customerAccountId,
          isActive: true,
          memberships: {
            some: {
              organization: { venues: { some: { id: issuer.venueId } } },
              role: 'OWNER',
            },
          },
        },
      });
      if (!account || !issuer.venueId)
        throw new NotFoundException('Download unavailable');
      await requireCommercialFeature(db, issuer.venueId, 'POS');
    } else {
      const actor = await db.platformUser.findFirst({
        where: {
          id: issuer.platformUserId,
          status: 'ACTIVE',
          role: { not: 'SUPPORT_READONLY' },
        },
      });
      if (!actor) throw new ForbiddenException('Download unavailable');
    }
  }
  private audit(
    db: any,
    issuer: {
      customerAccountId?: string | null;
      platformUserId?: string | null;
    },
    action: string,
    id: string,
  ) {
    const data = { action, targetType: 'InstallerDownloadGrant', targetId: id };
    return issuer.customerAccountId
      ? db.customerAuditEvent.create({
          data: { ...data, customerAccountId: issuer.customerAccountId },
        })
      : db.platformAuditEvent.create({
          data: { ...data, platformUserId: issuer.platformUserId },
        });
  }
  async issue(issuer: Issuer, ip: string) {
    await this.authorize(this.db, issuer);
    const config = this.configuration();
    if (!config.ready)
      throw new ServiceUnavailableException(
        'Protected installer storage is awaiting configuration.',
      );
    await admit(this.db, 'installer-issue-ip', ip, 10, 3600000);
    await admit(
      this.db,
      'installer-issue-actor',
      issuer.customerAccountId ?? issuer.platformUserId!,
      3,
      86400000,
    );
    const token = randomBytes(32).toString('base64url');
    const grant = await this.db.$transaction(async (tx) => {
      if (issuer.customerAccountId)
        await tx.$queryRaw`SELECT "id" FROM "pos"."CustomerAccount" WHERE "id"=${issuer.customerAccountId} FOR UPDATE`;
      else
        await tx.$queryRaw`SELECT "id" FROM "pos"."PlatformUser" WHERE "id"=${issuer.platformUserId!} FOR UPDATE`;
      await this.authorize(tx, issuer);
      const old = await tx.installerDownloadGrant.findMany({
        where: { ...issuer, revokedAt: null, expiresAt: { gt: new Date() } },
        select: { id: true },
      });
      await tx.installerDownloadGrant.updateMany({
        where: { id: { in: old.map((g) => g.id) } },
        data: { revokedAt: new Date() },
      });
      for (const grant of old)
        await this.audit(tx, issuer, 'installer_link.superseded', grant.id);
      const row = await tx.installerDownloadGrant.create({
        data: {
          ...issuer,
          artifactId: config.assetId!,
          artifactBytes: config.bytes,
          artifactSha256: config.sha256!,
          tokenHash: secretHash(token),
          expiresAt: new Date(Date.now() + 900000),
        },
        select: fields,
      });
      await this.audit(tx, issuer, 'installer_link.issued', row.id);
      return row;
    });
    return {
      grant,
      downloadUrl:
        'https://releases.vynic.ge/windows/access/' +
        grant.id +
        '#token=' +
        token,
      ...this.status(),
    };
  }
  async listCustomer(actor: CustomerPrincipal, venueId: string) {
    await this.authorize(this.db, { ...actor, venueId });
    return {
      ...this.status(),
      grants: await this.db.installerDownloadGrant.findMany({
        where: { customerAccountId: actor.customerAccountId, venueId },
        select: fields,
        orderBy: { createdAt: 'desc' },
        take: 20,
      }),
    };
  }
  async listAdmin() {
    return {
      ...this.status(),
      grants: await this.db.installerDownloadGrant.findMany({
        select: fields,
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
    };
  }
  async revoke(id: string, actor: CustomerPrincipal | PlatformPrincipal) {
    return this.db.$transaction(async (tx) => {
      const row = await tx.installerDownloadGrant.findUnique({ where: { id } });
      if (
        !row ||
        ('customerAccountId' in actor &&
          row.customerAccountId !== actor.customerAccountId)
      )
        throw new NotFoundException('Download unavailable');
      await tx.installerDownloadGrant.update({
        where: { id },
        data: { revokedAt: new Date() },
      });
      await this.audit(tx, actor, 'installer_link.revoked', id);
      return { revoked: true };
    });
  }
  async linkContext(id: string, ip: string) {
    await admit(this.db, 'installer-link-ip', ip, 60, 3600000);
    if (!/^[a-f0-9-]{36}$/.test(id))
      throw new NotFoundException('Download unavailable or expired');
    const row = await this.db.installerDownloadGrant.findUnique({
      where: { id },
    });
    if (!row || row.revokedAt || row.expiresAt <= new Date())
      throw new NotFoundException('Download unavailable or expired');
    await this.authorize(this.db, row);
    return row;
  }
  async resolve(token: unknown, ip: string, id?: string) {
    await admit(this.db, 'installer-open-ip', ip, 60, 3600000);
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token))
      throw new NotFoundException('Download unavailable or expired');
    const row = await this.db.installerDownloadGrant.findUnique({
      where: { tokenHash: secretHash(token) },
    });
    if (
      !row ||
      (id && row.id !== id) ||
      row.revokedAt ||
      row.expiresAt <= new Date()
    )
      throw new NotFoundException('Download unavailable or expired');
    await this.authorize(this.db, row);
    return row;
  }
  async stream(token: unknown, req: Request, res: Response, id: string) {
    const grant = await this.resolve(token, req.ip ?? 'unknown', id);
    const config = this.configuration();
    if (!config.ready)
      throw new ServiceUnavailableException(
        'Protected installer storage is awaiting configuration.',
      );
    if (
      grant.artifactId !== config.assetId ||
      grant.artifactBytes !== config.bytes ||
      grant.artifactSha256 !== config.sha256
    )
      throw new NotFoundException(
        'Installer changed. Issue a new download link.',
      );
    const range = req.headers.range;
    if (range && !/^bytes=\d+-\d*$/.test(range))
      throw new BadRequestException('One byte range is supported');
    let start = 0,
      end = config.bytes - 1;
    if (range) {
      const [a, b] = range.slice(6).split('-');
      start = Number(a);
      end = b ? Math.min(Number(b), end) : end;
      if (
        !Number.isSafeInteger(start) ||
        !Number.isSafeInteger(end) ||
        start > end ||
        start >= config.bytes
      ) {
        res.setHeader('Content-Range', `bytes */${config.bytes}`);
        res.status(416).end();
        return;
      }
    }
    if (req.method !== 'HEAD') {
      const admitted = await this.db.installerDownloadGrant.updateMany({
        where: {
          id: grant.id,
          revokedAt: null,
          expiresAt: { gt: new Date() },
          requestCount: { lt: 16 },
        },
        data: { requestCount: { increment: 1 } },
      });
      if (!admitted.count)
        throw new NotFoundException(
          'Download limit reached. Issue a new link.',
        );
      await this.audit(this.db, grant, 'installer_download.started', grant.id);
    }
    // Fetch only a fixed private release asset; never return an upstream redirect.
    const abort = new AbortController();
    const closed = () => {
      if (!res.writableFinished) abort.abort();
    };
    res.on('close', closed);
    let upstream: globalThis.Response | undefined;
    let phase = 'storage_request';
    try {
      let url = `https://api.github.com/repos/vaanskii/vynic-releases/releases/assets/${config.assetId}`;
      for (let hop = 0; hop < 4; hop++) {
        const api = new URL(url).hostname === 'api.github.com';
        upstream = await fetch(url, {
          method: api ? 'GET' : req.method,
          redirect: 'manual',
          signal: abort.signal,
          headers: {
            Accept: 'application/octet-stream',
            'User-Agent': 'Vynic-protected-download',
            ...(api
              ? {
                  Authorization: `Bearer ${config.token}`,
                  'X-GitHub-Api-Version': '2022-11-28',
                }
              : {}),
            ...(range && !api ? { Range: `bytes=${start}-${end}` } : {}),
          },
        });
        if (![301, 302, 303, 307, 308].includes(upstream.status)) break;
        phase = 'storage_redirect';
        const location = upstream.headers.get('location');
        await upstream.body?.cancel();
        if (!location) throw new Error('Missing storage redirect');
        const next = new URL(location, url);
        if (
          next.protocol !== 'https:' ||
          next.hostname !== 'release-assets.githubusercontent.com' ||
          next.username ||
          next.password
        )
          throw new Error('Storage redirect refused');
        url = next.href;
      }
      const expectedStatus = range ? 206 : 200;
      phase = 'storage_response';
      if (
        !upstream ||
        upstream.status !== expectedStatus ||
        upstream.headers.get('content-type')?.includes('json') ||
        Number(upstream.headers.get('content-length')) !== end - start + 1 ||
        (range &&
          upstream.headers.get('content-range') !==
            `bytes ${start}-${end}/${config.bytes}`)
      ) {
        await upstream?.body?.cancel();
        throw new Error('Storage response rejected');
      }
      res.status(expectedStatus);
      res.setHeader('Content-Type', 'application/zip');
      res.setHeader(
        'Content-Disposition',
        'attachment; filename="Vynic-Windows-beta-offline.zip"',
      );
      res.setHeader('Content-Length', end - start + 1);
      res.setHeader('Accept-Ranges', 'bytes');
      if (range)
        res.setHeader('Content-Range', `bytes ${start}-${end}/${config.bytes}`);
      if (req.method === 'HEAD') {
        await upstream.body?.cancel();
        res.end();
      } else {
        phase = 'storage_stream';
        await pipeline(Readable.fromWeb(upstream.body as any), res);
        await this.audit(
          this.db,
          grant,
          'installer_download.completed',
          grant.id,
        );
      }
    } catch {
      this.logger.warn({
        event: 'installer_storage_unavailable',
        phase,
        status: upstream?.status ?? null,
        json: upstream?.headers.get('content-type')?.includes('json') ?? false,
        expectedBytes: end - start + 1,
        receivedLength: upstream?.headers.get('content-length') ?? null,
        method: req.method,
        range: Boolean(range),
      });
      await this.audit(this.db, grant, 'installer_download.failed', grant.id);
      if (res.headersSent) res.destroy();
      else
        throw new ServiceUnavailableException(
          'Protected installer storage is unavailable. Try again later.',
        );
    } finally {
      res.off('close', closed);
      abort.abort();
    }
  }
}
