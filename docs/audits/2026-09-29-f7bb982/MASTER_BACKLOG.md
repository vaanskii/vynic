# ერთიანი implementation backlog

ეს არის **ერთადერთი პრიორიტეტული სამუშაო სია**. დომენურ ანგარიშებში issue cards არის მტკიცებულება და არა პარალელური roadmap. მიმდინარე დასრულებული ეტაპები იხილეთ project state-ში.

**2026-10-06 scope update:** EDGE-01 is required now with Windows LAN/cabled
printer stations and optional explicitly compatible sound. Follow
[Windows POS and multi-terminal readiness](../../POS_MULTI_TERMINAL_READINESS_PLAN.md).
The single-POS-only proposal no longer defines the selected release.

P0 კეტავს **მითითებულ** release-ს: უსაფრთხოება, ფული, ჩუმი დაკარგვა ან ძირითადი ოპერაცია. P1 საჭიროა ფართო გაშვებამდე/დაპირებულ ფუნქციამდე; P2 — მნიშვნელოვანი UX/maintainability; P3 — არჩევითი. P0 multi-POS არ კეტავს მხოლოდ ამის გამო single-POS-ს; single-POS-ს თავისი P0-ები აქვს. confidence H=მაღალი, M=საშუალო, L=დაბალი. ზომა S/M/L/XL შედარებითია, კალენდარული დაპირება არაა.

**გაერთიანებული aliases:** `MENU-04 → COM-01`; `INV-03 → MENU-06`; `EDGE-02 → OPS-01`. `POS-04` card recording-ის განზრახ შეზღუდვაა და `PROD-01` disclosure task-ში შედის. განმეორებული ID-ები ცალკე სამუშაოდ არ დაითვალოს.

თითო ჩანაწერის reproduction, expected/actual, actor, endpoint/model და ზუსტი code lines არის მის **მტკიცებულების ბარათში**. ქვემოთ ემატება განხორციელება, dependencies, acceptance, migration/rollback და owner decision. საერთო პირობები: ისტორიული Sale/შეთანხმებული ფასი არ გადაიწეროს; existing migrations/generated contracts ხელით არ შესწორდეს; old clients-ის თავსებადობა დაიცვას versioned additive ცვლილებამ; audit actor/tenant server-owned იყოს.

## P0 — ფარგლებით განსაზღვრული ბლოკერები

### SEC-01 — ყველა website booking გზაზე trusted amount

**SECURITY HARDENING / BUG FIX; paid website; M; H; REPRODUCED mock.** [მტკიცებულება](WEB_COMMERCIAL_SECURITY.md#sec-01--საჯარო-მეორე-booking-endpoint-გვერდს-უვლის-სერვერულ-ფასს). 110 GEL preorder 1 GEL-ად იქმნება alternate endpoint-ით. ერთი pricing/booking application boundary გამოიყენოს ორივე controller-მა; minor units, validated quantities/IDs/capabilities. Dependency: უსაფრთხო test environment OPS-01-ის proof ნაწილი, სხვა ფუნქციას არ ელოდება. Acceptance: ორივე route-ზე altered amount/price/currency/quantity და უცხო/disabled item denied ან trusted amount; fake bank payload exact. Migration: არა; ძველი საეჭვო თანხების read-only reconciliation ცალკე. Rollback: დაუცველი route არ გაიხსნას. Decision: ცარიელი-cart deposit/service fee-ის წესი.

### SEC-02 — guest booking-ის ownership

**SECURITY HARDENING; website accounts; M; H; REPRODUCED mock.** [ბარათი](WEB_COMMERCIAL_SECURITY.md). Unverified email სხვის booking-ს აჩენს. Read ownership მხოლოდ authenticated user binding/verified-email claim-ით, legacy guest claim ერთჯერადი მტკიცებით. Acceptance: victim email signup არაფერს აბრუნებს; verified explicit claim, wrong-Venue deny, old booking სწორად რჩება. Dependency: არა. Migration: შესაძლოა verified/claim state; historical links არ გადანაწილდეს email-ით ავტომატურად. Rollback fail-closed. Decision: ისტორიული guest claim-ის UX.

### WEB-01 — concurrent reservation hold და late payment

**DONE in source; BUG FIX; isolated qualification.** [მტკიცებულება](../../WEB0104_BOOKING_HOLDS_PAYMENT_LEDGER.md). Whole-day physical table/day holds ატომურია; 20 პარალელური მოთხოვნიდან მხოლოდ ერთი hold/bank order. Website ვადა უცვლელი ათი წუთია, BOG TTL=10; დაკარგული პასუხი ვადას არ ზრდის. Late/unproved expired money manual owner review-ს მოითხოვს; დროული signed proof სხვაზე გამოყოფილ მაგიდას არ ითვისებს. Additive migration ძველ IDs/history-ს ინარჩუნებს. D038-ის ხუთი წესი დამტკიცებულია. Real bank/fleet/stale-POS reconciliation release gate რჩება.

### WEB-02 — private draft-ის migration დაცვა

**BUG FIX; shared-foundation upgrade/publication; M/L; H; CONFIRMED_BY_CODE.** [ბარათი](WEB_COMMERCIAL_SECURITY.md). `COALESCE(draft,published)` approval-ს გვერდს უვლის. ჯერ affected state-ის read-only report; შემდგომი repair/reconciliation, არა ძველი migration-ის გადაწერა. Acceptance: published A/draft B upgrade-ზე public=A; private B recoverable; legacy content owner review. Dependency: წინამიგრაციული backup ხელმისაწვდომობა. Migration: ახალი, source evidence-ზე დაფუძნებული; დაკარგული approved values არ გამოიგონოთ. Rollback/restoration staging-ში დამტკიცდეს. Decision: live public-info edit policy და affected-owner communication.

### WEB-03 — confirmed booking და durable dispatch ერთ boundary-ში

**DONE at delivery boundary; BUG FIX; website→POS paid booking; M; H.** [მტკიცებულება](../../WEB03_DURABLE_BOOKING_DELIVERY.md). Payment + immutable CREATE/CANCEL intent ერთი transaction-ით; queue/receipt/POS link ატომურად. Restart/concurrent worker, დაკარგული reply/ACK, terminal no-revival და tenant fencing შემოწმებულია. Platform Website ჩანართში read-only queue/ACK/unresolved/historical tracking ჩანს; ძველი ჯავშნები ავტომატურად არ გადაითამაშება. 26 ახალი PG/HTTP, 1005 distinct backend, 176 frontend და 28 POS/Hive ტესტი გადის. WEB-01/04 source-qualified; რეალური bank/fleet acceptance რჩება ღია. Additive migration ინარჩუნებს ძველ IDs/history-ს; rollback ინარჩუნებს outbox/callback-compatible handling-ს და აჩერებს new create-ს. Decision: none; D002 უცვლელია.

### WEB-04 — BOG event ledger/state machine

**DONE in source; BUG FIX; isolated qualification.** [მტკიცებულება](../../WEB0104_BOOKING_HOLDS_PAYMENT_LEDGER.md). Exact expected snapshot + immutable sanitized receipt observations + pinned reconciliation; authorized/partial preauthorization არ არის paid confirmation. Partial refund ჯავშანს ინარჩუნებს; სრულად დაბრუნებული თანხა არსებულ CANCEL handoff-ს იყენებს. Late/unproved payment არ აღდგება/ბრუნდება ავტომატურად. Owner/Platform read-only review და truthful Vankisi redirects. 32 ახალი PG/HTTP; 1007 distinct backend, 208 frontend, 6 SDK pass; 684 opt-in unrun. D038 და ოფიციალური BOG facts; live certification/deploy არ შესრულებულა.

### MENU-01 — აღდგენადი backup ყველა durable intent-ით

**BUG FIX; canonical POS/მანქანის ჩანაცვლება; L; H; CONFIRMED_BY_CODE.** [ბარათი](POS_MENU_EDGE.md). Backup-დან canonical state/journal, closure და Edge journals გამოტოვებულია. Versioned consistent snapshot, journal inclusion/recovery, tenant/device identity safety. Acceptance: pending create/update/delete, interrupted close/command backup→fresh machine; no duplicate Sale/print; wrong Venue import cannot upload. Dependency: MENU-02 mutation boundary. Migration: versioned backup reader, old backups explicit incomplete metadata; rollback ძველ backup-ს არ „გააუმჯობესებს“ გამოგონილი intent-ით. Decision: encryption/key recovery SEC-05-თან.

### MENU-02 — local acknowledgement და projection ერთ recoverable boundary-ში

**BUG FIX; canonical local-first POS; L; H; CONFIRMED_BY_CODE.** [ბარათი](POS_MENU_EDGE.md). Direct edit sync await-ისას შეიძლება projection clear/rewrite-მა წაშალოს; reapply remove→put შორის intent ქრება. Shared serialized journal-first commit ან equivalent recoverable coordinator ყველა writer-ზე. Acceptance: interleaving edit/pull/ACK/reconcile/reapply + kill ყოველი write-ის შემდეგ; accepted UI edit ან projection-შია, ან recoverable journal-ში. Dependency: MENU-03 reply contract; local offline availability შენარჩუნდეს. Migration: additive journal phases; rollback pending entries არ წაშალოს. Decision: none.

### MENU-06 — menu retirement historical consumption-ის გარეშე არ უნდა იშლებოდეს

**BUG FIX; canonical Menu+Inventory+offline sale; M/L; H; CONFIRMED_BY_CODE.** [ბარათები](POS_MENU_EDGE.md), [INV-03 trace](INVENTORY_MANAGER_FINDINGS.md). Hard delete recipe/presentation cascade-ით pending sale intent-ს 400-ზე ტოვებს. Default archive/retired identities და historical recipe authority; cross-Venue validation დარჩეს. Acceptance: offline close→item/variant delete→intent once applied; exact retry/reversal/archive restore; historical Sale unchanged. Dependency: MENU-01/02. Migration: additive retired metadata/retained recipe references; already-deleted data recovered only with evidence. Rollback: immutable identity/reference retention. Decision: permanent delete-ის პროდუქტის პოლიტიკა.

### POS-01 — recoverable Close Day და mutation admission

**BUG FIX; single-POS business-day close; L; H; CONFIRMED_BY_CODE.** [ბარათი](POS_MENU_EDGE.md). თარიღი/total/order cleanup/audit ცალ-ცალკეა; updater counter operational lock არ არის. Durable day transition ID/phases და shared barrier ყველა local/remote mutation-ზე. Acceptance: order/settlement concurrently close-day; kill after every phase; თარიღი ერთხელ იცვლება და active order არ ქრება. Dependency: shared local mutation infrastructure. Migration: additive journal; ძველ daily totals-ს არ გადაწერს. Rollback recognizes pending transition. Decision: closure-ის დროს ახალი action deny/queue UX.

### POS-03 — item transfer-ის რაოდენობრივი მთლიანობა

**BUG FIX; single-POS split/transfer; M/L; H; CONFIRMED_BY_CODE.** [ბარათი](POS_MENU_EDGE.md). Destination commit source-ზე ადრეა. Transfer journal stable ID+before/after phases და idempotent audit. Acceptance: destination/source/audit boundary crash→quantity/value conservation, empty-source closure correct. Dependency: same admission layer POS-01/05. Migration: additive transfer journal; no historical Sale reprice. Rollback incomplete transfer recovery-ს უნდა ცნობდეს. Decision: none.

### POS-05 — ერთი table-ის ერთი active Order

**BUG FIX; simultaneous local+remote create ერთ POS-ში; M; H; CONFIRMED_BY_CODE.** [ბარათი](POS_MENU_EDGE.md). Free check await-ით reservation write-ს სცილდება. Per-table authoritative create/reserve serialization + request idempotency. Acceptance: local/remote double-create, transfer/edit/close races; rejected attempt no orphan/audit duplicate. Dependency: POS-01 shared admission. Migration: existing inconsistent pairs repair report, no silent selection. Rollback refuses ambiguity. Decision: simultaneous viewing დაშვებული, mutation conflict explicit; permanent screen lock არა.

### MGR-02 / MGR-05 — ორი განსხვავებული operational boundary defect

**BUG FIX; Manager operational writes; M და M; H.** [დეტალური ბარათები](INVENTORY_MANAGER_FINDINGS.md). MGR-02 `REPRODUCED` mock: freeTable Cloud-ს ცვლის POS dispatch-ის გარეშე; MGR-05 `CONFIRMED_BY_CODE`: updateOrder deletes/recreates lines transaction-ის გარეშე. **ეს ორი ID ცალკე acceptance-ით რჩება**, საერთო coordinator-ზე მუშაობის მიუხედავად. MGR-02: guarded repair intent→POS result→mirror; missing table error. MGR-05: validate DTO, atomic durable command, result projection; no partial replacement. Acceptance: offline/pending/reject/retry და every-write failure no split state. Dependencies: MGR-03 UI contract, POS-05 admission. Migration: additive delivery state/outbox where needed; no overwrite of authoritative POS. Rollback write action გამორთული იყოს, history შენარჩუნდეს. Decision: ვის აქვს repair უფლება.

### EDGE-01 — 3/10 operational writers ჯერ unsupported

**Current priority:** implementation now, three terminals before ten. Retain
single-primary containment until complete fenced cutover is proven; containment
does not postpone this milestone.

**MISSING CAPABILITY; required current multi-POS release; XL; H; CONFIRMED_BY_CODE.** [Scenarios](POS_MENU_EDGE.md). Phase 0 contains Cloud primary authority; Phase 2A is shadow and does not fence all local Hive writers. Implement selected Venue-local authority, stable durable intents/results/events/effects, every writer boundary, settlement exclusion and explicit unavailable-authority denial. Three-terminal race/partition/crash/old-host-return proof precedes ten-terminal scale. Single-primary containment remains until complete cutover; it is not the selected completed release. Dependencies: accepted single-POS integrity plus complete writer and print-owner migration. Migration/rollback: controlled per-Venue cutover, old host stopped/fenced, compatible data readers and no automatic fleet switch/failover. Independent offline writers cannot promise strict exclusivity.

## P1 — მომდევნო გაშვების აუცილებელი სამუშაო

| ID / ტიპი / ფარგლები | evidence, რატომ | განხორციელება და acceptance | dependencies; migration/rollback; ზომა/confidence; decision |
|---|---|---|---|
| MENU-03 BUG FIX, canonical retry | REPRODUCED mock; stored revision + current entity არ არის original outcome | mutation-ში immutable serialized outcome; exact retry after later edit/delete identical original; changed payload conflict | MENU-02; additive response column, old-row explicit fallback; M/H; legacy outcome recovery policy |
| MENU-09 BUG FIX, client rollout | CODE; old client silently skips canonical menu | protocol capability/min version enrollment+cutover gate; old/new matrix, sync success≠menu success | OPS-01, MENU-01; additive handshake; legacy Venue unchanged; M/H; supported fleet cutoff |
| COM-01 BUG FIX, POS-only dashboard | CODE; WEBSITE gate canonical editor-ს კეტავს | catalog permission shared policy; POS-only enabled, NO_PLAN/suspended/foreign denied; website presentation stays separate | commercial policy; no schema; narrow revert; M/H; POS owner authoring offer |
| MGR-01 BUG FIX, generic Manager | REPRODUCED mock; first/10 და terrace/1 იმალება | Venue floor/table config, explicit virtual type; counts/payable match POS | no dependency; backfill only explicit type if needed; M/H; none |
| MGR-03 UX REDESIGN+BUG FIX, remote work | CODE; posDelivery body ignored | typed QUEUED/CLAIMED/SUCCEEDED/FAILED/UNAVAILABLE with commandId; widget+HTTP+Edge delayed ACK | MGR-02/05; additive response compatibility; M/H; pending expiry copy |
| MGR-06 MISSING CAPABILITY, payroll/planning | CODE intentional limit; mistaken payment irreversible in UI | linked signed reversal, reason/actor/idempotency, allocation guards; duplicate reversal once, cross-Venue denied | finance ledger; additive reversal relations, immutable old rows; M/H; correction role/date policy |
| SEC-03 SECURITY HARDENING, public/admin accounts | CODE; public auth throttle/session lifecycle gaps | bounded passwords, IP+identifier limiter, revoke/rotation policy, admin session control/MFA appropriate scope; stolen/logout/disable token matrix | before accounts release; token/session version additive; M/L,H; lifetime/recovery owner |
| SEC-05 SECURITY HARDENING, local device/backup | CODE raw PIN export/storage | verifier/keystore/encrypted backup+recovery; synthetic confidentiality and old import | MENU-01; versioned format/key recovery; L/H; key custodian |
| SEC-06 SECURITY HARDENING+PRODUCT DECISION, real PII | placeholder notice CODE; governance NOT_TESTED | actual privacy notices, retention/export/deletion/backup expiry/legal review; synthetic rights exercise | SEC-02; retained financial history policy; M/M; Georgian legal sign-off |
| WEB-06 BUG FIX, rotated BOG readiness | DONE read-only boundary: [current readiness proof](../../WEB06_CURRENT_PAYMENT_READINESS.md), including CUSTOM operator status | Shared greatest-revision metadata query across merchant/capabilities/CUSTOM; r1→r2→disable/reconnect and old pinned credentials verified; 10 focused cases, 899 distinct final backend case records | WEB-01/04 source qualified with separate real acceptance gates; WEB-03 delivery boundary qualified; WEB-06 makes no schema or payment-rule changes |
| WEB-07 BUG FIX, shared data promise | **DONE source boundary:** [shared information proof](../../WEB07_SHARED_INFORMATION.md); owner contacts/hours/socials/gallery reach bespoke readers; 8 real PG/HTTP cases, 233 frontend tests and builds pass | same Host-bound CUSTOM/SAAS info; explicit error/retry; capability-off hide; phone parity and cache refresh proven; payment verification unchanged | WEB-05 deployment attestation/global launch admission still OPEN; no starter adoption; bespoke narrative assets and existing booking time choices retained |
| POS-02 DEPLOYMENT/OPERATIONS+BUG FIX, kitchen print | CODE memory queue/TCP uncertainty; hardware NOT_TESTED | durable jobs and uncertain/labeled reprint; cable/paper/power/kill tests on supported hardware | OPS-01, local journal; additive IDs; L/H; supported printer list and human reconciliation |
| OPS-01 DEPLOYMENT/OPERATIONS, any real pilot | ENV BLOCKED and historical-only hardware; no running revision/restore proof | isolated PG negative+upgrade/replay+restore; immutable source/image/native release dossier; real Windows/core hardware checklist | domain P0s; key/schema compatibility restore; L/H gap; pilot device/host owner |
| OPS-03 SECURITY HARDENING, supply chain | advisory scan ENV BLOCKED; mutable base tags CODE | current npm/Go/Dart/container scans, SBOM/digests/provenance, reachable advisory triage; no force upgrade | approved scanner environment; compatibility tests per upgrade; M/H gap; acceptable residual advisories |
| UX-01 BUG FIX, public lead acquisition | DONE: active HomeContact timer-only false success reproduced; [proof](../../UX01_REAL_DEMO_REQUEST.md) | KA/EN contact CTA opens existing `/request-access`; success only after pending row persists; keyboard/mobile/error/retry verified | Existing client/service/approval policy unchanged; 186 frontend, 7 new HTTP/PG +16 commercial, 851 aggregate backend pass; no new lead model/deployment |
| PROD-01 PRODUCT DECISION, offered packages | CODE limitations: card recording/manual billing/incomplete modules | product contract/copy and enforceable switches: one primary, manual card reconciliation, no automatic recurring claim | all release scope decisions; no migration; S/H; exact pilot package |

ბარათების წყარო: MENU/POS — [POS_MENU_EDGE.md](POS_MENU_EDGE.md); MGR — [INVENTORY_MANAGER_FINDINGS.md](INVENTORY_MANAGER_FINDINGS.md); WEB/COM/SEC-03 — [WEB_COMMERCIAL_SECURITY.md](WEB_COMMERCIAL_SECURITY.md); SEC-05/06 და OPS — [SECURITY_AND_RELIABILITY.md](SECURITY_AND_RELIABILITY.md).

## P2 — გასაგები პროდუქტი და მართვადი ტექნიკური საფუძველი

| ID / ტიპი / scope | evidence/მიზეზი → განხორციელება | acceptance | dependencies; data/rollback; effort/confidence; decision |
|---|---|---|---|
| INV-01 MISSING CAPABILITY, სრული Inventory | Partial [F1 backend checkpoint](../../INV01_LOCATIONS_TRANSFERS_CHECKPOINT.md): location backfill/quantity ledger/API; transfer workflow and POS issue-location policy still pending; waste/count absent | flour16.6kg/49.80GEL/debt30; transfer net0; duplicate/cutoff/reversal — full acceptance remains OPEN | მიღება+cost ledger; additive schemas, backfill one default location; XL/H; transfer approval/negative-stock/POS issue-location decisions. **დაპირებულ full Inventory-მდე P1** |
| UX-02 UX REDESIGN, Manager daily work | CODE task confusion → [შემოთავაზებული ნავიგაცია](INVENTORY_MANAGER_UX.md), receipt/payment/stock history ცალკე მიზნებით | 5 novice users სცენარს სწორად ასრულებს; each balance→document; mobile no clipped action | MGR correctness fixes, INV scope; UI-only first, existing IDs stable; M/H; mobile vs web scope |
| INV-02 PRODUCT DECISION, Profitability | Implemented/proven [INV-02/04](../../INV02_INV04_INVENTORY_PROVENANCE_HISTORY.md): current/provisional/reconstructed/frozen labels; revenue/close payments/outflows/debt separate; historical COGS ცალკე feature | late sale/reversal, current/provisional/historical განსხვავდება | MENU-06; historical sale no reprice; M/H; costing method remains D015 unless new decision |
| INV-04 UX/BUG FIX, history | Implemented/proven [INV-02/04](../../INV02_INV04_INVENTORY_PROVENANCE_HISTORY.md): additive cursor pages + load-more/full CSV; legacy/POS excerpts labelled | 101+ same-day records all discoverable, stable ordering | no dependencies; additive API cursor; S/M,H; none |
| MGR-04 UX/BUG FIX, monitoring | CODE cache hides errors/source age → source/fetchedAt/completeness envelope | API down vs POS down vs partial ledger vs one failed block explicit | MGR-01; additive metadata; M/H; stale action policy |
| MENU-05 UX REDESIGN, disabled item restore | CODE workflow gap → same-ID enable/restore UI, clear active/inactive view | disable→restart→restore preserves recipe/presentation/IDs | MENU-06; no destructive recreation; S/M,H; none |
| MENU-07 TECHNICAL DEBT, monetary representation | CODE Float/double, incorrect charge NOT_TESTED → one exact money contract | decimals/discount/service/split/large values/reprint equal captured cents | money fixture design; versioned wire/backfill only proven values; L/H representation; monetary format decision |
| MENU-08 BUG FIX, resolution audit | CODE Use current removes journal intent without resolution event → immutable actor/reason/discard IDs | both conflict choices survive restart/backup/cloud audit | MENU-02/01; additive events; M/H; required reason policy |
| MENU-10 TECHNICAL DEBT, feed scale | CODE full catalog/tombstone fetch → bounded cursor pages/high-water/retention floor | representative dataset p95/memory, reconnect beyond retention preserves pending | durability first; no blind mutation purge; L/M; offline retention horizon |
| WEB-05 UX+DEPLOYMENT, CUSTOM binding | **DONE source/local candidate boundary:** [build identity proof](../../WEB05_BUILD_IDENTITY.md); stable Venue ID, reviewed manifest/HTML and five distinct facts; 17 PG/HTTP, 21 checker, 246 frontend pass | same-name/wrong-build/legacy/stale/pending/error/disabled-domain cases; three local images and complete emitted artifact checks; no production acceptance | OPS-01 deployed origin/functional acceptance remains OPEN; status stays operator tracking, global public gate needs separate approval; Host authority unchanged |
| SEC-04 PRODUCT DECISION, public media | CODE immutable public delivery persists after entitlement → explicit retention/removal policy | removal/cache expiry/user notice and referenced file behavior | legalSEC-06; keep reference history; S/M,H; public asset revocation expectation |
| OPS-02 DEPLOYMENT/OPERATIONS, local exposure | SUSPECTED source loopback vs lsof wildcard → field-limited port/firewall verification | actual authorized address only; no DB/Studio/operator LAN | Docker permission; config only if proved; S/L; **P1 if exposure confirmed** |
| TECH-01 TECHNICAL DEBT, static quality | REPRODUCED lint debt → new/touched boundaries typed, baseline tracked, no blanket rule disabling | no new errors, meaningful changed-path lint; full debt reduction separately | P0 fixes first; no schema; L/H; cleanup budget |

TECH-01-ის reproducible evidence: `npm run lint` — backend3860 errors/646warnings, platform13/5, Vankisi18/6. კონკრეტული `any`/unchecked serialization production input-ს როდესაც ეხება, შესაბამის bug-ის scope-ში შეკეთდეს; დანარჩენი debt release safety-ის ნაცვლად არ გამოიყენოთ.

## P3 — არჩევითი, მხოლოდ gates-ის შემდეგ

**PROD-02 — ავტომატური subscription collection, KDS/delivery integration, მეტი themes/advanced analytics.** MISSING CAPABILITY; evidence მიმდინარე არაარსებული/არასრული შეთავაზება; confidence scope-ზე M/H. Manual verified billing valid pilot-ია, ამიტომ automatic checkout-ის არქონა მისთვის blocker არ არის. თითო capability ცალკე product brief/bank/provider contract-ით; effort L/XL; dependency core P0+OPS-01; additive integration schema და safe disable rollback; acceptance provider sandbox, idempotency/reconciliation და operational owner. მიმდინარე roadmap-ის პირველ 5 milestone-ში არ შედის. Market benchmark-ის სამი measurable advantage ამ არჩევანზე წინ დგას.

## საერთო release acceptance

შერჩეულ package-ში unresolved P0 არ დარჩეს; A–F core journey და cross-Venue negative tests შესრულდეს; acknowledged edit-ის ჩუმი დაკარგვის გზა არ არსებობდეს; migration **upgrade** და fresh restore დამტკიცდეს; physical claim-ს physical proof ჰქონდეს; manual/unsupported მდგომარეობა product/UI/server gates-ით enforceable იყოს. „UI დამალულია“ არ არის API უსაფრთხოების მტკიცება. Owner-ის approval-მდე implementation არ იწყება.
