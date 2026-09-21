# SaaS Phase 3 — Build identity, runtime configuration and onboarding

This is the canonical build/configuration/onboarding guide. Phase 1 tenant auth,
Phase 2 entitlements/subscriptions and offline POS authority remain in place.
No billing processor, deployment, public release or production database change
is included.

## Previous behavior, verified from source

Before Phase 3, `lib/main.dart` loaded the bundled `.env`. Android/iOS always
started Manager. Desktop read `--dart-define=APP_ROLE`, then `.env` APP_ROLE;
`client` started Manager, everything else initialized POS Hive, printing, the
legacy HTTP ingest listener and sync. Therefore `flutter build windows` did not
select a product: the same `vynic.exe` could boot either UI from its bundled
configuration. PRINT_HOST independently overrode print-host behavior.
Windows title/resources and macOS ProductName said Vynic Pos; Android/iOS labels
said Vynic Manager, with `com.vanski.vynic` mobile IDs. The same Windows executable
name/resources could not describe two distinct installed products.

ApiConfig preferred a local saved URL, then platform-specific `.env`, shared
`.env`, dart defines and finally localhost. POS_SYNC_API_KEY could ship as an
asset or define. Printer IP environment fallback had already been removed from
SettingsRepository, but obsolete keys still existed in the local development
file, and printer ports were fixed to 9100. Customer owners/portal did not exist.

## Product identity and supported targets

`main.dart` now exports `main_manager.dart`: the default always starts Manager.
`main_pos.dart` supports Windows production and macOS debug development.
It rejects other host platforms and non-development macOS modes. It calls
`startup_pos.dart`. Neither entrypoint loads `.env` or reads APP_ROLE/PRINT_HOST.
Manager initializes only its own Hive cache/preferences/auth and notifications;
it does not initialize DatabaseService, printing, POS ingestion or POS sync.
Manager cache storage uses a `VynicManager` subdirectory. POS retains its existing
operational data/credential discovery and never boots companion Manager navigation.
Unfinished POS setup persists across restart, including after Staff delivery.
Only a restaurant name is required; logos are optional and edited later in Settings.
Startup never copies Vankisi identity, logo, menu or tables into missing fields.
Existing stored restaurant data is preserved.
Fresh release POS has no universal bootstrap PIN; first Manager credentials arrive
through Edge. Existing Staff are untouched. Debug bootstrap accounts remain for
existing developer tests only. After a deliberate release data wipe, use portal
Manager reset to queue that identity again; there is no universal recovery PIN.

| Product | Targets | Windows executable / native application identity |
| --- | --- | --- |
| Vynic POS | Windows only | `vynic_pos.exe`, `ge.vynic.pos` |
| Vynic Manager | Windows, macOS, Android, iOS | `vynic_manager.exe`, `ge.vynic.manager` |

Windows title, resource ProductName/FileDescription and AppUserModelID are fixed
per product. Separate output/install directories permit coexistence. POS keeps
company `vanski` and the Windows-case-equivalent Vynic POS product directory;
Manager has its own product directory, so its caches cannot become POS Hive.
macOS Manager uses `ge.vynic.manager` and `Vynic Manager.app`. Android/iOS retain
the already registered Manager ID `com.vanski.vynic`, preserving their Firebase
configuration and installed mobile identity. Existing Vynic logo assets are shared;
native icon resources/configuration remain isolated in each build output.
Web/Linux are not supported release targets: existing `dart:io` and operational
plugin dependencies have not been certified for Web. No POS Mac/mobile download
is advertised.

The repository has one shared Dart tree. `tool/product.py` materializes an isolated
build workspace with a fixed entrypoint and native metadata; generated build
copies are not another maintained application codebase. This avoids assuming
that changing `-t` alone changes installed identity, or requiring Windows flavors
from a newer SDK. Validated SDK: Flutter 3.44.1 / Dart 3.12.1. Flutter's current
[deployment guidance](https://docs.flutter.dev/deployment) describes the supported
native build families; newer [Windows flavor support](https://docs.flutter.dev/deployment/flavors-windows)
is not a dependency of this implementation.

## Four configuration layers

1. **Environment:** `VYNIC_ENV=development|staging|production`, `VYNIC_API_URL`.
   These identify one deployment, never a restaurant. Release builds require an
   HTTPS origin. No production DNS/API endpoint is invented in source.
2. **Venue:** Cloud owns identity, subscription and effective entitlements.
   Existing operational settings/Menu/Tables remain POS-owned unless a specific
   Cloud authority already exists.
3. **Device:** enrollment establishes the Device; Device.runtimeConfig owns
   kitchen/receipt printer host, port and enabled state. Edge pulls a complete
   versioned document and caches it in one Hive settings value.
4. **Credentials:** customer/Manager login and Device enrollment provide runtime
   credentials. They are never build settings. Existing Device credential-file
   persistence is retained; migration to OS keychain is separate work.

Production ignores saved backend overrides and enrollment-advertised URL changes.
The same production endpoint and binary serve every Venue. Device credentials and
Manager restaurant-code/PIN authority determine the Venue. Debug development may
use the explicitly labelled API override; neither release nor staging exposes it.
The production deployment must supply its established shared API origin and set
backend DEVICE_API_BASE_URL consistently if it uses that optional response field.

## Environment key classification and retirement

Only key names were reported during the local `.env` audit; secret values were
not logged or copied into documentation. The existing developer file is untouched.

| Existing key | Classification | New-build treatment |
| --- | --- | --- |
| APP_ROLE | REMOVE_LEGACY | SAFE_TO_REMOVE from build configuration; fixed entrypoints |
| PRINT_HOST | REMOVE_LEGACY | SAFE_TO_REMOVE; POS owns printing, per-printer enabled is runtime |
| POS_SYNC_API_KEY | SECRET_MUST_NOT_SHIP | NEW_BUILDS_DO_NOT_USE; ApiConfig returns no shared key |
| BACKEND_URL_ANDROID/IOS/MACOS/WINDOWS/WEB/FALLBACK and BACKEND_URL | KEEP_AS_ENVIRONMENT_CONFIG concept | Replace with VYNIC_API_URL; no Venue-specific URL |
| PRINTER_TYPE | REMOVE_LEGACY | Existing local ESC/POS rendering retained |
| PRINTER_KITCHEN_IP / PRINTER_RECEIPT_IP / PRINTER_PORT | MOVE_TO_DEVICE_CONFIG | Cloud Device config → durable local cache |
| POS_INGEST_PORT / POS_CALLBACK_HOST / POS_CONNECTION_KEY | REMOVE_LEGACY | NEW_BUILDS_DO_NOT_USE; listener never starts in new entrypoints |
| Device credential / Manager token | SECRET_MUST_NOT_SHIP | Runtime enrollment/login only |
| debug API override | DEV_ONLY | Debug development only |

`.env` is removed from pubspec assets. The product builder omits the legacy restaurant `data/menu.json` asset (a local
developer fixture, not a SaaS restaurant configuration) and copies no `.env*`,
keystores, key properties or provisioning secrets. Legacy backend shared-key and
callback compatibility stays frozen for old installed terminals; retire only
after real fleet enrollment and old-build retirement evidence. New onboarding
never displays callback settings, Venue UUIDs or shared keys.

## macOS development shortcuts

Source `apps/operations/tool/dev.zsh` from `~/.zshrc`, then run `vynic-pos`
or `vynic-manager` from any directory (separate terminals to run both).
POS remains Windows-only for production. These shortcuts use debug development,
separate macOS bundle IDs/names and cached workspaces under
`apps/operations/.dart_tool/vynic-dev/`. Their `lib` directories link to the
shared source, so Flutter `r`/`R` hot reload/restart uses your actual edits.
They do not read APP_ROLE or `.env`.

Default API is `http://127.0.0.1:3000`. Override per invocation with
`VYNIC_DEV_API_URL=http://HOST:3000 vynic-pos` (or `vynic-manager`).
Additional Flutter run arguments pass through, e.g. `vynic-pos --verbose`.
Quit with `q`; launch the same command again to refresh native configuration/assets.
The shortcuts preserve build caches and never delete the POS operational database.

## Developer and release commands

Run from the repository root. Use a fresh output directory each invocation; the
builder refuses to overwrite an existing workspace. `prepare` can inspect native
metadata on any host. Compilation must run on a host supported by Flutter for
the chosen target. POS/Manager Windows require Windows; Apple builds require Mac.

```sh
# Backend and web (their normal local environment setup remains unchanged)
cd apps/backend
npm run start:dev
# Separate terminal, repository root:
cd apps/platform-web
npm run dev
```

```sh
# Repository root: Manager on this Mac / iOS simulator / Android emulator
python3 apps/operations/tool/product.py run manager macos --output /tmp/manager-dev
python3 apps/operations/tool/product.py run manager ios --device DEVICE_ID --output /tmp/manager-ios-dev
python3 apps/operations/tool/product.py run manager android --device EMULATOR_ID --output /tmp/manager-android-dev
# Defaults: 127.0.0.1:3000 on Apple/Windows, 10.0.2.2:3000 on Android.

# Windows developer host; replace the LAN address with the developer backend.
python apps/operations/tool/product.py run pos windows --api-url http://DEVELOPER_LAN_IP:3000 --output C:/vynic-builds/pos-dev
```

Set `VYNIC_RELEASE_API_URL` in the release shell to the established production
HTTPS API origin. It is intentionally not given a fake default. These commands
produce separate products, with identical Venue-independent binaries for all
restaurants:

```sh
python apps/operations/tool/product.py build pos windows --environment production --api-url "$VYNIC_RELEASE_API_URL" --output build-pos-windows
python apps/operations/tool/product.py build manager windows --environment production --api-url "$VYNIC_RELEASE_API_URL" --output build-manager-windows
python3 apps/operations/tool/product.py build manager macos --environment production --api-url "$VYNIC_RELEASE_API_URL" --output build-manager-macos
python3 apps/operations/tool/product.py build manager android --environment production --api-url "$VYNIC_RELEASE_API_URL" --output build-manager-android
python3 apps/operations/tool/product.py build manager ios --environment production --api-url "$VYNIC_RELEASE_API_URL" --output build-manager-ios
```

Use `--environment staging --api-url HTTPS_STAGING_ORIGIN` for a production-like
staging build. An unsigned iOS compatibility build accepts `--no-codesign`.
Android production requires VYNIC_ANDROID_KEYSTORE, VYNIC_ANDROID_STORE_PASSWORD,
VYNIC_ANDROID_KEY_ALIAS and VYNIC_ANDROID_KEY_PASSWORD in the build environment;
keys are not copied into Flutter assets. Missing signing produces an unsigned
staging APK, never a debug-signed release presented as production. Store signing,
macOS notarization, Windows installers/signing and published URLs remain release
pipeline inputs, not invented downloads.

## Customer authority and pilot registration

CustomerAccount is a distinct owner principal with Organization relation, email,
Argon2id password verifier, active state, explicit nullable emailVerifiedAt and
timestamps. Every account is an OWNER in this minimal pilot; no general membership
RBAC exists. Signup creates a new Organization/account atomically. It accepts no
existing organizationId, never links by an email/name match and cannot claim
Vankisi or another existing restaurant. PlatformUser, Staff and WebsiteUser are
separate identities and JWT audiences/types. Tokens are re-resolved against active
CustomerAccount on every request.

Public `/customer/auth/signup` and `/customer/auth/login` use normalized email,
15–128 character signup passwords and per-IP/per-email throttling. This follows
[OWASP authentication guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
on password length and throttling. Limits use the existing in-process limiter:
20 attempts/IP and 10/email per 15 minutes. A distributed deployment needs shared
rate limiting or an equivalent trusted edge limit. Configure trusted proxies
explicitly; arbitrary forwarded headers are not authority.

Registration defaults CLOSED. Platform `/admin/onboarding` selects an active
trial plan containing POS and MANAGER_APP, trial duration (1–90 days), enables
the pilot and optionally configures real release links. These mutations are
Platform-audited; SUPPORT_READONLY cannot change them.
There is no mail provider/verification/reset email implementation. Accounts remain
unverified, clearly labelled; they can manage only the new Organization created
with their own password. Email ownership never grants access to existing data.
No invitations, auto-verification or email-based account linking are simulated.
Do not enable broad public registration before deploying a recovery/verification
and abuse-control policy suitable for that launch.

## Wizard and portal

Public Navbar → `/start` / `/portal` → signup or login → restaurant name,
timezone and currency → first Manager display name/username/PIN → restaurant
code → one-time POS enrollment → printers → readiness.

The pilot supports one Venue per newly registered Organization; a locked
Organization transaction makes restaurant creation retry-safe. It creates a TRIAL
subscription and assigns the Platform-selected plan. Plan/feature changes remain
Platform authority. Default timezone/currency are editable Asia/Tbilisi/GEL.

Manager create/reset/disable delegates to Phase 2's atomic Staff/vault/Edge/audit
operation, including its request UUID and revision conflict handling. Customer
actions write CustomerAuditEvent with their real actor, never a fake PlatformUser.
PINs clear on successful submission/cancel and are not read back. Disabled Staff
history survives. Manager uses restaurant code plus PIN on its branded first
screen. Production users see no backend settings.

Enrollment reuses DeviceEnrollment's selector/hash, expiry, cancellation,
redemption/retry and Device lifecycle. Its creator is exactly one PlatformUser or
CustomerAccount, enforced by an additive database constraint. Codes are shown once;
lost codes can be cancelled and regenerated. The customer cannot select a foreign
Venue or Device. Device responses provide no stored credential hashes.

Fresh POS shows its branded code-entry screen; successful enrollment persists its
credential and begins Edge/catalog/runtime pulls. It waits for local Staff delivery
before showing PIN login. Existing locally configured POS
can continue operating before fleet enrollment, preserving offline compatibility.
The website polls status every 15 seconds. Recent connectivity is based on the
Device lastSeenAt within two minutes, not permanently inferred from existence.

Readiness requires active Venue, active Manager, active Device and first successful
full snapshot (`Device.firstSyncAt`). A realtime-only or failed snapshot does not
establish first-sync readiness. Existing devices start with this field empty and
populate it on their next successful full sync. Menu/Tables/first Sale checklist
items reflect Cloud mirrors of POS-authored records; the portal gives instructions,
not a competing menu/table editor.

After setup, the same portal shows subscription/trial, features, code, Managers,
Devices, printer forms and checklist. Platform Venue detail links to owner/status
inspection at `/admin/onboarding/:venueId`; existing commercial/device pages
retain the operator's controls. Release links show “not published” until real
HTTPS URLs are configured. POS is Windows-only; Manager lists its four targets.

## Printer delivery and offline safety

`PUT /customer/venues/:venueId/devices/:deviceId/printers` verifies owner → Venue →
Device. Platform has the corresponding operator route. Host, integer port and
boolean enabled values are validated; writes and semantic audit are atomic.
Cloud stores configuration but never connects to the supplied LAN host.

`GET /edge/runtime-config` derives Device/Venue solely from its credential and
returns Venue identity, effective feature keys and that Device's versioned config.
POS pulls on startup/enrollment and every 10 seconds. Device display name and
effective features refresh independently of printer settings; the UI observes
changes without restarting. Validation precedes one atomic
Hive write. Null Cloud config preserves existing local printers. Failed pulls
leave the last good config; backup already includes every settings key. Updates
wait until the print queue is idle, then refresh local connections. Renderers,
receipt semantics and routing are retained. Kitchen and receipt have separate
ports/enabled flags. Disabled printers resolve to an empty target. Printing and
checkout never issue a Cloud configuration request.

Normal customer configuration is available through the portal without a developer
token. Existing developer-only local printer diagnostics remain. A new remote
**physical test-print action is deferred**; this phase provides config delivery,
not a false “paper printed” success. Operators can use existing local diagnostics.

## Migration and compatibility

`20260919120000_customer_onboarding_runtime` is additive: CustomerAccount/audit,
OnboardingPolicy, nullable enrollment customer creator, Device runtimeConfig and
firstSyncAt. Existing enrollment Platform creators and credentials are unchanged.
No existing Organization gets an owner or portal password. Existing Venue codes,
Staff, subscriptions and entitlements are not rewritten. No live Vankisi database
was accessed. All 36 migrations are tested from empty on isolated PostgreSQL 17.

## Validation

Completed validation: backend **65 suites / 680 passed / 1 skipped**; Flutter
full suite **1,381 passed / 3 skipped**, plus the subsequent three-test POS
first-run regression (including the new Manager-delivery waiting state); web
**9 files / 28 passed**; product builder **2 passed**. Backend/web builds,
TypeScript, Flutter analyze, Prisma validate, contracts check and diff check pass.
All 36 migrations apply from empty; migrate diff reports no difference.
Native-host limits are recorded below. Test-only native builds use `https://example.invalid` as a non-contacted
compile fixture; this is never a repository production endpoint or release URL.

- Real HTTP/PostgreSQL two-customer signup → Venue → trial → first Manager → code
  → Device enrollment → Manager login; foreign resource and principal denial;
  independent printer/feature projection; cancellation, disabled owner and throttle.
- Existing backend tenant/auth/Edge/entitlement suites; Flutter full suite and
  new cached-printer restart/first-run layout tests; Platform wizard/control tests.
- Browser signup inspected at 360/768/1280, with document scroll width matching
  viewport width at each. Wizard forms also have component interaction coverage.
- Manager macOS, Android APK and unsigned iOS release compilation succeeded.
  Bundle/package IDs and Manager branding were inspected. All three artifacts
  have no `.env` or legacy menu fixture and no matches for the audited local
  source shared POS key/printer addresses. This scan checks known source values;
  it is not a claim to discover every possible secret in arbitrary dependencies.
- Product-builder regression tests inspect both Windows product names, binaries,
  native IDs and fixed entrypoints; Windows execution requires a Windows host.
- Prisma validate, all migrations, migrate diff, TypeScript/backend build,
  Flutter analysis and contracts generation check.

## Rollout order and remaining launch inputs

1. Back up and apply the additive migration through the deployment procedure.
2. Deploy backend with registration closed. Verify Phase 1/2 and existing enrolled
   Vankisi credentials/code against the deployment; no recreation required.
3. Deploy Platform/customer web; choose trial plan and supply actual release URLs
   only after artifact signing/publication. Keep pilot closed until ready.
4. Upgrade POS to Phase 2/3-compatible Staff revision handling and new runtime
   config pull before customer Manager access actions are enabled.
5. Publish separated Manager/POS products with the real shared HTTPS API origin;
   verify Windows coexistence, existing POS data discovery and offline printer
   behavior on actual restaurant hardware. Retain old callback/shared-key backend
   compatibility until the old fleet is retired.
6. Open the controlled pilot, run two-customer enrollment checks, then verify
   first sync, local Menu/Tables and first Sale. Printing needs real hardware proof.

Remaining inputs: hosted API/DNS/TLS and backups; signed/installable artifacts and
store/notarization pipelines; Windows native build/coexistence verification; mail
verification/recovery and distributed abuse controls before broad signup;
OS-keychain credential storage; physical test-print command/hardware verification.
No production deployment, publishing, billing or legacy fleet shutdown was done.

## Live menu and feature changes

Local POS menu saves refresh the open ordering menu without resetting the cart.
Device names come from enrollment/runtime configuration, never a fixed POS-01 label.
`NON_FISCAL_CLOSE` is an optional capability enforced from the last cached snapshot
in addition to Staff permissions, including a final check before starting closure.
The additive `20260920120000_non_fiscal_close_feature` migration adds it to existing
POS plans to preserve their prior behavior. New custom plans choose their own set.
Operators can Enable/Disable/Inherit it per Venue through Georgian product controls.
Cloud feature updates normally appear within 10 seconds while connected; offline
POS retains its last known capabilities and does not request Cloud during checkout.

## Shared Venue profile

Apply `20260921120000_venue_profile` before deploying the new backend/client.
It adds nullable branchName/address/phone/legalId/profileUpdatedAt to Venue and
never fills in a default branch, address or logo.

Owners edit the profile in their portal (including optional fields at signup).
Managers edit it under Management → Settings → Restaurant profile. POS edits the
same text identity in Settings; logo and receipt layout remain local and optional.
The name is required for shared profile writes; other text fields may be cleared.

Owner routes check Organization ownership; `/mobile/venue-profile` resolves Staff
and requires MANAGER_APP/Manager role; `/edge/venue-profile` resolves Device.
Client Venue IDs never establish authority. Every accepted profile change and its
before/after values are recorded atomically in Venue audit history.

POS persists pending edits with its enrolled Venue identity before syncing. They
survive restart/offline use and retry during runtime pulls. A pending edit restored
from another Venue is discarded without sending it. Failed uploads do not block
feature/printer refresh or overwrite local pending identity. Cloud pulls refresh
idle forms and login identity; unsaved forms keep user edits. Last accepted profile
save wins. The setup-complete marker remains independent from profile delivery.
Legacy local receipt identity is retained until a profile has been configured in
Cloud; no nullable migration field erases an existing local identity at startup.

NON_FISCAL_CLOSE hides optional non-fiscal sales/report/dashboard presentation as
well as the close action. It does not delete Sale records, rewrite totals, remove
advance receipts/cancellations, or erase audit/consumption history. Re-enabling it
restores visibility of the original history. Feature dependency warnings are
advisory and never silently enable other modules or override plan precedence.
