# უსაფრთხოება, საიმედოობა და გამოშვების საზღვრები

2026-09-29; `f7bb982` + საწყისი WIP. ეს არის შეზღუდული, მტკიცებულებაზე დაფუძნებული აუდიტი — **არა უსაფრთხოების სერტიფიცირება ან ნულოვანი შეცდომის გარანტია**. დეტალური issue cards: [WEB_COMMERCIAL_SECURITY.md](WEB_COMMERCIAL_SECURITY.md), [POS_MENU_EDGE.md](POS_MENU_EDGE.md), [INVENTORY_MANAGER_FINDINGS.md](INVENTORY_MANAGER_FINDINGS.md). პრიორიტეტების ერთადერთი სამუშაო სიაა [MASTER_BACKLOG.md](MASTER_BACKLOG.md).

## საფრთხის მოდელი

დასაცავია: რესტორნის გაყიდვა/შეკვეთა, captured tender, მარაგი/ვალი, სტუმრისა და თანამშრომლის პირადი მონაცემები, merchant credential, Device identity, public content approval და update trust chain. თავდამსხმელად განიხილება anonymous სტუმარი, ერთი Venue-ს კანონიერი მაგრამ სხვის მონაცემზე წვდომის მსურველი მომხმარებელი, მოპარული session/device/backup-ის მფლობელი, არასწორი deployment და განმეორებული/დაგვიანებული callback. crash, დაკარგული ACK და partition განზრახ შეტევა არ არის, თუმცა იგივე integrity boundary-ს აზიანებს.

| საზღვარი | კონტროლი და არსებული საფუძველი | მიმდინარე დასკვნა |
|---|---|---|
| browser/native → Cloud | განსხვავებული principals; DTO/guards; production proxy trust | alternate booking path თანხას ენდობა (SEC-01); სრულ HTTP negative matrix-ს ხელახლა გაშვება სჭირდება |
| principal → Venue | Device→Venue; Staff→Venue; owner membership; Host→VenueDomain; callback stored identity | სწორი დიზაინია; mock proof tenant-isolation proof-ად არ ჩაითვალა |
| Platform → restaurant | ცალკე PlatformUser; live role/active checks, audit | Staff impersonation არაა; per-session revocation/MFA ფართო admin rollout gate-ია |
| guest → WebsiteUser | session cookie და account identity | email match ownership-ის მტკიცებად გამოიყენება (SEC-02) |
| Cloud → POS | durable pull/claim/ACK და local command journal | Cloud mirror-ის direct writes და false completed UI (MGR-02/03/05) |
| POS → local disk/backup | Hive, close journal, pinned data dir | menu/closure/Edge journal backup gaps; plaintext PIN/credential protection |
| website → bank | Venue encrypted config revision, signature raw body | expected amount/state ordering/reconciliation gaps (SEC-01, WEB-04) |
| source → image/update | lockfiles, generated contracts, Ed25519 manifests | image digest/source revision unknown; production Authenticode/hardware proof missing |

კრიტიკული წესები უცვლელია: Cloud არ რეკავს LAN-ში; Venue-ს client ID არ იძლევა tenant authority-ს; plan არ ნიშნავს operational policy-ს; POS core offline მუშაობას subscription renewal არ უნდა აუქმებდეს.

## ყველაზე მნიშვნელოვანი მიმდინარე რისკები

**SEC-01 / SEC-02 — სინთეზურად გამეორებული უსაფრთხოების დეფექტები.** რეალური service კოდით, mocked persistence/network-ზე 110 GEL-ის ნაცვლად provider payload 1 GEL გახდა; arbitrary unverified email account-მა შესაბამისი guest reservation-ის name/email/phone/notes მიიღო. ეს ორი მიზეზი ბლოკავს შესაბამის paid booking/customer-account ფუნქციას. ნამდვილ provider-ზე/მომხმარებელზე ტესტი არ ჩატარებულა.

**WEB-01/03/04 — reservation/payment lifecycle.** check-then-create availability ვერ უზრუნველყოფს ერთ მაგიდას ერთ hold-ს; 10-წუთიანი hold და 30-წუთიანი bank order სხვადასხვა ფანჯარაა. `posReservationId` queue insert-მდე იწერება და failure შეიძლება retry-ს გამოტოვებდეს. ხელმოწერილი callback-ის ნამდვილობა საკმარისი არაა: საჭიროა amount/currency, event identity და დაშვებული monotonic financial transition. Entitlement-ის გაუქმების შემდეგ უკვე დაწყებული გადახდის reconciliation სწორად უნდა გაგრძელდეს.

**WEB-02 — migration publication boundary.** shared website foundation migration draft-ს published-ზე პრიორიტეტს აძლევს და live row-ში გადააქვს. კონკრეტული live გაჟონვა არ შემოწმებულა, მაგრამ upgrade algorithm publication-ის კონტრაქტს არღვევს. არსებული migration არ გადაიწეროს; საჭიროა audit/reconciliation და საჭიროებისას წინამიგრაციული backup-იდან მხოლოდ დამტკიცებული მნიშვნელობების აღდგენა.

**MENU/POS — ადგილობრივი აღდგენადობა.** acknowledged local edit-ისათვის journal+projection recoverable boundary აკლია; projection rewrite-ს შეუძლია await-ის დროს გაკეთებული ცვლილება დაკარგოს; reapply-ში old intent-ის remove და replacement put ცალ-ცალკეა. backup აკლებს canonical/closure/Edge command journal-ებს. Close Day, item transfer და table create-ს shared durable admission/recovery proof აკლია. Scope-ით ეს P0-ებია ახალი canonical POS/შესაბამისი core operation release-სათვის; არ ნიშნავს, რომ ყველა არსებულ Sale ჩანაწერს უკვე შეცდომა აქვს.

**Manager — ავტორიტეტისა და შედეგის სინამდვილე.** 4 synthetic table-იდან fixed filter-მა 2 დამალა; actual `freeTable` method-მა success დააბრუნა, Cloud pointer გაანულა და 0 POS dispatch გააკეთა. queued request-ს completed toast და stale cache-ს fresh success შეიძლება მოჰყვეს. inventory/payroll direct Cloud mutations და POS work განსხვავებული completion contracts-ით უნდა იყოს ნაჩვენები.

## მოქმედი დადებითი კონტროლები

კოდში არსებობს membership/Staff/Device/server-Host tenant resolution; `SUPPORT_READONLY` mutation denial; NO_PLAN და server-time trial expiry; NON_FISCAL_CLOSE plan filtering; hashed ერთჯერადი invite/enrollment codes; preview audience და live membership recheck; Venue-სკოპიანი media references, raster decode/byte/pixel caps/quota; registered-domain-only DNS-pinned SSRF check redirect-ის გარეშე; BOG AES-GCM+A​​AD და credential revisions; signed callback verification; idempotent CloudSale/receiving/payment identities; Edge durable delivery და uncertain remote print-ის ავტომატური გამეორების შეზღუდვა. მათი მიმდინარე unit proof არსებობს; ყველა DB/concurrency/production control ამ run-ში ხელახლა არ გამოგვიცდია.

ძველი leads-ის შედეგი: anonymous reservation map-ში guest names/phones აღარ ბრუნდება; Website SUPER_ADMIN `adminVenueId`-ით არის შემოსაზღვრული; global WebsiteUser თავისთავად cross-Venue privilege არ არის. unverified email linkage და booking concurrency **რჩება**. public immutable media-ის ხელმისაწვდომობა access removal-ის შემდეგ **განზრახ პოლიტიკის დასაზუსტებელი** საკითხია; ეს ავტომატურად private-media leak არ არის, რადგან public URL თავიდანვე საჯაროა.

## ASVS მოთხოვნების შერჩეული L2 რუკა

მიმდინარე ოფიციალური stable release არის **OWASP ASVS 5.0.0**; bleeding-edge build არ გამოყენებულა მოთხოვნების ნომრებისთვის. [ოფიციალური releases](https://github.com/OWASP/ASVS/releases), [ვერსიით დაფიქსირებული მოთხოვნები](https://raw.githubusercontent.com/OWASP/ASVS/v5.0.0/5.0/docs_en/OWASP_Application_Security_Verification_Standard_5.0.0_en.json), წვდომა 2026-09-29. L2 მოიცავს შესაბამის L1 მოთხოვნებსაც. ქვემოთ მოკლე შინაარსია, არა სრული სტანდარტი.

| ზუსტი ID | დონის მინიმუმი / თემა | Vynic evidence / ხარვეზი |
|---|---|---|
| `v5.0.0-1.2.4` | L1, query parameterization | Prisma/parameterized SQL არსებობს; exhaustive injection sweep NOT_TESTED |
| `v5.0.0-1.3.6` | L2, SSRF | runtime check allowlist/pinning/no redirects; adversarial live matrix NOT_TESTED |
| `v5.0.0-2.2.1` | L1, input validation | SEC-01 pricing/body trust ვერ აკმაყოფილებს მიზანს |
| `v5.0.0-2.3.2` | L2, business limits | trusted amount/commercial gates; alternate path პრობლემურია |
| `v5.0.0-2.3.3` | L2, სრული transaction | MGR-05, WEB-03, POS transfer/day gaps |
| `v5.0.0-2.3.4` | L2, double-booking lock | WEB-01; local table admission POS-05 |
| `v5.0.0-5.2.1` | L1, upload size | byte/pixel decode limits კოდით; HTTP transport blocked |
| `v5.0.0-7.3.1` | L2, inactivity timeout | სრულ session policy proof-ს საჭიროებს |
| `v5.0.0-7.4.1` | L1, logout invalidation | self-contained token revocation gap, SEC-03 |
| `v5.0.0-7.4.2` | L1, disabled account | live active checks დადებითია; socket/open-session matrix ღიაა |
| `v5.0.0-7.4.3` | L2, factor-change session termination | password-change replay/session reset ჯერ დასამტკიცებელია |
| `v5.0.0-7.4.5` | L2, admin session termination | per-session revoke gap |
| `v5.0.0-8.2.2` | L1, object authorization | SEC-02 guest ownership flaw; cross-Venue PG tests blocked |
| `v5.0.0-8.2.3` | L2, field authorization | anonymous map safe projection დადებითია |
| `v5.0.0-8.3.1` | L1, trusted authorization layer | server product guards; UI hiding ერთადერთი კონტროლი არაა |

Native/mobile reference: [OWASP MASVS](https://mas.owasp.org/MASVS/) — storage, authentication, network, platform და privacy მიმართულებები. ეს Windows desktop-ის სრული სტანდარტი არ არის. საჭიროა ადგილობრივი file ACL/keychain, backup confidentiality, signed update+rollback, IPC caller/authentication და physical admin threat model-ის ცალკე proof. MASVS certification არ ხდება.

## SEC-05 — local PIN/credential და backup confidentiality

- **ტიპი:** SECURITY HARDENING; **P1** restaurant device/backup rollout; `CONFIRMED_BY_CODE`, მაღალი confidence. მომხმარებელი: Staff/owner, დაკარგული backup-ის ან shared workstation-ის შემთხვევაში.
- კოდი: `apps/operations/lib/core/database/repositories/user_repository.dart:85` raw `pinCode` comparison; `backup_repository.dart:203` user PIN serialization; `:148` plaintext JSON write. Device credential `edge_device.json`-შია, OS keychain არაა. Default `000000` debug-only-ა და release default password-ად არ გამოცხადებულა.
- მოსალოდნელი: backup/device disclosure არ ხსნიდეს მოქმედ credential-ს დამატებითი დაცვის გარეშე. ფაქტი: filesystem readability უსაფრთხოების მთავარი საზღვარია; leaked backup რეალურად არ შეგვიქმნია/წაგვიკითხავს.
- Remedy: bounded authentication verifier/attempt control, OS-keystore credential, encrypt/authenticate backup + გასაღების რეალური recovery procedure, ACLs, owner-visible export warning. არსებული offline auth და usable recovery არ დაიკარგოს.
- Acceptance: restricted-user read denial, stolen backup plaintext scan synthetic fixture-ით, wrong key/integrity failure, supported old backup import, fresh machine recovery; backup key-ს მონაცემთან ერთად იმავე დაუცველ bundle-ში არ ჩააბაროთ. effort M/L, versioned backup compatibility; owner-ს key recovery owner უნდა განესაზღვროს.

## დამოკიდებულებები და პროგრამული მიწოდების ჯაჭვი

ექვს Node package-ში გაშვებულია `npm audit --json --registry=https://registry.npmjs.org --fetch-retries=0 --fetch-timeout=20000`. ყველა გაჩერდა **registry DNS `ENOTFOUND`**-ზე. ამიტომ **მიმდინარე advisory რაოდენობა, CVE severity ან „0 vulnerability“ არ გვაქვს**. ძველი advisory count არ გადმოტანილა. არც upgrade და არც `audit fix` გაშვებულა.

| ეკოსისტემა | ზუსტი მიმდინარე inventory | რისკის/შემდგომი triage-ის ფარგლები |
|---|---|---|
| Backend Node | Prisma6.19.3, Nest core11.1.27, axios1.18.0, sharp0.35.4 lockfile-ში | axios server fetch/provider/runtime-ს აღწევს; sharp untrusted uploaded image-ს; registry scan BLOCKED |
| Platform | Vite8.2.2, ReactRouter7.18.3 | Vite ძირითადად build/dev; ReactRouter browser runtime; direct/transitive advisory ხელახლა სკანირდეს |
| SaaS | Vite7.3.6 | build/dev; static deployed server vulnerability განსხვავებული საქმეა |
| Vankisi | axios1.17.0, ReactRouter7.17.0, sharp0.34.5, Vite6.4.2 | browser axios vs backend SSRF reachability არ აურიოთ; sharp აქ build tooling-შია |
| Dart/Flutter | lockfiles არსებობს; SDK metadata3.44.1/3.12.1 | `dart pub outdated`/audit unavailable; native plugin advisory map NOT_TESTED |
| Go | target1.26.0; grpc1.79.3, protobuf1.36.11, modernc sqlite1.59.0 | `govulncheck` unavailable; binary call reachability უცნობია |
| Containers | node22-bookworm-slim, postgres17-bookworm, traefik3.6, nginx-unprivileged1.28-alpine | mutable tags, digest pinning არაა; image scanner/runtime image inventory unavailable |

ცალკეული advisory-ის საბოლოო ჩანაწერს უნდა ჰქონდეს: exact locked version, direct/transitive chain, runtime/build/dev scope, reachable function/input, advisory URL, severity, fixed version, compatibility risk და owner. დაუდასტურებელი exploit exposure-ზე P0 არ მინიჭებულა. `OPS-03` არის **უცნობი supply-chain release gate**, არა გამოგონილი CVE.

დადებითი: package lockfiles, `npm ci` Docker build-ში, `.dockerignore` გამორიცხავს `.env*`, secrets/node_modules/git; generated contracts check pass; runtime non-root/cap_drop/no-new-privileges. `.dockerignore` არ ამტკიცებს, რომ image contents secret-free-ა — built layers არ შემოწმებულა. Dockerfile-ებში source revision OCI LABEL და immutable manifest binding არ ჩანს; `GET /healthz` მხოლოდ DB connectivity-ს აბრუნებს, არა build identity-ს. package.json-ის `latest`-ების მიუხედავად lockfile ამ build-ის resolve-ს აფიქსირებს; lock update review კვლავ საჭიროა. ახალი skill/plugin არ დაყენებულა; pinned skills-ის არსებობა მათი სრული supply-chain audit არ არის.

## Deployment და აღდგენა

ერთი migration owner (`migrate` service), backend startup direct node, PostgreSQL internal network, media persistent volume და optional Studio loopback/tools profile სწორ საფუძველს ქმნის. production TLS-ს external certificate/DNS/provisioning სჭირდება; hosted production აქ არ არსებობს დადასტურებული მტკიცებულებით. static frontend env build-timeა; runtime config-ის შეცვლა compile-time setting-ს ავტომატურად არ ცვლის.

`docs/DEPLOYMENT.md:400` აღწერს DB/media backup და selective restore-ს; ეს **runbook-ია**, არა ამ აუდიტში fresh restore-ის შედეგი. DB dump-ს სჭირდება შესაბამისი media snapshot და payment/PIN encryption key versions. აცდენილ DB/media snapshot-ს შეუძლია reference mismatch. key-ის დაკარგვა encrypted merchant config-ის აღდგენას შეუძლებელს გახდის. binary rollback მხოლოდ მაშინ ვარგა, თუ ძველი client schema/contract-ს ესმის; migration rollback-ის ავტომატური გარანტია არ არსებობს.

**OPS-01:** source+WIP → immutable build manifest → image digest → running health/build ID → DB migration checksum → owner-owned backup restore უნდა გადაიბას ერთ release dossier-ში. exact native origin REST+Socket.IO+LAN flow, Windows install/enroll/close/restart/printer, encrypted-key recovery და old/new compatibility proof rollout gate-ია. ამ აუდიტში built/running image provenance, Windows hardware, DB replay/restore **BLOCKED/NOT_TESTED** დარჩა. პროდუქტის „completed ingress“ მტკიცება მხოლოდ code state-ს ეხება.

**OPS-02:** local source loopback binding და `lsof` wildcard port80 დაკვირვება ერთმანეთს გადასამოწმებლად ტოვებს. სიმძიმე **P1 მხოლოდ თუ unintended LAN exposure დადასტურდა**, confidence დაბალი; ახლა `SUSPECTED`. არ გაგვიხსნია port და არც ქსელი დაგვისკანირებია. Owner-run check: `docker port <exact-proxy-container>` და field-limited inspect; არსებული mapping/firewall-ის შეთანხმებულ საზღვართან შედარება. არ დაბეჭდოთ სრული secret-bearing Compose config.

## Privacy, იურიდიული და ლიცენზიის gaps — SEC-06

პირადი მონაცემებია owner/operator accounts, Staff identity/PIN verifier, guests name/phone/email/reservation/preorder/notes, payment refs, audit actors/device addresses, push tokens და შესაძლოა ფოტოებზე ადამიანები. მესამე მხარეები კოდით: BOG, Firebase/FCM, Google Maps, owner-configured external media/social URLs. მათი privacy/processor contracts ამ საცავიდან ვერ დასტურდება.

მოქმედი ქართული პირველწყაროა [„პერსონალურ მონაცემთა დაცვის შესახებ“ კანონის კონსოლიდირებული ტექსტი](https://www.matsne.gov.ge/ka/document/view/5827307), წვდომა 2026-09-29. განხილვის ჩარჩო: მუხლი4 — მიზანი/მინიმიზაცია/შენახვა; 26–27 — დიზაინში დაცვა და უსაფრთხოება; 28 — processing record. კონკრეტული retention ვადა, deletion-ისა და საბუღალტრო ჩანაწერის სავალდებულო შენახვის შეჯერება, საზღვარგარეთ გადაცემა და incident obligations **კვალიფიციურ ქართულ იურიდიულ შემოწმებას მოითხოვს**. ძველი მარეგულირებლის სახელით მოქმედი ვალდებულება არ უნდა ვივარაუდოთ; მიმდინარე ტექსტი უნდა შემოწმდეს. VAT/ფისკალური პოლიტიკა ამ აუდიტით არ შექმნილა.

- `apps/vankisi-custom-web/src/components/Footer.tsx:163` privacy link `href="#"`-ია; code search-მა platform request flow-ში სრულ notice/retention/export/deletion workflow ვერ გამოავლინა. ეს scoped evidence-ია, არა ყველა გარე სამართლებრივი დოკუმენტის არარსებობის მტკიცება.
- **P1** რეალური პირადი მონაცემის collection rollout-ისათვის, `CONFIRMED_BY_CODE` placeholder + `NOT_TESTED` operational compliance. Remedy: რეალური notices, processing inventory, role-based exports, authenticated deletion/request workflow; legally retained financial history-ის immutable retention და public/anonymized projection ცალ-ცალკე. Marketing consent/demo follow-up purpose ცხადი უნდა იყოს.
- Acceptance: synthetic person export/delete request, wrong-tenant denial, retained Sale-ის კანონიერი reason, backup expiry/re-delete plan და request audit. Fonts/photos/vendor assets-ის license inventory და მესამე მხარის terms ჯერ `NOT_TESTED`; უფლებების დოკუმენტირება, არა ავტომატური file deletion. effort M, owner/legal გადაწყვეტილება აუცილებელია.

## უსაფრთხო გასაშვები proof გეგმა

პირველ რიგში მხოლოდ audit-owned PostgreSQL/Cloud/media directory/fixtures. ყოველი DB-ის ზუსტი სახელის არარსებობა შემოწმდეს შექმნამდე; resource manifest შეივსოს; cleanup მხოლოდ manifest-owned სახელებს შეეხოს. ორი Venue, separate principals, fake provider, fixed time. შემდეგ crash/replay tests; ბოლოს Windows/physical device checklist. არც არსებული customer reset, არც password reset, არც real payment, არც production deployment ამ გეგმაში არ არის ნებადართული ავტომატურად.

ოპერაციული დეტალური failure matrix და 1/3/10 terminal-ის შეზღუდვები: [POS_MENU_EDGE.md](POS_MENU_EDGE.md). ამ გარემოში შესრულებული/დაბლოკილი commands: [EVIDENCE_AND_MATRICES.md](EVIDENCE_AND_MATRICES.md).
