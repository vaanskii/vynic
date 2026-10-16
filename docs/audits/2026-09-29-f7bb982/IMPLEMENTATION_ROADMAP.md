# განხორციელების თანმიმდევრული გეგმა

ჭრილი: `f7bb982` + საწყისი WIP, 2026-09-29. **ეს გეგმაა; implementation არ დაწყებულა.** Issue-ის სრული scope, code evidence, effort, migration/backfill და rollback არის [MASTER_BACKLOG.md](MASTER_BACKLOG.md). ქვემოთ იგივე issue-ებს ახალი ნომრები არ ენიჭება.

## სამუშაოს დაწყებამდე მისაღები გადაწყვეტილებები

- **პირველი გასაშვები პროდუქტი:** ერთი primary POS; ან menu/contact-only Website; ან paid reservations. რეკომენდაცია: პირველი ორი ვიწრო scope-დან ერთი, არსებული P0-ებისა და proof gates-ის დახურვის შემდეგ. 3/10-terminal გაყიდვა ჯერ არ დაიგეგმოს.
- **Billing:** საწყის scope-ში manual verified payment დასაშვებია; automatic collection-ის დაპირება არ გაიცეს. POS-ის card tender მხოლოდ გარე ტერმინალით მიღებული თანხის ჩანაწერია.
- **Inventory:** არსებული receipts/debt/payments/consumption subset თუ სრული საწყობი. სრული საწყობის დაპირება INV-01-ის დასრულებამდე დაუშვებელია.
- **გარე მტკიცებულება:** audit-owned PostgreSQL, სწორი Docker permissions, Windows/პრინტერის ხელმისაწვდომობა და provider sandbox-ის პასუხისმგებელი. არ გამოიყენოთ არსებული customer dataset; database name-ის არყოფნა შექმნამდე შეამოწმეთ.

ეს გადაწყვეტილებები implementation-ის ფარგლებს ადგენს. არ საჭიროებს framework-ის შეცვლას, მიკროსერვისებს ან მთელი repository-ის გადაადგილებას. არსებული WIP-ის ავტორთან ინტეგრაცია ცალკე გათვალისწინდეს; stash/მიმდინარე changes არ გადაიწეროს.

## პირველი ხუთი დამოუკიდებლად შესამოწმებელი ეტაპი

### 1. SEC-01 — ერთიანი სერვერული booking ფასი

**რა იცვლება?** ორივე საჯარო booking/payment შესასვლელი იყენებს ერთ trusted pricing გზას. მომხმარებლის `totalAmount`, service charge ან item price persisted/provider თანხას ვერ განსაზღვრავს. თუ ძველი route საჭირო არ არის, ის აშკარად იხურება; URL-ის ჩუმი განსხვავებული ქცევა არ რჩება.

**რატომ ახლა?** რეალური service კოდით 110 GEL → 1 GEL შემცირება გამეორდა. ეს ფინანსური ზიანის პირდაპირი, მაღალი სანდოობის მიგნებაა და შედარებით მცირე ცვლილებით იზოლირდება.

**როგორ?** აიღეთ არსებული სერვერული Menu/pricing გზა; shared application service-ში მოაქციეთ item existence, Venue ownership, quantity, entitlement/capability და final amount validation. პროვაიდერის adapter იღებდეს მხოლოდ სერვერის მიერ შექმნილ payment intent-ს. ახალი ბანკის ინტეგრაცია ამ task-ში არ შედის.

**რა რჩება უცვლელი?** merchant credential ownership, Host-derived Venue, manual subscription billing, POS captured historical prices, existing reservation policy. არ გადაიწეროს historical reservation amount გარედან გადამოწმების გარეშე.

**როგორ ვამტკიცებთ?** ორივე route-ზე `totalAmount:1`, სხვა Venue item, დაკარგული item, შეცვლილი price/service charge, invalid quantity, disabled capability, expired trial; expected persisted/provider amount ერთნაირია. Unit/controller mock proof + იზოლირებულ PostgreSQL-ზე HTTP negative test; network stub ან bank sandbox, არასოდეს რეალური charge. Fix-მდე regression test აჩვენებდეს დეფექტს, fix-ის შემდეგ success/denial contract-ს.

**რას ხსნის?** ხურავს თანხის ნდობის დეფექტს. **Paid booking release-ს ჯერ არ ხსნის:** WEB-01/03/04/06 და provider reconciliation დარჩება. Effort M; schema change ჩვეულებრივ არ უნდა დასჭირდეს. ეს არის **პირველი task დასამტკიცებლად**.

### 2. SEC-02 — guest booking-ის კუთვნილების დამტკიცება

**რა იცვლება?** დაუდასტურებელი matching email account-ს guest booking აღარ მიეწერება. საკუთრება დგინდება კონკრეტული booking-ის ერთჯერადი claim-ით ან რეალურად დადასტურებული email-ით, განსაზღვრული Venue scope-ით.

**რატომ ახლა?** service mock-ში პირადი name/email/phone/notes გაჟონვა გამეორდა. მხოლოდ frontend-ში booking list-ის დამალვა ავტორიზაციის პრობლემას ვერ აგვარებს.

**როგორ?** ყველაზე მცირე უსაფრთხო პირველი ცვლილებაა implicit email association-ის შეწყვეტა. თუ claim flow საჭიროა, გამოიყოს ერთი scope/expiry/replay კონტროლით და აუდიტით. ფართო auth redesign ან ახალი global role ამ ეტაპის ნაწილი არ არის.

**რა რჩება უცვლელი?** global WebsiteUser identity და Venue-owned reservations განსხვავებული რჩება; სხვა რესტორნის admin უფლება არ ჩნდება; guest booking არ იშლება. ძველი კუთვნილება მხოლოდ email equality-ით უკან არ შეივსოს.

**როგორ ვამტკიცებთ?** ორი Venue, ორი account, დაუდასტურებელი ერთი email, guest booking, claim replay/expiry, account-bound existing reservation. Unverified account response პირად ველებს არ შეიცავს; legitimate owner-ს მოქმედი გზა აქვს. Controller/service და HTTP/DB negative tests.

**რას ხსნის?** ხურავს guest ownership disclosure-ს; შემდგომ SEC-03 session/throttle proof-სა და privacy policy-ს ამზადებს. Effort M/L არჩეული claim scope-ის მიხედვით. Stage 1-ის merged interface-ს იყენებს, მაგრამ payment state machine-ზე არ არის დამოკიდებული.

### 3. WEB-02 — upgrade-ისას გამოუქვეყნებელი კონტენტის დაცვა

**რა იცვლება?** shared website foundation-ის გადასვლისას private draft-ის public profile/menu/contact fields-ში ავტომატური გადატანა იდენტიფიცირდება და უსაფრთხო წესით იმართება. უკვე მოქმედი migration არ გადაიწერება.

**რატომ ახლა?** ახალ backend-ზე გადასვლა თვითონ არ უნდა იქცეს კონტენტის გამოქვეყნების თანხმობად. ეს menu-only website rollout-საც ეხება და PostgreSQL upgrade proof-ის წინაპირობაა.

**როგორ?** ჯერ disposable DB fixture-ებით აშენდეს ძველი schema-ს ოთხი მდგომარეობა: published only, draft only, divergent draft+published, empty. შემდეგ დადგინდეს უკვე migrated მონაცემიდან რა აღდგება სანდოდ. საჭიროებისას ახალი repair/backfill დიზაინი და operator review; თუ draft/published provenance დაკარგულია, არ გამოიცნოთ სასურველი public value.

**რა რჩება უცვლელი?** shared backend და SAAS/CUSTOM მოდელი; historical migration ფაილები; owner-ის explicit publish-ის მნიშვნელობა. უკვე საჯარო approved content თვითნებურად არ გაქრეს.

**როგორ ვამტკიცებთ?** pre-upgrade public response + fixture snapshots → upgrade → public response; draft-only საიტი private რჩება, approved published value ინარჩუნებს უფლებას. Rollback compatibility და backup/key restore ახალ DB-ში. Existing owner DB-ზე audit experiment არ ტარდება.

**რას ხსნის?** უსაფრთხო website-only migration gate-ს. რეალური deployment-ს დამატებით OPS-01 და tenant/Host proof სჭირდება. Effort M/L; data correction შეიძლება საჭირო იყოს; repair მხოლოდ დადასტურებული provenance-ით.

### 4. MENU-02 — acknowledged local edit-ის crash-საგამძლე საზღვარი

**რა იცვლება?** POS Menu-ის ადგილობრივი intent და projection ერთ recoverable protocol-ში მოექცევა. Cloud await-ის შემდეგ მიღებული projection ვეღარ წაშლის meanwhile შექმნილ ადგილობრივ edit-ს; reapply-ისას ძველი intent ახალი durable intent-ის წინ არ დაიკარგება.

**რატომ ახლა?** local-first-ის ძირითადი დაპირება სწორედ აქ მოწმდება: ოპერატორისთვის მიღებული ცვლილება restart-სა და sync-ს უნდა გადაურჩეს. ჯერ durability, შემდეგ backup და conflict UX.

**როგორ?** მცირე local mutation coordinator/journal API, mutation generation/serialization boundary და deterministic replay. existing Hive/UUID/revision protocol გამოიყენეთ; Cloud→LAN ახალი გზა არ დაამატოთ. PR შეიძლება შიგნით source-level checkpoints-ად დაიყოს, მაგრამ მიღების პირობა ერთია: აღიარებული intent recoverable რჩება.

**რა რჩება უცვლელი?** offline authoring; per-entity conflicts; existing compatibility-mode venues; captured open/historical OrderLine prices. ახალი write serialization სხვა terminal-ის operational authority-ს არ ქმნის.

**როგორ ვამტკიცებთ?** fault injection local save/journal-ის შორის; sync await-ისას მეორე edit; projection clear/write შუაში process kill; Cloud commit შემდეგ ACK loss; reapply/discard restart. ყოველი მიღებული edit ერთ-ერთი ახსნადი მდგომარეობით ბრუნდება: pending, accepted, explicit conflict ან audited discard. რეალური Flutter test და native restart proof აუცილებელია.

**რას ხსნის?** canonical local durability-ს; MENU-01 backup და MENU-03 exact-retry outcome-ის ჩაკეტვის საფუძველს. Effort L; journal schema version თუ იცვლება, ძველი pending mutations-ის migration/rollback წინასწარ შეთანხმდეს. Test environment gap OPS-01 ამ ეტაპის შემოწმებამდე უნდა მოიხსნას.

### 5. MENU-01 — სრული აღდგენის პაკეტი და machine-replacement proof

**რა იცვლება?** backup შეიცავს canonical state/cursors, pending mutations, closure/recovery journals და საჭირო operational identity metadata-ს თანმიმდევრული snapshot-ით; credentials/keys უსაფრთხო განცალკევებული აღდგენის წესით იმართება.

**რატომ ახლა?** backup-ის ფაილის არსებობა ვერ იცავს acknowledged edit-ს, თუ შესაბამისი journal საერთოდ არ ინახება. Stage 4-ის journal contract ახლა უკვე აღსადგენად სტაბილური უნდა იყოს.

**როგორ?** versioned manifest/checksum, exact included-store inventory, unsupported-version refusal და fresh install restore sequence. Device credential-ს ბრმად არ გაამრავლოთ: replacement/old primary fencing ცალკე authority gate-ია.

**რა რჩება უცვლელი?** სალარო ისტორია და IDs; tenant/device ownership; older backup-ის მხარდაჭერა განსაზღვრული წესით; ახალი primary activation operator-controlled რჩება. არ ითქვას encrypted backup, თუ რეალურად plaintext payload იწერება.

**როგორ ვამტკიცებთ?** fixture-ში pending menu edit, unresolved conflict, uncertain closure, unsent Sale და cached catalog; backup შუა საქმიანობაში → ახალი installation → restore → replay. არც duplicate sale/charge, არც დაკარგული edit; corrupted/incompatible backup ჩანს შეცდომად. Lost-key სცენარი და restore duration ჩაიწეროს; Windows machine replacement ფაქტობრივად შესრულდეს.

**რას ხსნის?** backup/restore gate-ის Menu ნაწილი. **Single-POS launch ჯერ კიდევ ელოდება POS-01/03/05-ს, MENU-06-სა და physical qualification-ს.** Effort M/L; additive backup format; ძველი format migration და keys-ის პასუხისმგებელი owner decision-ია.

## შემდეგი release dependencies — იგივე master backlog-დან

ეს ცალკე დუბლირებული task list არ არის; აჩვენებს, პირველი ხუთი ეტაპის შემდეგ რომელი არსებული ბარათი ხსნის კონკრეტულ პროდუქტს. არც ერთი რიგი ავტომატურად დამტკიცებულ release-ს არ ნიშნავს.

| სასურველი გამოშვება | დარჩენილი აუცილებელი დამოკიდებულებები | დასასრულის მტკიცებულება |
|---|---|---|
| Menu/contact-only website | WEB-02 → OPS-01; CUSTOM-ზე WEB-05/07; security/tenant subset; scope-ის enforceable switches | owner publish, სწორი Host/Venue/build, disabled routes rejected, fresh restore, TLS/revision dossier |
| ერთი primary POS | MENU-01/02/03/06/09 → POS-01/03/05; POS-02/SEC-05; OPS-01 | offline core, close/transfer/race/fault/replay, replacement, actual Windows/print/manual card reconciliation |
| POS + Manager | single-POS gates → MGR-01/02/03/05/04; action permissions | queued/failed/succeeded რეალურად ემთხვევა POS ACK-ს; ორი Venue layout; stale action policy |
| არსებული Inventory subset | MENU-06 + POS sale integrity → receipt/debt/payment/consumption proofs; INV-02 labels, MGR-06 corrections | duplicate/late sale, recipe retirement, negative stock, supplier cross-Venue, debt/cash/stock განსხვავება |
| სრული Inventory | subset → INV-01 → UX-02; quantities/locations/documents ჯერ, bulk polish შემდეგ | სრული flour walkthrough, transfers net0, waste/count/reversal, concurrent trading cutoff |
| paid reservations | SEC-01/02 → WEB-01/03/04/06 → SEC-03 + OPS-01 | two-client capacity race, callback permutations, amount/currency reconciliation, durable POS outbox, provider sandbox |
| manual subscription billing | commercial PostgreSQL matrix + OPS-01 + PROD-01 | pending quote არ ააქტიურებს; manual proof/replay, agreed price/anchor preservation, open-session revoke |
| 3 terminal → შემდეგ 10 terminal | single-POS gates → EDGE-01 design/active rollout decision → bounded correctness/load proof | authoritative command log, epochs/fencing, partitions deny unsafe settlement, uncertain outcome recovery; შემდეგ რეალური latency |

ახალი Edge active architecture დიდი ცალკე milestone იქნება, არა „სინქრონიზაციის ჩართვა“. read/view ერთდროულად დასაშვებია; table/order mutation-ს atomic authority სჭირდება. edit lease, თუ საჭირო გახდა, უნდა იყოს მოკლევადიანი/renewable/crash-expiring; ეკრანის გახსნა მაგიდის სამუდამო lock-ს არ ნიშნავს. Partition-ისას strict settlement exclusivity შეიძლება unsafe მოქმედების უარყოფას მოითხოვდეს.

## შემოწმებისა და rollout-ის საერთო წესი

ყოველ task-ს ჰქონდეს ერთი scoped change, meaningful regression test და შეცვლილი boundary-ის integration proof. Tests არ შეიცვალოს მხოლოდ მწვანე შედეგისთვის; გარემოს failure ცალკე ჩაიწეროს. Deployment dossier შეიცავდეს source HEAD+WIP identity-ს, image digest-ს, migrations-ს, native version-სა და compatibility/rollback გეგმას. Migration down script არ არის default rollback; აპლიკაციის rollback ახალ schema-სთან უნდა იყოს შემოწმებული.

პირველი pilot ჩატარდეს synthetic training data-ით, შემდეგ owner-approved ერთ Venue-ზე მკაფიო scope-ით. Release გადაწყვეტილებამდე შესრულდეს [README-ის gates](README.md). გაუმართაობისას მხარდაჭერას უნდა შეეძლოს გაურკვეველი command/payment-ის მოძებნა და reconciliation; „ხელახლა დააჭირეთ“ არ უნდა იყოს ბრმა ფინანსური retry.

## რა არ იწყება ახლა

PROD-02-ის automatic subscription collection, KDS/delivery, დამატებითი themes და advanced analytics გადაიდოს. TECH-01 lint cleanup მხოლოდ შესაბამის ცვლილებასა და ცალკე შეთანხმებულ debt budget-ში; ათასობით lint finding-ის ერთ PR-ში ჩასწორება reliability milestone არ არის. Folders-ის მასობრივი rewrite, ახალი database per CUSTOM site, Vankisi-ის starter-ზე იძულებით გადაყვანა და Go Edge active cutover ამ პირველი ხუთი ეტაპის ნაწილები არ არის.

**STOP. პირველი გასაკეთებელი task დასახელებულია — SEC-01. მის დასაწყებად owner-ის ცალკე implementation დავალებაა საჭირო; ამ აუდიტში მხოლოდ ანგარიშები შეიქმნა.**
