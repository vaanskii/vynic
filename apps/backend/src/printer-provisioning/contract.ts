import { BadRequestException, ConflictException } from '@nestjs/common';
import {
  createHash,
  createPublicKey,
  verify,
  X509Certificate,
} from 'node:crypto';
import { isIP } from 'node:net';

export const PURPOSE = 'VYNIC_PRINTER_PRODUCTION';
export const DOMAIN = 'vynic/printer-provisioning/production/v1\0';
export const ENROLL_DOMAIN = 'vynic/printer-enrollment/v1\0';
export const OFFLINE_SECONDS = 7 * 24 * 60 * 60;
export const digest = (b: Buffer | string) =>
  createHash('sha256').update(b).digest('hex');
export const signatureInput = (b: Buffer) =>
  Buffer.concat([Buffer.from(DOMAIN), createHash('sha256').update(b).digest()]);
export function object<T extends object = Record<string, unknown>>(
  v: unknown,
  required: string[],
  optional: string[] = [],
): T {
  if (
    !v ||
    typeof v !== 'object' ||
    Array.isArray(v) ||
    required.some((k) => !(k in v)) ||
    Object.keys(v).some((k) => !required.includes(k) && !optional.includes(k))
  )
    throw new BadRequestException('Invalid printer object fields');
  return v as T;
}
export function id(v: unknown): string {
  if (
    typeof v !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      v,
    )
  )
    throw new BadRequestException('Canonical UUID required');
  return v;
}
function label(v: unknown) {
  if (
    typeof v !== 'string' ||
    !v ||
    v.length > 160 ||
    v.trim() !== v ||
    [...v].some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127)
  )
    throw new BadRequestException('Invalid printer label');
}
export function integer(v: unknown, min = 0, max = 2147483646): number {
  if (!Number.isSafeInteger(v) || (v as number) < min || (v as number) > max)
    throw new BadRequestException('Invalid printer revision/number');
  return v as number;
}
function array(v: unknown, max: number, min = 0): unknown[] {
  if (!Array.isArray(v) || v.length < min || v.length > max)
    throw new BadRequestException('Invalid printer array');
  return v;
}
function unique(values: string[]) {
  if (new Set(values).size !== values.length)
    throw new BadRequestException('Duplicate printer identity');
}
function bool(v: unknown) {
  if (typeof v !== 'boolean') throw new BadRequestException('Boolean required');
}
export interface Enrollment {
  installationId: string;
  publicKey: string;
  certificate: string;
  proof: string;
}
export function enrollment(value: unknown, deviceId: string): Enrollment {
  const b = object<Enrollment>(value, [
    'installationId',
    'publicKey',
    'certificate',
    'proof',
  ]);
  id(b.installationId);
  try {
    if (
      typeof b.publicKey !== 'string' ||
      !/^[A-Za-z0-9_-]{43}$/.test(b.publicKey)
    )
      throw Error();
    const der = Buffer.from(b.certificate, 'base64');
    if (der.length > 16384 || der.toString('base64') !== b.certificate)
      throw Error();
    const cert = new X509Certificate(der);
    const key = createPublicKey({
      key: { kty: 'OKP', crv: 'Ed25519', x: b.publicKey },
      format: 'jwk',
    });
    if (
      cert.ca ||
      !cert.raw.equals(der) ||
      cert.keyUsage.length !== 2 ||
      !cert.keyUsage.includes('1.3.6.1.5.5.7.3.1') ||
      !cert.keyUsage.includes('1.3.6.1.5.5.7.3.2') ||
      cert.publicKey.asymmetricKeyType !== 'ed25519' ||
      cert.publicKey.export({ format: 'jwk' }).x !== b.publicKey ||
      !cert.verify(key) ||
      cert.subjectAltName !==
        `URI:spiffe://vynic-printer-production/${b.installationId}` ||
      Date.parse(cert.validFrom) > Date.now() ||
      Date.parse(cert.validTo) <= Date.now() + OFFLINE_SECONDS * 1000
    )
      throw Error();
    const input = Buffer.from(
      ENROLL_DOMAIN + deviceId + '\0' + b.installationId + '\0' + digest(der),
    );
    const proof = Buffer.from(b.proof, 'base64');
    if (
      proof.length !== 64 ||
      proof.toString('base64') !== b.proof ||
      !verify(null, input, key, proof)
    )
      throw Error();
  } catch {
    throw new BadRequestException(
      'Printer key possession or certificate refused',
    );
  }
  return b;
}

export interface Member {
  installationId: string;
  deviceId: string;
  publicKey: string;
  certificateSha256: string;
  authorized: boolean;
  role: 'CLIENT' | 'VOTER';
  endpointHint: string;
}
export interface Controller {
  id: string;
  installationId: string;
  deviceId: string;
  name: string;
}
export interface Destination {
  physicalPrinterId: string;
  workerHostId: string;
  transport: string;
  host: string;
  port: number;
  queueName: string;
  expectedDriverName: string;
  expectedPortName: string;
  documentName: string;
}
export interface PhysicalPrinter {
  id: string;
  name: string;
  controllerId: string;
  destination: Destination;
  profile: Record<string, unknown>;
  enabled: boolean;
  failoverMode: string;
}
export interface Station {
  id: string;
  name: string;
  role: string;
  scope: string;
  ownerDeviceId?: string;
  enabled: boolean;
  sortOrder: number;
  routes: string[];
}
export interface Rule {
  kind: string;
  matchId: string;
  orderType?: string;
  stations: string[];
}
export interface Catalog {
  version: number;
  venueId: string;
  revision: number;
  controllers: Controller[];
  printers: PhysicalPrinter[];
  stations: Station[];
  rules: Rule[];
}
export interface Configuration {
  topology: 'LOCAL_ONLY' | 'SINGLE_REPLICA' | 'THREE_REPLICAS';
  voters: string[];
  endpoints: Record<string, string>;
  catalog: Catalog | null;
}
export const emptyConfiguration = (): Configuration => ({
  topology: 'LOCAL_ONLY',
  voters: [],
  endpoints: {},
  catalog: null,
});
export function endpoint(p: PhysicalPrinter): string {
  return p.destination.transport === 'tcp'
    ? `tcp:${p.destination.host}:${p.destination.port}`
    : `windows:${p.controllerId}:${p.destination.queueName.toLowerCase()}`;
}
// Validates the existing station Catalog contract, then intersects every identity
// with server-owned enrollment. Saving JSON cannot invent a member or controller.
export function configuration(
  value: unknown,
  venueId: string,
  revision: number,
  members: Member[],
): Configuration {
  const c = object<Configuration>(value, [
    'topology',
    'voters',
    'endpoints',
    'catalog',
  ]);
  const active = new Map(
    members.filter((m) => m.authorized).map((m) => [m.installationId, m]),
  );
  const voters = array(c.voters, 3).map(id);
  unique(voters);
  const count =
    c.topology === 'LOCAL_ONLY'
      ? 0
      : c.topology === 'SINGLE_REPLICA'
        ? 1
        : c.topology === 'THREE_REPLICAS'
          ? 3
          : -1;
  if (voters.length !== count || voters.some((v) => !active.has(v)))
    throw new BadRequestException(
      'Explicit stable full replica membership required',
    );
  if (
    !c.endpoints ||
    Array.isArray(c.endpoints) ||
    typeof c.endpoints !== 'object'
  )
    throw new BadRequestException('Invalid discovery hints');
  for (const [key, hint] of Object.entries(c.endpoints)) {
    if (
      !active.has(id(key)) ||
      typeof hint !== 'string' ||
      hint.length > 256 ||
      !/^\[[0-9a-f:]+\]:[0-9]+$|^[0-9.]+:[0-9]+$/.test(hint)
    )
      throw new BadRequestException('Numeric peer endpoint required');
    const host = hint.startsWith('[')
      ? hint.slice(1, hint.indexOf(']'))
      : hint.split(':')[0];
    if (
      !isIP(host) ||
      !Number(hint.slice(hint.lastIndexOf(':') + 1)) ||
      Number(hint.slice(hint.lastIndexOf(':') + 1)) > 65535
    )
      throw new BadRequestException('Invalid peer endpoint');
  }
  if (c.catalog === null) {
    if (count !== 0) throw new BadRequestException('Catalog required');
    return c;
  }
  const cat = object<Catalog>(c.catalog, [
    'version',
    'venueId',
    'revision',
    'controllers',
    'printers',
    'stations',
    'rules',
  ]);
  if (cat.version !== 1 || cat.venueId !== venueId || cat.revision !== revision)
    throw new BadRequestException('Catalog scope/revision mismatch');
  const controllers = array(cat.controllers, 256, 1).map((v) => {
    const x = object<Controller>(v, [
      'id',
      'installationId',
      'deviceId',
      'name',
    ]);
    id(x.id);
    id(x.installationId);
    id(x.deviceId);
    label(x.name);
    if (active.get(x.installationId)?.deviceId !== x.deviceId)
      throw new BadRequestException('Unenrolled controller');
    return x;
  });
  unique(controllers.map((x) => x.id));
  unique(controllers.map((x) => x.installationId));
  const printers = array(cat.printers, 64, 1).map((v) => {
    const x = object<PhysicalPrinter>(v, [
      'id',
      'name',
      'controllerId',
      'destination',
      'profile',
      'enabled',
      'failoverMode',
    ]);
    id(x.id);
    label(x.name);
    bool(x.enabled);
    if (
      !controllers.some((k) => k.id === x.controllerId) ||
      !['NONE', 'FIXED_CONTROLLER'].includes(x.failoverMode)
    )
      throw new BadRequestException('Fixed enrolled controller required');
    const d = object<Destination>(x.destination, [
      'physicalPrinterId',
      'workerHostId',
      'transport',
      'host',
      'port',
      'queueName',
      'expectedDriverName',
      'expectedPortName',
      'documentName',
    ]);
    if (d.physicalPrinterId !== x.id || d.workerHostId !== x.controllerId)
      throw new BadRequestException('Destination identity mismatch');
    label(d.documentName);
    if (d.transport === 'tcp') {
      // Canonical IPv4 only in the initial production issuer; Go also reads IPv6.
      if (
        isIP(d.host) !== 4 ||
        d.host.split('.').map(Number).join('.') !== d.host ||
        d.queueName !== '' ||
        d.expectedDriverName !== '' ||
        d.expectedPortName !== ''
      )
        throw new BadRequestException('Invalid TCP route');
      const octets = d.host.split('.').map(Number);
      if (
        !(
          octets[0] === 10 ||
          octets[0] === 127 ||
          (octets[0] === 192 && octets[1] === 168) ||
          (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
          (octets[0] === 169 && octets[1] === 254)
        )
      )
        throw new BadRequestException('Literal LAN address required');
      integer(d.port, 1, 65535);
    } else if (d.transport === 'windowsSpooler') {
      label(d.queueName);
      label(d.expectedDriverName);
      label(d.expectedPortName);
      if (d.host !== '' || d.port !== 0)
        throw new BadRequestException('Invalid spooler route');
    } else throw new BadRequestException('Unsupported transport');
    const p = object(
      x.profile,
      [
        'protocol',
        'paperWidthMm',
        'rasterWidthDots',
        'language',
        'cutter',
        'encoding',
      ],
      ['beep'],
    );
    integer(p.paperWidthMm, 40, 120);
    integer(p.rasterWidthDots, 64, 2048);
    if (
      p.protocol !== 1 ||
      integer(p.rasterWidthDots) % 8 ||
      p.language !== 'escposRaster' ||
      p.encoding !== 'georgianViaRaster' ||
      !['none', 'full', 'partial'].some((cutter) => cutter === p.cutter)
    )
      throw new BadRequestException('Unsupported profile');
    return x;
  });
  unique(printers.map((x) => x.id));
  unique(printers.map(endpoint));
  const stations = array(cat.stations, 64, 1).map((v) => {
    const x = object<Station>(
      v,
      ['id', 'name', 'role', 'scope', 'enabled', 'sortOrder', 'routes'],
      ['ownerDeviceId'],
    );
    id(x.id);
    label(x.name);
    label(x.role);
    bool(x.enabled);
    integer(x.sortOrder, -2147483647);
    if (
      !['LOCAL', 'VENUE_SHARED'].includes(x.scope) ||
      (x.scope === 'VENUE_SHARED' && (x.ownerDeviceId || count === 0))
    )
      throw new BadRequestException('Invalid station scope');
    if (x.scope === 'LOCAL') id(x.ownerDeviceId);
    const routes = array(x.routes, 8, 1).map(id);
    unique(routes);
    let profile = '';
    for (const route of routes) {
      const p = printers.find((p) => p.id === route);
      if (
        !p ||
        (x.scope === 'LOCAL' &&
          controllers.find((k) => k.id === p.controllerId)!.deviceId !==
            x.ownerDeviceId)
      )
        throw new BadRequestException('Foreign station route');
      // Compare semantic primary profile fields, including optional signal config.
      const next = JSON.stringify(
        Object.keys(p.profile)
          .sort()
          .map((k) => [k, p.profile[k]]),
      );
      if (profile && profile !== next)
        throw new BadRequestException('Incompatible backup profile');
      profile = next;
    }
    return x;
  });
  unique(stations.map((x) => x.id));
  const keys: string[] = [];
  for (const v of array(cat.rules, 2048)) {
    const x = object<Rule>(v, ['kind', 'matchId', 'stations'], ['orderType']);
    if (!['item', 'subcategory', 'category', 'default'].includes(x.kind))
      throw new BadRequestException('Invalid routing kind');
    if (x.kind === 'default') {
      if (x.matchId !== '') throw new BadRequestException('Invalid default');
    } else label(x.matchId);
    if (x.orderType !== undefined && x.orderType !== '') label(x.orderType);
    const ids = array(x.stations, 64, 1).map(id);
    unique(ids);
    if (ids.some((s) => !stations.some((x) => x.id === s)))
      throw new BadRequestException('Unknown station');
    keys.push(JSON.stringify([x.kind, x.matchId, x.orderType || '']));
  }
  unique(keys);
  if (Buffer.byteLength(JSON.stringify(c)) > 128 * 1024)
    throw new BadRequestException('Printer configuration too large');
  return c;
}
export function retainBindings(
  old: Record<string, string>,
  c: Configuration,
): Record<string, string> {
  const next = { ...old };
  const catalog = c.catalog;
  if (!catalog) return next;
  for (const p of catalog.printers) {
    const controller = catalog.controllers.find((x) => x.id === p.controllerId);
    if (!controller) throw new ConflictException('Unregistered controller');
    const binding = JSON.stringify([
      controller.id,
      controller.installationId,
      controller.deviceId,
      endpoint(p),
    ]);
    if (
      (next[p.id] && next[p.id] !== binding) ||
      Object.entries(next).some(
        ([key, value]) =>
          key !== p.id && (JSON.parse(value) as string[])[3] === endpoint(p),
      )
    )
      throw new ConflictException(
        'Physical ownership/endpoint replacement requires a separately qualified cutover',
      );
    next[p.id] = binding;
  }
  return next;
}
