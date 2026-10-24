# Protected Windows delivery and invitation continuation

The anonymous Windows beta distribution was withdrawn on 2026-10-24. Release
`vaanskii/vynic-releases` / `422823783` remains **draft** with its seven original
assets intact. The current beta is protected draft release `422983256`, POS 1.0.1
build 18 / Edge and Setup 1.0.1.18, complete ZIP asset `673319647`; see
`WINDOWS_BETA_TEST_INSTALL.md` for hash, compatibility and test instructions.
Old EXE, POS ZIP and Edge ZIP URLs were anonymously verified 404.
The source repository `vaanskii/vynic` is public; its visibility was not changed.
Never commit protected binaries or credentials to that repository.

The release origin is technical-only: root, index and unrecognized paths return
neutral 404. It contains no installer catalog, signup page or public download
landing. Main-site `/download` GET/HEAD redirects to the canonical main site with
an explicit cleared fragment; other methods return 404. Old public bootstrap and
repair copies are removed. Only `/windows/access/*` routes to the backend.
Previously obtained files and already-issued third-party CDN URLs cannot be
recalled by this change.

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
- Issued links use `https://releases.vynic.ge/windows/access/<grant-id>#token=…`.
  Render redirects the non-secret selector to the backend; the fragment stays in
  the browser. Only a live, authorized grant selector gets a minimal transport
  handshake, with no catalog/navigation. Its nonce-protected script clears the
  fragment and performs a same-origin CSRF-checked POST. A host-only HttpOnly,
  SameSite=Strict cookie (Secure in production) is scoped to that single grant.
  The selector alone cannot retrieve bytes. GET/HEAD/Range files additionally
  require the matching secret/cookie. There is no generic download page. No
  secret enters query strings, access-log paths, client storage, audit metadata,
  referrers or client bundles. The complete
  link is a bearer capability: a recipient can forward it, and the next holder
  may download until expiry/revocation. Rechecking the issuer does not identify
  the recipient; this is explicitly not recipient identity-bound authentication.
  Do not enable request/response-body or Cookie logging on these endpoints.
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
authorized ZIP instead includes the matched Setup, POS/Edge archives and their
signed metadata. Extract **all** files before running Setup.

Setup's offline transport maps original signed URLs to adjacent fixed filenames.
It cannot fall back to public HTTP and does not store a download credential.
Pinned Ed25519 signatures, metadata expiry, compatibility, SHA-256, antirollback,
safe extraction and retained-data checks remain authoritative. Altering the local
index cannot authorize modified bytes. Current POS is 1.0.1 build 18; Edge and
Setup are 1.0.1.18. The original build 16 archive and Setup 1.0.0.17 remain immutable.
No live installation was changed. Existing receipts pin their baseline; this new
package is not an in-place upgrade of those receipts and supplies no Edge self-update.

Repair of this exact baseline requires the complete authorized package before
its signed metadata expires (current baseline 18: `2026-11-23T21:06:43Z`; original
baseline 16: `2026-11-23T15:28:45Z`). Later POS releases require
their own qualified package. The future automatic update feed remains inactive;
this change creates no Cloud-to-LAN calls or new live POS updater behavior.
Unsigned Windows beta acceptance remains; real clean-PC installation/repair and
physical printer qualification are separate pending gates.

## Backend configuration

Set only on the Render backend, using its secret UI:

- `VYNIC_RELEASE_GITHUB_TOKEN`: a fine-grained GitHub token restricted to
  `vaanskii/vynic-releases`, **Contents: read** only, owned by an actor that can
  read the draft. Never reuse a broad desktop Git credential in the backend.
- `VYNIC_INSTALLER_ASSET_ID`: the newly uploaded complete offline ZIP's immutable
  asset ID, not the original small EXE.
- `VYNIC_INSTALLER_BYTES` and `VYNIC_INSTALLER_SHA256`: verified complete ZIP
  byte size and SHA-256.

Keep the release draft. Do not expose the protected archive publicly or publish a
private credential. Update only the nonsecret asset ID/size/hash selection after
verified immutable upload; preserve the existing read credential.
The separately approved credential `Vynic Render releases read` is configured on
the backend, restricted to this one repository with Contents and Metadata read-only
and expiration on November 23, 2026. Renew it through the secure provider UI before
expiry. Missing configuration makes APIs and both UIs explicitly unavailable;
no permanent public-asset redirect or cosmetic public-download gate is substituted.
Email sender integration remains unconfigured, and no real email is sent. Admin
can copy approved invitation/download links manually.

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

## Browser delivery failure handling

The per-grant handshake now verifies an authorized HEAD response (ZIP MIME,
attachment disposition and positive byte length) before offering the file link.
The link relies on the server attachment header; it no longer forces arbitrary
error responses into browser downloads named `file.json`. File GET/HEAD errors
retain their HTTP status and return a no-store HTML explanation without an
attachment header or raw upstream details. Grant expiry, revocation, authority,
rate and current-artifact checks remain enforced.

Storage failures log only fixed phase/reason, numeric status/length and method;
no capability URL, token, cookie, credential or upstream signed redirect is logged.
The delivery regression suite exercises a local technical-origin redirect,
script/session-cookie handshake, complete ZIP response and resumed range through
real HTTP, plus denied/upstream JSON failures. Existing disposable PostgreSQL
coverage retains real grant authorization, expiry/revocation and issuer isolation.
These local cases do not attest the owner's live browser session. A fresh authorized
link and browser download approval remain necessary for the production handoff;
authenticated GitHub readback alone does not verify that handoff.

A production startup performs one bounded read-only asset-header check with the
existing server-held credential. It does not create a grant, retrieve a complete
archive, or block API/restaurant readiness. Its single-line diagnostic contains
only the selected nonsecret asset/size/hash, provider status, a fixed error class,
rate-limit counters and a parsed credential-expiry timestamp when supplied.
Provider error-body parsing is capped at 8 KiB; raw bodies, credentials and signed
redirect URLs never enter the log. This distinguishes provider permission refusal
from expiry, rate limiting, missing assets and redirect/length failures without
requiring a customer capability to diagnose storage. Runtime client failures use
the same classification. Byte ranges are sent to the fixed GitHub API too, since
that endpoint may return bytes directly as well as redirecting to the asset host.
