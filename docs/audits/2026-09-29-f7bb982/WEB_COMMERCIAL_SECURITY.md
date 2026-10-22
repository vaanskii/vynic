# კომერციული უფლებები, ვებსაიტები და უსაფრთხოება — შემავსებელი აუდიტი

თარიღი: 2026-09-29, Asia/Tbilisi. სამუშაო ხე: `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b` + აუდიტის დაწყებამდე არსებული WIP. ეს ტექსტი არის ცენტრალურ ანგარიშში შესაერთებელი მიმოხილვა; აპლიკაცია, ჩვეულებრივი ტესტები და კონფიგურაცია არ შეცვლილა. კოდის მითითებები ეხება ამ checkout-ს. ორი სინთეზური გამეორება შესრულდა ცენტრალური აუდიტის მიერ მომზადებულ უცვლელ ასლზე: `/private/tmp/vynic-audit-20260929-f7bb982-180325/checkout`.

ამ მიმოხილვის პირობებში რეალური BOG, საწარმოო მონაცემთა ბაზა და `vankisi_database` არ გამოყენებულა. PostgreSQL/HTTP ინტეგრაციულ ტესტებს ცენტრალური აუდიტი ასრულებს; ქვემოთ მათი არსებობა შედეგს არ ნიშნავს. OWASP-ის ზუსტი მოთხოვნები, იურიდიული წყაროები და მიმდინარე dependency audit ცენტრალურ ანგარიშშია.

## რა არსებობს

| კომპონენტი | მომხმარებელი და ავტორიტეტი | წყარო/ჩაწერა | ოფლაინ შესაძლებლობა |
|---|---|---|---|
| Platform Admin | `PlatformUser`, ცალკე audience/type; აქტიურობა/როლი ყოველი მოთხოვნისას იკითხება | ორგანიზაცია, Venue, პროდუქტები, overrides, subscriptions, domains, Device, invitations, audit PostgreSQL-ში | არა |
| Customer Dashboard | `CustomerAccount → OWNER membership → Organization → Venue` | პროფილი, Cloud catalog, საიტის presentation/public info, media, enrollment, Manager setup, subscription requests | არა |
| Windows POS | Device → Venue; ადგილობრივი Staff/PIN | Hive ოპერაციული ავტორიტეტი; Cloud-ში სინქრონიზაცია; ახალი canonical Menu mutations | პირველადი გამართვის შემდეგ ადგილობრივი ოპერაცია რჩება; მისი სრული proof სხვა მიმოხილვაშია |
| Manager | Staff → Venue + `MANAGER_APP`, დამატებითი feature/role gates | Cloud mirror და Cloud inventory/finance; POS ცვლილებები Edge queue-ით | მიმდინარე Cloud ოპერაციები ინტერნეტს მოითხოვს |
| SaaS website | Host → ACTIVE VenueDomain → ACTIVE Venue | shared Menu/profile/public info; presentation-ის published snapshot | შენახული browser გვერდი არ არის გარანტირებული ოფლაინ პროდუქტი |
| CUSTOM website | იგივე Host tenancy; ცალკე frontend build | იგივე menu/reservation/account/BOG backend; shared info ხელმისაწვდომია, თუმცა Vankisi სრულად არ იყენებს | ცალკე გარანტია არ არსებობს |
| Go Edge / POS pull transport | credentials/წინასწარ დადგენილი tenant | Cloud command queue-ის ჩამოტანა, შესრულება/ACK; ოპერაციული Go authority ჯერ shadow-ია | არსებული POS-ის ავტორიტეტს არ ცვლის |

მნიშვნელოვანი წყაროები: `customer/customer-auth.ts:82–124`, `customer/customer.service.ts:60–101`, `platform/platform-auth.service.ts:110–160`, `auth/jwt.strategy.ts:24–40`, `website/tenancy/website-tenant.service.ts:62–94`, `edge/edge-device.guard.ts:10–49` (ყველა backend-ის `src/` ქვეშ).

მფლობელობის შექმნა გამოწერა არ არის: public request მხოლოდ მოთხოვნას ქმნის; ოპერატორი ამტკიცებს NO_PLAN ან აშკარად არჩეულ Trial-ს. მოწვევის მიღება ამატებს membership-ს და ხარჯავს ვადიან token-ს; არსებულ ანგარიშს ნორმალური Customer login სჭირდება (`owner-invitations.service.ts:299–387`). `website/provisioning/website-provisioning.ts:48–95` არჩეული Website პროდუქტისათვის SAAS/CUSTOM არჩევანს ითხოვს, ხოლო Website-only ახალი Venue-ს Cloud Menu-ს გამართვას აკეთებს. ძველი POS authority/history ჩუმად არ უნდა გადაიწეროს; admission-ის შემოწმება რჩება.

## პროდუქტისა და მდგომარეობის მატრიცა

ქვემოთ „დაშვებულია“ ნიშნავს კოდით უფლებას და არა რესტორნისათვის დასრულებულ readiness-ს. საბაზო გეგმები migration-ებითაა წარმოდგენილი: `20260831160000_product_entitlements_website_mode/migration.sql:125–142`, `20260929120000_website_only_plan/migration.sql:1–8`. ოპერატორი გეგმებს ცვლის, ამიტომ კონკრეტული live გაყიდვადი შეთავაზებების სია ცოცხალი DB-ის გარეშე არ მტკიცდება.

| კომბინაცია | Dashboard/სერვერის რეალური უფლება | Menu authoring | website/Manager/POS დამოკიდებულება |
|---|---|---|---|
| NO_PLAN | ownership, პროფილი, მოთხოვნა/კომერციული ინფორმაცია; paid API-ები დახურულია | დახურული | არც enrollment, არც ახალი website |
| Website only | WEBSITE, site setup/publication | Cloud editor პირველი დაშვების შემდეგ | POS/Manager საჭირო არ არის; SAAS ან CUSTOM |
| POS only | POS enrollment/configuration | POS წერს; Dashboard editor შეცდომით WEBSITE-ს ითხოვს — COM-01 | website NONE/არ მიენიჭება |
| POS + Manager | POS და MANAGER_APP | POS; იგივე COM-01 | Manager code+Staff; Cloud ოპერაციული მონაცემები POS mirror-იდან |
| POS + Website | POS/WEBSITE | POS + ნებადართული owner editor | canonical და legacy authority უნდა განვასხვაოთ |
| POS + Website + Manager | სამივე | canonical writers ერთ catalog-ზე | მრავალ-POS ოპერაციული მზადყოფნა აქედან არ გამომდინარეობს |
| სრული/optional | ზემოთ + `INVENTORY`, `PAYROLL`, `FINANCIAL_PLANNING`, `PROFITABILITY`, `MANAGER_RESERVATIONS`, `ADVANCED_AUDIT`, `ONLINE_PAYMENTS` | იგივე | feature მარტო სრული workflow არ არის; Manager გეგმების migration-მა ძველი modules შეინარჩუნა |
| Manager-only / Website+Manager | custom Plan/override ტექნიკურად შესაძლებელია; გეგმის ფორმა POS დამოკიდებულებას არ ამოწმებს | Website თუ შედის, owner Menu; მარტო Manager-ში არა | Staff Cloud-ში იქმნება და Edge command იწერება POS-ის გარეშეც; POS mirror-ზე დაფუძნებული ეკრანები/ქმედებები არასრულია. დასრულებულ ცალკე პროდუქტად არ გაყიდოთ გადაწყვეტილებისა და journeys-ის გარეშე |

`NON_FISCAL_CLOSE` plan defaults-იდან ყოველთვის იფილტრება; მხოლოდ Venue override ირთვება (`entitlements/effective-features.ts:18–34`). ეს ცალკე პროდუქტის გადაწყვეტილებაა და „Full“ ავტომატურად არ უნდა მოიცავდეს. `PlanCatalogService` არ უნდა დავახასიათოთ როგორც თვითნებური მომხმარებლის granting: მისი გზები Platform ოპერატორის უფლებას მოითხოვს.

| Commercial state | effective paid features/ახალი setup | media upload | უკვე არსებული მონაცემი/სესია |
|---|---|---|---|
| მოქმედი TRIAL | არჩეული plan + overrides, მხოლოდ `trialEndsAt > server now` | აკრძალულია | website მუშაობს გამოქვეყნების შემდეგ; ახალი request ხელახლა ამოწმებს უფლებას |
| ვადაგასული ან უთარიღო TRIAL | დაუყოვნებლივ დაიხურება; reconciliation → SUSPENDED | აკრძალულია | მონაცემი რჩება; საათის ადგილობრივი გადაწევა უფლებას არ ანიჭებს |
| ACTIVE, unmanaged legacy/manual | არჩეული გეგმა მოქმედებს | მხოლოდ WEBSITE+ACTIVE და quota | ავტომატური billing expiry არ უნდა დავაბრალოთ billingManaged=false ისტორიულ მდგომარეობას |
| ACTIVE, billingManaged | მოქმედი period end აუცილებელია | WEBSITE+ACTIVE + quota | end-ზე reconciliation |
| PAST_DUE | unmanaged-ში დაშვებულია; billingManaged-ში მხოლოდ ჯერ კიდევ მომავალში მყოფი period end-ისას | აკრძალულია (`ACTIVE` აუცილებელია) | ვადაგასული unpaid renewal-ში features ცარიელია |
| SUSPENDED / CANCELLED | დახურულია; ENABLED override ვერ აუვლის | აკრძალულია | მონაცემის შენახვა; callback-ის დასრულება რჩება; ადგილობრივი POS completion არ იბლოკება გამოწერის გამო |
| subscription არ არის | ახალი Venue დახურულია; მხოლოდ explicit `legacyCommercialAccess` გამონაკლისია | ACTIVE არ არის, შესაბამისად არა | „არსებული Venue“ არ არის უფლება |
| scheduled downgrade | საზღვრამდე არსებული package; შემდეგ ცვლილება | მიმდინარე სტატუსით | agreed future terms ინახება; ახალი unpaid period წვდომას არ იძლევა |
| scheduled cancellation | period end-მდე მიმდინარე package | მიმდინარე სტატუსით | საზღვარზე CANCELLED, ისტორია რჩება |
| pending upgrade payment | quote ახალ უფლებას არ იძლევა | არსებული სტატუსით | მხოლოდ trusted/manual success ცვლის გეგმის უფლებას |

ზუსტი წესები: `entitlements/commercial-state.ts:26–50`, `subscription-policy.ts:1–11`, `venue-entitlements.service.ts:17–30`, `subscriptions/subscription-reconciliation.ts:11–99`, `website/core/website-logo.service.ts:47–133`. ფოტო quota ყველა ატვირთულ, მათ შორის ჯერ დაუკავშირებელ ფაილს ითვლის; raster decode, 16M pixel limit, metadata removal, WebP conversion და Venue lock არსებობს. ძველი media-ის ownership adoption და 24-საათიანი orphan cleanup არსებობს.

Owner Dashboard საიტის/მენიუს/საათების/ფოტოების სექციებს WEBSITE-ზე ხსნის (`OwnerDashboard.tsx:90–108`). Manager credentials და loginCode იმალება feature removal-ისას (`customer.service.ts:162,188`), Staff/Platform/Customer აქტიურობა HTTP request-ზე ხელახლა მოწმდება. უკვე გახსნილი browser-ის ეკრანი შეიძლება ძველ მონაცემს აჩვენებდეს refresh-მდე; ეს მონაცემის გაქრობა არ არის. Manager WebSocket-ის რევოკაცია ცალკე შემოწმებას საჭიროებს. Enrollment-ს POS სჭირდება, მაგრამ არსებული Device authentication/sync/Edge transport სპეციალურად არ არის subscription-gated (`device-enrollment.service.ts:165–188`, `edge-device.guard.ts:21–22`); Device ან Venue-ის უსაფრთხოების გათიშვა სხვა მოქმედებაა.

## სერიოზული აღმოჩენები და backlog კანდიდატები

### SEC-01 — საჯარო მეორე booking endpoint გვერდს უვლის სერვერულ ფასს

- **P0; BUG FIX / SECURITY HARDENING; scope:** რეალური ონლაინ გადახდებიანი ვებსაიტი, SAAS/CUSTOM ერთნაირად თუ route დაშვებულია. Menu-only pilot-ს თავისთავად არ კეტავს.
- **მდგომარეობა:** `REPRODUCED` — მხოლოდ სინთეზური controller/service გამეორება; confidence მაღალი. რეალური provider acceptance და HTTP guards ამ გამეორებაში არ შესრულებულა.
- **მტკიცებულება:** `website/reservation/reservation.controller.ts:93–105` მთელ body-ს გადასცემს service-ს. `reservation.service.ts:163–195` `totalAmount`-ს ინახავს და BOG-ს აწვდის. `payment.service.ts:74–89` მხოლოდ მინიმუმ 1 GEL-ს ადგენს. უსაფრთხო `/api/bog/create-order` სხვა handler-ში ხელახლა ითვლის ფასს (`payment.controller.ts:69–87`), თუმცა მეორე გზა ღიაა. TypeScript interface DTO runtime validation კლასს არ ქმნის.
- **მოსალოდნელი/ფაქტი:** synthetic menu 100 GEL + 10% = 110 GEL; პირდაპირი booking handler-ის body `totalAmount:1`-მა ბაზის mock-ში 1 და ნამდვილ `BogService.createOrder`-ში აწყობილ provider payload-ში 1 GEL მისცა. UI ღილაკის დამალვა გზას არ ხურავს.
- **ზიანი:** სასურველი preorder-ის თვითნებური ფასით შექმნა/გადახდა; `ONLINE_PAYMENTS` operator capability-ის გათიშვის წესიც მეორე route-ზე პირდაპირ არ დგას, თუმცა feature/integration შემოწმება `requireEnabled`-ში რჩება.
- **გამეორება:** კერძო `web-proofs/website-security.cjs`; command ქვემოთ. HTTP acceptance: სინთეზური Host+active Website/BOG stub-ზე ორივე POST-ს იგივე cart და შეცვლილი ფასი მიეცეს.
- **გამოსწორება:** ფასის დათვლა ერთი server-owned application service-ის შიგნით, ყველა create entrypoint-ისთვის; integer minor units, quantity bounds, ერთიანი capability checks, validated DTO. გამართვა მოიცავდეს 0/negative/fraction/large quantities და disabled/unpublished/cross-Venue items.
- **მისაღები შედეგი:** ორივე route server amount-ს იყენებს ან legacy route დახურულია; client total/private item price ვერ აღწევს persisted/provider value-ს; ბანკთან ტესტი მხოლოდ sandbox fixture-ით.
- **მიგრაცია/rollback:** ახალი source ცვლილება, ძველი რეალური ფასების reconciliation ცალკე; უკვე დაწერილი financial record არ გადაითვალოს ჩუმად. effort M; დამოკიდებულება WEB-04-ზე მხოლოდ საბოლოო payment proof-ში; owner decision — ცარიელი-cart deposit და service fee-ის შეთანხმებული წესი.

### SEC-02 — დაუდასტურებელი email სხვის guest booking-ს აჩენს

- **P0; SECURITY HARDENING; scope:** Website customer accounts + ისტორიული guest bookings; confidence მაღალი; `REPRODUCED` mock-only.
- **მტკიცებულება:** `website/auth/auth.service.ts:48–68` arbitrary email-ით ანგარიშს verification-ის გარეშე ქმნის. `website/user/user.service.ts:40–60` confirmed/completed anonymous bookings-ს email equality-ით უკავშირებს, პასუხში სახელი/email/ტელეფონი/notes შედის (`99–114`). endpoint `GET /api/user/reservations`.
- **გამეორება/ფაქტი:** synthetic attacker დარეგისტრირდა `victim@example.invalid`-ით; matching synthetic guest-ის 1 ჯავშანი და 4 პირადი field დაბრუნდა. აუცილებელი წინაპირობა: ამ email-ის ანგარიშად რეგისტრაცია მანამდე არ არის დაკავებული.
- **მოსალოდნელი:** ანგარიშს დაუმტკიცებელი email-ით guest booking-ის ნახვა არ შეუძლია.
- **გამოსწორება:** პირველ რიგში მხოლოდ authenticated `userId` ownership; guest-ის მიბმა ერთჯერადი booking-scoped claim ან verified-email პროცესით. არ მიაბათ ყველა წარსული booking ავტომატურად მხოლოდ ტექსტური email-ის გამო.
- **მიღება:** spoofed signup-ს 0 სხვისი booking; სწორი signed claim ერთი Venue/booking-ის ფარგლებში, expiry/replay/revocation negative tests; query-შიც ownership გაფილტვრა (ახლა ყველა email-იანი guest row იტვირთება).
- **მიგრაცია:** უკვე არსებული auto-linked behavior-ის მოცილება წარსულ guest მონაცემს არ შლის; claim flow-ს შესაძლოა token persistence დასჭირდეს. effort M; owner decision — guest claim UX. rollback-მა email-based disclosure არ უნდა აღადგინოს.

### WEB-01 — availability check და booking შექმნა ატომური არ არის

- **P0; BUG FIX; scope:** გარანტირებული paid reservation გაყიდვა; `CONFIRMED_BY_CODE`, მაღალი confidence race window-ზე, რეალური PostgreSQL პარალელური გამეორება ჯერ `NOT_TESTED`.
- `reservation.service.ts:148–164` availability read-ის შემდეგ ცალკე create აკეთებს. `schema.prisma:1782–1823` table/day/slot exclusivity constraint არ აქვს; join unique მხოლოდ `(reservationId,tableId)`-ია. ორი parallel request ერთსა და იმავე თავისუფალ მაგიდას ხედავს. შემდეგ POS bridge-მა conflict შეიძლება დაინახოს უკვე გადახდის შემდეგ.
- მეორე ფანჯარა: pending booking 10 წუთში FAILED ხდება (`reservation.service.ts:456–470`), BOG order TTL 30-ია (`payment.service.ts:97`); დაგვიანებულმა გადახდამ უკვე ხელახლა დაჯავშნილი მაგიდა დაადასტუროს. POS mirror stale-ობისას მხოლოდ log warning იწერება (`website-pos-reservation-bridge.service.ts:93–117`), მომხმარებელი `isAvailable` პასუხში freshness-ს ვერ ხედავს.
- Remedy: Venue/table/date შესაბამისი lock ან occupancy record/constraint, ერთ transaction-ში hold; hold expiry-სა და ბანკის settlement-ის განსაზღვრული პოლიტიკა; stale POS mirror-ისას მკაფიო degraded state. ეს არ ნიშნავს Cloud → LAN გამოძახების აღდგენას.
- Acceptance: 20 სინთეზურ concurrent request-ში ერთი hold; timeout/late capture-ზე მკაფიო reconciliation, არც ორმაგი CONFIRMED; POS offline conflict-ისას მომხმარებელთან/ოპერატორთან მოქმედებადი სტატუსი. effort L; schema/backfill impact შესაძლებელი, არსებულ duplicates-ზე operator review; rollback არ შლის paid bookings. Owner decision: დღეს booking მთელი დღის მაგიდას კეტავს, `_timeSlot` availability-ში არ გამოიყენება (`reservation.service.ts:86–108`).

### WEB-02 — migration-მა private draft ველები საჯარო live მონაცემად გადააქცია

- **P0 migration rollout-ზე; BUG FIX / DATA MIGRATION; scope:** unpublished draft-ის მქონე უკვე გამოქვეყნებული საიტები; მაღალი confidence, `CONFIRMED_BY_CODE`; კონკრეტული მომხმარებლის მონაცემთა გაჟონვა `NOT_TESTED`.
- `20261010120000_shared_website_foundation/migration.sql:38–66` აშკარად იყენებს `COALESCE(draft,published)`, public table-ში გადააქვს workingHours/contactEmail/mapUrl/socials/gallery და ორივე snapshot-იდან შლის. `venue-public-profile.service.ts:88–104` იმავე მნიშვნელობებს live public პასუხში აბრუნებს. shared storage-ის მოთხოვნა private draft-ის publish ნებართვა არ არის.
- Expected: ბოლო დამტკიცებული published public state შენარჩუნდეს; unpublished განსხვავება owner review-მდე private იყოს. Actual: შენახული draft პრიორიტეტულია ცალკე approval-ის გარეშე.
- Verification: ცარიელ audit DB-ზე pre-migration published A/draft B შექმნა → migration replay → public პასუხში A უნდა იყოს, B private; ცენტრალურმა runner-მა უნდა დაამატოს upgrade fixture, უბრალო fresh replay ამ regression-ს ვერ ამტკიცებს.
- Remedy: უკვე გატარებული migration არ გადაწეროთ; ახალი reconciliation/repair migration და recovery report, საჭიროებისას წინამიგრაციული backup-ის staged აღდგენა. გამოქვეყნებული საწყისი მნიშვნელობები არსებული snapshot-ებიდან უკვე წაშლილია, ამიტომ ხელოვნურად ნუ გამოიგონებთ backfill-ს.
- effort M/L მონაცემის არსებობაზე; owner გადაწყვეტილება აუცილებელია live edits-ის შემდგომ პოლიტიკაზე და affected owners-ის ინფორმირებაზე. Rollback-ს separate saved published/draft evidence სჭირდება.

### WEB-03 — paid booking-ის POS identity-ის ჩაწერასა და queue dispatch-ს შორის დაკარგვის ფანჯარა

- **P0; BUG FIX; scope:** საიტიდან POS-ზე მიწოდებული ფასიანი ჯავშანი; `CONFIRMED_BY_CODE`, confidence მაღალი; fault injection `NOT_TESTED`.
- `website-pos-reservation-bridge.service.ts:229–257`: ჯერ წერს `posReservationId`, შემდეგ სხვა ოპერაციით `dispatch`. Queue write-ის ჩავარდნას `reservation.service.ts:413–431` მხოლოდ log-ავს; განმეორებული callback `!existing.posReservationId` პირობას ვეღარ გადის. Dedicated retry/reconciliation worker ამ გზაზე ვერ მოიძებნა.
- Expected: confirmed paid booking-ის durable dispatch intent ან ადამიანისთვის ხილული unresolved delivery; Actual: DB-ში link დგას, command შეიძლება საერთოდ არ არსებობდეს და ახალი callback აღარ აგზავნიდეს.
- Remedy: allocate identity + Edge/outbox insert ერთ transaction-ში; durable delivery state/retry და customer/operator pending UI. ინვარიანტი: Cloud → LAN ახალი callback არ დაემატოს.
- Acceptance: crash DB link-სა და queue insert-ს შორის; restart/replay მხოლოდ ერთი durable command და ერთი POS booking; failed handoff Dashboard-ში ჩანს. effort M; backlog/backfill — confirmed+posId+missing command აუდიტი, ავტომატურად ახალი ID არ დაემატოს. Stable idempotency identity rollback-ზეც შენარჩუნდეს.

### WEB-04 — BOG callbacks არ ქმნის დალაგებულ, თანხით შემოწმებულ payment ledger-ს

- **P0 real paid website release-სთვის; BUG FIX; `CONFIRMED_BY_CODE`, მაღალი confidence; bank sandbox/live proof არ ჩატარებულა.**
- ხელმოწერა raw bytes-ზე სწორად მოწმდება (`payment.controller.ts:184–213`); reservation→Venue/paymentIntegration და stored paymentId mismatch შემოწმება არსებობს (`reservation.service.ts:378–399`). Callback-ს entitlement არ კეტავს: ეს სწორია უკვე დაწყებული თანხის დასასრულებლად.
- დარჩენილი პრობლემა: `reservation.service.ts:365–410` ყოველი status-ით unconditional update-ს აკეთებს; completed→old pending ან refunded→replayed completed უკან გადადის. `zoned_request_time` არ გამოიყენება; event identity ledger/monotonic transition არ ჩანს. `auth_requested` და `partial_completed` პირდაპირ CONFIRMED-ია; callback handler captured amount/currency-ს stored expected amount-ს არ ადარებს. `payment.service.ts:222–225` floating 10%-ს rounding-ის გარეშე ითვლის. Provider-ის ზუსტი სტატუსების მნიშვნელობა მიმდინარე პირველწყაროს მიხედვით უნდა შეთანხმდეს; აქ მნიშვნელობები არ გამოგონილა.
- Remedy: expected minor-unit amount/currency snapshot, bank receipt reconciliation და explicit payment state machine; callback receipt/event dedupe; accepted/authorized/captured/refunded განსხვავება; harmless replay ფინანსურ მდგომარეობას არ ცვლის.
- Acceptance: completed→pending, refunded→completed replay, duplicate/concurrent callback, partial/authorized, amount/currency mismatch, provider timeout-after-create და retry; new config rotation / entitlement removal-ის შემდეგ original integration გამოყენება. effort L; ახალი payment-event persistence/backfill საჭირო, არსებული statuses reconciliation-ით და არა ისტორიის rewriting-ით. WEB-01/03-თან ინტეგრირებული proof, თუმცა დამოუკიდებელი root cause.

### COM-01 — POS-only Dashboard Menu ჯერ WEBSITE-ზეა დამოკიდებული

- **P1; BUG FIX / PRODUCT CONTRACT; scope:** POS-only / POS+Manager owner Menu editor; `CONFIRMED_BY_CODE`, მაღალი confidence.
- `customer/restaurant-foundation.service.ts:38–66` read/mutate WEBSITE-ს ითხოვს; `apps/platform-web/src/customer/OwnerDashboard.tsx:96–98` menu → WEBSITE mapping აქვს. Canonical Menu არის restaurant data და მომხმარებლის მოთხოვნა POS-only Dashboard permissions-ის შემოწმებას პირდაპირ ითხოვს.
- Expected: operator-approved owner catalog editing POS package-შიც; Actual: WEBSITE-ის გარეშე 403/დამალული Menu, მიუხედავად `cloudMenuEditingEnabled`-ისა.
- Remedy: ერთი `canRead/WriteRestaurantCatalog` policy შესაბამის კომერციულ package+owner permission+canonical authority-ით; website presentation კონტროლი ცალკე. Acceptance: active POS-only owner reads/mutates; NO_PLAN/suspended/cross-Venue denied; POS compatibility Venue ჩუმად არ გადადის CLOUD-ში; current POS-local writer უცვლელი. effort M; schema საჭირო არ არის; permission rollback ვიწრო იყოს. პროდუქტის owner-მა დაადასტუროს POS-only authoring-ის შეთავაზება.

### WEB-05 — CUSTOM binding ჯერ configuration/attestation-ია, deployed build-ის მტკიცება არა

- **P1 დაპირებული CUSTOM onboarding-ისთვის / P2 operator UX; DEPLOYMENT/OPERATIONS; `CONFIRMED_BY_CODE`, confidence მაღალი.**
- `custom-website.ts:62–83` READY/ACTIVE-ისათვის მხოლოდ entitlement+mode+siteKey+active domain-ს ითხოვს. Runtime checker (`custom-website-runtime.ts:265–317`) frontend HTTP <400-ს „reachable“-დ თვლის; `/api/website/venue`-ში მხოლოდ `profile.name` შედარებით ამბობს სწორ Venue-ს. ერთნაირი სახელი სხვადასხვა Venue-ს ვერ არჩევს და HTML build identity არ მოწმდება. Reachability და API OK ცალკეა, ამიტომ ეს თავისთავად მონაცემთა tenancy bypass არ არის.
- `website-capabilities.service.ts:79–88` ყველა entitled CUSTOM mode-ს launched=true-დ მიიჩნევს, binding.status-ს არ კითხულობს. Starter-ის `packages/website-client/src/site.ts:17–25` siteKey და ACTIVE-ს ამოწმებს, მაგრამ ეს frontend gate-ია. Vankisi standalone რჩება და bootstrap gate არ აქვს (`apps/vankisi-custom-web/src/App.tsx:52–139`).
- Remedy: operator summary-ში 5 ცალკე ფაქტი — commercial / domain registration / renderer deployed / binding identity verified / publication live. Server-ში stable non-secret identity და deployed manifest comparison; pending/error serving-ის ბიზნესწესი აშკარა. Vankisi-ს optional starter-ზე გადაყვანა საჭირო არ არის.
- Acceptance: ერთი სახელი ორ Venue-ში; wrong custom build; API სწორი, frontend შეცდომით SaaS; 302 სხვა დომენზე; SETUP_PENDING/ERROR; disabled domain. effort M; additive metadata/backward compatibility, არ შეცვალოს Host authority. Owner decision: CUSTOM status უნდა იყოს public gate თუ მხოლოდ ოპერატორის ჩანაწერი.

### WEB-06 — rotated BOG integration-ის capability readiness არადეტერმინისტულია

- **P1; BUG FIX; scope:** rotated website payments; `CONFIRMED_BY_CODE`, საშუალო/მაღალი confidence (unordered DB შედეგი implementation-dependent).
- `website-capabilities.service.ts:42–45` BOG `findFirst({venueId,provider})`-ს order/enabled filter არ აქვს. Rotation ძველ revision-ს disabled ტოვებს და ახალ enabled row-ს ამატებს (`payment-integrations.service.ts:185–209`). შესაბამისად capabilities შეიძლება ძველი disabled row-ით დაითვალოს, მაშინ როდესაც actual `requireEnabled` ახალს იღებს (`:50–61`).
- Expected: readiness current enabled/latest revision-ს ემთხვეოდეს; Actual: ორი ან მეტი revision-ისას false readiness შესაძლებელია. Remedy: ერთი canonical integration status query გამოიყენოს ორივე ადგილზე. Acceptance: save r1→rotate r2→disabled old remains→onlinePayments live; disable current→false; original payment r1 credentials-ით settle. effort S; schema/backfill არა, readonly query ცვლილება.

### SEC-03 — Website login throttling და session revocation არასრულია

- **P1; SECURITY HARDENING; scope:** საჯარო website accounts; `CONFIRMED_BY_CODE`, confidence მაღალი, attack-load `NOT_TESTED`.
- `website/auth/auth.controller.ts:37–64`/`auth.service.ts:48–93` website signup/signin-ს rate limiter არ აქვს; `dto/auth.dto.ts:19–30` მინ. 6 სიმბოლო და password max length არ არის. Global 50MB request limit (`main.ts:46–57`) expensive argon abuse-ის რისკს ზრდის. Platform/Customer throttling არსებობს და ამავე პრობლემად არ უნდა ჩაითვალოს.
- `auth.service.ts:96–123` 15m access/7d refresh-ს ქმნის, refresh endpoint ვერ მოიძებნა; password change `173–186` მხოლოდ hash-ს ცვლის. Logout მხოლოდ cookies-ს შლის (`auth.controller.ts:67–71`), მოპარული access token expiry-მდე ძალაში რჩება. Platform/Customer 8h tokens და per-request account disable არსებობს, მაგრამ per-session revoke/MFA არა — ფართო ადმინისტრაციული launch-ის ცალკე security gate.
- Remedy: IP+identifier throttle, bounded validated passwords და plain-object request limits; მკაფიო refresh rotation/reuse detection ან unused refresh-ის მოცილება; password change/logout/session kill-ის განსაზღვრული semantics. Acceptance: stale token/replayed refresh denied, პარალელური refresh სწორია, disabled accounts deny, დაბლოკილი მცდელობა hash-მდე შეწყდეს. effort M/L; session schema/key rotation მხარდაჭერა; არსებული მომხმარებლის პაროლის reset აუდიტის ფარგლებში არ გაკეთებულა.

### SEC-04 — public media subscription removal-ის შემდეგაც public რჩება

- **P2; PRODUCT DECISION / PRIVACY; `CONFIRMED_BY_CODE`, მაღალი confidence; ეს არსებული განზრახ public-asset პოლიტიკაა.**
- `website-logo.controller.ts:4–13`: auth/feature/domain checks არ აქვს და ერთწლიანი immutable public cache. `website-logo.service.ts:237–245` disk bytes-ს აბრუნებს DB asset ownership/reference check-ის გარეშე. Unattached/private draft image URL-იც ატვირთვისთანავე public URL-ია; unreferenced cleanup-ის საათამდე რჩება, ხოლო referenced asset შეიძლება subscription removal-ის მერეც დარჩეს.
- არ ვამტკიცებთ URL-ის გამოცნობას (UUID შემთხვევითია), თუმცა URL confidentiality boundary არ არის. Website API access removal media recall-ს არ ნიშნავს.
- Remedy/decision: თუ მხოლოდ საჯარო promotional assets დაიშვება, owner UI-ში live/public retention აუხსენით; პირადი draft media-სთვის authenticated preview + explicit publish, revocable URL/cache policy. Acceptance: chosen retention/cache contract, cross-Venue reference rejection, failed upload cleanup, removal state. effort M; old cached bytes წარსულ browser/CDN-დან გარანტირებულად ვერ გაიწმინდება.

### WEB-07 — Vankisi shared hours/contact/gallery management სრულად არ მიაქვს frontend-მდე

- **P1, თუ CUSTOM shared management გაყიდვადი დაპირებაა; UX/DATA INTEGRATION; `CONFIRMED_BY_CODE`, მაღალი confidence.**
- Backend shared public information ხელმისაწვდომია `website-venue.service.ts:40–65`; canonical Menu old `/api/menu`-ზეც გამოიყენება (`:69–72`). Vankisi frontend-ში `/api/website/venue` მოხმარება ვერ მოიძებნა. `Footer.tsx:39–47` hardcoded ყოველდღე `11:00–00:00`; Header/modal booking time არჩევანი ცალკე fixed lists; Footer `:72–79` ტელეფონის href `+995000000000`-ია, ტექსტი სხვა ნომერი.
- Expected: owner-ს shared hours/contact ცვლილება ორივე renderer-ში აესახოს; Actual: bespoke ნაწილს code/deploy change სჭირდება. Remedy: standalone დიზაინი შენარჩუნდეს, shared bootstrap/profile/info კონკრეტულ existing components-ში ჩაირთოს; time-slot policy-სთან შეთანხმება. Acceptance: synthetic owner info edit→SaaS და bespoke თანმიმდევრულად განახლდეს; capability off hide; tel: და visible phone ემთხვევა. effort M; schema არა, API additive; Vankisi-ს shared client-ზე გადასვლა აუცილებელი არ არის.

## ხელმისაწვდომი დაცვები და ისტორიული ლიდების სტატუსი

| კითხვა | მიმდინარე შედეგი და მტკიცებულება |
|---|---|
| global WebsiteUser როლი სხვა რესტორნის admin უფლებას იძლევა? | შესწავლილ reservations route-ში არა: `adminVenueId === tenant.venueId` აუცილებელია (`reservation.controller.ts:123–127`). Identity global-ია, booking tenant-owned. აუდიტი ყველა მომავალი endpoint-ის გარანტია არ არის. |
| anonymous public map სტუმრის სახელს/ტელეფონს აბრუნებს? | შესწავლილ route-ში გამოსწორებულია: serialization ბოლოს null-ს აყენებს (`reservation.service.ts:316–321`). SEC-02 სხვა, authenticated email-claim გზაა. |
| body tenant id გადამისამართებს საიტს? | Host mapping server-owned; unknown/disabled domain და Venue fail closed; forged body userId booking-ში იგნორირდება. Existing cross-tenant suites არსებობს. |
| Host/forwarded Host | forwarded authority მხოლოდ explicit `TRUST_PROXY_HOST`-ით; production direct-backend exposure/proxy header stripping ინფრასტრუქტურის აუცილებელი ნაწილი რჩება. Code მარტო proxy trust-ის სწორ deployment-ს არ ამტკიცებს. |
| CSRF/CORS | website cookies HttpOnly/Secure production/SameSite=strict, signup/signin/change-password double-submit check; profile patch/booking არ იყენებს იმავე CSRF check-ს. Global CORS same-origin/allowlist guards არსებობს. Full browser cross-site matrix არ ჩატარებულა; დაუდასტურებელ exploit-ს არ ვაცხადებთ. |
| preview/invitation | preview-ს საკუთარი audience/type, 30m და live ownership recheck; owner invitation hashed one-use/expiry/revocation + membership lock. |
| SSRF runtime check | registered domain-only, public-address checks, DNS პასუხის pinning, redirect არ მიჰყვება, 5s timeout/64KB API cap (`custom-website-runtime.ts:119–216`); სრული exotic IPv6/DNS adversarial matrix აქ არ შესრულებულა. |
| cache isolation | generic public JSON `private,no-cache`, ყოველი revalidation current entitlement-ს გადის; preview `private,no-store` (`website-cache.ts:18–19,43–64`). Media სხვა პოლიტიკაა SEC-04. |
| payment secrets | AES-256-GCM, random nonce, AAD-ში Venue+integration ID (`payment-config.crypto.ts:10–49`); credential revision binding/old credentials settlement; master-key backup/rotation რეალური restore-ის გარეშე დაუმტკიცებელია. |

## სამი ფინანსური დომენი

1. **POS settlement** ინახავს რესტორნის ადგილზე დაფარვას; `CARD` ჩანაწერი bank-terminal capture-ის მტკიცება არ არის. ადგილობრივი money integrity ცალკე POS ანგარიშშია.
2. **Restaurant Website BOG** იყენებს Venue-ის merchant config-ს; server-owned reservation განსაზღვრავს callback tenant-ს. Signature/credential revision დადებითი საფუძვლებია, მაგრამ SEC-01 და WEB-01/03/04 რეალურ paid launch-ს კეტავს. Checkout-ის real provider proof არ გვაქვს.
3. **Vynic subscription billing** ფლობს Vynic-ის კომერციულ უფლებას; restaurant BOG credential ამ დომენში არ მონაწილეობს. `subscription.service.ts:649–681` manual success მოითხოვს operator, reason, external reference და confirm=true-ს. `:683–684` future adapter boundary-ია, ავტომატური checkout/recurring collection არა. `:714–771` event identity+amount/currency+quote version+expiry შემოწმებულია; `billing-policy.ts:3–26` proration BigInt minor units-ითაა; `:29–62` UTC anchored month/year rollover; agreed price/period შენარჩუნება `subscription.service.ts:528–540,808–823`. Browser success redirect არც ერთ ცალკე paid subscription access-ს არ უნდა ანიჭებდეს; შესწავლილ routes-ში ასეთი გზა ვერ მოიძებნა.

**ხელით დადასტურებული billing pilot** ცალკე ლეგიტიმური scope-ია. ავტომატური payment collection-ის არქონა მას ავტომატურად არ კეტავს. Manual reference ტექნიკურად ვერ ამოწმებს საბანკო თანხას — ეს operator-ის რეალური გადამოწმების მოქმედებაა და UI/გაყიდვის პირობებში ასე უნდა ეწეროს.

## SaaS/CUSTOM დაკავშირების ფაქტობრივი გზა და გამარტივება

**ახალი SaaS-ის მინიმალური business ნაბიჯები:** (1) public request/operator-created owner invitation; (2) operator plan+TRIAL/paid choice+SAAS — ერთი atomic approval-ით; (3) owner invitation acceptance; (4) menu/profile/public info/presentation შევსება; (5) preview+publish. უკვე owner-ის მქონე Venue-ზე პირველი/მესამე აღარ მეორდება. Auto-assigned SaaS hostname ცალკე claim form-ს არ უნდა ითხოვდეს. Paid hostname ცვლილება request → operator reason/approval → atomic rebind; reserved names/uniqueness/late revalidation არსებობს (`hostname-requests.ts:48–73,130–208`). მოქმედი disabled domain status ახალ hostname-საც გადაეცემა; ძველი SaaS hostname იშლება, redirect არ იქმნება.

**ახალი CUSTOM-ის დამატებითი აუცილებელი ნაბიჯები:** (1) operator CUSTOM არჩევა; (2) standalone frontend build-ის რეალური შექმნა/დეპლოი; (3) siteKey binding; (4) domain registration; (5) proxy route + საჭირო DNS/TLS; (6) same-origin `/api`/media route; (7) runtime/backend identity და რეალური flow proof; (8) READY/ACTIVE attestation. ზოგი UI მოქმედება ერთ save-შია, მაგრამ infrastructure ნაბიჯები ავტომატური არ ხდება. `deploy/traefik/routes.yml:78–111` ერთ `CUSTOM_HOST`-ს ერთ `vankisi-custom-web` service-ზე ატარებს; ახალი სხვა custom app მხოლოდ DB mode/siteKey ცვლილებით არ გამოჩნდება. საჭიროა app/build/service/router ცვლილება ან შემდგომ შეთანხმებული deployment registry. Template განლაგებული საიტი არ არის; shared client აპლიკაცია არ არის.

**მინიმალური გამარტივება:** ერთი operator „პროდუქტის ჩართვა“ workflow არჩეული plan/mode-ით და დამოუკიდებელი readiness checklist; Customer Dashboard-ში მხოლოდ owner-ის გადასადგმელი ნაბიჯები. Domain არის port-free identity; dev port server config-შია. „შემოწმება წარმატებულია“ უნდა ასხვავებდეს frontend reachable / expected build / expected backend / business ready-ს. SaaS-ს auto hostname, CUSTOM-ს explicit deployment ticket; ორივეს ერთი restaurant information editor, ცალკე presentation publish. ტექნიკური architecture-ის შეცვლა და ავტომატური DNS/TLS-ის გამოგონება საჭირო არ არის.

## ტესტები, კერძო მტკიცებულება და დარჩენილი gates

შესრულებული ბრძანება (წარმატებული exit 0):

```sh
TS_NODE_PROJECT=/private/tmp/vynic-audit-20260929-f7bb982-180325/checkout/apps/backend/tsconfig.json node /private/tmp/vynic-audit-20260929-f7bb982-180325/web-proofs/website-security.cjs
```

`result.log`: SEC-01 expectedServerAmount=110, actualPersistedAmount=1, actualProviderPayload={amount:1,currency:GEL}; SEC-02 bookingsReturned=1, privateFieldsReturned=[customerName,customerEmail,customerPhone,notes]; realNetworkAttempts=0. Network methods წინასწარ fail-closed ჩანაცვლდა, provider POST ცალკე capture mock-ია. არ შექმნილა ბაზა, რეალური account, real payment ან service process. ორი კერძო evidence ფაილი განზრახ შენარჩუნებულია; normal test suite არ შეცვლილა.

ცენტრალური runner-ისათვის შესაბამისი არსებული suites (isolated DB guards გარემოში):

```sh
npm test -- --runInBand --runTestsByPath src/customer/commercial-access.integration.spec.ts src/subscriptions/subscription.integration.spec.ts src/payment-integrations/payment-integrations.integration.spec.ts src/website/custom/custom-website.integration.spec.ts src/website/provisioning/website-provisioning.integration.spec.ts src/website/core/website-core.integration.spec.ts src/website/core/website-w3.integration.spec.ts src/tenancy/public-tenant-isolation.integration.spec.ts src/tenancy/manager-saas.integration.spec.ts
```

ეს command ტესტის შედეგის განცხადება არ არის. არსებული coverage: NO_PLAN direct denied; explicit trial; expiry/open session HTTP recheck; media quota/cross-Venue references; NON_FISCAL_CLOSE; owner tenant isolation; quote replay/stale amount; signature reject/mismatched reference; old payment credential rotation. აუცილებელი დამატებითი negative proofs: SEC-01 alternate route, SEC-02 unverified email, WEB-01 parallel holds+late settlement, WEB-03 dispatch crash, WEB-04 event reordering, WEB-02 preexisting published/draft upgrade, same-name wrong CUSTOM build, rotated readiness, exact missing-subscription+override product cross-product.

Readiness მხოლოდ ამ ნაწილის მიხედვით: **Website-only SAAS menu/contact pilot — READY WITH EXPLICIT LIMITATIONS**, თუ migration draft gate და შესაბამისი central tests გაივლის; accounts/payment capabilities ამ scope-ში უნდა დარჩეს გამორთული. **Website-only CUSTOM — READY WITH EXPLICIT LIMITATIONS**, მხოლოდ კონკრეტული deployed build+domain+shared info proof-ის შემდეგ; Vankisi managed hours/contact parity ამჟამად არაა სრული. **Website payments — BLOCKED** SEC-01 და WEB-01/03/04-ის გამო. **Customer website accounts — BLOCKED** guest privacy-ის scope-ში SEC-02-ის გამო. **Subscription lifecycle — manual pilot candidate**, central integration outcomes-ის მიხედვით; **automatic subscription billing — BLOCKED როგორც ჯერ არარსებული დაპირებული შესაძლებლობა**, თუმცა manual-billing pilot-ს არ ბლოკავს.

## უსაფრთხოების დაფარვის რეესტრი

საფრთხის მოდელში განსახილველი აქტორებია anonymous visitor, რეგისტრირებული website customer, ერთი Venue-ის owner/Manager/Device, Platform ოპერატორი, მოპარული სესიის მფლობელი, არასწორად მიბმული CUSTOM deploy და signed მაგრამ დაგვიანებული payment event. ძირითადი საზღვრებია browser→proxy→Cloud, principal→tenant, Cloud→PostgreSQL, Cloud queue→Device/POS, website→bank და backup→აღდგენის გარემო. ოპერატორის განზრახ მცდარი გადაწყვეტილება და დაბალი როლის API bypass სხვადასხვა საფრთხეა.

| ზედაპირი | შემოწმებული მტკიცებულება / შედეგი | რაც დაუმტკიცებელია |
|---|---|---|
| Platform auth/session | `CONFIRMED_BY_CODE`: audience/type/issuer, active role re-read, IP/email throttling; disable account მოქმედებს შემდეგ HTTP მოთხოვნაზე | `NOT_TESTED`: authenticated real browser, MFA/recovery/session kill journey; per-session revoke არ ჩანს |
| Owner auth/membership | `CONFIRMED_BY_CODE`: self-signup უარყოფილია; invitation token expiry/replay/OWNER membership checks; 8h bearer | `BLOCKED_BY_ENVIRONMENT`: ამ run-ის PG negative tests; `NOT_TESTED`: browser logout replay და account transfer |
| Website auth | `REPRODUCED`: SEC-02 synthetic email claim; `CONFIRMED_BY_CODE`: 15m cookie, role live reread; SEC-03 limiter/session gaps | `NOT_TESTED`: real browser password/logout/replay/cookie combinations |
| Staff / Device / Edge | `CONFIRMED_BY_CODE`: Staff/Device re-resolution, explicit Device credential, tenant-required transport | native IPC/PIN/backup security POS მიმოხილვაში; აქ მტკიცებულება არ დუბლირდება. Default `000000` debug-only lead ცალკე პროდუქციის defect-ად არ გამოცხადებულა |
| Object/tenant authorization | `CONFIRMED_BY_CODE`: Venue-scope queries, owner membership, SUPER_ADMIN adminVenueId; tests არსებობს | `BLOCKED_BY_ENVIRONMENT`: ორი live synthetic Venue-ის PostgreSQL/HTTP negative matrix არ გაშვებულა; controller mocks tenant isolation proof არაა |
| Internal admin origin | `CONFIRMED_BY_CODE`: admin host-ზე reverse proxy route + Platform API principal guard | `NOT_TESTED`: რეალური production direct backend exposure/forwarded header sanitization |
| Cookies / CSRF | `CONFIRMED_BY_CODE`: strict+HttpOnly+production secure cookies; auth mutation CSRF check; profile patch-ზე იგივე explicit check არაა | `NOT_TESTED`: browser cross-site/form/same-site-subdomain matrix, payment return navigation cookie behavior |
| CORS / CSP / XSS | `CONFIRMED_BY_CODE`: allowlist/same-origin CORS და content URL parsers; inspected backend/proxy ფაილებში CSP header/Helmet ვერ მოიძებნა | `NOT_TESTED`: served production response headers, complete stored/DOM XSS fuzzing, strict CSP compatibility. CSP-ის არქონა აღმოჩენილ XSS exploit-ს არ ნიშნავს |
| SSRF | `CONFIRMED_BY_CODE`: fixed paths, registered hosts, public address validation/pinning/no-follow/time cap | `NOT_TESTED`: adversarial DNS/IPv6 cases running server-ზე; unit suite results ცენტრალურ ledger-ში |
| Upload/media | `CONFIRMED_BY_CODE`: raster format/pixel/byte limits, conversion, quota lock, reference ownership, cleanup; SEC-04 public delivery | `BLOCKED_BY_ENVIRONMENT`: PG concurrent quota proof; `NOT_TESTED`: disk-full/live permissions/restart orphan exercise |
| Enrollment / invitation / preview token | `CONFIRMED_BY_CODE`: tenant-bound limited token, server expiry, one-time enrollment/invite, preview audience+membership recheck | `BLOCKED_BY_ENVIRONMENT`: replay/concurrency DB proof ამ run-ში; already-enrolled native journey სხვა მიმოხილვაში |
| Payments | `REPRODUCED`: SEC-01 mock payload; `CONFIRMED_BY_CODE`: signature raw-body check, per-Venue old credentials, callback financial-state gaps | `NOT_TESTED`: bank sandbox signed fixtures, actual merchant capture/refund/receipt; real payment განზრახ არ შესრულებულა |
| Secrets/rotation | `CONFIRMED_BY_CODE`: payment AES-GCM+A​​AD, redacted provider errors, preserved config revisions | `NOT_TESTED`: master key rotation/recovery, full image/backup secret scan. ანგარიშში secret values არ იბეჭდება |
| Privacy/retention/deletion | `CONFIRMED_BY_CODE`: SEC-02; public media retention; accounts/guest data source models | `NOT_TESTED`: comprehensive retention/export/deletion/backup expiry policy და customer-rights exercise. Customer/Website/Platform routes-ში სრულფასოვანი self-service account deletion/export ვერ მოიძებნა; legal compliance აქ არ დასტურდება |

პირადი მონაცემების საწყისი ინვენტარი: owner/operator email/name/password hash და membership; Staff username/name/PIN hash და დაშიფრული plain-PIN vault; guest booking name/phone/email/date/tables/preorder/notes/payment reference; WebsiteUser phone/email/name/password/refresh hash; audit actor/IP მონაცემები endpoint-ის მიხედვით; media ატვირთვები. მომხმარებლის ფოტო შეიძლება მესამე პირის მონაცემსაც შეიცავდეს, მიუხედავად promotional დანიშნულებისა.

კოდით იდენტიფიცირებული მესამე მხარეებია BOG (restaurant payments), Firebase/FCM (Manager notifications, scope სხვა მიმოხილვაში), Google Maps iframe Vankisi Contact-ზე (`apps/vankisi-custom-web/src/pages/Contact.tsx:97`) და owner-configured external media/social/map URLs. External URL visitor-ს მესამე მხარეს უკავშირდება; მარტო backend-დან ფაილის არგადმოწერა privacy inventory-ს არ გამორიცხავს. სრულ font/image license inventory-ს და marketing consent-ს ამ reviewer-ს არ დაუმტკიცებია. კონკრეტული სამართლებრივი ვადები/ვალდებულებები მხოლოდ ცენტრალური primary-source legal review-ის მიხედვით უნდა დაემატოს.

### ცენტრალური runner-ის განახლება

ცენტრალურმა აუდიტმა გვაცნობა: PostgreSQL/initdb და Docker შეზღუდვის გამო ამ run-ში PG negative integration tests არ ჩატარებულა; backend 536 pass / 7 socket environment-blocked; web tests/builds გაიარა; npm audit DNS-ით დაბლოკილია. Public browser-ზე შემოწმდა `vynic.localhost` `/ka`, `/request-access`, `/login` 390px-ზე; authenticated Admin/Customer journeys არ შემოწმებულა. ეს reviewer-ის მიერ დამოუკიდებლად მიღებული შედეგი არ არის; ზუსტი commands/logs ცენტრალურ `EVIDENCE_AND_MATRICES.md`-ში უნდა აისახოს. შესაბამისად integration test-ის არსებობა აქ **არ ითვლება შესრულებულ tenant/security proof-ად**.
