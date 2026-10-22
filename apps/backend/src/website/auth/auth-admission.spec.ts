import 'reflect-metadata';
jest.mock('argon2', () => ({ hash: jest.fn(), verify: jest.fn() }));
import {
  BadRequestException,
  ValidationPipe,
  type INestApplication,
} from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { Server } from 'node:http';
import { createHash } from 'node:crypto';
import request from 'supertest';
import cookieParser from 'cookie-parser';
import { json } from 'express';
import type { Express, Request, Response } from 'express';
import * as argon from 'argon2';
import { EnrollmentRateLimiter } from '../../edge/enrollment-rate-limiter';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { PrismaService } from '../../prisma.service';
import { CsrfService } from '../common/csrf.service';
import { CryptoService } from '../common/crypto.service';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { WebsiteCapabilityGuard } from '../tenancy/website-capability.guard';
import { WebsiteAuthController } from './auth.controller';
import { WebsiteAuthService } from './auth.service';
import { WebsiteAuthGuard } from './website-auth.guard';
import { websiteAuthBodyParsers } from './auth-body-parsers';
import { validateWebsiteAuthInput } from './auth-input';
import { AuthDto, ChangePasswordDto, RegisterDto } from './dto';

const registration = {
  phone: 'synthetic-phone',
  email: 'synthetic@example.invalid',
  password: 'six123',
};

describe('SEC-03 bounded website authentication input', () => {
  beforeEach(() => jest.clearAllMocks());
  it.each([null, [], 'password', 42])(
    'rejects a non-object body: %p',
    (value) => {
      expect(() => validateWebsiteAuthInput(AuthDto, value)).toThrow(
        BadRequestException,
      );
    },
  );

  it.each([
    { identifier: 'x', password: 123456 },
    { identifier: ['x'], password: 'secret' },
    { identifier: 'x'.repeat(321), password: 'secret' },
    { identifier: 'x', password: 'x'.repeat(513) },
    { identifier: 'x', password: { secret: 'hidden' } },
    { identifier: 'x', password: '' },
    { identifier: 'x', password: 'secret', venueId: 'untrusted' },
  ])(
    'rejects invalid sign-in case %# before lookup/hash work',
    async (value) => {
      const findUnique = jest.fn();
      const auth = new WebsiteAuthService(
        { websiteUser: { findUnique } } as unknown as PrismaService,
        {} as never,
        {} as never,
        {} as never,
      );
      const verify = jest.mocked(argon.verify);
      await expect(auth.signin(value as AuthDto)).rejects.toMatchObject({
        status: 400,
      });
      expect(findUnique).not.toHaveBeenCalled();
      expect(verify).not.toHaveBeenCalled();
    },
  );

  it.each([
    { ...registration, password: 123456 },
    { ...registration, password: 'x'.repeat(513) },
    { ...registration, password: 'five!' },
    { ...registration, phone: 'x'.repeat(65) },
    { ...registration, email: 'invalid' },
    { ...registration, firstName: 'x'.repeat(121) },
    { ...registration, lastName: ['name'] },
  ])(
    'rejects invalid registration case %# before hashing or persistence',
    async (value) => {
      const create = jest.fn();
      const auth = new WebsiteAuthService(
        { websiteUser: { create } } as unknown as PrismaService,
        {} as never,
        {} as never,
        {} as never,
      );
      const hash = jest.mocked(argon.hash);
      await expect(auth.signup(value as RegisterDto)).rejects.toMatchObject({
        status: 400,
      });
      expect(create).not.toHaveBeenCalled();
      expect(hash).not.toHaveBeenCalled();
    },
  );

  it.each([
    { oldPassword: 123456, newPassword: 'six123' },
    { oldPassword: 'x'.repeat(513), newPassword: 'six123' },
    { oldPassword: 'old', newPassword: 'x'.repeat(513) },
    { oldPassword: 'old', newPassword: 'short' },
  ])(
    'rejects invalid password change case %# before lookup/hash work',
    async (value) => {
      const findUnique = jest.fn();
      const auth = new WebsiteAuthService(
        { websiteUser: { findUnique } } as unknown as PrismaService,
        {} as never,
        {} as never,
        {} as never,
      );
      await expect(
        auth.changePassword('synthetic-user', value as ChangePasswordDto),
      ).rejects.toMatchObject({ status: 400 });
      expect(findUnique).not.toHaveBeenCalled();
    },
  );

  it('retains existing minimums, exact passwords and valid boundary lengths', () => {
    expect(() =>
      validateWebsiteAuthInput(AuthDto, {
        identifier: 'x'.repeat(320),
        password: ' ',
      }),
    ).not.toThrow();
    expect(() =>
      validateWebsiteAuthInput(RegisterDto, {
        ...registration,
        phone: 'x'.repeat(64),
        password: ' '.repeat(512),
        firstName: 'x'.repeat(120),
      }),
    ).not.toThrow();
    expect(() =>
      validateWebsiteAuthInput(ChangePasswordDto, {
        oldPassword: ' ',
        newPassword: 'six123',
      }),
    ).not.toThrow();
  });
});

describe('SEC-03 website authentication HTTP admission', () => {
  let app: INestApplication;
  let auth: { signin: jest.Mock; signup: jest.Mock; changePassword: jest.Mock };
  const csrf = 'ab'.repeat(32);
  const http = () => request(app.getHttpServer() as Server);
  const post = (route: string, body: object, host = 'a.example.invalid') =>
    http()
      .post(`/api/auth/${route}`)
      .set('Host', host)
      .set('Cookie', `csrf_token=${csrf}`)
      .set('X-CSRF-Token', csrf)
      .send(body);
  const signin = (identifier = 'user@example.invalid', host?: string) =>
    post('signin', { identifier, password: 'synthetic-password' }, host);

  beforeEach(async () => {
    const tokens = {
      access_token: 'synthetic-access',
      refresh_token: 'synthetic-refresh',
    };
    auth = {
      signin: jest.fn().mockResolvedValue(tokens),
      signup: jest.fn().mockResolvedValue(tokens),
      changePassword: jest.fn().mockResolvedValue({ message: 'updated' }),
    };
    const module = await Test.createTestingModule({
      controllers: [WebsiteAuthController],
      providers: [
        { provide: WebsiteAuthService, useValue: auth },
        {
          provide: CryptoService,
          useValue: { encrypt: (token: string) => token },
        },
        CsrfService,
        EnrollmentRateLimiter,
      ],
    })
      .overrideGuard(WebsiteTenantGuard)
      .useValue({ canActivate: () => true })
      .overrideGuard(FeatureGuard)
      .useValue({ canActivate: () => true })
      .overrideGuard(WebsiteCapabilityGuard)
      .useValue({ canActivate: () => true })
      .overrideGuard(WebsiteAuthGuard)
      .useValue({
        canActivate: (ctx: {
          switchToHttp: () => { getRequest: () => { user?: object } };
        }) => {
          ctx.switchToHttp().getRequest().user = { id: 'synthetic-user' };
          return true;
        },
      })
      .compile();
    app = module.createNestApplication();
    app.use('/api/auth', ...websiteAuthBodyParsers());
    app.use(
      json({
        limit: '50mb',
        verify: (req, _res, bytes) => {
          (req as Request & { rawBody?: Buffer }).rawBody = bytes;
        },
      }),
    );
    (app.getHttpAdapter().getInstance() as Express).post(
      '/synthetic-webhook',
      (req: Request & { rawBody?: Buffer }, res: Response) =>
        res.json({
          rawBytes: req.rawBody?.length,
          rawDigest: createHash('sha256')
            .update(req.rawBody ?? Buffer.alloc(0))
            .digest('hex'),
        }),
    );
    app.use(cookieParser());
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.listen(0, '127.0.0.1');
  });

  afterEach(async () => {
    await app?.close();
    jest.restoreAllMocks();
  });

  it('shares normalized global email windows across Hosts and endpoints; success counts', async () => {
    await post('signup', registration).expect(201);
    for (let n = 0; n < 9; n++) await signin(registration.email).expect(201);
    await signin(
      `  ${registration.email.toUpperCase()}  `,
      'b.example.invalid',
    ).expect(429);
    expect(auth.signin).toHaveBeenCalledTimes(9);
    await signin('different@example.invalid').expect(201);
  });

  it('shares phone windows between registration and sign-in', async () => {
    for (let n = 0; n < 10; n++)
      await post('signup', {
        ...registration,
        email: `other${n}@example.invalid`,
      }).expect(201);
    await signin(` ${registration.phone} `).expect(429);
    expect(auth.signin).not.toHaveBeenCalled();
  });

  it('caps one peer at twenty attempts and ignores spoofed forwarding headers', async () => {
    for (let n = 0; n < 20; n++)
      await signin(`user${n}@example.invalid`).expect(201);
    await post('signup', {
      ...registration,
      email: 'fresh@example.invalid',
      phone: 'fresh',
    })
      .set('X-Forwarded-For', '198.51.100.99')
      .set('X-Real-IP', '198.51.100.99')
      .expect(429);
    expect(auth.signup).not.toHaveBeenCalled();
  });

  it('uses forwarded peer identities only under explicit proxy trust and keeps global account windows', async () => {
    (app.getHttpAdapter().getInstance() as Express).set(
      'trust proxy',
      'loopback',
    );
    for (let n = 0; n < 10; n++)
      await signin()
        .set('X-Forwarded-For', `198.51.100.${n + 1}`)
        .expect(201);
    await signin().set('X-Forwarded-For', '198.51.100.99').expect(429);
    await signin('different@example.invalid')
      .set('X-Forwarded-For', '198.51.100.99')
      .expect(201);
    expect(auth.signin).toHaveBeenCalledTimes(11);
  });

  it('returns the same throttle for known and unknown failures before further service calls', async () => {
    auth.signin.mockRejectedValue(
      new BadRequestException('synthetic rejected credentials'),
    );
    for (let n = 0; n < 10; n++) await signin().expect(400);
    await signin().expect(429);
    expect(auth.signin).toHaveBeenCalledTimes(10);
  });

  it('admits only ten simultaneous requests for the same identifier', async () => {
    const responses = await Promise.all(
      Array.from({ length: 15 }, () => signin()),
    );
    expect(
      responses.filter((response) => response.status === 201),
    ).toHaveLength(10);
    expect(
      responses.filter((response) => response.status === 429),
    ).toHaveLength(5);
    expect(auth.signin).toHaveBeenCalledTimes(10);
  });

  it('opens the fixed window after fifteen minutes', async () => {
    let now = 1000000;
    jest.spyOn(Date, 'now').mockImplementation(() => now);
    for (let n = 0; n < 10; n++) await signin().expect(201);
    now += 899999;
    await signin().expect(429);
    now += 1;
    await signin().expect(201);
  });

  it('caps password verification attempts for the authenticated account', async () => {
    for (let n = 0; n < 10; n++)
      await post('change-password', {
        oldPassword: 'old',
        newPassword: 'six123',
      }).expect(201);
    await post('change-password', {
      oldPassword: 'old',
      newPassword: 'six123',
    }).expect(429);
    expect(auth.changePassword).toHaveBeenCalledTimes(10);
  });

  it.each(['signup', 'signin', 'change-password'])(
    'rejects absent CSRF on %s before service work',
    async (route) => {
      const body =
        route === 'signup'
          ? registration
          : route === 'signin'
            ? { identifier: 'user', password: 'secret' }
            : { oldPassword: 'old', newPassword: 'six123' };
      await http().post(`/api/auth/${route}`).send(body).expect(403);
      expect(auth.signin).not.toHaveBeenCalled();
      expect(auth.signup).not.toHaveBeenCalled();
      expect(auth.changePassword).not.toHaveBeenCalled();
    },
  );

  it.each(['', 'short', 'cd'.repeat(32)])(
    'rejects malformed/mismatched CSRF without consuming authentication attempts',
    async (token) => {
      for (let n = 0; n < 25; n++)
        await signin().set('X-CSRF-Token', token).expect(403);
      await signin().expect(201);
      expect(auth.signin).toHaveBeenCalledTimes(1);
    },
  );

  it('rejects malformed/extra fields before admission and does not disclose their values', async () => {
    const secret = 'PRIVATE-SYNTHETIC-REJECTED-PASSWORD'.repeat(20);
    for (let n = 0; n < 25; n++) {
      const rejected = await post('signin', {
        identifier: 'user',
        password: secret,
      }).expect(400);
      expect(JSON.stringify(rejected.body)).not.toContain(secret);
    }
    await post('signin', { identifier: 'user', password: 123456 }).expect(400);
    await post('signin', {
      identifier: 'user',
      password: 'secret',
      venueId: 'client-choice',
    }).expect(400);
    await signin().expect(201);
    expect(auth.signin).toHaveBeenCalledTimes(1);
  });

  it('rejects oversized JSON and forms with 413 before DTO/service work', async () => {
    await post('signin', {
      identifier: 'user',
      password: 'x'.repeat(9000),
    }).expect(413);
    await http()
      .post('/api/auth/signup')
      .type('form')
      .send({ ...registration, firstName: 'x'.repeat(9000) })
      .expect(413);
    expect(auth.signin).not.toHaveBeenCalled();
    expect(auth.signup).not.toHaveBeenCalled();
  });

  it('rejects excessive form parameters before DTO/service work', async () => {
    const body = Object.fromEntries(
      Array.from({ length: 13 }, (_, n) => [`field${n}`, 'synthetic']),
    );
    await http().post('/api/auth/signup').type('form').send(body).expect(413);
    expect(auth.signup).not.toHaveBeenCalled();
  });

  it('leaves larger non-auth bodies and exact webhook bytes to the general parser', async () => {
    const raw = '{  "synthetic" : "' + 'x'.repeat(9000) + '"  }\n';
    const response = await http()
      .post('/synthetic-webhook')
      .type('json')
      .send(raw)
      .expect(200);
    expect(response.body).toEqual({
      rawBytes: Buffer.byteLength(raw),
      rawDigest: createHash('sha256').update(raw).digest('hex'),
    });
  });

  it('accepts bounded form requests through the same validation/admission boundary', async () => {
    await http()
      .post('/api/auth/signin')
      .set('Cookie', `csrf_token=${csrf}`)
      .set('X-CSRF-Token', csrf)
      .type('form')
      .send({
        identifier: 'synthetic@example.invalid',
        password: 'synthetic-password',
      })
      .expect(201);
    expect(auth.signin).toHaveBeenCalledTimes(1);
  });
});
