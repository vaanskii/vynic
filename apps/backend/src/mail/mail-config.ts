import { isEmail } from 'class-validator';
import type SMTPTransport from 'nodemailer/lib/smtp-transport';

export type MailEnvironment = Record<string, string | undefined>;
export type MailConfiguration =
  | { status: 'disabled' | 'misconfigured'; diagnostic: string }
  | {
      status: 'ready';
      from: string;
      origin: string;
      transport: SMTPTransport.Options;
    };

export function mailbox(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length <= 254 &&
    !/[\r\n,;<>]/.test(value) &&
    isEmail(value, { allow_display_name: false })
  );
}
const placeholder = (value: string) =>
  /\.invalid(?:\b|$)|placeholder|change[-_ ]?me|replace[-_ ]?me|example\.(com|org|net)/i.test(
    value,
  );

export function mailConfiguration(env: MailEnvironment): MailConfiguration {
  if (!env.MAIL_ENABLED || env.MAIL_ENABLED === 'false')
    return {
      status: 'disabled',
      diagnostic: 'MAIL_ENABLED=false; share the invitation link manually.',
    };
  const invalid = (diagnostic: string): MailConfiguration => ({
    status: 'misconfigured',
    diagnostic,
  });
  if (env.MAIL_ENABLED !== 'true')
    return invalid('MAIL_ENABLED must be true or false.');
  const required = [
    'MAIL_SMTP_HOST',
    'MAIL_SMTP_PORT',
    'MAIL_AUTH_MODE',
    'MAIL_USER',
    'MAIL_FROM',
    'MAIL_PUBLIC_ORIGIN',
  ];
  if (env.MAIL_AUTH_MODE === 'app-password') required.push('MAIL_APP_PASSWORD');
  else if (env.MAIL_AUTH_MODE === 'oauth2')
    required.push(
      'MAIL_OAUTH_CLIENT_ID',
      'MAIL_OAUTH_CLIENT_SECRET',
      'MAIL_OAUTH_REFRESH_TOKEN',
    );
  else return invalid('Set MAIL_AUTH_MODE to app-password or oauth2.');
  const missing = required.filter(
    (key) => !env[key]?.trim() || placeholder(env[key]),
  );
  if (missing.length)
    return invalid(
      'Replace missing or placeholder settings: ' + missing.join(', ') + '.',
    );
  if (
    env.MAIL_SMTP_HOST !== 'smtp.gmail.com' ||
    !['465', '587'].includes(env.MAIL_SMTP_PORT!)
  )
    return invalid('Use smtp.gmail.com with port 465 (TLS) or 587 (STARTTLS).');
  if (!mailbox(env.MAIL_USER) || !mailbox(env.MAIL_FROM))
    return invalid('MAIL_USER and MAIL_FROM must each be one mailbox address.');
  let origin: URL;
  try {
    origin = new URL(env.MAIL_PUBLIC_ORIGIN!);
  } catch {
    return invalid('MAIL_PUBLIC_ORIGIN must be the HTTPS owner portal origin.');
  }
  if (
    origin.protocol !== 'https:' ||
    origin.username ||
    origin.password ||
    origin.pathname !== '/' ||
    origin.search ||
    origin.hash
  )
    return invalid(
      'MAIL_PUBLIC_ORIGIN must be an HTTPS origin without credentials, path, query or fragment.',
    );
  const auth: SMTPTransport.Options['auth'] =
    env.MAIL_AUTH_MODE === 'oauth2'
      ? {
          type: 'OAuth2',
          user: env.MAIL_USER,
          clientId: env.MAIL_OAUTH_CLIENT_ID,
          clientSecret: env.MAIL_OAUTH_CLIENT_SECRET,
          refreshToken: env.MAIL_OAUTH_REFRESH_TOKEN,
        }
      : {
          user: env.MAIL_USER,
          pass: env.MAIL_APP_PASSWORD!.replace(/\s/g, ''),
        };
  if (
    env.MAIL_AUTH_MODE === 'app-password' &&
    !/^[a-z]{16}$/i.test((auth as { pass: string }).pass)
  )
    return invalid(
      'MAIL_APP_PASSWORD must be a Google 16-letter app password, not the account password.',
    );
  return {
    status: 'ready',
    from: env.MAIL_FROM,
    origin: origin.origin,
    transport: {
      host: 'smtp.gmail.com',
      port: Number(env.MAIL_SMTP_PORT),
      secure: env.MAIL_SMTP_PORT === '465',
      requireTLS: true,
      tls: { minVersion: 'TLSv1.2', rejectUnauthorized: true },
      auth,
      connectionTimeout: 10000,
      greetingTimeout: 10000,
      socketTimeout: 20000,
      logger: false,
      debug: false,
      disableFileAccess: true,
      disableUrlAccess: true,
    },
  };
}
