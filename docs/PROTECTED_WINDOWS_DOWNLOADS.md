# Protected Windows delivery and invitation continuation

The anonymous Windows beta distribution was withdrawn on 2026-10-24. Release
`vaanskii/vynic-releases` / `422823783` remains **draft** with its seven original
assets intact. Old EXE, POS ZIP and Edge ZIP URLs were anonymously verified 404.
The source repository `vaanskii/vynic` is public; its visibility was not changed.
Never commit protected binaries or credentials to that repository.

The release site directs visitors to request access or sign in. Old bootstrap and
repair paths are replaced by authorization notices. Previously obtained files and
already-issued third-party CDN URLs cannot be recalled by this change.

## Download authority and transport

- `/platform/onboarding/downloads`: authenticated write-capable Platform operator
  issues/revokes; SUPPORT_READONLY may inspect status, not issue or revoke.
- `/customer/venues/:venueId/downloads`: active CustomerAccount with live OWNER
  membership and effective commercial POS access. Public registration requests
  alone grant no download or ownership.
- Random 256-bit capabilities last 15 minutes. Only SHA-256 verifiers are stored.
  Each grant pins the private asset ID, byte size and archive SHA-256. Issuing a
  replacement serializes on the issuer and revokes previous active links for that
  issuer/venue. Every open/file request rechecks expiry, revocation, active issuer,
  customer membership and current POS entitlement. Revocation cannot recall bytes
  already received or abort a transfer already admitted.
- Links use `/download#token=…`. A same-origin, CSRF-checked POST exchanges the
  fragment for a host-only HttpOnly/SameSite=Strict cookie, Secure in production,
  scoped to `/customer/downloads`. No secret enters query strings, access-log
  paths, client storage, audit metadata, referrers or client bundles. Do not enable
  request/response-body or Cookie logging on these endpoints.
- The backend streams the fixed GitHub draft asset, following only HTTPS redirects
  to `release-assets.githubusercontent.com` internally. The storage credential
  goes only to `api.github.com`; the client never receives an upstream Location or
  permanent public asset URL. No large Buffer, local disk cache or Vercel function
  body assembly is used. GET, HEAD and one `bytes=start-end`/`bytes=start-` range
  are supported, with length/range validation, cancellation and no-store headers.
- Durable PostgreSQL admission bounds issuance to 3 links per actor/day and
  10 per IP/hour; opening/file admission is 60 per IP/hour, with at most 16 GET
  transfers/ranges per grant. Rejected/HEAD requests cannot bypass authority.
  Issuance, supersession, revocation and transfer start/completion/failure are
  audited without secrets. Hashed anonymous admission rows expire after 7 days.

## Initial installation, repair and future updates

The former small Setup fetched public POS/Edge URLs. Restricting only its EXE would
leave a bypass and break installation after withdrawing those payloads. The new
authorized ZIP instead includes Setup plus the unchanged POS/Edge archives and
their original signed metadata. Extract **all** files before running Setup.

Setup's offline transport maps original signed URLs to adjacent fixed filenames.
It cannot fall back to public HTTP and does not store a download credential.
Pinned Ed25519 signatures, metadata expiry, compatibility, SHA-256, antirollback,
safe extraction and retained-data checks remain authoritative. Altering the local
index cannot authorize modified bytes. Setup is rebuilt as revision `1.0.0.17`;
POS/Edge remain the build-16 beta payloads. No live installation was changed.

Repair of this exact baseline requires the complete authorized package before
the signed metadata expires (`2026-11-23T15:28:45Z`). Later POS releases require
their own qualified package. The future automatic update feed remains inactive;
this change creates no Cloud-to-LAN calls or new live POS updater behavior.
Unsigned Windows beta acceptance remains; real clean-PC installation/repair and
physical printer qualification are separate pending gates.

## Deployment prerequisite

Set only on the Render backend, using its secret UI:

- `VYNIC_RELEASE_GITHUB_TOKEN`: a fine-grained GitHub token restricted to
  `vaanskii/vynic-releases`, **Contents: read** only, owned by an actor that can
  read the draft. Never reuse a broad desktop Git credential in the backend.
- `VYNIC_INSTALLER_ASSET_ID`: the newly uploaded complete offline ZIP's immutable
  asset ID, not the original small EXE.
- `VYNIC_INSTALLER_BYTES` and `VYNIC_INSTALLER_SHA256`: verified complete ZIP
  byte size and SHA-256.

Keep the release draft. Do not publish the protected archive or private credential.
Until all configuration exists, APIs and both UIs explicitly report unavailable;
no token redirect or cosmetic public-download gate is substituted. A repository
credential needs separate exact approval/configuration; none is minted by this
implementation. Email sender integration is also unconfigured, and no real email
is sent. Admin can copy approved invitation/download links manually.

Render free-instance sleep may delay the first request. Downloads stream through
the API and consume actual upstream and Render transfer quotas (about 45 MiB per
current complete package); this design promises no paid plan or unlimited free
bandwidth. Ephemeral disk is not used as artifact storage. Verify a real complete
and resumed transfer after credential configuration before declaring delivery live.

## Validation

`protected-onboarding.integration.spec.ts` runs real HTTP against a fresh disposable
PostgreSQL database and covers refresh continuation, repeat/concurrent acceptance,
expired/used/reissued links, wrong account, CSRF/cross-host rejection, recovery,
authorization/entitlement loss, revocation/expiry, HEAD/ranges, internal redirects,
credential non-forwarding and atomic rate admission. Nearby commercial isolation
and invitation-name regressions remain included. The frontend invitation journey
covers refresh, lost-link recovery, existing accounts and prepared-Venue routing.
Offline Go tests install only synthetic bundles, with the network server stopped,
and reject corrupt metadata/artifacts and unsafe/missing mappings.
