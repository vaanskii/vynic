import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { json, urlencoded } from 'express';
import cookieParser from 'cookie-parser';
import { AppModule } from './app.module';

import { validateDeploymentEnvironment } from './shared/deployment-config';

import { isDevLanOrigin } from './dev-origins';
import { isSameOriginRequest } from './website/tenancy/same-origin';

validateDeploymentEnvironment();

function normalizeOrigin(origin: string): string {
  return origin.endsWith('/') ? origin.slice(0, -1) : origin;
}

function buildAllowedOrigins(): string[] {
  const fromEnv = [
    process.env.FRONTEND_URL,
    ...(process.env.ALLOWED_ORIGINS
      ? process.env.ALLOWED_ORIGINS.split(',')
      : []),
  ]
    .map((value) => value?.trim())
    .filter((value): value is string => Boolean(value))
    .map(normalizeOrigin);

  return process.env.NODE_ENV === 'production'
    ? fromEnv
    : ['http://localhost:5173', 'http://127.0.0.1:5173', ...fromEnv];
}

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const proxyIps = process.env.TRUST_PROXY_IPS?.split(',')
    .map((ip) => ip.trim())
    .filter(Boolean);
  if (proxyIps?.length)
    app.getHttpAdapter().getInstance().set('trust proxy', proxyIps);
  app.enableShutdownHooks();
  const isProduction = process.env.NODE_ENV === 'production';
  const allowedOrigins = new Set(buildAllowedOrigins());

  app.use(
    json({
      limit: '50mb',
      // Preserve the exact raw bytes so webhook signature verification
      // (e.g. BOG payment callbacks) can validate against what was signed,
      // not a re-serialized object.
      verify: (req, _res, buf: Buffer) => {
        (req as unknown as { rawBody?: Buffer }).rawBody = buf;
      },
    }),
  );
  app.use(urlencoded({ extended: true, limit: '50mb' }));
  app.use(cookieParser());

  const trustForwardedHost = ['1', 'true'].includes(
    (process.env.TRUST_PROXY_HOST ?? '').trim().toLowerCase(),
  );
  const corsOptions = {
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'X-CSRF-Token',
      'X-Real-IP',
      'X-Forwarded-For',
      'X-POS-Sync-Key',
      'x-connection-key',
    ],
  };
  // Explicit origins, development LAN clients, and requests a restaurant site
  // sends to its own host (see isSameOriginRequest). Everything else is refused
  // before a handler runs; there is no wildcard.
  app.enableCors(
    (
      req: { headers: Record<string, string | string[] | undefined> },
      callback: (error: Error | null, options?: object) => void,
    ) => {
      const origin =
        typeof req.headers.origin === 'string' ? req.headers.origin : undefined;
      if (!origin) {
        callback(null, { ...corsOptions, origin: true });
        return;
      }
      const normalized = normalizeOrigin(origin);
      if (
        allowedOrigins.has(normalized) ||
        (!isProduction && isDevLanOrigin(normalized)) ||
        isSameOriginRequest(origin, req.headers, { trustForwardedHost })
      ) {
        callback(null, { ...corsOptions, origin: true });
        return;
      }
      callback(new Error(`Not allowed by CORS: ${origin}`));
    },
  );

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port, '0.0.0.0');
}
bootstrap();
