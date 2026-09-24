import { PrismaService } from '../../prisma.service';
import { requireCommercialFeature } from '../../entitlements/commercial-state';
import { Interval } from '@nestjs/schedule';
import { referencedMedia } from './website-media';
import {
  BadRequestException,
  ForbiddenException,
  Logger,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import {
  mkdir,
  readFile,
  writeFile,
  unlink,
  readdir,
  stat,
} from 'node:fs/promises';
import { join, resolve } from 'node:path';
import sharp from 'sharp';
import type { Prisma } from '@prisma/client';

export const MAX_LOGO_BYTES = 5 * 1024 * 1024;

/** Public website image assets (legacy logo URL prefix), addressed by immutable, unguessable names; no original filenames. */
@Injectable()
export class WebsiteLogoService {
  private readonly logger = new Logger(WebsiteLogoService.name);
  constructor(
    private readonly config: ConfigService,
    private readonly db: PrismaService,
  ) {}

  private root() {
    const configured = this.config.get<string>('WEBSITE_MEDIA_DIR');
    if (!configured && this.config.get<string>('NODE_ENV') === 'production')
      throw new ServiceUnavailableException(
        'Website media storage is not configured',
      );
    return resolve(configured || '.data/website-media');
  }

  async upload(
    venueId: string,
    file?: { buffer: Buffer; size: number },
    kind: 'logo' | 'hero' = 'logo',
  ) {
    await this.requireUpload(venueId);
    if (!file || !file.size || file.size > MAX_LOGO_BYTES)
      throw new BadRequestException('Choose an image up to 5 MB');
    let image: Buffer;
    try {
      const input = sharp(file.buffer, {
        limitInputPixels: 16_000_000,
        animated: false,
      });
      const metadata = await input.metadata();
      if (
        !['png', 'jpeg', 'webp'].includes(metadata.format ?? '') ||
        (metadata.pages ?? 1) > 1
      )
        throw new Error('Unsupported image');
      // Decode fully, discard metadata and active formats, constrain dimensions.
      image = await input
        .rotate()
        .resize(kind === 'hero' ? 2400 : 1024, kind === 'hero' ? 2400 : 1024, {
          fit: 'inside',
          withoutEnlargement: true,
        })
        .webp({ quality: 90 })
        .toBuffer();
    } catch {
      throw new BadRequestException('Choose a valid PNG, JPEG or WebP image');
    }
    const root = this.root();
    await mkdir(root, { recursive: true });
    const name = `${randomUUID()}.webp`;
    try {
      await this.db.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
        const state = await requireCommercialFeature(tx, venueId, 'WEBSITE');
        if (state.venue.subscription?.status !== 'ACTIVE')
          throw new ForbiddenException(
            'Photo uploads require an active Website package',
          );
        const plan = state.venue.planAssignment!.plan;
        await this.adoptLegacyAssets(tx, venueId);
        const usage = await tx.websiteMediaAsset.aggregate({
          where: { venueId },
          _sum: { byteSize: true },
          _count: true,
        });
        if (
          usage._count >= plan.mediaQuotaFiles ||
          (usage._sum.byteSize ?? 0) + image.length > plan.mediaQuotaBytes
        )
          throw new ForbiddenException('Website photo storage limit reached');
        await tx.websiteMediaAsset.create({
          data: {
            venueId,
            storageKey: name,
            purpose: kind,
            byteSize: image.length,
          },
        });
        await writeFile(join(root, name), image, { flag: 'wx', mode: 0o600 });
      });
    } catch (error) {
      try {
        await unlink(join(root, name));
      } catch (cleanup) {
        if ((cleanup as NodeJS.ErrnoException).code !== 'ENOENT')
          this.logger.error(
            'Failed to remove unsuccessful media upload',
            cleanup,
          );
      }
      throw error;
    }
    return { url: `/media/website-logos/${name}` };
  }

  private async requireUpload(venueId: string) {
    const state = await requireCommercialFeature(this.db, venueId, 'WEBSITE');
    if (state.venue.subscription?.status !== 'ACTIVE')
      throw new ForbiddenException(
        'Photo uploads require an active Website package',
      );
  }

  /** All uploads count toward quota, including unattached files. Retain unused files for 24h. */
  async cleanup(now = new Date()) {
    const cutoff = new Date(now.getTime() - 86400000);
    const venues = await this.db.venue.findMany({ select: { id: true } });
    for (const { id: venueId } of venues)
      await this.db.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
        await this.adoptLegacyAssets(tx, venueId);
        const referenced = await referencedMedia(tx, venueId);
        for (const asset of await tx.websiteMediaAsset.findMany({
          where: { venueId },
        })) {
          if (referenced.has(asset.storageKey)) {
            if (asset.unusedSince)
              await tx.websiteMediaAsset.update({
                where: { id: asset.id },
                data: { unusedSince: null },
              });
          } else if (!asset.unusedSince) {
            await tx.websiteMediaAsset.update({
              where: { id: asset.id },
              data: { unusedSince: now },
            });
          } else if (asset.unusedSince <= cutoff) {
            await this.remove(asset.storageKey);
            await tx.websiteMediaAsset.delete({ where: { id: asset.id } });
          }
        }
      });
    // Crash between disk write and commit: collect only untracked, unreferenced UUID assets.
    // Pre-migration assets still referenced by any website/menu are preserved.
    const allReferences = new Set<string>();
    for (const venue of await this.db.venue.findMany({ select: { id: true } }))
      for (const key of await referencedMedia(this.db, venue.id))
        allReferences.add(key);
    let files: string[];
    try {
      files = await readdir(this.root());
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') return;
      throw error;
    }
    for (const name of files) {
      if (!/^[a-f0-9-]{36}\.webp$/.test(name) || allReferences.has(name))
        continue;
      if ((await stat(join(this.root(), name))).mtime > cutoff) continue;
      if (
        !(await this.db.websiteMediaAsset.findUnique({
          where: { storageKey: name },
        }))
      )
        await this.remove(name);
    }
  }
  /** Add metadata for pre-migration local files using their persisted Venue references. */
  private async adoptLegacyAssets(
    tx: Prisma.TransactionClient,
    venueId: string,
  ) {
    for (const storageKey of await referencedMedia(tx, venueId)) {
      if (!/^[a-f0-9-]{36}\.webp$/.test(storageKey)) continue;
      if (await tx.websiteMediaAsset.findUnique({ where: { storageKey } }))
        continue;
      let file;
      try {
        file = await stat(join(this.root(), storageKey));
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') continue;
        throw error;
      }
      if (!file.isFile()) continue;
      await tx.websiteMediaAsset.create({
        data: {
          venueId,
          storageKey,
          purpose: 'legacy',
          byteSize: file.size,
          createdAt: file.mtime,
          unusedSince: null,
        },
      });
    }
  }
  private async remove(name: string) {
    try {
      await unlink(join(this.root(), name));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    }
  }
  @Interval(3600000)
  async scheduledCleanup() {
    try {
      await this.cleanup();
    } catch (error) {
      this.logger.error(
        'Website media cleanup failed',
        error instanceof Error ? error.stack : String(error),
      );
    }
  }

  async read(name: string) {
    if (
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.webp$/.test(
        name,
      )
    )
      throw new NotFoundException();
    try {
      return await readFile(join(this.root(), name));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'ENOENT')
        throw new NotFoundException();
      throw error;
    }
  }
}
