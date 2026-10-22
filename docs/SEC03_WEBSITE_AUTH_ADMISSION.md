# SEC-03 — Website authentication request admission

Source and isolated-test qualification. This completes the bounded-input and
attempt-admission portion of SEC-03; the full security milestone remains open.

## Current behavior

- `/api/auth` JSON and form bodies are limited to 8 KiB before the general
  50 MiB POS/webhook parsers. Forms allow at most 12 parameters. Oversized input
  returns 413. The general parser still preserves webhook raw bytes.
- Sign-in identifiers and registration emails: at most 320 characters;
  registration phone: 64; optional first/last name: 120 each. Password fields
  must be strings of at most 512 characters. Existing minimums remain: six
  characters for new passwords; nonempty for sign-in/current passwords.
  Password bytes are preserved, including spaces.
- HTTP DTO validation rejects malformed/extra fields with 400. The service
  repeats the same validation for internal callers before account lookup,
  Argon hashing/verification or writes; errors never include rejected secrets.
- Signup, signin and password changes require a matching generated 64-character
  hexadecimal CSRF header/cookie. Missing, malformed or mismatched values return
  403 before signup/signin/password-change service work or attempt admission.
  The existing authenticated cookie guard resolves password-change users first.
- A shared website-auth peer window permits 20 valid attempts in 15 minutes.
  Normalized identifiers permit 10: email trim/lowercase matches lookup; phone
  trim matches lookup. Signup spends both email and phone windows, and signin
  uses the same identifier namespace. Global WebsiteUser identity means these
  windows span restaurant Hosts. Phone and email remain distinct aliases.
- Password changes have a 10-attempt window for the authenticated server-owned
  user ID, plus the same peer window. The existing cookie guard runs first.
- Every admitted attempt counts, including successful authentication. Spent
  windows return the same 429 before service work for known and unknown
  identifiers. Counters advance synchronously before asynchronous password work,
  so concurrent requests cannot exceed a process's allowance.
- Peer identity uses Express `req.ip` and the existing explicit
  `TRUST_PROXY_IPS` configuration. Untrusted forwarding headers cannot select a
  new peer. Host, Venue status, WEBSITE entitlement and CUSTOMER_ACCOUNTS guards
  continue to run through their existing server-owned boundaries.

## Qualification

`docs/proofs/SEC03_ADMISSION_3463ee40_2026-10-14/qualification.json` records exact
counts, final source hashes, preservation, isolated database ownership and
cleanup. Tests cover HTTP parsing/DTO/CSRF/admission, parallel attempts,
normalization/Host changes, successful and failed attempts, window expiry,
trusted/untrusted proxy handling, and rejection before password/service work.

Real PostgreSQL/Nest HTTP evidence uses a newly created, migrated loopback
`disposable_sec03_*` database and synthetic global users with separate SAAS and
CUSTOM Venues. Existing SEC-02 booking ownership and CUSTOM integration suites
are also run on separate freshly migrated disposable databases. No real user,
session, PIN, setting or credential is used or changed.

Focused default proof:

```sh
cd apps/backend
./node_modules/.bin/jest --runInBand --runTestsByPath \
  src/website/auth/auth-admission.spec.ts \
  src/website/user/guest-booking-ownership.spec.ts \
  src/platform/platform-auth.controller.spec.ts
```

Opt-in PostgreSQL suite, after the verification operator creates and migrates a
fresh database on a verification-owned loopback cluster:

```sh
SEC03_TEST_DATABASE_URL='<fresh disposable_sec03_* URL>' \
  ./node_modules/.bin/jest --runInBand --runTestsByPath \
  src/website/auth/auth-admission.integration.spec.ts
```

## Remaining SEC-03 gates

The existing `EnrollmentRateLimiter` is in-memory, per process. A process restart
clears its counters, and several replicas each have their own allowance. Shared
or gateway-level enforcement needs qualification before horizontally scaled
public rollout; these tests do not prove a distributed limit.

Existing access/refresh token generation and logout/password-change session
behavior are retained. Refresh rotation/reuse handling, stolen-token revocation,
session kill semantics, lifetime/recovery ownership and Platform MFA/recovery
remain separate SEC-03 decisions and implementation. This change does not claim
they are secure or complete. A full cookie/CSRF/CORS cross-site browser matrix
and real production rollout remain release acceptance work.

No schema migration, deployment, live service restart or live security setting
change is part of this qualification. OPS-01's denied restore remains paused;
unanswered INV-01.F2 decisions and printer/POS-02 work remain outside this step.
