# WEB-07 — Vankisi shared public information

Status: **DONE for the supported public-information source boundary** on dirty
`3463ee406184fec7f53818416e11d0e5f5602c87`. This is local source qualification,
not deployment or full CUSTOM build attestation. Machine evidence:
[`WEB07_INFO_3463ee40_2026-10-13/qualification.json`](proofs/WEB07_INFO_3463ee40_2026-10-13/qualification.json).

## Ownership and behavior

D026/D028 and `WEBSITE_FOUNDATION.md` already establish the source of truth;
this work introduces no new product policy. Host resolves the public Venue.
`Venue.profile` supplies name/address/phone; `VenuePublicProfile` supplies
contact email/map/socials/hours/gallery. Owner saves remain live for both SAAS
and CUSTOM. The existing publication-review and capability rules remain intact.

Vankisi now consumes `/api/website/venue` in its existing bespoke frontend:

- Footer and Contact use owner contacts, map and socials; Footer shows the
  seven-day schedule, including closed days and overnight clocks.
- The Atmosphere gallery teaser uses owner gallery URLs and alt text, rather
  than its former four fixed photos. Capability-off or empty data hides it.
- Confirmed PaymentSuccess contact uses the same current email. Its payment
  verification/cart logic is byte-identical after removing only the contact
  import/markup substitution. Unavailable information cannot gate confirmation.
- Reads occur on route changes, browser focus and explicit retry. Abort plus an
  active-request guard prevents older responses overwriting current state.
  The installed Axios fetch adapter uses browser `cache: no-cache`; this
  revalidates without adding a CORS request-header requirement. Credentials and
  existing API interceptors remain in use.
- Loading and failed/setup/misattached information have explicit localized
  status/retry. Missing or deliberately empty values never restore stale
  business contacts, map or hours. Phone display and `tel:` target agree;
  mail address characters cannot inject URI headers. External links allow HTTPS
  only; managed images also allow the established relative media path.

The reader accepts schema v1/CUSTOM/ACTIVE/`vankisi-web`, validates the consumed
fields and reuses only the shared types/pure binding gate. It never supplies a
Venue ID or changes tenant authority. It is **an informational reader gate**,
not a global App/booking/payment launch gate. WEB-05 remains open.

The Vite proxy also serves the existing `/media/website-logos` path while keeping
Host; production ingress already routes that path. ImageWithSkeleton received
only an explicit React type import needed by cross-app TypeScript verification;
its emitted runtime JavaScript is byte-identical.

## Verification

All final checks have zero failures unless explicitly described below.

| Check | Exact result |
|---|---|
| New real Nest HTTP/PostgreSQL test | 8 passed, 0 failed/skipped |
| Backend aggregate Jest | 851 passed, 0 failed, 848 opt-in skips |
| Backend case records executed in this phase | 859 passed; 840 opt-in cases not run in this phase |
| Focused frontend, including existing payment-return regressions | 41 passed, 0 failed/skipped |
| Platform frontend aggregate | 233 passed, 0 failed/skipped; 22 new shared-info cases |
| Backend TypeScript | passed |
| Platform and Vankisi `npm run build` | both passed |
| New/touched reader, consumer, test and proxy lint | 0 errors/warnings |
| Atmosphere existing helper lint | 1 inherited `no-explicit-any`; same rule/message/source statement before and after |
| `git diff --check` | passed |

The real database proof covers live CUSTOM/SAAS projection without page
republishing; foreign owner denial; Host authority despite client selectors;
revision conflicts; invalid URL/foreign asset denial; old ETag revalidation;
operator-off hours/gallery; explicit empty values; server-owned binding and
unpublished SAAS. Both disposable databases used all 74 repository migrations.
No backend production implementation/schema/migration was changed in this phase.

Actual CUA browser QA rendered real components/providers against synthetic
public JSON exported by that HTTP test. A loopback fixture responded with
`public,max-age=3600` and ETags: owner edit then focus updated the same request
URL without a build/reload. Cross-origin fixture preflight requested only
`content-type`, with the backend's existing allow-header constraint emulated.
375/768/1440 widths had no horizontal overflow; KA/EN weekdays, image loading,
phone targets, off/wrong/error states and a visible 2px retry focus outline were
verified. RU and browser Intl English fallback are also covered by unit tests.
The managed image fixture used existing repository JPEG bytes at a synthetic
asset URL; it was not a real upload or storage/deployment acceptance.

Reproduce from app directories with a fresh, migrated disposable database:

```text
backend: WEB07_TEST_DATABASE_URL=<owned disposable_web07 URL> ./node_modules/.bin/jest --runInBand --runTestsByPath src/website/core/web07-shared-info.integration.spec.ts
backend: MENU09_TEST_DATABASE_URL=<owned disposable_menu09 URL> ./node_modules/.bin/jest --runInBand
backend: ./node_modules/.bin/tsc --noEmit
platform-web: npm test
platform-web: npm run build
vankisi-custom-web: npm run build
```

## Remaining boundaries

WEB-05 stable deployment/build identity and global launch admission need their
own source and deployed acceptance. The selected owner-info boundary does not
change booking time choices, whole-day holds, deadlines, payment/Primary/Hive
semantics, or enforce opening hours as a booking admission policy. Brand/design
and narrative Atmosphere photos remain bespoke frontend content. Existing
newsletter placeholder and privacy/accessibility placeholder links are deferred.

POS-02.C continues independently; INV-01.F2 product decisions remain unapproved.
Real production host/DNS/TLS/proxy/media, bank/fleet/hardware and restore
acceptance remain release work. This phase did not rerun unrelated opt-in bank
or POS suites or alter real customer data, credentials, services, deployments,
commits or pushes. Its owned preview and PostgreSQL cluster were stopped and
its temporary browser tab/viewport were cleaned up.
