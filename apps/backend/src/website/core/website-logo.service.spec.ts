import { mediaDatabaseFixture } from './website-media-test-fixture';
import { ConfigService } from '@nestjs/config';
import { mkdtemp, rm, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { WebsiteLogoService, MAX_LOGO_BYTES } from './website-logo.service';

describe('Website logo storage', () => {
  let root: string;
  let service: WebsiteLogoService;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), 'vynic-logo-'));
    service = new WebsiteLogoService(
      new ConfigService({ WEBSITE_MEDIA_DIR: root }),
      mediaDatabaseFixture(),
    );
  });
  afterEach(() => rm(root, { recursive: true, force: true }));
  it('decodes and resizes real images, returning immutable media references', async () => {
    const buffer = await sharp({
      create: { width: 1400, height: 700, channels: 4, background: '#008844' },
    })
      .png()
      .toBuffer();
    const first = await service.upload('venue-a', {
      buffer,
      size: buffer.length,
    });
    const second = await service.upload('venue-a', {
      buffer,
      size: buffer.length,
    });
    expect(first.url).not.toBe(second.url);
    const bytes = await service.read(first.url.split('/').at(-1)!);
    expect(await sharp(bytes).metadata()).toMatchObject({
      format: 'webp',
      width: 1024,
      height: 512,
    });
  });
  it('keeps main photos large enough for desktop and preserves their proportions', async () => {
    const buffer = await sharp({
      create: { width: 3000, height: 1500, channels: 3, background: '#223344' },
    })
      .jpeg()
      .toBuffer();
    const uploaded = await service.upload(
      'venue-a',
      { buffer, size: buffer.length },
      'hero',
    );
    expect(
      await sharp(
        await service.read(uploaded.url.split('/').at(-1)!),
      ).metadata(),
    ).toMatchObject({ width: 2400, height: 1200, format: 'webp' });
  });
  it('rejects fake images, active SVG, oversized files and traversal', async () => {
    for (const buffer of [
      Buffer.from('not a PNG'),
      Buffer.from(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>',
      ),
    ])
      await expect(
        service.upload('venue-a', { buffer, size: buffer.length }),
      ).rejects.toThrow('Choose a valid');
    await expect(
      service.upload('venue-a', {
        buffer: Buffer.alloc(1),
        size: MAX_LOGO_BYTES + 1,
      }),
    ).rejects.toThrow('5 MB');
    await expect(service.read('../secret')).rejects.toThrow();
    expect(await readdir(root)).toEqual([]);
  });
  it('requires explicit persistent storage in production', async () => {
    const prod = new WebsiteLogoService(
      new ConfigService({ NODE_ENV: 'production' }),
      mediaDatabaseFixture(),
    );
    await expect(
      prod.read('11111111-1111-1111-1111-111111111111.webp'),
    ).rejects.toThrow('not configured');
  });
});
