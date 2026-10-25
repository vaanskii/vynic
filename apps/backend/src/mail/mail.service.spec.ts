import { ConfigService } from '@nestjs/config';
import { Logger } from '@nestjs/common';
import * as nodemailer from 'nodemailer';
import { mailConfiguration } from './mail-config';
import { MailService } from './mail.service';
jest.mock('nodemailer', () => ({ createTransport: jest.fn() }));

const env = {
  MAIL_ENABLED: 'true',
  MAIL_SMTP_HOST: 'smtp.gmail.com',
  MAIL_SMTP_PORT: '465',
  MAIL_AUTH_MODE: 'app-password',
  MAIL_USER: 'sender@unit.test',
  MAIL_FROM: 'sender@unit.test',
  MAIL_PUBLIC_ORIGIN: 'https://owner.unit.test',
  MAIL_APP_PASSWORD: 'abcdefghijklmnop',
};
const invitation = {
  id: 'invitation',
  email: 'owner@unit.test',
  organization: '<Vynic & Co>',
  path: '/invite#token=' + 'a'.repeat(43),
  expiresAt: new Date(Date.now() + 86400000),
};
describe('Google invitation sender (mock transport only)', () => {
  const sendMail = jest.fn<
    Promise<{ accepted: string[]; rejected: string[] }>,
    [nodemailer.SendMailOptions]
  >();
  const close = jest.fn();
  const create = jest.mocked(nodemailer.createTransport);
  const service = (overrides = {}) =>
    new MailService(new ConfigService({ ...env, ...overrides }));
  beforeEach(() => {
    jest.clearAllMocks();
    create.mockReturnValue({ sendMail, close } as unknown as ReturnType<
      typeof nodemailer.createTransport
    >);
    sendMail.mockResolvedValue({ accepted: [invitation.email], rejected: [] });
  });
  it.each([undefined, 'false'])(
    'does no work when disabled (%s)',
    async (MAIL_ENABLED) => {
      expect(
        (await service({ MAIL_ENABLED }).sendOwnerInvitation(invitation))
          .status,
      ).toBe('disabled');
      expect(create).not.toHaveBeenCalled();
    },
  );
  it.each([
    { MAIL_ENABLED: 'yes' },
    { MAIL_SMTP_HOST: 'smtp.invalid' },
    { MAIL_FROM: 'sender@sender.invalid' },
    { MAIL_USER: '' },
    { MAIL_APP_PASSWORD: 'replace-me.invalid' },
    { MAIL_APP_PASSWORD: 'account-password' },
    { MAIL_SMTP_PORT: '25' },
    { MAIL_PUBLIC_ORIGIN: 'https://owner.unit.test/invite' },
    { MAIL_PUBLIC_ORIGIN: 'http://owner.unit.test' },
    { MAIL_AUTH_MODE: 'oauth2' },
    { MAIL_FROM: 'sender@unit.test\r\nBcc: other@unit.test' },
  ])('fails closed with nonsecret config errors: %o', async (overrides) => {
    const result = await service(overrides).sendOwnerInvitation(invitation);
    expect(result.status).toBe('misconfigured');
    expect(create).not.toHaveBeenCalled();
    expect(JSON.stringify(result)).not.toContain(env.MAIL_APP_PASSWORD);
  });
  it('uses mandatory TLS, one envelope recipient and a plaintext private fragment link', async () => {
    expect((await service().sendOwnerInvitation(invitation)).status).toBe(
      'accepted',
    );
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        secure: true,
        requireTLS: true,
        logger: false,
        debug: false,
        tls: { minVersion: 'TLSv1.2', rejectUnauthorized: true },
      }),
    );
    expect(sendMail).toHaveBeenCalledWith(
      expect.objectContaining({
        envelope: { from: env.MAIL_FROM, to: [invitation.email] },
        disableFileAccess: true,
        disableUrlAccess: true,
      }),
    );
    expect(sendMail.mock.calls[0][0].text).toContain(
      env.MAIL_PUBLIC_ORIGIN + invitation.path,
    );
    expect(sendMail.mock.calls[0][0].html).toBeUndefined();
    expect(close).toHaveBeenCalledTimes(1);
  });
  it('supports OAuth2 and STARTTLS without startup auth/network verification', () => {
    const settings = mailConfiguration({
      ...env,
      MAIL_SMTP_PORT: '587',
      MAIL_AUTH_MODE: 'oauth2',
      MAIL_OAUTH_CLIENT_ID: 'synthetic-client',
      MAIL_OAUTH_CLIENT_SECRET: 'synthetic-secret',
      MAIL_OAUTH_REFRESH_TOKEN: 'synthetic-refresh',
    });
    expect(settings).toMatchObject({
      status: 'ready',
      transport: {
        secure: false,
        requireTLS: true,
        auth: {
          type: 'OAuth2',
          user: env.MAIL_USER,
          refreshToken: 'synthetic-refresh',
        },
      },
    });
    expect(create).not.toHaveBeenCalled();
  });
  it.each([
    'owner@unit.test,other@unit.test',
    'Name <owner@unit.test>',
    'owner@test.invalid',
    'owner@unit.test\r\nBcc:x@unit.test',
  ])('rejects unsafe recipient %s', async (email) => {
    expect(
      (await service().sendOwnerInvitation({ ...invitation, email })).status,
    ).toBe('skipped');
    expect(create).not.toHaveBeenCalled();
  });
  it('does not claim success for an unaccepted recipient', async () => {
    sendMail.mockResolvedValue({ accepted: [], rejected: [invitation.email] });
    expect((await service().sendOwnerInvitation(invitation)).status).toBe(
      'failed',
    );
  });
  it.each([
    ['EAUTH', 'failed'],
    ['EENVELOPE', 'failed'],
    ['ETIMEDOUT', 'unknown'],
    ['ECONNECTION', 'unknown'],
  ])('sanitizes %s and never retries', async (code, status) => {
    const log = jest
      .spyOn(Logger.prototype, 'warn')
      .mockImplementation(() => undefined);
    sendMail.mockRejectedValue({
      code,
      message: env.MAIL_APP_PASSWORD + invitation.path + invitation.email,
      response: 'secret-response',
    });
    const result = await service().sendOwnerInvitation(invitation);
    expect(result.status).toBe(status);
    expect(sendMail).toHaveBeenCalledTimes(1);
    for (const secret of [
      env.MAIL_APP_PASSWORD,
      invitation.path,
      invitation.email,
      'secret-response',
    ])
      expect(JSON.stringify([result, log.mock.calls])).not.toContain(secret);
    log.mockRestore();
  });
});
