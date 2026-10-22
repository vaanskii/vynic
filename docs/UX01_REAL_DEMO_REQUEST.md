# UX-01 — truthful demo request entry

Status: **DONE**, 2026-10-13, `3463ee406184fec7f53818416e11d0e5f5602c87` plus preserved working-tree changes. This is a source/UI qualification, not a deployment.

The active `HomePage` mounts `components/home/HomeContact.tsx`. Its demo form previously displayed a received/success message after a 700 ms timer with no HTTP request or persistence. The older `components/sections/DemoForm.tsx` is not mounted on the current Homepage and was not changed.

The active contact section now presents a localized, keyboard-accessible React Router link to the existing `/request-access` flow. It collects nothing and claims no submission on the Homepage. Georgian and English copy explains the next step. Existing visual components/styles, process text and byte-identical `HomeFooter` are retained; no new onboarding or lead policy is introduced.

The existing `AccessRequest.tsx` client and `OnboardingRequestsService.submit` are byte-identical to the pre-task snapshot. That service persists a pending application and returns `received: true`, without creating an account, Organization, Venue, subscription, domain, Device, enrollment or invitation. A pending-email retry keeps the original row and returns the existing specific conflict; ordinary errors do not become success. The existing request page remains Georgian for both entry locales; this fix does not translate that separate surface.

## Verification

[Machine-readable qualification](proofs/UX01_3463ee40_2026-10-13/qualification.json).

| Check | Result |
|---|---|
| New route/journey/state tests | 10 passed: KA/EN entry + Enter navigation, delayed POST, 429/503 retry, network failure, exact existing-request conflict, unrelated conflict, required fields and unavailable plan list |
| Focused frontend with public/customer route regressions | 33 passed |
| Frontend aggregate | **186 passed, 0 failed**; focused cases are included, not counted again |
| New real Nest HTTP/PostgreSQL request persistence cases | **7 passed**, including normalized row, no provisioning, validation, exact/concurrent duplicate, IP/email throttle and injected DB failure/retry |
| Existing commercial-access HTTP/PG suite | **16 passed** |
| Backend aggregate with mandatory fresh MENU-09 DB | **851 passed / 808 opt-in skipped / 0 failed** |
| Distinct backend cases exercised | **874 passed**; 23 opt-in cases run separately, no aggregate overlap; 785 opt-in cases not run |
| Frontend/backend build, TypeScript, changed-source/new-test lint, contracts, diff check | pass; no new lint diagnostics |
| Browser QA on owned loopback preview + synthetic API | baseline false success with 0 submissions; corrected link and actual route; error with no success; retry acceptance; 375/768/1440 viewports with no horizontal page overflow; keyboard activation and visible focus ring |

A test-only `unknown` argument type initially failed backend TypeScript and was narrowed to `Record<string, unknown>`. Its emitted JavaScript is byte-identical to the tested source; the final typecheck and lint pass. No production handler changed.

Screenshots:

- [Desktop contact and keyboard focus](proofs/UX01_3463ee40_2026-10-13/home-contact-1440.jpg)
- [375px contact CTA](proofs/UX01_3463ee40_2026-10-13/home-contact-375-card.jpg)
- [768px English contact](proofs/UX01_3463ee40_2026-10-13/home-contact-768-en.jpg)
- [Synthetic request error](proofs/UX01_3463ee40_2026-10-13/application-error.jpg)
- [Synthetic request success](proofs/UX01_3463ee40_2026-10-13/application-success.jpg)

Only synthetic `.invalid` contact data was submitted to the owned loopback fixture and disposable database. No real notification, production application, live migration/service restart, push or deployment occurred. Temporary browser viewport was reset and its tab closed; the owned preview/API and PostgreSQL cluster are stopped. Existing repository changes remain intact.

The user subsequently approved WEB-01/04's five rules: whole-day occupancy, 10-minute Website/bank payment window, genuinely late payment after expired hold shown for manual review with no automatic restoration/refund, partial refund does not automatically cancel the whole booking, and restaurant-owner financial decisions with Vynic support technical assistance. WEB-01/04 implementation follows separately; INV01 F2 remains pending.
