import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import sharp from 'sharp';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { CustomerWebsiteController } from './customer-website.controller';
import { CustomerGuard } from './customer-auth';
import { CustomerService } from './customer.service';
import { WebsiteCoreService } from '../website/core/website-core.service';
import { WebsiteMenuService } from '../website/core/website-menu.service';
import { WebsitePreviewTokens } from '../website/core/website-preview';
import {
  WebsiteLogoService,
  MAX_LOGO_BYTES,
} from '../website/core/website-logo.service';
import { WebsiteLogoController } from '../website/core/website-logo.controller';

describe('Logo upload HTTP transport', () => {
  let app: INestApplication;
  let root: string;
  beforeAll(async () => {
    root = await mkdtemp(join(tmpdir(), 'vynic-logo-http-'));
    const module = await Test.createTestingModule({
      controllers: [CustomerWebsiteController, WebsiteLogoController],
      providers: [
        WebsiteLogoService,
        {
          provide: ConfigService,
          useValue: new ConfigService({ WEBSITE_MEDIA_DIR: root }),
        },
        { provide: CustomerService, useValue: { venue: jest.fn() } },
        {
          provide: WebsiteCoreService,
          useValue: { settings: async () => ({ mode: 'SAAS' }) },
        },
        { provide: WebsiteMenuService, useValue: {} },
        { provide: WebsitePreviewTokens, useValue: {} },
      ],
    })
      .overrideGuard(CustomerGuard)
      .useValue({
        canActivate(context) {
          const req = context.switchToHttp().getRequest();
          req.customer = { customerAccountId: 'fixture-owner' };
          return req.headers.authorization === 'Bearer fixture';
        },
      })
      .compile();
    app = module.createNestApplication();
    await app.init();
  });
  afterAll(async () => {
    await app.close();
    await rm(root, { recursive: true, force: true });
  });
  it('accepts multipart, persists WebP and serves the reference with safe headers', async () => {
    const image = await sharp({
      create: { width: 40, height: 20, channels: 4, background: '#224433' },
    })
      .png()
      .toBuffer();
    const uploaded = await request(app.getHttpServer())
      .post('/customer/venues/a/website/logo')
      .set('Authorization', 'Bearer fixture')
      .attach('file', image, 'logo.png')
      .expect(201);
    const media = await request(app.getHttpServer())
      .get(uploaded.body.url)
      .expect(200)
      .expect('Content-Type', 'image/webp')
      .expect('X-Content-Type-Options', 'nosniff');
    expect(await sharp(media.body).metadata()).toMatchObject({
      format: 'webp',
      width: 40,
      height: 20,
    });
  });
  it('rejects unauthenticated, invalid and oversized uploads', async () => {
    await request(app.getHttpServer())
      .post('/customer/venues/a/website/logo')
      .attach('file', Buffer.from('bad'), 'logo.png')
      .expect(403);
    await request(app.getHttpServer())
      .post('/customer/venues/a/website/logo')
      .set('Authorization', 'Bearer fixture')
      .attach('file', Buffer.from('bad'), 'logo.png')
      .expect(400);
    await request(app.getHttpServer())
      .post('/customer/venues/a/website/logo')
      .set('Authorization', 'Bearer fixture')
      .attach('file', Buffer.alloc(MAX_LOGO_BYTES + 1), 'logo.png')
      .expect(413);
  });
});
