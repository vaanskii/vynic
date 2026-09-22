# Website Phase W1 — Venue payment integrations

## Boundary and model

`apps/venue-web` remains the CUSTOM Vankisi site; shared NestJS handles BOG.
No generic SaaS site, Go Edge payment callback, POS authority or Manager change.

`pos.PaymentIntegration` holds BOG credential revisions, each owned by a Venue.
A partial unique index allows one enabled revision per Venue/provider. Updates
serialize on the Venue row, disable the previous revision and insert a new one.
`website.reservations.paymentIntegrationId` plus its Venue forms a composite FK:
a payment cannot reference another Venue's credentials even through a bad write.
Historical revisions remain encrypted for outstanding receipt checks. Disconnect
stops new payments without deleting historical payment authority.

Browser creation resolves Host -> registered active VenueDomain -> Venue,
requires WEBSITE through the existing guard, and ONLINE_PAYMENTS through the
shared entitlement service before inserting a booking. Both booking entry points
use the same reservation service. BOG receives that Venue's selected revision.
Browser status also requires the matching Host and stored payment ID; it is not
commercially gated so existing payments can settle. Signed callbacks have no
host/commercial gate; stored reservation/payment identity establishes the Venue.
Existing raw-body RSA verification is unchanged. Mismatched stored bank IDs fail.
An early signed callback may bind the bank ID before the order response arrives.

## Encryption and key management

AES-256-GCM; fresh 96-bit nonce per revision, 128-bit authentication tag, versioned
`v1` envelope. Associated data binds provider, Venue and revision ID. Copying a
ciphertext to another Venue/revision, tampering, wrong or absent keys fails closed.
`PAYMENT_INTEGRATION_MASTER_KEY` is exactly 32 random bytes encoded as 64 hex
characters, supplied by the deployment secret manager. There is no development
fallback key. Credentials and return origin are encrypted together. API status
selects only provider/configured/entitled/revision/timestamp; neither client ID,
secret nor ciphertext is returned. Owner forms clear both inputs after saving.

Back up the key separately from the database, restrict both to the backend, and
ensure request-body/APM capture is disabled/redacted on payment-settings routes.
The application does not log credential bodies; adapter errors discard Axios
request/header payloads and provider error text. Losing the key makes all stored
revisions unreadable. Do not simply replace it: rotation requires a controlled
maintenance re-encryption of **all** revisions (including disabled historical
ones), with old-key backup, validation and atomic cutover across backend workers.
Automated master-key rotation is not implemented by W1.

## Controls and entitlement

CustomerAccount -> Organization -> Venue ownership guards GET/PUT
`/customer/venues/:venueId/payments/bog` and POST `.../disable`. Save requires both
Client ID and Client Secret plus a website return origin belonging to an active
VenueDomain. HTTPS is required except registered localhost names in development.
The origin is rechecked for new payments; arbitrary provider/API URLs are never
accepted. Owners may configure before commercial activation. Saves/disconnects
write CustomerAuditEvent in the same transaction, with provider/revision only.

Platform GET `/platform/venues/:venueId/payments/bog` returns safe status. Existing
Product access controls manage ONLINE_PAYMENTS as a normal feature, including
plan/override/subscription precedence. No plan is automatically granted it.
Website mode CUSTOM/SAAS and WEBSITE remain independent. The Platform Website
panel shows status; owners see Georgian online-payment settings. No connection
check button is added: W1 preserves the existing BOG adapter without introducing
a new live-bank validation workflow. Configured status does not certify bank acceptance.

## Environment inventory

| Existing value | Classification and action |
| --- | --- |
| BOG_CLIENT_ID | Venue credential; runtime use removed, explicit import only, retire from service env after rollout |
| BOG_CLIENT_SECRET | Venue secret; runtime use removed, explicit import only, retire after rollout |
| FRONTEND_URL | Shared website deployment setting still used elsewhere; no longer BOG redirect authority. Import-only fallback for returnOrigin |
| API_URL | Keep deployment callback origin; no merchant authority |
| PORT | Keep deployment listener/local callback fallback |
| BOG token/order/receipt URLs and RSA public key | Existing fixed provider constants; remain Cloud-side |
| PAYMENT_INTEGRATION_MASTER_KEY | New deployment secret; never stored in Prisma |
| BOG_RETURN_ORIGIN | Optional import-only override for legacy FRONTEND_URL; not a runtime key |

Only two legacy BOG credential keys were found in backend runtime/config checks.
No merchant-ID or additional BOG secret field is required by the existing adapter.
No actual secret files or production credential values are needed for this audit.

## Controlled legacy import and rollout

1. Provision the master key and backup policy. Register the Venue's active domain.
2. Stop/drain new website payment creation during the cutover; preserve callback
   delivery/retries. Apply schema migration `20260924120000_venue_payment_integrations`.
   The migration creates structures and the feature only, never reads secrets.
3. Explicitly supply DATABASE_URL, PAYMENT_INTEGRATION_MASTER_KEY, BOG_CLIENT_ID,
   BOG_CLIENT_SECRET and BOG_RETURN_ORIGIN (or legacy FRONTEND_URL) from the
   operator's controlled environment. The command does not source a legacy env
   file; it requires explicit inputs before loading application dependencies.
4. From `apps/backend`, run:

   ```sh
   node -r ts-node/register/transpile-only scripts/import-bog-integration.ts VENUE_UUID OPERATOR_ID --confirm-import
   ```

   The command intentionally refuses `vankisi_database`. Production access was
   prohibited for W1; any production-specific execution must be separately
   authorized and that explicit guard reviewed before rollout. Do not work around it.
5. First import creates one encrypted revision, associates the selected Venue's
   existing bank-ID-bearing bookings, and atomically audits `payment_integration.imported`.
   Same enabled config is a no-op on repetition. Different credentials or a
   disabled existing integration fail rather than overwrite/reactivate.
6. Enable ONLINE_PAYMENTS explicitly via Platform. Verify the correct CUSTOM
   hostname, HTTPS callback/return origins, reverse proxy Host handling and a
   controlled bank payment/status/callback. Resume new payments only after this.
7. Remove old BOG credentials from the service environment after validation.
   Keep prior bank credentials valid until historical payments settle. A bank-side
   revocation can prevent old receipt polling despite retained encrypted revisions;
   signed callbacks still work independently of OAuth credentials.

Never run a credential import as an automatic deploy hook. Retry/import stdout
contains only generic success/failure, not credentials. Local fixtures use fake
credentials and mock BOG network calls; no bank or production request was made.

## Repeatable local proof

Initialize disposable PostgreSQL on loopback port 55439, database
`vynic_w1_disposable`. Use an explicit local DATABASE_URL for `prisma migrate deploy`.
Never use the default environment database for validation.

```sh
W1_TEST_DATABASE_URL=postgresql://LOCAL_USER@127.0.0.1:55439/vynic_w1_disposable \
  npm test -- --runInBand payment-integrations
```

The suite validates the URL before connecting. Real PostgreSQL, Nest HTTP, owner
JWT guards, Host guards, entitlement resolution, Prisma composite tenancy and
reservation services are exercised. BOG HTTP and the operational bridge are mocked;
only the successful callback signature verifier is stubbed (bank private key is
unavailable). Invalid signature rejection exercises the unchanged real verifier.
Proof covers cross-owner reads/writes/disconnect, ciphertext tenancy, Host vs body
Venue authority, entitlement/disable denial, original revision after rotation,
callback original Venue and bank-ID mismatch, safe provider failures, audited
updates/disconnect and idempotent subprocess import with legacy payment binding.
Unit tests additionally cover tampering, nonce randomness, wrong/malformed keys.
Portal tests cover save/clear/disconnect, failure/retry, and existing owner/Platform
website flows. Builds and targeted entitlement/Host regression tests are required.

## Exact prerequisites before Phase W2

- Define and approve W2 scope: separate generic SaaS website versus custom-site
  runtime/deployment management. Neither is implied by W1.
- Preserve CUSTOM Vankisi deployment and Host authority; define the separate SAAS
  application's routing, domain/TLS verification, reverse-proxy trust and origins.
- Establish production key backup/recovery and rotation procedure; separately
  authorize production credential import/cutover and complete real BOG acceptance.
- Resolve subscription/feature assignments explicitly: WEBSITE, WebsiteMode and
  ONLINE_PAYMENTS must stay independent from integration configuration.
- Define public content/menu/table contracts and privacy/auth boundaries for the
  chosen W2 scope. Existing global WebsiteUser ownership is not solved here.
- Address transactional reservation holds before promising contention-safe booking;
  current availability checks remain non-transactional.
- Keep merchant authority/callback settlement Cloud-side; any operational delivery
  uses the existing durable Venue command path, without adding legacy callbacks.

W1 stops here. W2 is not implemented or deployed.
