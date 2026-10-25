import { InstallerDownloadsService } from './installer-downloads.service';
import {
  installerObjectKey,
  installerRange,
  requireInstallerGateway,
  workerRequest,
} from './installer-worker-gateway';
import { secretHash } from './security-admission';
const id = '12345678-1234-1234-1234-123456789abc',
  token = 'a'.repeat(43),
  key =
    'windows/beta/1.0.1/build18/Vynic-Windows-1.0.1-build18-beta-offline.zip';
const old = { ...process.env };
afterEach(() => {
  process.env = { ...old };
  jest.restoreAllMocks();
});
function fixture() {
  process.env.VYNIC_INSTALLER_STORAGE = 'r2-worker';
  process.env.VYNIC_INSTALLER_R2_KEY = key;
  process.env.VYNIC_INSTALLER_BYTES = '5';
  process.env.VYNIC_INSTALLER_SHA256 = 'c'.repeat(64);
  process.env.VYNIC_INSTALLER_WORKER_ORIGIN = 'https://releases.vynic.ge';
  process.env.VYNIC_DOWNLOAD_GATEWAY_SECRET = 'b'.repeat(43);
  const grant = {
    id,
    artifactId: 'r2:' + key,
    artifactBytes: 5,
    artifactSha256: 'c'.repeat(64),
    expiresAt: new Date(Date.now() + 60000),
    revokedAt: null,
    platformUserId: 'actor',
    requestCount: 1,
  };
  const db: any = {
    securityAdmission: { deleteMany: jest.fn() },
    installerDownloadGrant: {
      findUnique: jest.fn().mockResolvedValue(grant),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    platformAuditEvent: { create: jest.fn() },
    platformUser: { findFirst: jest.fn().mockResolvedValue({ id: 'actor' }) },
    $queryRaw: jest.fn().mockResolvedValue([{ count: 1 }]),
  };
  return { s: new InstallerDownloadsService(db), db, grant };
}
test('key and range validation binds version/build and single bounded range', () => {
  expect(installerObjectKey(key)).toBe(true);
  expect(installerObjectKey(key.replace('build18-beta', 'build19-beta'))).toBe(
    false,
  );
  expect(installerRange('bytes=1-', 5)).toEqual({
    start: 1,
    end: 4,
    partial: true,
  });
  for (const r of ['bytes=-1', 'bytes=0-1,2-3', 'bytes=5-', 'bytes=2-1'])
    expect(() => installerRange(r, 5)).toThrow();
});
test('machine secret required, malformed/unconfigured secrets fail closed', () => {
  expect(() => requireInstallerGateway(undefined)).toThrow();
  process.env.VYNIC_DOWNLOAD_GATEWAY_SECRET = 'b'.repeat(43);
  expect(() => requireInstallerGateway('Bearer ' + token)).toThrow();
  expect(() =>
    requireInstallerGateway('Bearer ' + 'b'.repeat(43)),
  ).not.toThrow();
});
test('gateway shape excludes caller-selected objects and bad IP', () => {
  const r = {
    operation: 'file',
    id,
    token,
    clientIp: '192.0.2.1',
    method: 'HEAD',
  };
  expect(workerRequest(r).method).toBe('HEAD');
  for (const change of [
    { key },
    { clientIp: 'unknown' },
    { operation: '__proto__' },
    { token: 'bad' },
    { method: 'PUT' },
  ])
    expect(() => workerRequest({ ...r, ...change })).toThrow();
});
test('r2 configuration requires exact protected origin, secret and immutable artifact', () => {
  const { s } = fixture();
  expect(s.configuration().ready).toBe(true);
  delete process.env.VYNIC_DOWNLOAD_GATEWAY_SECRET;
  expect(s.configuration().ready).toBe(false);
  process.env.VYNIC_INSTALLER_STORAGE = 'typo';
  expect(s.configuration().ready).toBe(false);
});
test('HEAD and GET call live resolution; only GET consumes grant and audits', async () => {
  const { s, db } = fixture();
  const resolve = jest.spyOn(s, 'resolve');
  const request = {
    operation: 'file' as const,
    id,
    token,
    clientIp: '192.0.2.1',
    method: 'HEAD' as const,
  };
  expect(await s.workerDecision(request)).toMatchObject({
    key,
    bytes: 5,
    start: 0,
    end: 4,
  });
  expect(resolve).toHaveBeenCalledWith(token, request.clientIp, id);
  expect(db.platformUser.findFirst).toHaveBeenCalled();
  expect(db.installerDownloadGrant.updateMany).not.toHaveBeenCalled();
  await s.workerDecision({ ...request, method: 'GET', range: 'bytes=1-3' });
  expect(db.installerDownloadGrant.updateMany).toHaveBeenCalledWith(
    expect.objectContaining({
      where: expect.objectContaining({
        requestCount: { lt: 16 },
        revokedAt: null,
      }),
    }),
  );
  expect(db.platformAuditEvent.create).toHaveBeenCalledWith(
    expect.objectContaining({
      data: expect.objectContaining({ action: 'installer_download.started' }),
    }),
  );
});
test('revocation, actor suspension, changed artifact and exhausted quota deny file', async () => {
  for (const reason of ['revoke', 'actor', 'artifact', 'quota']) {
    const { s, db, grant } = fixture();
    if (reason === 'revoke') grant.revokedAt = new Date() as any;
    if (reason === 'actor') db.platformUser.findFirst.mockResolvedValue(null);
    if (reason === 'artifact') grant.artifactSha256 = 'd'.repeat(64);
    if (reason === 'quota')
      db.installerDownloadGrant.updateMany.mockResolvedValue({ count: 0 });
    await expect(
      s.workerDecision({
        operation: 'file',
        id,
        token,
        clientIp: '192.0.2.1',
        method: 'GET',
      }),
    ).rejects.toThrow();
  }
});
test('legacy proxy does not read bytes in Worker mode', async () => {
  const { s } = fixture();
  const resolve = jest.spyOn(s, 'resolve');
  await expect(s.stream(token, {} as any, {} as any, id)).rejects.toThrow();
  expect(resolve).not.toHaveBeenCalled();
});
test('outcome checks capability verifier and fixed artifact without returning data', async () => {
  const { s, db } = fixture();
  expect(
    await s.workerDecision({
      operation: 'outcome',
      id,
      token,
      clientIp: '192.0.2.1',
      outcome: 'completed',
    }),
  ).toEqual({ recorded: true });
  expect(db.installerDownloadGrant.findUnique).toHaveBeenCalledWith({
    where: { tokenHash: secretHash(token) },
  });
});
