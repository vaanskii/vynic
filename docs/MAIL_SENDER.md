# Owner invitation mail

Mail is **disabled by default**. `apps/backend/.env.example`, `.env.docker.example`, and `.env.production.example` contain only nonworking mail `.invalid` values. `compose.yaml` passes these backend-only settings through with disabled/placeholder defaults. No real credentials, OAuth consent, external email, production configuration, deployment, or domain changes were performed for this implementation.

## Implemented scope

`src/mail/` provides the NestJS mail module, Google SMTP configuration validator, plain-text Georgian/English owner invitation template, and Nodemailer transport. The backend uses the module from CustomerModule. Node 20+ is required by Nodemailer; the existing backend image uses Node 22.

Existing authorized Platform operations now attempt email after their database transaction commits:

- manual invitation creation;
- explicit regeneration (revokes the previous invitation);
- assisted customer/Organization/Venue provisioning;
- approval of a public access request, after the outer approval transaction commits.

There were no existing SMTP abstractions, mail templates, enabled flags or other email send callsites in the baseline. This does not add marketing, receipts, payment confirmations, staff emails or password reset. Public lost-link requests remain enumeration-safe operator review requests; only an operator regeneration sends a replacement. Rejections and existing-owner trial approvals do not create or send invitations.

The invitation recipient, organization and expiry come from the persisted invitation. Before sending, the service checks its ID, organization, recipient, token hash, acceptance, revocation and expiry. Request-supplied Host is never used in the email URL. Existing Platform guards and admission limits remain in place. Recipients must be a single mailbox, with no display-name syntax or header injection. `.invalid` recipients never reach the transport.

## Result and recovery contract

Issuance responses retain `invitation` and `invitationPath`, and add `mail: { status, diagnostic }`. Access-request approval returns this under `prepared.mail`. Platform screens show the result alongside the copyable private link.

| Status | Meaning / operator action |
| --- | --- |
| `disabled` | No transport was created. Share the link manually. |
| `misconfigured` | Missing, invalid or placeholder configuration; no transport created. API diagnostics name settings, never their values. Fix configuration or share manually. |
| `accepted` | Google accepted the envelope recipient; inbox delivery is **not confirmed**. |
| `failed` | Authentication/envelope rejection or no recipient acceptance. Review Google authorization and sender settings. |
| `unknown` | Submission could not be confirmed, including connection/timeouts. Share the existing link or regenerate explicitly after review. |
| `skipped` | Invitation changed/expired or recipient/link is invalid. Review before sharing. |

Mail failure does not roll back committed provisioning or return an HTTP failure that encourages duplicate provisioning. No application retry, scheduled queue, outbox or durable delivery history is added. One send is attempted per successful issuance operation. A process crash between commit and SMTP can leave an unsent invitation; the operator can use the existing audited, rate-limited regeneration action. Explicit regeneration sends a new token and invalidates the previous one. A repeat approval is rejected before sending. Arbitrary duplicate HTTP creation requests are not idempotent and can issue replacements, as before; clients must not blindly retry creation after a lost HTTP response.

SMTP cannot prove exactly-once delivery after a lost acknowledgement. Nodemailer may refresh/retry OAuth authentication before message submission; Vynic does not retry a message submission. Concurrent regeneration can still invalidate a link already submitted to Google; acceptance always rechecks invitation validity. This synchronous manual-recovery policy preserves the existing token-hash-only persistence boundary instead of storing raw bearer tokens for a new outbox.

Provider errors, response text, recipient addresses, email body and credentials are not logged or returned. Transport debug logging and attachment URL/file access are disabled. TLS certificate verification is mandatory; ports 465 and 587 are the only supported ports. The module does not connect or verify credentials on application startup.

## Later Google setup (operator-owned; not performed)

1. Choose the actual sending Google mailbox and owner portal HTTPS origin. Personal Gmail and Google Workspace account policy differ; neither account type nor sender address is assumed. Set `MAIL_USER` to that mailbox and `MAIL_FROM` to it or a verified Google Send As identity. Google may rewrite unauthorized From addresses. This implementation uses `smtp.gmail.com`, not Workspace SMTP Relay or a service account.
2. Keep `MAIL_ENABLED=false` while replacing placeholders. Set `MAIL_SMTP_HOST=smtp.gmail.com`; choose `MAIL_SMTP_PORT=465` for implicit TLS or `587` for mandatory STARTTLS. Set `MAIL_PUBLIC_ORIGIN` to the exact owner-facing HTTPS origin, without path, query, fragment or credentials; never the internal admin origin.
3. Choose **one** authorization mode:
   - `MAIL_AUTH_MODE=app-password`: if the account policy permits app passwords, enable 2-Step Verification and create a dedicated Google app password. Store its 16 letters in `MAIL_APP_PASSWORD` (spaces are accepted and removed). Do not use the ordinary Google account password. See [Google app-password instructions](https://support.google.com/accounts/answer/185833?hl=en).
   - `MAIL_AUTH_MODE=oauth2`: configure an operator-owned Google OAuth client and consent policy, authorize the selected mailbox with offline access and SMTP scope `https://mail.google.com/`, and store `MAIL_OAUTH_CLIENT_ID`, `MAIL_OAUTH_CLIENT_SECRET`, and `MAIL_OAUTH_REFRESH_TOKEN`. Nodemailer refreshes access tokens at send time. Confirm consent publication/testing restrictions and Workspace policy before use. No OAuth callback or consent UI is added to Vynic. See [Nodemailer OAuth2 configuration](https://nodemailer.com/smtp/oauth2).
4. Store credentials only in the backend's secret manager/local untracked configuration. Never use `VITE_` variables or commit credentials. `GOOGLE_APPLICATION_CREDENTIALS` is existing Firebase configuration and is unrelated to this sender. Clear unused mode credentials if appropriate.
5. For a custom domain, its administrator must verify the selected sender/domain and configure SPF, DKIM and DMARC for the actual Google arrangement. No DNS setup is inferred or performed. See [Google Workspace email authentication](https://support.google.com/a/answer/81126?hl=en).
6. In a separately authorized delivery test, enable `MAIL_ENABLED=true`, restart the backend with the new configuration, and issue one synthetic invitation to a mailbox you control. Check the returned status, inbox/spam, sender identity, link origin and authentication headers. SMTP acceptance is insufficient proof of deliverability. Disable again if configuration is incomplete. Existing unsent invitations are not automatically replayed when enabled; regenerate explicitly if needed.

Google policies and sending limits apply; see [Nodemailer Gmail guidance](https://nodemailer.com/guides/using-gmail). The transport is intended for the existing low-volume transactional invitation workflow.

## Validation on 2026-10-25

- `npm run build` and `npx tsc --noEmit` in backend: passed.
- ESLint for all new mail sources/tests and the new mail integration suite: passed. Changed customer services retain exactly three pre-existing `no-base-to-string` findings, reproduced on untouched `bf7bd647` (two in onboarding-requests, one in owner-invitations).
- Six backend suites: **81 passed**. New sender tests cover disabled/missing/placeholder settings, OAuth2/TLS options, one recipient, injection rejection, acceptance/rejection, sanitized diagnostics and no application retry. New real PostgreSQL tests cover post-commit visibility, nested rollback, mail failure with committed data, explicit regeneration, stale/token/organization/recipient checks and anonymous recovery. Existing protected onboarding, applicant-name, commercial-access and subscription lifecycle suites pass.
- Platform web: **19 tests passed** across mail-status, owner-invitations and commercial-hardening; production build/typecheck passed. ESLint for changed production UI files and mail-status tests passed. Existing Vite chunk-size advisory remains.
- Legacy `owner-invitations.integration.spec.ts`: **3 passed / 4 failed**, identical on untouched `bf7bd647`. The suite expects implicit TRIAL and permitted public signup, contrary to the current NO_PLAN/invitation-only product; two downstream failures depend on its failed signup setup. This suite was not rewritten for mail.
- `docker compose -f compose.yaml config --quiet` with synthetic required settings: passed (configuration validation only; no containers started).
- `git diff --check`: passed. No schema changes or new migrations.

Tests used a newly initialized loopback PostgreSQL cluster on port 55443, database `disposable_mail_sender`, with synthetic fixtures. The unchanged-baseline check used `disposable_mail_baseline`. Existing migrations were applied only to these disposable databases. All mail was mocked or disabled; no external email or OAuth was invoked.

Reproduce selected backend suites with a **fresh, migrated disposable database** and these synthetic test settings (substitute your disposable URL):

```sh
SAAS_WEBSITE_BASE_DOMAIN=saas.vynic.test \
COOKIE_ENCRYPTION_KEY=synthetic-mail-test-cookie-key \
MAIL_TEST_DATABASE_URL="$DISPOSABLE_MAIL_DATABASE_URL" \
PROTECTED_ONBOARDING_TEST_DATABASE_URL="$DISPOSABLE_MAIL_DATABASE_URL" \
COMMERCIAL_TEST_DATABASE_URL="$DISPOSABLE_MAIL_DATABASE_URL" \
npx jest --runInBand \
  src/mail/mail.service.spec.ts \
  src/customer/owner-invitations-name.spec.ts \
  src/customer/owner-invitation-mail.integration.spec.ts \
  src/customer/protected-onboarding.integration.spec.ts \
  src/customer/commercial-access.integration.spec.ts \
  src/subscriptions/subscription.integration.spec.ts
```

The fixture explicitly injects disabled mail; the new integration suite injects a mock. Neither reads live mail credentials. Integration prerequisites are synthetic cookie/signing settings, a configured test SaaS hostname, and database migrations. Do not point these tests at business data.
