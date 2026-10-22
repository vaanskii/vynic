import { BadRequestException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';

/** Internal callers must observe the same bounds as the HTTP ValidationPipe. */
export function validateWebsiteAuthInput<T extends object>(
  dto: new () => T,
  value: unknown,
): void {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    validateSync(plainToInstance(dto, value), {
      whitelist: true,
      forbidNonWhitelisted: true,
      forbidUnknownValues: true,
    }).length
  ) {
    // Never include a password, token, or the rejected object in an error.
    throw new BadRequestException('Invalid authentication input');
  }
}
