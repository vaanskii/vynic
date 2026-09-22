import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { ServiceUnavailableException } from '@nestjs/common';

function key() {
  const value = process.env.PAYMENT_INTEGRATION_MASTER_KEY ?? '';
  if (!/^[a-fA-F0-9]{64}$/.test(value))
    throw new ServiceUnavailableException('Payment encryption key unavailable');
  return Buffer.from(value, 'hex');
}
export function encryptPaymentConfig(
  venueId: string,
  id: string,
  config: object,
): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), iv);
  cipher.setAAD(Buffer.from(`payment:v1:BOG:${venueId}:${id}`));
  const encrypted = Buffer.concat([
    cipher.update(JSON.stringify(config), 'utf8'),
    cipher.final(),
  ]);
  return [
    'v1',
    iv.toString('base64'),
    cipher.getAuthTag().toString('base64'),
    encrypted.toString('base64'),
  ].join('.');
}
export function decryptPaymentConfig(
  venueId: string,
  id: string,
  value: string,
): unknown {
  const master = key();
  try {
    const [version, iv, tag, ciphertext, extra] = value.split('.');
    if (version !== 'v1' || extra || !ciphertext) throw Error();
    const decipher = createDecipheriv(
      'aes-256-gcm',
      master,
      Buffer.from(iv, 'base64'),
    );
    decipher.setAAD(Buffer.from(`payment:v1:BOG:${venueId}:${id}`));
    decipher.setAuthTag(Buffer.from(tag, 'base64'));
    return JSON.parse(
      Buffer.concat([
        decipher.update(Buffer.from(ciphertext, 'base64')),
        decipher.final(),
      ]).toString('utf8'),
    );
  } catch {
    throw new ServiceUnavailableException('Payment configuration unavailable');
  }
}
