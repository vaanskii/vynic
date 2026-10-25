import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import type SMTPTransport from 'nodemailer/lib/smtp-transport';
import { mailConfiguration, mailbox, MailEnvironment } from './mail-config';
import { ownerInvitationText } from './owner-invitation-template';

export type MailResult = {
  status:
    | 'disabled'
    | 'misconfigured'
    | 'accepted'
    | 'failed'
    | 'unknown'
    | 'skipped';
  diagnostic: string;
};
export type InvitationMail = {
  id: string;
  email: string;
  organization: string;
  path: string;
  expiresAt: Date;
};

@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  constructor(private readonly config: ConfigService) {}

  async sendOwnerInvitation(invitation: InvitationMail): Promise<MailResult> {
    const env: MailEnvironment = {};
    for (const key of [
      'MAIL_ENABLED',
      'MAIL_SMTP_HOST',
      'MAIL_SMTP_PORT',
      'MAIL_AUTH_MODE',
      'MAIL_USER',
      'MAIL_FROM',
      'MAIL_PUBLIC_ORIGIN',
      'MAIL_APP_PASSWORD',
      'MAIL_OAUTH_CLIENT_ID',
      'MAIL_OAUTH_CLIENT_SECRET',
      'MAIL_OAUTH_REFRESH_TOKEN',
    ])
      env[key] = this.config.get<string>(key);
    const settings = mailConfiguration(env);
    if (settings.status !== 'ready') return settings;
    if (
      !mailbox(invitation.email) ||
      /\.invalid$/i.test(invitation.email) ||
      !/^\/invite#token=[A-Za-z0-9_-]{43}$/.test(invitation.path) ||
      !Number.isFinite(invitation.expiresAt.getTime()) ||
      invitation.expiresAt <= new Date()
    )
      return {
        status: 'skipped',
        diagnostic:
          'Invitation recipient, link or expiry is not valid for sending.',
      };
    let transport:
      | nodemailer.Transporter<SMTPTransport.SentMessageInfo>
      | undefined;
    try {
      transport = nodemailer.createTransport(settings.transport);
      const info = await transport.sendMail({
        from: { name: 'Vynic', address: settings.from },
        to: { address: invitation.email, name: '' },
        envelope: { from: settings.from, to: [invitation.email] },
        subject: 'Vynic — მფლობელის მოწვევა / Owner invitation',
        text: ownerInvitationText(
          invitation.organization,
          settings.origin + invitation.path,
          invitation.expiresAt,
        ),
        disableFileAccess: true,
        disableUrlAccess: true,
      });
      if (
        info.accepted?.some(
          (address) => address.toLowerCase() === invitation.email.toLowerCase(),
        ) &&
        !info.rejected?.length
      )
        return {
          status: 'accepted',
          diagnostic:
            'Google accepted the email for delivery; inbox delivery is not confirmed.',
        };
      return {
        status: 'failed',
        diagnostic:
          'Google did not accept the recipient. Share the link manually or review sender settings.',
      };
    } catch (error: unknown) {
      // Never expose SMTP responses, tokens, message content or recipient addresses.
      const code =
        error && typeof error === 'object' && 'code' in error
          ? error.code
          : undefined;
      const definite = code === 'EAUTH' || code === 'EENVELOPE';
      this.logger.warn(
        definite
          ? 'Invitation email rejected; check mail configuration.'
          : 'Invitation email outcome unknown; no automatic retry.',
      );
      return definite
        ? {
            status: 'failed',
            diagnostic:
              'Mail authentication or recipient rejected. Check Google authorization and sender settings.',
          }
        : {
            status: 'unknown',
            diagnostic:
              'Mail submission could not be confirmed. No automatic retry; share this link or regenerate explicitly.',
          };
    } finally {
      transport?.close();
    }
  }
}
