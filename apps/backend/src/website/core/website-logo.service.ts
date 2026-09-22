import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import sharp from 'sharp';

export const MAX_LOGO_BYTES = 5 * 1024 * 1024;

/** Public website image assets (legacy logo URL prefix), addressed by immutable, unguessable names; no original filenames. */
@Injectable()
export class WebsiteLogoService {
  constructor(private readonly config: ConfigService) {}

  private root() {
    const configured = this.config.get<string>('WEBSITE_MEDIA_DIR');
    if (!configured && this.config.get<string>('NODE_ENV') === 'production')
      throw new ServiceUnavailableException(
        'Website media storage is not configured',
      );
    return resolve(configured || '.data/website-media');
  }

  async upload(
    file?: { buffer: Buffer; size: number },
    kind: 'logo' | 'hero' = 'logo',
  ) {
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
    await writeFile(join(root, name), image, { flag: 'wx', mode: 0o600 });
    return { url: `/media/website-logos/${name}` };
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
