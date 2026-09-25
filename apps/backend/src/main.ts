import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { json, urlencoded } from 'express';
import cookieParser from 'cookie-parser';
import { AppModule } from './app.module';

import { isDevLanOrigin } from './dev-origins';

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

  return ['http://localhost:5173', 'http://127.0.0.1:5173', ...fromEnv];
}

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
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

  app.enableCors({
    origin: (origin: string | undefined, callback) => {
      if (!origin) {
        callback(null, true);
        return;
      }
      const normalized = normalizeOrigin(origin);
      if (allowedOrigins.has(normalized)) {
        callback(null, true);
        return;
      }
      if (!isProduction && isDevLanOrigin(normalized)) {
        callback(null, true);
        return;
      }
      callback(new Error(`Not allowed by CORS: ${origin}`), false);
    },
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
  });

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
