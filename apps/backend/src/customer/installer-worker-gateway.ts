import {
  BadRequestException,
  HttpException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';

export interface InstallerWorkerRequest {
  operation: 'context' | 'session' | 'file' | 'outcome';
  id: string;
  clientIp: string;
  token?: string;
  method?: 'GET' | 'HEAD';
  range?: string;
  outcome?: 'completed' | 'failed';
}

export function installerObjectKey(value: string | undefined): boolean {
  const match =
    /^windows\/beta\/(\d+\.\d+\.\d+)\/build([1-9]\d*)\/Vynic-Windows-(\d+\.\d+\.\d+)-build([1-9]\d*)-beta-offline\.zip$/.exec(
      value ?? '',
    );
  return (
    !!match &&
    value!.length < 240 &&
    match[1] === match[3] &&
    match[2] === match[4]
  );
}

export function installerRange(range: string | undefined, bytes: number) {
  let start = 0,
    end = bytes - 1;
  if (range !== undefined) {
    if (range.length > 64 || !/^bytes=\d+-\d*$/.test(range))
      throw new BadRequestException('One byte range is supported');
    const [a, b] = range.slice(6).split('-');
    start = Number(a);
    end = b ? Math.min(Number(b), end) : end;
    if (
      !Number.isSafeInteger(start) ||
      !Number.isSafeInteger(end) ||
      start > end ||
      start >= bytes
    )
      throw new HttpException({ bytes }, 416);
  }
  return { start, end, partial: range !== undefined };
}

export function workerRequest(
  raw: Record<string, unknown>,
): InstallerWorkerRequest {
  if (
    !raw ||
    typeof raw !== 'object' ||
    Array.isArray(raw) ||
    JSON.stringify(raw).length > 2048
  )
    throw new BadRequestException('Invalid gateway request');
  const permitted = {
    context: ['operation', 'id', 'clientIp'],
    session: ['operation', 'id', 'clientIp', 'token'],
    file: ['operation', 'id', 'clientIp', 'token', 'method', 'range'],
    outcome: ['operation', 'id', 'clientIp', 'token', 'outcome'],
  };
  const operation = raw.operation as InstallerWorkerRequest['operation'];
  if (
    !Object.hasOwn(permitted, operation) ||
    Object.keys(raw).some((k) => !permitted[operation].includes(k)) ||
    typeof raw.id !== 'string' ||
    !/^[a-f0-9-]{36}$/.test(raw.id) ||
    typeof raw.clientIp !== 'string' ||
    !isIP(raw.clientIp) ||
    (operation !== 'context' &&
      (typeof raw.token !== 'string' ||
        !/^[A-Za-z0-9_-]{43}$/.test(raw.token))) ||
    (operation === 'file' &&
      (!['GET', 'HEAD'].includes(raw.method as string) ||
        (raw.range !== undefined && typeof raw.range !== 'string'))) ||
    (operation === 'outcome' &&
      !['completed', 'failed'].includes(raw.outcome as string))
  )
    throw new BadRequestException('Invalid gateway request');
  return raw as unknown as InstallerWorkerRequest;
}

export function requireInstallerGateway(header: string | undefined) {
  const expected = process.env.VYNIC_DOWNLOAD_GATEWAY_SECRET;
  if (!/^[A-Za-z0-9_-]{43}$/.test(expected ?? ''))
    throw new ServiceUnavailableException(
      'Private download gateway is not configured',
    );
  const actual = header?.startsWith('Bearer ') ? header.slice(7) : '';
  const hash = (s: string) => createHash('sha256').update(s).digest();
  if (!timingSafeEqual(hash(actual ?? ''), hash(expected!)))
    throw new UnauthorizedException('Private gateway authentication required');
}
