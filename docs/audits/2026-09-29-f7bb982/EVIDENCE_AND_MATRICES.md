# მტკიცებულებები და შემოწმების მატრიცები

აუდიტის თარიღი: **2026-09-29**, `Asia/Tbilisi` (UTC+04:00). საწყისი დრო: დაახლოებით 22:03. წყარო: `/Users/vaanskii/Developer/vynic`, branch `codex/docker-deployment-foundation`, HEAD `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b` **და უკვე არსებული WIP**. ეს არ არის მხოლოდ HEAD-ის აუდიტი.

## მტკიცებულების მნიშვნელობა

| იარლიყი | რას ამტკიცებს |
|---|---|
| `REPRODUCED` | მიმდინარე წყაროს კონკრეტული ქცევა გამეორდა; ცალკე მითითებულია mock/unit/browser/რეალური DB/აპარატურა |
| `CONFIRMED_BY_CODE` | მიმდინარე შესრულების გზა და კონტრაქტი იძლევა დასკვნას; გაშვება არ უდრის დამტკიცებულს |
| `HISTORICAL_REPORT_ONLY` | ძველი ანგარიშის მტკიცება; ამ აუდიტის ტესტად არ ითვლება |
| `SUSPECTED` | დასამტკიცებელი ჰიპოთეზა |
| `NOT_TESTED` | ამ გარემოში არ შესრულებულა |
| `BLOCKED_BY_ENVIRONMENT` | კონკრეტულმა ტექნიკურმა/ნებართვის შეზღუდვამ დაბლოკა |

წარმატებული build არ ამტკიცებს მომხმარებლის სრული გზის, მონაცემთა მთლიანობის ან აპარატურის გამართულობას. ტესტების რაოდენობები დაფარვის პროცენტები არ არის.

## რეალური baseline: ხუთი განსხვავებული ფენა

| ფენა | მიმდინარე მტკიცებულება | დასკვნის საზღვარი |
|---|---|---|
| HEAD | `f7bb982`; ბოლო თემები canonical Menu, ადგილობრივი Docker, guarded local tools | native ingress-ის ახალი allowlist HEAD-ში არ არის |
| სამუშაო ასლი | 30 modified tracked ფაილი და 2 untracked ფაილი დასაწყისში; 1,937 არსებული ფაილის SHA-256 baseline | ტესტირებულია მათი იზოლირებული ასლი, არსებული `.env*`/საიდუმლოებების გარეშე |
| იმიჯები | Docker CLI 29.8.0; Docker socket-ზე `permission denied` | არც image ID, digest, label და არც ჩაშენებული commit არ დადასტურებულა |
| პროცესები | რეალურ ბრაუზერში `http://vynic.localhost/ka`, `/request-access`, `/login`, `http://admin.vynic.localhost/login` ჩანს; `lsof` ხედავს Docker-ის port 80-ს, Vynic/Dart პროცესებს | მიმდინარე renderer-ის წყაროს parity უცნობია; `ps` აკრძალულია. მოქმედი POS/Manager არ გახსნილა მომხმარებლის მონაცემების დასათვალიერებლად |
| DB | წყაროს migration tip `20261011120000_canonical_menu_sync`; PostgreSQL binary 17.10 | მოქმედი DB-ის migration state არ წაკითხულა; migration ფაილის არსებობა deployment-ის მტკიცება არ არის |

`git show HEAD:deploy/traefik/routes.yml` და სამუშაო ფაილის შედარება ადასტურებს: `native-api`, `native-fallback`, Socket.IO-ის allowlist, opt-in LAN entrypoint, `compose.lan.yaml`, `ApiConfig`-ის explicit HTTP port 80 და enrollment URL-ის ცვლილებები **WIP-ში ინტეგრირებულია**. მიმდინარე runtime-ში მათი მუშაობა ვერ დამტკიცდა: Docker inspect აკრძალულია, ბრაუზერმა `http://api.vynic.localhost/healthz` გახსნა შეწყვიტა `ERR_BLOCKED_BY_CLIENT`-ით. ეს არ არის backend 404/გაუმართაობის მტკიცება. არც LAN listener ჩართულა და არც არსებული სერვისი გადატვირთულა.

`lsof -nP -iTCP -sTCP:LISTEN` აჩვენებს Docker proxy-ს `*:80`, მაშინ როცა `compose.local.yaml:49` loopback binding-ს ითხოვს. რეალური LAN ხელმისაწვდომობა **SUSPECTED**, არა დამტკიცებული exposure: საჭიროა Docker port mapping-ისა და host firewall-ის ნებადართული შემოწმება. ადგილობრივი PostgreSQL listener-ები დაფიქსირდა მხოლოდ metadata-ით; მათთან კავშირი არ დამყარებულა. `vankisi_database` არ წაკითხულა და არ შეცვლილა.

საწყისი stash: `stash@{0}: On main: reorg-wip-holdout`; მხოლოდ ჩამონათვალი წაკითხულია. სამუშაო ხეები: მთავარი საცავი; `/Users/vaanskii/Developer/vynic-commercial` (`e0e85f7`); `.claude/worktrees/youthful-dijkstra-f6e376` (`3583b84`); private scratch worktree (`d0d238e`, detached). HEAD-ში არ შერწყმული local branches: `main` და `claude/youthful-dijkstra-f6e376` (`cb04890`), `commercial/nonfiscal-policy-and-plan-pricing` (`e0e85f7`). არაფერი შერწყმულა/გადატანილა.

| ინსტრუმენტი | ვერსია / მდგომარეობა |
|---|---|
| Node / npm | `v24.16.0` / `11.13.0` |
| Prisma | installed `6.19.3` |
| Flutter / Dart | SDK cache metadata: `3.44.1` / `3.12.1`; CLI cache write აკრძალულია, ბრძანების წარმატება არ მტკიცდება |
| Go | `go` PATH-ში ვერ მოიძებნა; module target `go 1.26.0` ვერსიის ინსტალაციას არ ამტკიცებს |
| Docker | client `29.8.0`; server ვერსია უცნობია |
| PostgreSQL | binary `17.10 (Homebrew)`; existing DB state უცნობია |
| Python / OS | `3.9.6`; macOS `27.0`, build `26A428` |
| რესურსები | RAM-ის `sysctl` წაკითხვა აკრძალულია; CPU/RAM დატვირთვის პრეტენზია არ კეთდება |

Docker build იყენებს Node 22-ს; ჩვენი isolated build Node 24-ზე შესრულდა. production image-ის თანაბრობა ამ შედეგით არ დასტურდება.

წყაროში არსებული ბოლო milestone-ები მოიცავს commercial subscription lifecycle/access hardening-ს, canonical Menu-ს legacy compatibility-ით, shared website foundation-ს, Docker/native ingress-ის WIP-ს, POS shared input/localization/fullscreen/clean Quit-ს, signed updater/Setup-სა და local publisher-ს. ისინი შესაბამის execution paths-თან შეჯერებულია დომენურ ანგარიშებში; „implemented“ არ ნიშნავს ყველა reliability boundary-ის დახურვას. Project state-ის ისტორიული publication labels არის POS `1.0.12 / release 13`, Edge `1.0.1 / bootstrap 3`, Setup `1.0.8.0`; ეს **HISTORICAL_REPORT_ONLY** deployed-version ცნობებია და არა ამ აუდიტში წაკითხული running binary identities. Hive source format v9; აქტიური user storage არ გახსნილა.

## შესრულებული ავტომატური შემოწმებები

ყველა ქვემოთ ჩამოთვლილი source test/build შესრულდა `/private/tmp/vynic-audit-20260929-f7bb982-180325/checkout`-ში. წყაროები baseline-იდან დაკოპირდა, dependencies არსებული ინსტალაციებიდან clone-copy-ით; install/upgrade არ შესრულებულა. DB გარემო გაწმენდილი იყო და არ მიუთითებდა მომხმარებლის DB-ზე. სრული ლოგები private evidence directory-შია.

| ნაწილი | ბრძანება შესაბამის app directory-ში | შედეგი | მტკიცებულება / ფარგლები |
|---|---|---|---|
| Backend unit/service + HTTP specs | `node node_modules/jest/bin/jest.js --runInBand --testPathIgnorePatterns=integration.spec.ts --json --outputFile=<evidence>/backend-unit-result.json` | **536 pass / 7 fail**, 61/63 suites pass | `backend-unit.log`, `backend-unit-result.json`; 7 failure გარემოს socket აკრძალვას უკავშირდება |
| PostgreSQL integration | 38 არსებული `*.integration.spec.ts` suite | **არ გაშვებულა** | ახალი cluster-ის `initdb` → `shmget: Operation not permitted`; integration არ ჩათვლილა unit coverage-ში |
| Platform/customer web | `npm test -- --reporter=json --outputFile=<evidence>/apps-platform-web-test.json` | **158 pass**, 57 reported suites | component/mock proofs; ნამდვილ owner/admin session flow-ს არ ამტკიცებს |
| SaaS web | იგივე `npm test` | **19 pass**, 11 reported suites | `apps-restaurant-web-test.json` |
| Vankisi CUSTOM | test script არ აქვს | **NOT_TESTED** როგორც ავტოტესტების suite | build და lint შესრულდა; live customer flow არ გაშვებულა |
| website-client | `npm test` | **6 pass** | `packages-website-client-test.json` |
| custom-site template | `npm test` | **3 pass** | `templates-custom-site-test.json`; template არ არის deployed customer app |
| Backend, Platform, SaaS, Vankisi, template build | თითოეულში `npm run build` | **ყველა 5 pass** | `build-results.json`; დაახლოებით 4.90 / 3.86 / 1.58 / 7.21 / 1.22 წამი |
| website-client typecheck | `npm run typecheck` | pass | 0.47 წამი; ეს capacity benchmark არ არის |
| Shared contracts | `node packages/contracts/scripts/generate.mjs --check` | pass | `contracts.log`; generated ფაილები არ შეცვლილა |
| Flutter POS / Manager unit-widget-live | `flutter --version` preflight | **BLOCKED_BY_ENVIRONMENT** | SDK engine stamp/realm write აკრძალულია; არც `flutter test` და არც `analyze`-ის pass არ გვეკუთვნის |
| Go Edge / installer executable | `go version` preflight | **BLOCKED_BY_ENVIRONMENT** | binary PATH-ში არ არის; `go test ./...`, `govulncheck` არ გაშვებულა |
| Product wrapper | `python3 tool/product_test.py` | **3 pass** | `product_test.py.log` |
| Fullscreen source/wrapper | `python3 tool/windows_fullscreen_test.py` | **1 pass** | ფიზიკური fullscreen ქცევას არ ამტკიცებს |
| Publisher | `python3 tool/publish_local_pos_test.py` | **11 pass** | mocked publisher, რეალური release არ გამოქვეყნებულა |
| Local release tooling | `python3 tool/local_windows_release_test_test.py` | **11 pass** | mocked VM/files, არა Windows execution |
| PE resource tooling | `python3 tool/windows_pe_test.py` | **5 pass** | resource encoding, არა Authenticode trust |
| Migration replay/backfill, fresh restore | preflight მხოლოდ | **BLOCKED_BY_ENVIRONMENT** | DB შექმნილი არ არის; არსებულ მონაცემებზე fallback არ გამოგვიყენებია |
| Docker smoke/restore/native LAN | read-only preflight | **BLOCKED_BY_ENVIRONMENT** | არც rebuild და არც reset არ შესრულებულა |

Backend-ის 7 failure: `custom-website-runtime.spec.ts`-ის 4 local-server case — `listen EPERM 127.0.0.1` და შედეგად beforeAll timeout; `customer-website-logo.http.spec.ts`-ის 3 case — `listen EPERM 0.0.0.0`, შედეგად Supertest null-port. კლასიფიკაცია: **გარემოს მიერ დაბლოკილი HTTP verification**, არა ავტომატურად პროდუქტის bug, flaky test ან stale fixture. წარმატებული unit ნაწილი ამ HTTP გზებს არ ფარავს. timeout არ გაზრდილა და ტესტი არ შეცვლილა.

Python-ის პირველი მცდელობა `python3 -m unittest tool/...` იყო არასწორი invocation: sibling import ვერ პოულობდა `product`/`publish_local_pos`/`windows_pe`. შემდეგ გაშვებულია ფაილების არსებული პირდაპირი entrypoint-ები. ეს იყო აუდიტის harness invocation-ის შეცდომა; source/test ცვლილება არ მომხდარა.

გაუშვებელი ფაილების სრული path inventory შენახულია private `unexecuted-test-inventory.json`-ში: **38** backend integration spec, **135** Flutter `_test.dart` ფაილი, **16** Go `_test.go` ფაილი. ეს source-file counts-ია, არა executed test case count და არც coverage. სიის ხელახლა აგება: შესაბამის roots-ზე `rg --files` და suffix filter; SDK/platform/build-tag განსხვავება გაშვებისას უნდა გათვალისწინდეს.

### Lint

| ნაწილი | `npm run lint` | კლასიფიკაცია |
|---|---|---|
| Backend | 3,860 errors + 646 warnings | `REPRODUCED`, მოქმედი static-analysis baseline წითელია; ყველა ჩანაწერი runtime defect არ არის |
| Platform web | 13 errors + 5 warnings | იგივე; test code-იც შედის |
| SaaS web | pass | ამ lint კონფიგურაციის ფარგლებში |
| Vankisi | 18 errors + 6 warnings | unsafe `any` და hook dependencies ჩათვლით |

არ შესრულებულა `--fix`, dependency upgrade ან წესების შესუსტება. საწყისი შედეგები: `*-lint.log`.

## ახალი სინთეზური დეფექტის რეპროდუქციები

| ID | ტიპი | მოსალოდნელი | მიღებული |
|---|---|---|---|
| SEC-01 | რეალური TypeScript service, mocked DB/axios | 110 GEL კალათა ვერ გადადის 1 GEL provider order-ში | direct reservation path-მა შეინახა და BOG payload-ში გაგზავნა 1 GEL |
| SEC-02 | რეალური signup/user service, synthetic records | სხვისი guest booking არ ჩანს email ownership-ის მტკიცების გარეშე | ახალი unverified account იღებს email-ით დამთხვევილ ჯავშნის პირად ველებს |
| MENU-03 | რეალური `MenuCatalogService.apply`, mocked Prisma | mutation-ის exact retry აბრუნებს თავდაპირველ durable entity result-ს | result revision 2 + current entity revision 3; წაშლის შემდეგ `deleted:false`, `entity:null` |
| MGR-01 | რეალური Manager service, mocked Prisma | ოთხივე synthetic table სხვადასხვა floor-ზე ხელმისაწვდომია | hardcoded 9+4 filter-მა 4-დან 2 დატოვა |
| MGR-02 | რეალური Manager service, mocked Prisma/dispatcher | table release-ს POS command/ACK სჭირდება | success true, Cloud pointer null, dispatch count 0 |

ლოგები: `web-proofs/result.log`, `menu-retry-repro.log`, `manager-synthetic-repro.log`. არც DB, არც HTTP guard, არც provider acceptance არ იყო ამ mock proofs-ის ნაწილი. ქსელური საბანკო მოთხოვნები: **0**. ზუსტი გაშვების ინსტრუქციები შესაბამის დომენურ ანგარიშებშია.

## Manual proof მატრიცა

| საშუალება | ახალი მტკიცებულება | რაც არ შემოწმებულა |
|---|---|---|
| რეალური ბრაუზერი | Georgian public page, access request, owner login, Platform login; DOM/სკრინშოტი; რეალურად გაზომილი viewport **390×844**; required/name/autocomplete/type ატრიბუტები; პირველი Tab-ის ხილული outline | authenticated flows, submit persistence, 375/768/1280/1440 რეალური layout |
| Viewport control | მოთხოვნილი სხვა ზომები; DOM მაინც 390 აჩვენებდა | ამიტომ სხვა ზომები **არ ჩაითვალა** checked-ად |
| რეალური Flutter app | არ შეხებია გაშვებულ მომხმარებლის აპს | POS 1024×768, Manager phone/tablet, screen-reader/native semantics |
| Windows executable | ისტორიული runbooks არსებობს | ამ აუდიტში install/update/restart/crash/rollback არ გაშვებულა |
| ფიზიკური printer/payment device | არცერთი | ბეჭდვა, ქაღალდის ამოწურვა, duplicate print, EFT authorization/capture |
| სიმულირებული protocol | მიმდინარე unit suites + ზემო mock proofs | multi-terminal hardware/partition/capacity |

საწყის მობილურ screenshot-ზე form entrance animation ჯერ არ დასრულებულიყო; მოგვიანებით სრული form გამოჩნდა. ეს არ გამოცხადებულა ცარიელი ფორმის მუდმივ დეფექტად. Access request field labels/required/type/autocomplete კარგია. `/ka` floor-demo-ს AX სახელებში `Zoom in`, `Zoom out`, `Fit canvas` ჯერ ინგლისურად რჩება — მცირე ლოკალიზაციის საკითხი, არა acquisition blocker. Web audit სამიზნეა [WCAG 2.2 AA](https://www.w3.org/TR/WCAG22/); შესაბამისობა არ სერტიფიცირდება.

## პროდუქტისა და მდგომარეობის მატრიცის წაკითხვის წესი

დეტალური server enforcement და უარყოფითი ტესტების წყარო იხ. [WEB_COMMERCIAL_SECURITY.md](WEB_COMMERCIAL_SECURITY.md). პროდუქტის entitlement ≠ UI button ≠ runtime readiness. მიმდინარე direct API negative integration test შესრულება **დაბლოკილია**; ქვემოთ `CONFIRMED_BY_CODE` მატრიცაა.

| კომბინაცია | owner sections/მენიუ | POS / Manager | უსაფრთხო კომერციული ფარგლები |
|---|---|---|---|
| NO_PLAN / missing non-legacy subscription | identity/settings/subscription/request; paid sections locked | ახალი enrollment/Manager product access denied | onboarding shell; არა trial/paid პროდუქტი |
| Website only | profile/menu/public info/publish, SAAS/CUSTOM ოპერატორის არჩევანი | POS/Manager არ ეძლევა | ყველაზე ვიწრო read-only website pilot კანდიდატი; payments/accounts/reservations გამორთული |
| POS only | POS setup; owner menu გზა WEBSITE-ს ითხოვს — COM-01 | enrollment; live operation ლოკალურია | ახალი canonical POS pilot MENU/POS durability gate-ებზეა დამოკიდებული |
| POS + Manager | Manager setup + modules entitlement-ის მიხედვით; იგივე menu წინააღმდეგობა WEBSITE-ის გარეშე | ერთი operational primary; remote mutations პრობლემურია | Manager read-only რეჟიმი უნდა იყოს რეალურად enforceable |
| POS + Website | ერთიანი catalog, ორივე renderer | ერთი operational writer | menu journal/backup და website gates საჭიროა |
| POS + Website + Manager | ყველა შესაბამისი section | მეტი entitlement არ ქმნის multi-POS authority-ს | full package ამ ეტაპზე BLOCKED |
| optional inventory/finance/payroll/profitability | module feature და Staff permission ერთმანეთს ემატება | inventory/finance writes Cloud-ში | მიმდინარე valuation არ არის ისტორიული realized profit; warehouse suite არასრულია |
| Manager only / Website + Manager | feature override-ით ტექნიკურად შესაძლებელი grant არ უდრის სრულ დამოუკიდებელ პროდუქტს | Cloud inventory/payroll მუშაობის გზები არსებობს; live operation/Sale mirror POS-ზეა დამოკიდებული | ცალკე გასაყიდი პაკეტის product decision; ავტომატურად supported-ად არ ჩაითვალოს |

| subscription მდგომარეობა | server commercial შედეგი | ადგილობრივი POS / შენახული მონაცემები |
|---|---|---|
| TRIAL, მომავალი end | არჩეული plan features; media upload denied | initial setup-ის შემდეგ offline core ინარჩუნებს მუშაობას |
| expired/undated trial | server clock-ით უარი; reconciliation → SUSPENDED | მონაცემი არ იშლება; established local operation არ ჩერდება |
| ACTIVE | plan + ნებადართული overrides, readiness/permission დამატებითი პირობით | ისტორიული Sale/შეთანხმებული ფასი უცვლელია |
| PAST_DUE | ახალი anchored unpaid პერიოდი access-ს კეტავს; historical manual grace ცალკე compatibility-ა | enrolled device sync/settlement continuity გამონაკლისები განზრახაა |
| SUSPENDED / CANCELLED | effective module keys ცარიელია | data retention; არ უდრის remote disk wipe-ს |
| scheduled downgrade/cancel | ცვლილება renewal-ზე | ძველი შეთანხმება მანამდე მოქმედებს |
| pending upgrade payment | ახალი უფლებები trusted confirmation-მდე არ გაიცემა | redirect წარმატებას არ ანიჭებს |
| missing subscription + explicit legacy marker | შეზღუდული server-owned compatibility | ჩვეულებრივ ახალ Venue-ზე არ ვრცელდება |

Already-open session-ზე server request-ის entitlement ხელახლა მოწმდება; browser-ის უკვე ჩამოტვირთული ინფორმაცია ვერ „დაბრუნდება“. Socket-ის სრული revocation/privacy უარყოფითი ტესტი, native cache expiry და open-session transition matrix ჯერ ხელახლა გასაშვებია. `NON_FISCAL_CLOSE` default-off-ია და plan-ში არ უნდა მოხვდეს; მხოლოდ explicit override + Staff permission. ფინანსური/provider settlement-მდე entitlement-ის დაკარგვამ დასრულებული ფულის reconciliation არ უნდა შეაფერხოს.

## გაუმართაობები და შეზღუდული performance გეგმა

| სცენარი | მიმდინარე შეფასება | აუცილებელი შემდეგი proof |
|---|---|---|
| Cloud down, უკვე დაყენებული ერთი POS | DEGRADED WITH EXPLICIT LIMITATION | local order/close/restart, შემდეგ exact mirror; ახალი menu lines სხვადასხვა ტერმინალზე არ არის ერთნაირობის გარანტია |
| projection დროს local edit / pending menu backup | DATA LOSS/INTEGRITY RISK | MENU-01/02 fault-injection |
| item transfer / Close Day crash | DATA LOSS/INTEGRITY RISK | ყოველი durable write-ის შემდეგ kill/restart |
| uncertain cloud ACK | domain-dependent | canonical retry MENU-03; Edge command journal და ledger replay-ის PG proof |
| Edge restart/down / partition | DEGRADED / NOT PROVEN multi-writer | primary-only policy; shadow არ ჩაითვალოს production authority-დ |
| DB down / media disk unwritable | NOT PROVEN end-to-end | isolated server: explicit error, no false success, persisted quota rollback |
| clock/trial expiry/suspension | code/unit evidence; live NOT PROVEN | fake clock + real DB + უკვე გახსნილი sessions |
| old client / canonical Venue | compatibility gate საჭირო | enrollment/version protocol negotiation; legacy Venue unchanged |
| backup + key recovery | NOT PROVEN / journal gaps | fresh machine/db restore; key versions + media + journals |

შემდეგი bounded benchmark-ის მონაცემები: პატარა Venue — 20 table, 200 MenuItem, 2,000 Sale, 100 StockItem; დატვირთული — 100 table, 2,000 MenuItem, 100,000 Sale, 2,000 StockItem. ეს **დაგეგმილი**, არა უკვე შექმნილი dataset-ებია. თავდაპირველად 1, შემდეგ 3 და 10 synthetic client, თითო 5 წუთი audit-owned გარემოში, max 5 requests/sec; CPU/RAM/disk/DB timings და p50/p95/p99 ცალკე. stop: error >1%, p95 >2s ან host resource contention. owner-ის service-ზე load არ გაშვებულა. არ არსებობს ამ აუდიტით დამტკიცებული production capacity.

N+1 რისკი: legacy snapshot ingestion რიგრიგობით upsert-ავს reservations/menu/history-ს; დოკუმენტის ძველი Vankisi latency **ისტორიულია** და ხელახლა არ გაზომილა. canonical delta და keyset Sale pagination დადებითი ცვლილებაა. დიდი inventory fetch/Flutter list და journal retention უნდა გაიზომოს ზემო isolated datasets-ით.

## გარემოს შეზღუდვების სრული სია

Docker socket denied; Flutter SDK cache writes denied; PostgreSQL isolated `initdb` shared-memory denied; HTTP test listeners denied; npm advisory registry DNS `ENOTFOUND`; Go/govulncheck/trivy/grype ვერ მოიძებნა; `ps`/RAM `sysctl` denied; native API browser navigation blocked; viewport override requested sizes ფაქტობრივად არ აისახა. ნებართვის ბლოკები არ შემოვლილა. ეს შეზღუდვები განმეორებითი proof milestone-ის ნაწილია და არა პროდუქტის წარმატების ნიშნები.

საბაზრო პირველწყაროები და წვდომის თარიღი: [MARKET_BENCHMARK.md](MARKET_BENCHMARK.md). საბოლოო WIP-ის უცვლელობისა და რესურსების შედეგი: [RESOURCE_MANIFEST.md](RESOURCE_MANIFEST.md).
