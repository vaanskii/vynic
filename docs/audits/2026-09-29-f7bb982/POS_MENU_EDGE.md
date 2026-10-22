# POS, canonical Menu, Edge და Windows გამოშვების დამატებითი აუდიტი

აუდიტის თარიღი: 2026-09-29, `Asia/Tbilisi`. წყარო: `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b` და აუდიტის დაწყებისას არსებული WIP. ეს დოკუმენტი კითხულობს მიმდინარე კოდს; არ ამტკიცებს, რომ იგივე კოდი მუშაობს დაყენებულ Windows POS-ში ან Docker image-ში. ორიგინალი application/test/config ფაილები არ შეცვლილა. მიმდინარე runtime/build ფაქტები და ცენტრალურად გაშვებული ტესტების შედეგები თავმოყრილია `EVIDENCE_AND_MATRICES.md`-ში.

მთავარი დასკვნა: არსებობს მდიდარი ერთტერმინალიანი, ლოკალურ Hive-ზე მომუშავე POS, გაყიდვის დახურვის ცალკე აღდგენის მექანიზმით. canonical Menu-ს Cloud კონფლიქტები დამუშავებულია, მაგრამ ლოკალური ცვლილების, projection-ის და backup-ის საერთო გამძლეობა ჯერ არაა საკმარისი. წარმოებაში რამდენიმე დამოუკიდებელი POS ერთობლივ ოპერაციულ ავტორიტეტად არ მუშაობს. Phase 0 მხოლოდ Cloud-ში შემომავალი ოპერაციების მთავარ მოწყობილობას ზღუდავს; Phase 2A არის shadow/იზოლირებული მოდელი. Windows installer/updater-ის კონტროლები არსებობს, თუმცა ამ აუდიტში Windows-ისა და ფიზიკური მოწყობილობების ახალი გამოცდა არ ჩატარებულა.

## მტკიცებულების საზღვარი

- `CONFIRMED_BY_CODE`: ქვემოთ მითითებული მიმდინარე შესრულების გზა პირდაპირ ადასტურებს ქცევას; ეს არ ნიშნავს ფიზიკური დენის გათიშვის ექსპერიმენტს.
- `REPRODUCED`: `MENU-03`-ის განმეორებითი პასუხი შესრულდა უცვლელი `MenuCatalogService.apply`-ით, სინთეზური mocked Prisma seam-ით, DB/network-ის გარეშე. ეს არ არის PostgreSQL ან HTTP ინტეგრაციის მტკიცებულება.
- `BLOCKED_BY_ENVIRONMENT`: მიმდინარე Flutter გაშვება მოითხოვდა SDK cache-ში აკრძალულ ჩაწერას; ეს შეზღუდვა არ შემოვლილა. ამ დამატებით შემოწმებაში ახალი Dart/Flutter სცენარები არ გაშვებულა.
- `HISTORICAL_REPORT_ONLY`: წინა Flutter/macOS/Windows/Go proof ანგარიშების რიცხვები ამ გაშვების შედეგებად არ ჩაითვლება.
- `NOT_TESTED`: ამ აუდიტში რეალური Windows პროცესი, ფიზიკური printer, payment terminal, დენის გათიშვა, სრული დისკი და 3/10 მოქმედი რესტორნის ტერმინალი არ შემოწმებულა.

ყველა code reference არის repository-relative path + მიმდინარე one-based line. კრიტიკული მოთხოვნების წყარო: მომხმარებლის მოთხოვნის §7–9, §18–20; `docs/agent-state/VYNIC_DECISIONS.md:335` (D030), D001 და Phase 0/2A გადაწყვეტილებები. ზოგიერთ ქვემოთ ჩამოთვლილ ფუნქციას აქვს ტესტის ფაილი; მხოლოდ ფაილის არსებობა PASS არ არის.

საბოლოო პრიორიტეტებისა და დუბლირების ავტორიტეტია `MASTER_BACKLOG.md`. აქ `MENU-04` არის `COM-01`-ის domain alias; `INV-03` უკავშირდება `MENU-06` root cause-ს; `EDGE-02` ცენტრალური `OPS-01` qualification-ის alias-ია. `POS-04` product limitation-ია და ცალკე bug task არ არის. P0 ქვემოთ ვრცელდება კონკრეტულ მონაცემის დაკარგვის/core integrity გზაზე და მის პროდუქტის release-ზე; ყველა Vynic პროდუქტის ერთიან P0 შეფასებას არ ნიშნავს.

ძირითადი გადამოწმებული წყაროები: [backup payload](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/database/repositories/backup_repository.dart:79), [local menu sync](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/menu/pos_menu_sync.dart:349), [canonical retry](/Users/vaanskii/Developer/vynic/apps/backend/src/menu-catalog/menu-catalog.service.ts:449), [owner menu gate](/Users/vaanskii/Developer/vynic/apps/backend/src/customer/restaurant-foundation.service.ts:38), [Close Day](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/database/transactions/close_day_transaction.dart:109), [transfer](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/pos/order_item_transfer.dart:248), [order creation](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/database/repositories/order_repository.dart:102), [primary fencing](/Users/vaanskii/Developer/vynic/apps/backend/src/edge/operational-authority.ts:36), [shadow-only observer](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/edge/orders_tables/shadow.dart:10), [updater manifest](/Users/vaanskii/Developer/vynic/apps/edge/internal/updater/manifest.go:87).

## არსებული POS-ის სრული ციკლი

| ეტაპი | მიმდინარე შესრულება და მონაცემი | ოფლაინ/დადასტურების ზღვარი |
| --- | --- | --- |
| ინსტალაცია | `apps/edge/cmd/setup`, `internal/setup`; signed bootstrap → pinned Edge → signed POS bundle; ცალკე user data და binaries | პირველი download/enrollment ქსელს საჭიროებს. Install არ ნიშნავს Venue-ის enrollment-ს ან Go operational authority-ს |
| პირველი გაშვება | `apps/operations/lib/startup_pos.dart:69` იწყებს printer/updater-ს; `:75–79` იწყებს sync, Edge polling, inventory/config/Menu pulls; `screens/pos_first_run.dart` და `pos_enrollment_service.dart:98` ახორციელებენ Device enrollment-ს | წარმატებული საწყისი მოწყობის შემდეგ არსებული Hive-ის გახსნა Cloud-ს არ ელოდება. საწყისი menu/config/Staff bootstrap-ის ინტეგრაცია ცალკე უნდა დამტკიცდეს ახალი release build-ით |
| PIN/უფლებები | `user_repository.dart:90` ადარებს ლოკალურ PIN-ს და cached platform-disabled სტატუსს; `staff_role.dart`, `pos_permission.dart`, order action helpers ადგენენ როლურ ქმედებებს | Cloud-ის unavailable დროს ლოკალური PIN მუშაობს. Remote revoke-ის დაუყოვნებლივი ოფლაინ აღსრულება არ არსებობს. Default `000000` მხოლოდ `kDebugMode`-ში იქმნება (`user_repository.dart:40–47`); release default credential-ად არ კლასიფიცირდება |
| მაგიდა/დარბაზი | `order_repository.dart:102` ამოწმებს ლოკალურ occupancy-ს, `:139` ინახავს Order-ს და `:144` იკავებს მაგიდებს | გახსნილი ეკრანის ყურება occupancy-ს სინონიმი არაა; რეალური order creation იკავებს მაგიდას. სხვა Hive ამას ავტომატურად არ ხედავს |
| კალათა/რაოდენობა/ვარიანტი | `menu_screen.dart:685` აყალიბებს cart-ს, `:726` ქმნის `OrderItem`; item-ში არის unitPrice, quantity, total, comment, menuItemId, variantId (`order.dart:8–49`) | ახალი ხაზი იყენებს იმ POS-ის ამჟამინდელ ლოკალურ ფასს. კომენტარი არის free-text მითითება; სრულფასოვანი ფასიანი modifier group/required-choice მოდელი ამ model-ში არ ჩანს |
| თანხა/ფასდაკლება/service fee | `Order.recalculateTotal` (`order.dart:377`) აჯამებს captured line totals, package, service fee, discount, advance და manual adjustment-ს; round ხდება ორ ათწილადამდე | line price თავისით არ ეძებს Menu-ს. Global service fee default შეიძლება ხელახალ recalculation-ზე გახსნილ Order-ზე აისახოს, თუ საკუთარი override არ აქვს (`:557–595`); ამ პოლიტიკის UX განმარტება საჭიროა |
| გადატანა/ბილები | `order_item_transfer.dart:248` მუშაობს ასლებით, destination/source-ს ინახავს, წერს ორივე მხარის audit-ს; full move/split ინარჩუნებს შესაბამის identity-ს | ლოგიკა არის; შუალედური crash-ისას ორ Order-ს შორის ატომურობა დაუცველია (`POS-03`). რაოდენობების გაყოფა არ უდრის რამდენიმე acquiring authorization-ს |
| cash/card/split | `table_payment_service.dart` აგროვებს მეთოდს, provider label-სა და თანხებს; `:1110` bank selection-ს `cardBog/cardTbc` მნიშვნელობად აქცევს; `:1119` ინახავს transaction snapshot-ს | ეს არის ოპერატორის მიერ მიღებული თანხის აღრიცხვა. TBC/BOG ღილაკი აქ არ აკეთებს acquiring authorization/capture-ს. Website BOG-ის ინტეგრაცია სხვა Cloud payment flow-ა |
| მაგიდის დახურვა | `close_table_transaction.dart:153` ეძებს closure identity-ს; `:242` Order-ზე ინახავს მას, `:262` წერს journal-ს; Sale წინ უსწრებს table free-ს; `:404` ასრულებს იდემპოტენტურ post-Sale ეფექტებს | ძლიერი ერთტერმინალიანი აღდგენის საფუძველია. არ ამტკიცებს გლობალურ double-settlement exclusion-ს ან რეალური ბანკის პასუხის აღდგენას |
| გაუქმება/აღდგენა | `cancel_order_transaction.dart:84` ტოვებს cancel audit/Sale trail-ს; `closure_audit_integrity_test.dart` შეიცავს CLOSE→RESTORE→CLOSE სცენარებს; აღდგენა ახალ closure lifecycle-ს განასხვავებს ძველისგან | უკვე დახურული შეკვეთა cancellation-ით არ უნდა გადაიქცეს ჩვეულებრივ open row-ად. რეალური refund-ის გაცემა acquiring API-ით ამ POS-path-ის ნაწილი არაა |
| სამუშაო დღე | `close_day_transaction.dart:125` ამოწმებს active orders-ს, `:209` reserved tables-ს; `:270` გადაჰყავს business date, შემდეგ ასუფთავებს operational rows-ს | დღე კალენდარულ შუაღამეზე ავტომატურად არ იკეტება. `POS-01`: ეს პროცესი არ არის journaled/ატომური და concurrent admission არაა შეჩერებული |
| restart/recovery | `database_service.dart:233` ხსნის Hive-ს, ატარებს migrations-ს; `:271` იძახებს `ClosureRecoveryService.recoverPending()` | `closure_recovery_service.dart:87` Sale-ით ადგენს ჩაწერილია თუ არა თანხა: Sale არსებობს → post-Sale completion; არ არსებობს → attempt abandon და Order open რჩება. Backup-ში journal-ის არქონა ამ გზას replacement-ზე წყვეტს |
| outbound sync | Manager snapshot scheduler 30 წამია (`manager_sync_service.dart:70,110`); Sale/audit revision/ACK ცალკეა; Edge command journal იცავს დასრულებული command-ის განმეორებისგან (`edge_transport_service.dart:263`) | Cloud outage-ზე Hive მუშაობს; Manager/Website ბოლო Cloud snapshot-ს ხედავენ. `syncRealtimeToManagerApp`-ის არსებობა არ უდრის მის აქტიურ გამოყენებას |
| printing | `print_queue.dart:12` არის პროცესის მეხსიერებაში queue; raw TCP flush/close წარმატებულ send-ად ითვლება (`printer_transport.dart:68–81`) | კვების/კავშირის გაურკვეველი დასრულებისას exactly-once ფიზიკური ბეჭდვა დაუმტკიცებელია. Queue crash-ზე არ აღდგება (`POS-02`) |
| fullscreen/quit/update | clean quit საერთო readiness barrier-ს კეტავს, აჩერებს სერვისებს და flush/close-ს ელოდება (`pos_quit.dart:87–102`); updater readiness არის `update_readiness.dart` | clean exit-ის კონტროლი არსებობს; kill/power-loss განსხვავებული შემთხვევაა. updater open orders-ს არ ითვლის blockers-ად, მაგრამ აქტიურ payment/close/write/recovery-ს ბლოკავს |

## canonical Menu: რეალური შეთანხმება და ხარვეზები

Cloud არის canonical Menu-ს ავტორიტეტი; POS საკუთარ projection-სა და unresolved mutations-ს ინახავს. Legacy `menuAuthority=POS` რესტორნები თავსებადობის გზაზე რჩებიან. Dashboard/POS ცვლილება → entity mutation → Venue transaction lock → entity revision check → mutation row და changeSeq → სხვა clients-ის catch-up. Device-ს Venue credential ადგენს; primary requirement Menu-ზე არ ვრცელდება.

| მოთხოვნა | კოდის შედეგი | მტკიცებულება |
| --- | --- | --- |
| თითო entity-ის revision | იმავე entity/revision-ზე მეორე writer იღებს `REVISION_CONFLICT`; დამოუკიდებელი entity edits არ ეჯიბრება ერთ entity revision-ს | `menu-catalog.service.ts:499,520`; ყველა mutation ერთ Venue row lock-ს გადის `:439` |
| tenant-scoped mutation ID | `@@id([venueId, mutationId])`; შეცვლილი requestHash იმავე ID-ით უარყოფილია | `schema.prisma:2331–2354`, `menu-catalog.service.ts:449–457` |
| exact retry-ის ძველი outcome | ძველი resultRevision/sequence ბრუნდება, მაგრამ entity მიმდინარე row-დან იკითხება | `MENU-03`, `:458–476` |
| snapshot თანმიმდევრულობა | snapshot და changes `RepeatableRead` transaction-ში არიან | `:225–238`, `:250–285` |
| feed/cursor | ყველა მიმდინარე node იკითხება და changeSeq-ით იფილტრება; tombstones ცალკე მოყვება; POS sequence მხოლოდ feed-ის დამუშავების შემდეგ გადადის | `:259–282`; `canonical_menu.dart:170–193` |
| წაშლა/reconnect | omission-delete არაა; child variants tombstones-ს იღებს; stale client იჭერს წაშლას | `menu-catalog.service.ts:895–920`; `canonical_menu.dart:189` |
| retention-ის შემდეგ reconnect | ამ კოდში tombstone/mutation pruning და retention floor არ ჩანს. `RESYNC_REQUIRED` მხოლოდ client cursor > server sequence-ზეა | `:253–258`; retention-ის დანერგვის შემდეგ საჭირო იქნება floor + bootstrap contract (`MENU-10`) |
| offline dependent changes | creates/updates parent-first, deletes child-first; ერთი entity-ის conflicted predecessor მოგვიანო edits-ს აჩერებს | `canonical_menu.dart:458–562`, `pos_menu_sync.dart:339–345` |
| parent conflict-ის შვილები | dependency graph არ არსებობს: მხოლოდ იგივე entityId იბლოკება. უარყოფილი parent-ის child create შეიძლება ცალკე rejected დარჩეს | `pos_menu_sync.dart:339–359`; compound tree-edit recovery ცალკე ტესტირებას საჭიროებს |
| accepted და local pending | unresolved entries canonical copy-ზე იდება, მათ შორის conflict/rejected edits | `pos_menu_sync.dart:182–193`; conflict არ ნიშნავს, რომ ლოკალური selling price ავტომატურად შეიცვალა |
| disabled item | Cloud-ში რჩება, POS selling/Admin projection-იდან იმალება; POS fields-ში enabled არ არის | `canonical_menu.dart:83–97,270–282`, `MENU-05` |
| writer coverage | POS Admin და owner Dashboard writers; Manager read-only; legacy snapshot canonical Venue-ს menu-ს არ ცვლის | `menu-sync.service.ts:302–307`; future Manager writer დღეს არ არსებობს |

### MENU-01 — backup დაკარგავს mutation/recovery context-ს

- **ტიპი/პრიორიტეტი:** production durability defect, **P0 canonical local-first/replacement release-ის ფარგლებში**; გაყიდვების recovery-საც ეხება. `CONFIRMED_BY_CODE`, მაღალი ნდობა; replacement runtime reproduction არ ჩატარებულა.
- **მომხმარებელი/ზედაპირი:** POS ოპერატორი, backup/restore და machine replacement; `MenuCanonicalBox`, `menuMutationJournal`, `closureJournalBox`, `edge_command_journal`.
- **რეალურად:** backup შეიცავს `menu` projection-ს, orders/sales/settings/audit-ს, მაგრამ არ შეიცავს canonical state/baseline/cursor-ს, menu journal-ს, closure journal-სა და Edge command journal-ს. `backup_repository.dart:79–146`; closure storage ცალკე box-ია (`closure_journal_repository.dart:209,247`), ამიტომ `settingsAll` მას ვერ მოიცავს.
- **მოსალოდნელი/წყარო:** ლოკალურად მიღებული ცვლილება და დაუსრულებელი ფინანსური command აღდგენადი უნდა იყოს; მომხმარებლის §8 და D030. Backup-ის აღწერა „every Hive box“ ფაქტობრივ payload-ს აღემატება.
- **შემოწმების სცენარი:** A-ზე Cloud გათიშული → menu price edit → pending journal → JSON backup → ცარიელ, იმავე Venue-ში enrolled B-ზე restore → bootstrap. მოსალოდნელი: იგივე pending mutation ID/revision და local price; ფაქტობრივი კოდური შედეგი: local menu განსხვავდება Cloud-ისგან და adoptionBlocked ხდება ან explicit adoption-ზე intent იკარგება. უკვე canonical B-ზე restore wrapper ახლანდელ canonical+journal projection-ს აბრუნებს (`backup_repository.dart:797`, `pos_menu_sync_service.dart:193–201`), backup-ის menu edits აღდგენილ journal-ად არ გარდაიქმნება.
- **ფინანსური ზემოქმედება:** Sale-ის შემდეგ, cleanup-მდე გადაღებულ backup-ში Sale არსებობს, მაგრამ missing closure journal-ს `recoverPending` ვეღარ ეძებს. ეს არ ამტკიცებს ყველა ჩვეულებრივი backup-ის გაფუჭებას; ნიშნავს, რომ დაუმთავრებელი lifecycle ვერ ინარჩუნებს აღდგენის გარანტიას.
- **კონფიდენციალურობა:** `_serializeUser` backup-ში raw `pinCode`-ს წერს (`backup_repository.dart:203–207`), payload `writeAsString`-ით ჩვეულებრივ JSON-ად ინახება (`:148–150`); encryption აქ არ ჩანს. ეს `CONFIRMED_BY_CODE`, მაღალი ნდობაა: backup file-ზე წვდომის მქონე პირი Staff PIN-ებს წაიკითხავს. ფაილის რეალური გაჟონვა არ გამოგვიწვევია; პირადი მონაცემები არ წაგვიკითხავს. უსაფრთხოების backlog-ში encryption/access/restore-auth პოლიტიკას დაუკავშირდეს და იგივე რისკი მეორედ ცალკე bug-ად არ დაითვალოს.
- **შესწორება:** versioned backup manifest, იმავე Venue-ის durable intent/state/cursor და ყველა საჭირო recovery journal; consistent snapshot/admission barrier; მოწყობილობის credentials-ის მექანიკური კლონირების გარეშე explicit identity handoff. უსაფრთხო backup encryption/access policy ცენტრალურ security backlog-ს ეკუთვნის.
- **მიღება:** pending create/update/delete/conflict, interrupted close, uncertain command, repeated restore, new-machine restore და wrong-Venue reject; backup-ის SHA/format validation; ყოველი crash checkpoint-ის შემდეგ იგივე quantity/money/intent.

### MENU-02 — sync-ისას შენახული edit შეიძლება projection-მა წაშალოს

- **ტიპი/პრიორიტეტი:** production data-loss defect, **P0 canonical local-first release-ის ფარგლებში**. `CONFIRMED_BY_CODE`, მაღალი ნდობა; controlled Flutter reproduction გარემომ დაბლოკა.
- **გზა:** `menu_repository.dart:661–668` პირდაპირ ინახავს Hive category-ს და emits event-ს; `pos_menu_sync_service.dart:95–111` journal capture-ს `unawaited` გზით ითხოვს. Engine-ის `_Serial` მხოლოდ თავის task-ებს აწყობს რიგში (`pos_menu_sync.dart:113–120`), writer-ებს არა.
- **ზუსტი interleaving:** (1) sync `_capture()` `:353`; (2) HTTP await `:359` ან `:427`; (3) ოპერატორის edit save წარმატებულია, capture sync-ის უკან დგება; (4) sync ასრულებს `_write(_projection(current))` `:444`; (5) `_write` ასუფთავებს menu box-ს `:260` და თავიდან წერს ძველ projection-ს; (6) queued capture ახალ baseline-ს ხედავს და უკვე დაკარგულ edit-ს ვეღარ პოულობს.
- **მოსალოდნელი/ზემოქმედება:** §8-ის მიხედვით ACK-იანი ლოკალური ფასი/სახელი აღდგენადი უნდა იყოს. აქ UI-ს წარმატებული save შეიძლება გაქრეს და შემდეგი order არასწორ ლოკალურ ფასს იყენებდეს. ეს არის write coordination defect, არა უბრალოდ Cloud conflict.
- **შესწორება:** ყველა writer ერთ local mutation boundary-ში; journal-first recoverable commit ან atomic state frame; projection generation/version check; network wait არ უნდა ფლობდეს UI writer-ის durability რიგს. მხოლოდ კიდევ ერთი `_capture()` მთლიან race-ს ვერ ხურავს, თუ თავად `_write()`-თან direct writers დარჩება.
- **reconciliation-ის იგივე durability საზღვარი:** `reapply` ჯერ `await journal.remove(target)`-ს ასრულებს (`pos_menu_sync.dart:485`, remove flush-საც აკეთებს), შემდეგ წერს ჩანაცვლებულ entry-ს (`:486`). ამ ორ მოქმედებას შორის crash accepted local conflict intent-ს დაკარგავს. საჭიროა atomic replacement, რათა resolution-ისას intent არ გაქრეს.
- **მიღება:** transport completer-ით გააჩერეთ mutate/changes; ამ დროს Admin repository-ით შეცვალეთ ფასი, შემდეგ გაუშვით პასუხი; assert local projection და journal ზუსტად ინახავს edit-ს. გაიმეორეთ `_rebuilding` marker-ისა და `clear/addAll`-ის შუალედში restart-ით.

### MENU-03 — exact retry განსხვავებულ entity-ს აბრუნებს

- **ტიპი/პრიორიტეტი:** production protocol defect, **P1**. `REPRODUCED` მხოლოდ mocked persistence seam-ით; მაღალი ნდობა.
- **ზედაპირი:** `POST /edge/menu/mutations`, owner catalog mutation, `MenuCatalogMutation`.
- **გზა:** `menu-catalog.service.ts:449–477` prior resultRevision/seq-ს იყენებს, entity-ს კი current table-დან იღებს; `:546–561` original response body-ს არ ინახავს. წყარო: §8 „exact retry returns the durable original outcome“ და service-ის საკუთარი contract `:23–24`.
- **შედეგი:** mutation M1-ის პასუხი revision=2/name=First edit; M2-ის შემდეგ M1 retry: top-level revision=2, entity.revision=3/name=Second edit. entity-ის წაშლის შემდეგ იგივე UPSERT retry: `deleted:false`, `entity:null`. Changed-payload reuse rejection ცალკე კონტროლია და ამ ხარვეზს ვერ ასწორებს.
- **რეპროდუქცია:** private evidence-ში `menu-retry-repro.cjs` / `menu-retry-repro.log`; ბრძანება snapshot-ის `apps/backend`-დან: `node -r ts-node/register/transpile-only /private/tmp/vynic-audit-20260929-f7bb982-180325/menu-retry-repro.cjs`. Exit 0; actual duplicate branch უცვლელია, DB seam mocked. პირველ გაშვებაში private harness-ის არავალიდური UUID შესწორდა; application code არ შეცვლილა.
- **ზემოქმედება:** პასუხის identity/revision ერთმანეთს არ ეთანხმება; dependent local edit-ის rebase შეიძლება ძველ resultRevision-ზე მოხდეს, მიუხედავად ახალი entity state-ისა; დამატებითი conflict/მომხმარებლის გაუგებრობა. catch-up-ის არსებობა original-result contract-ს ვერ ცვლის.
- **შესწორება/მიღება:** შეინახოს immutable accepted result ან მის ზუსტად აღსადგენად სრული snapshot; PostgreSQL+HTTP test M1→M2→retry M1 და M1→delete→retry M1, restart-ის შემდეგაც; same ID changed payload კვლავ უარყოფილი.

### MENU-04 — POS-only owner menu-სთვის WEBSITE-ს ითხოვს

- **ტიპი/პრიორიტეტი:** product permission defect, **P1** POS-only Dashboard-ის შეთავაზებისთვის; `CONFIRMED_BY_CODE`, მაღალი ნდობა.
- **ზედაპირი:** `GET/POST /customer/venues/:venueId/catalog[/mutations]`; `restaurant-foundation.service.ts:38–67`.
- **რეალურად:** read `:40` და mutate `:61` ორივე `requireCommercialFeature(..., 'WEBSITE')`-ზეა. Device API POS-only canonical menu-ს ემსახურება; backend test `menu-catalog.integration.spec.ts:439` ამოწმებს Device გზას და არა POS-only owner write-ს.
- **მოსალოდნელი:** §8 პირდაპირ ითხოვს POS-only და Website-only owner editing-ის შემოწმებას; D030 ერთ shared catalog-სა და permissioned writer-ს განსაზღვრავს. თუ POS-only Dashboard editing განზრახ არ იყიდება, ეს ცალკე product decision უნდა გახდეს, არა ჩუმი WEBSITE დამოკიდებულება.
- **რეპროდუქცია:** ACTIVE POS-only synthetic Venue + owner membership + cloudMenuEditingEnabled=true; GET/POST ზემოთ → მიმდინარე gate deny. მოსალოდნელი შესაბამისი menu-authoring უფლება WEBSITE-ს გარეშე.
- **შესწორება/მიღება:** menu authoring entitlement-ს შესაბამის პროდუქტებზე მკაფიო წესი; direct negative tests NO_PLAN/expired/suspended + cross-Venue; მხოლოდ client button-ის გახსნა საკმარისი არაა.

### MENU-05 — disabled item-ის აღდგენა POS-იდან მიუწვდომელია

- **ტიპი/პრიორიტეტი:** intentional limitation + unresolved product workflow, **P2**, `CONFIRMED_BY_CODE`.
- **გზა:** `canonical_menu.dart:83–97` enabled field-ს გამორიცხავს; `:270–282` disabled item/variants-ს projection-იდან შლის. POS Admin იმავე menuBox-ს კითხულობს.
- **ქცევა:** Dashboard-ში disabled item POS-ში აღარ იყიდება; ეს სწორად იცავს owner-ის გადაწყვეტილებას. მაგრამ POS-ის უფლებამოსილი მენეჯერი ვეღარ ხედავს archived list-ს და ვერ re-enable-ავს, განსაკუთრებით ოფლაინ.
- **მოსალოდნელი/სცენარი:** §8 disabled restoration; Cloud disable→catch-up→POS Admin search/re-enable. მიმდინარე შედეგი: item არ ჩანს. მომხმარებელს არ უნდა ვურჩიოთ ახალი duplicate პროდუქტის შექმნა იგივე სახელით.
- **შესწორება/მიღება:** ცალკე „გათიშული პროდუქტები“, შესაბამისი უფლებით restore mutation; offline permission პოლიტიკა; თუ intentionally Cloud-only რჩება, POS-ში მკაფიო შეტყობინება და Dashboard გზა. გაუთვალისწინებელი re-enable ჩვეულებრივი price edit-ით დაუშვებელია.

### MENU-06 — delete ანადგურებს მოქმედ recipe/presentation-ს

- **ტიპი/პრიორიტეტი:** destructive-domain coupling / product decision, **P1** უსაფრთხო menu administration-ისთვის; `CONFIRMED_BY_CODE`.
- **გზა:** `menu-catalog.service.ts:895–911` item/variant-ს ფიზიკურად შლის. `schema.prisma:504–505` recipe relations Cascade-ია; `:1558` website presentation-იც Cascade-ია. Tombstone item-ის არსებობას ინახავს, recipe/presentation-ის აღსადგენ ვერსიას არა.
- **მოსალოდნელი/სცენარი:** §8 deletion recipe/presentation lead; შექმენით recipe + website override → delete menu item → rows gone → იგივე ID-ით restore tombstone conflict. Order/Sale-ის captured მონაცემები ამით არ გადაწერილა, მაგრამ მოქმედი configuration-ის დაბრუნება შეუძლებელია backup/ხელით recreation-ის გარეშე.
- **ზემოქმედება:** ზედმეტად მარტივი menu delete აუქმებს inventory consumption setup-ს და website copy-ს; recreation ახალი identity-ით ისტორიულ კავშირებს ვერ აღადგენს.
- **Inventory კავშირი:** offline გაყიდვის queued consumption შეიძლება მოგვიანებით წაიკითხოს უკვე წაშლილი recipe; დეტალური receiving/consumption შედეგი `INVENTORY_MANAGER_UX.md`-ის `INV-03`-შია. Backlog-ში deletion-ის root cause ერთ `MENU-06`-ად უნდა დარჩეს და inventory შედეგი მას დაუკავშირდეს.
- **შესწორება/მიღება:** archive/disable default, dependency preview, explicit destructive delete policy, retention/recoverable configuration snapshots. Test recipe/presentation შენარჩუნება archive/restore-ზე და historical Sale უცვლელობა.

### MENU-07 — თანხის storage კვლავ Float/double-ია

- **ტიპი/პრიორიტეტი:** ტექნიკური consistency risk, **P2**; representation `CONFIRMED_BY_CODE`, კონკრეტული არასწორი charge ამ აუდიტში `NOT_TESTED`.
- **გზა:** `schema.prisma:142,170` menu prices Float; `order.dart:16,22,377–399` local money double; canonical `_money` cents-მდე round-ს აკეთებს (`canonical_menu.dart:451`), mutation validation fractional cents-ს ზღუდავს (`menu-mutation.ts:79`).
- **მოსალოდნელი:** ერთგვაროვანი monetary contract ყველა writer/read/close-ში; §8 floating money lead. Float-ის არსებობა თავისთავად არ ადასტურებს ყველა receipt-ის არასწორობას: closure/sale ledger-ს reconciliation და exact-field validation უკვე აქვს.
- **შესწორება/მიღება:** GEL minor units ან შეთანხმებული decimal representation, versioned transport/migration; არ გადაწეროს ისტორიული Sale-ები. Test fractional sums, discounts/fee, split tender და large quantities; ყველა total/reprint იგივე უნდა იყოს.

### MENU-08 — „Use current“ გადაწყვეტილების კვალი იშლება

- **ტიპი/პრიორიტეტი:** auditability gap, **P2**, `CONFIRMED_BY_CODE`.
- **გზა:** `pos_menu_sync.dart:459–470` target-სა და მოგვიანო same-entity unresolved entries-ს journal-იდან შლის. არც actor/reason/resolution event იწერება. `reapply` განსხვავებით `resolution:REAPPLY`-ს აგზავნის (`:478–505`); Cloud mutation row ინახავს მას.
- **სცენარი/მოსალოდნელი:** price conflict→Use current→restart→audit search. შედეგი: rejected local change-ის resolution record არ არის; §8-ის auditable resolution მოთხოვნა ვერ სრულდება. საწყისი edit audit შესაძლოა არსებობდეს, მაგრამ discard-ის პასუხისმგებელი და დრო არა.
- **შესწორება/მიღება:** immutable local resolution event, actor/timestamp/entity/base/current revision და discarded mutation IDs, ქსელის დაბრუნებისას synchronized audit. Test ორივე resolution და dependent entries-ის შედეგი.

### MENU-09 — ძველი POS build canonical Venue-ში უსაფრთხოდ ვერ ერთვება

- **ტიპი/პრიორიტეტი:** rollout compatibility gap, **P1**, `CONFIRMED_BY_CODE`; actual old Windows binary interoperability `NOT_TESTED`.
- **გზა:** `menu-sync.service.ts:302–307` canonical Venue-ზე snapshot menu-ს ჩუმად გამოტოვებს, რათა Order/Sale sync გაგრძელდეს. ძველ client-ს entity protocol/journal არ აქვს. ახალ Venue-ებს canonical რეჟიმი ენიჭება; D030 legacy Venue-ს explicit cutover-ს ითხოვს.
- **სცენარი:** old client→new canonical Venue→local menu price edit→full sync success→Dashboard unchanged. backend სწორად იცავს canonical state-ს, მაგრამ საერთო sync success menu-ის convergence-ს არ ნიშნავს.
- **ზემოქმედება/მოსალოდნელი:** legacy Venue თავის რეჟიმში არ უნდა გადაირთოს ჩუმად; ახალი Venue-ის enrollment/cutover უნდა ითხოვდეს canonical capability-ს/minimum supported build-ს და მომხმარებელს აჩვენებდეს mismatch-ს.
- **შესწორება/მიღება:** capability negotiation/admission gate, enrolled fleet inventory, one-venue controlled cutover/rollback runbook; exact supported old+new pair tests, pending offline edits-ის შეფასება cutover-მდე.

### MENU-10 — feed/retention/capacity ჯერ შეუზღუდავია

- **ტიპი/პრიორიტეტი:** scale/reliability gap, **P2**, `CONFIRMED_BY_CODE`.
- **გზა:** `menu-catalog.service.ts:259` ყოველი incremental read ჯერ ყველა node-ს იღებს; `:262` ყველა მომდევნო tombstone-ს აბრუნებს; pagination/high-water retention contract არ ჩანს. `MenuCatalogMutation` append-only-ა; POS journal მხოლოდ synced entries-ს 50-მდე ამცირებს (`menu_mutation_journal.dart:178`), unresolved entries სრული რჩება.
- **მოსალოდნელი/ზემოქმედება:** cursor pagination და bounded catch-up; 10 terminals პერიოდული pulls catalog-ის მოცულობასთან ერთად ძვირდება, თუმცა ამ აუდიტში latency/capacity არ გაზომილა. Mutation/tombstone pruning-ის თვითნებური დამატება offline clients-ს მონაცემს დაუკარგავს.
- **მიღება:** representative 500/5,000 items, 10 clients, 10k mutations, bounded memory/response/p95 და offline retention replay; retention floor-ზე გადასული client იღებს explicit resync, pending local intent-ების შენარჩუნებით.

## Menu-ს crash checkpoints და ფასების ახსნა

| crash წერტილი | მიმდინარე აღდგენა | შეფასება |
| --- | --- | --- |
| local save-მდე | durable ცვლილება ჯერ არაა; UI წარმატება არ უნდა აჩვენოს | ჩვეულებრივი retry; failure UX-ის ახალი native proof საჭირო |
| local save-სა და journal capture-ს შორის | menu/baseline diff restart-ზე edit-ს ჩვეულებრივ იჭერს, თუ state/baseline/menu გადარჩა და projection-მა არ გადაფარა | DEGRADED; acknowledged journal boundary არ არის (`MENU-02`); disk-full durability NOT PROVEN |
| journal append-სა და baseline save-ს შორის | journal entry უკვე არსებობს, მაგრამ ძველი baseline შეიძლება იმავე diff-ს ხელახლა დააფიქსირებდეს ახალი mutation ID-ით | დამატებითი duplicate/conflict რისკი; controlled kill test საჭიროა. Same exact mutation retry ამას არ ფარავს, რადგან ახალი ID შეიძლება შეიქმნას |
| projection clear/addAll-ისას | `_rebuilding` flag არსებობისას state+journal-დან rebuild (`pos_menu_sync.dart:213`) | უბრალო interrupted rewrite აღდგენის გზა არის; თანმხლები ახალი direct edit შეიძლება „interrupted projection“-ად ჩაითვალოს და გაქრეს |
| Cloud commit-სა და ACK-ს შორის | იგივე journal mutation ID retry; server duplicate branch | side effect-ის duplication შეზღუდულია; response contract defect `MENU-03` |
| synced journal save-სა და canonical state save-ს შორის | sequence feed catch-up-ს შეუძლია canonical state-ის დაბრუნება; accepted reply თვითონ cursor-ს არ წინ სწევს | code recovery გზა არსებობს; all-points process test არ ჩატარებულა |
| conflict reconciliation-ისას | unresolved patch local projection-ში რჩება; Use current შლის; Reapply ახალ ID-ს ქმნის | audit gap `MENU-08`; dependent parent/child resolution ჯერ დასამტკიცებელია |
| backup/replacement | projection-only menu ვერ ინარჩუნებს original intents/revisions; missing closure/command journals | DATA LOSS/INTEGRITY RISK (`MENU-01`) |

**მაგალითი ფასზე:** Cloud-ში ხინკალი 2.00 GEL ღირს. გათიშულ A-ზე ოპერატორმა 2.20 დაწერა, გათიშულ B-ზე 2.50. A-ს ახალი OrderItem ფასი 2.20 იქნება, B-სი 2.50; ორივეს ოფლაინ ხელმისაწვდომობა არ ნიშნავს საერთო price consistency-ს. ქსელის აღდგენისას ერთ revision-ზე ერთი mutation მიიღება, მეორე conflict გახდება; unresolved local patch კვლავ ადგილობრივ projection-შია, სანამ ოპერატორი გადაწყვეტს. ამ პერიოდში ახალი ხაზების ფასები კვლავ შეიძლება განსხვავდებოდეს.

უკვე შექმნილი OrderItem-ის `unitPrice/total` captured მონაცემებია; Menu catch-up Order box-ს არ გადაწერს (`order.dart:27–28`, `menu_screen.dart:726–740`). იგივე cart key-ის დამატება არსებული entry-ის quantity-ს ზრდის და მის unitPrice-ს ინარჩუნებს (`menu_screen.dart:695–704`); `Order.addItem`-შიც იგივე მიდგომაა (`order.dart:518–528`). ამიტომ „ახალი order line“ და „ძველ ხაზზე მეტი ცალი“ განსხვავებული შემთხვევებია. Historical Sale/receipt snapshot-ის შეცვლა menu price conflict-ის გადაწყვეტის ნაწილი არ უნდა იყოს. Repricing, თუ მომავალში დაემატება, ცალკე უფლებამოსილი და აუდიტირებადი ქმედება უნდა იყოს.

## POS integrity findings

### POS-01 — Close Day არ არის recoverable transaction

- **ტიპი/სიმძიმე:** production core integrity risk, **P0 Close Day-enabled single-POS release-ის ფარგლებში**; `CONFIRMED_BY_CODE`, მაღალი ნდობა. runtime fault injection `BLOCKED_BY_ENVIRONMENT`. გამორიცხვის enforceable კონტროლი ვერ მოიძებნა.
- **გზა:** `close_day_transaction.dart:125–131` active-order guard, `:209` occupancy guard; შემდეგ awaits; `:270–299` currentDate update → daily total reset → closed Order delete → table free → audit `:306`. ფუნქციის catch `:322` მხოლოდ false-ს აბრუნებს. ცალკე day-close journal/recovery checkpoint არ არის.
- **მოსალოდნელი:** §7/9 Close Day/recovery; ერთი დასრულებული business-date transition ან აღდგენადი pending transition, რომელსაც ახალი orders ვერ გადაასწრებს.
- **სცენარები:** kill date put-ის შემდეგ; write failure total reset-ისას; ახალი Order guard-სა და final table cleanup-ს შორის. `UpdateReadiness.track` (`update_readiness.dart:46–58`) მხოლოდ updater admission counter-ია, არა ერთმანეთის გამომრიცხავი operation lock.
- **ზემოქმედება:** ხელახალი close შეიძლება უკვე შემდეგ დღეს შეეხოს; audit/cleanup ნაწილობრივ დარჩეს; ახალი order-ის მაგიდა cleanup-მა გაათავისუფლოს. რეალურად დაკარგული restaurant transaction ამ აუდიტში არ დაფიქსირებულა.
- **შესწორება/მიღება:** day-close durable intent/phases, ერთი transition ID, business-date admission barrier ყველა order/payment/remote writer-ზე, idempotent startup recovery; fail ყოველი await-ის შემდეგ და assert დღე ზუსტად ერთხელ იცვლება და არცერთი ახალი active order/table არ ქრება.

### POS-02 — print delivery-ის exactly-once გარანტია არ არსებობს

- **ტიპი/სიმძიმე:** implemented transport-ის reliability limitation, **P1** kitchen operational acceptance-ისთვის; `CONFIRMED_BY_CODE`, physical `NOT_TESTED`.
- **გზა/სცენარი:** `print_queue.dart:12–13` process-memory queue; kill enqueue/send შორის job-ს კარგავს. `printer_transport.dart:39` persistent send failure-ზე fallback; `:68–81` raw bytes flush/close success-ად ითვლება; გაურკვეველი send exception-ზე retry შეიძლება იგივე slip მეორედ დაბეჭდოს.
- **კარგი არსებული კონტროლი:** remote command interruption-ზე `edge_transport_service.dart:281–303` no-repeat command-ს `interrupted_not_repeated`-ად აღნიშნავს და ავტომატურად არ იმეორებს. ეს process redelivery-ს ეხება და TCP-ის შიგნით ნაწილობრივ გაგზავნას ან ფიზიკურ ქაღალდს ვერ ადასტურებს.
- **მოსალოდნელი/ზემოქმედება:** §7 printing; kitchen ticket დაკარგვამ/დუბლირებამ შეიძლება კერძის გამოტოვება/ორმაგი მომზადება გამოიწვიოს. Uncertain state მომხმარებელს უნდა ეჩვენოს.
- **შესწორება/მიღება:** durable print job identity, sent/uncertain/confirmed/reprint states, explicit labeled reprint; protocol-ის შესაძლებლობების მიხედვით printer ACK, რეალისტური limitation copy. Power/cable disconnect send-ისას; paper-out; process kill; deliberate reprint audit; real hardware proof თითო supported model-ზე.

### POS-03 — item transfer-ს შუა crash ორმაგ რაოდენობას დატოვებს

- **ტიპი/სიმძიმე:** production durability defect, **P0 transfers/split-enabled single-POS release-ის ფარგლებში**; `CONFIRMED_BY_CODE`, მაღალი ნდობა. crash checkpoint-ის enforceable exclusion ვერ მოიძებნა.
- **გზა:** `order_item_transfer.dart:257–267` valid copies; `:274–277` destination write შემდეგ source write; ორივე მხარის audit მოგვიანებითაა (`:311,328`). `OrderTableShadow.observe` failure-free local transaction-ს არ ქმნის და production observer null-ია.
- **სცენარი:** A bill-იდან 2 ერთეულის B-ზე გადატანა; destination update დაბრუნდა; process kill source persistence-მდე; reopen. მოსალოდნელი venue-wide quantity conservation და ერთი transfer. შესაძლო actual persisted state: B-ს დაემატა 2, A-ს ისევ აქვს 2; audit შესაძლოა არც იყოს.
- **შესწორება/მიღება:** durable transfer ID + ორივე before/after image/phase ან ერთ transactional operational store-ში commit; ყველა endpoint/UI writer-ის იგივე routine; kill destination/source/audit/empty-source closure-ს შორის და რაოდენობა/თანხა/identity invariant.

### POS-04 — card selection არ არის acquiring integration

- **ტიპი/სიმძიმე:** intentional product limitation, **P1** გაყიდვის დაპირების სიზუსტისთვის, არა არსებული code defect; `CONFIRMED_BY_CODE`.
- **გზა:** `table_payment_service.dart:481–531` bank dialog; `:1110–1116` provider mapping; `:1119` records data. ამ გზაზე terminal SDK authorization/capture response არ მონაწილეობს.
- **მოსალოდნელი/ზემოქმედება:** მომხმარებლის §7 მოითხოვს განსხვავებას. POS-ის „card paid“ ნიშნავს ოპერატორის აღრიცხვას; ეს არ ამტკიცებს ბანკიდან თანხის მიღებას. რეალური bank-terminal reconciliation/manual operating procedure აუცილებელია.
- **მიღება:** release/product text მკაფიოდ აღწერს manual recording-ს; acquiring-ის შეთავაზებამდე provider sandbox certification, request idempotency, uncertain authorization status, cancel/refund reconciliation და რეალური terminal proof. ამ აუდიტში real payment არ შესრულებულა.

### POS-05 — ერთ პროცესშიც table create-ს საერთო admission lock არ აქვს

- **ტიპი/სიმძიმე:** production core integrity risk, **P0 concurrent local/remote order-creation-ის მქონე single-POS release-ის ფარგლებში**, `CONFIRMED_BY_CODE`; კონკრეტული concurrent execution `NOT_TESTED`. საერთო admission exclusion ვერ მოიძებნა.
- **გზა:** `order_repository.dart:102–115` free check; await Order add `:139`; reservation `:144`; `table_repository.dart:323–326` unconditionally reserve/save. `UpdateReadiness.track` mutex არაა.
- **სცენარი:** local UI create A და remote/Manager create B ერთ table-ზე A-ს order save await-ისას; ორივემ შეიძლება free check გაიაროს, რადგან reservation ჯერ არ ჩაწერილა. მეორე reserve პირველს გადააწერს. ეს ცალკე multi-Hive პრობლემა არაა.
- **მოსალოდნელი/შესწორება:** ერთი active Order თითო table-ზე, authoritative create/reserve commit და ყველა writer-ის shared guard. UI button disable არასაკმარისია; per-table/order serialization + stable idempotency.
- **მიღება:** simultaneous local+remote create, duplicate command, cancellation/payment/edit races, Close Day admission test. table ერთ Order-ს მიუთითებს; უარყოფილი მოთხოვნა არც orphan Order-ს და არც duplicate audit-ს ტოვებს.

## 1 / 3 / 10 ტერმინალი: რეალური production authority

**EDGE-01 — live multi-POS ჯერ არასათანადო შეთავაზებაა.** ეს არის **intentional architecture limitation / P0 release gate** 3/10 simultaneous operational writers-ისთვის, არა მტკიცება, რომ Phase 2A implementation გაფუჭებულია. `CONFIRMED_BY_CODE`, მაღალი ნდობა.

Phase 0-ის ავტორიტეტი არის `Venue.activeOperationalDeviceId`. `operational-authority.ts:36–57` მოქმედი Device-ისა და primary identity-ის შემოწმებას აკეთებს; legacy fallback მხოლოდ zero-Device Venue-ზეა. Ingestion/replacement ერთი Venue transaction lock-ით სერიალიზდება (`:16,78–88`). Replacement attempted commands-ს `primary_replaced_outcome_unknown`-ში ტოვებს (`:113–129`), რათა ძველ Hive-ში შესაძლოა შესრულებული side effect ახალზე ავტომატურად არ გაიმეოროს. ეს Cloud containment-ია. ძველი POS-ის local UI/Hive გაყიდვას Cloud rejection ვერ აჩერებს.

Go Edge foundation grant აბრუნებს `businessMutationsEnabled:false` (`edge-foundation.ts:113–118`). Phase 2A `CommitIntent` ნამდვილად ინახავს digest/result/event/projection-ს SQLite transaction-ში, epoch და expectedRevision-ით (`coordination.go:260–358`); დაბრუნებული snapshot mode არის `SHADOW` (`:378`). production startup observer-ს არ რთავს; `shadow.dart:10–15,42–43`; ერთადერთი explicit attachment `tool/edge_phase2a_terminal.dart:163`-შია. ამიტომ Go-ში მიღებული simulated atomic commit live POS operation-ის გარანტია არაა.

| საკითხი | 1 მოქმედი primary | 3 მოწყობილობა | 10 მოწყობილობა |
| --- | --- | --- | --- |
| მიმდინარე მხარდაჭერის საზღვარი | ერთი Hive არის ოპერაციული სიმართლე; Cloud-independent მუშაობის ლოგიკა არსებობს | enrollment დასაშვებია; მხოლოდ ერთი primary წერს authoritative Cloud operations-ს | იგივე primary წესი; device count-ით writer permission არ მრავლდება |
| წარმოების შეკვეთების საერთო მდგომარეობა | same-process local state | სამ independent Hive-ს shared active-order replication არ აქვს | იგივე; მოცულობა რისკს ზრდის და ფუნქციას არ ამატებს |
| canonical Menu | local edits + Cloud revisions; ზემოთ blockers | configuration convergence პროტოკოლი არსებობს | 10-terminal menu test არის configuration proof, არ არის order/payment proof |
| pilot შეფასება | supervised synthetic qualification-ის კანდიდატი; `POS-01/03/05`, `MENU-01/02/03` ჯერ დასახურია | 3 active cashier-ის pilot აკრძალული; 1 active + მკაფიოდ არაოპერაციული secondary მხოლოდ runbook-ით | 10 active writer-ის გაყიდვა/წარმოების pilot დაუშვებელი; load/authority/recovery rollout ჯერ გასაკეთებელია |

### სავალდებულო კონკურენტული სცენარები

| სცენარი | დღეს | აქტიური multi-POS-ის მისაღები შედეგი |
| --- | --- | --- |
| A ხსნის Table 3; B/C ნახვა | A-ის Hive occupancy იცვლება. Cloud/Manager snapshot-ს ჩვეულებრივ 0–30 წამი + network/processing ემატება. B/C POS Hive-ში ამის operational replication არაა | Edge event→B/C projection; ასაკი/connection state ჩანს. Lag-ზე user არ უნდა ხედავდეს გარანტირებულად „თავისუფალს“ |
| A/B ერთ free table-ზე ქმნიან Order-ს | დამოუკიდებელ Hive-ებში ორივე locally succeed შეიძლება; Cloud მხოლოდ primary-ს მიიღებს | ერთი authoritative atomic create+occupancy CAS; მეორე conflict იღებს და პირველი Order-ის ნახვას სთავაზობს |
| ორი terminal same order/line edit | საერთო revision/exclusion production path-ში არაა; secondary local edits იზოლირებულია | order/line revisions ან serialized commands; no lost update, distinct-line policy აშკარა |
| transfer + source/destination edit | ადგილობრივი ორ-save transfer; სხვა Hive იზოლირებულია; local concurrent writer-იც რისკია | source+destination atomic revision check/commit; total/quantity conservation |
| card selection + cash close/cancel | payment dialog არის ადგილობრივი; სხვა terminal-ს global settlement claim არ ეცნობება | settlement state machine და durable payment attempt; shared authority-მ ერთი attempt მიიღოს; acquiring uncertain status explicit |
| Close Day + ახალი Order | Close Day guard და later mutations საერთო lock-ში არაა | Venue/business-date transition barrier; დაწყებული ოპერაციების drain ან explicit reject; ერთი day-close ID |
| primary crash uncertain command-ზე | local execution journal terminal outcome-ს ხელახლა ACK-ავს; interrupted unsafe print-ს ავტომატურად არ იმეორებს | უცნობი outcome აღდგეს იგივე durable authority-დან; ახალი identity-ით ავტომატური replay არა |
| Edge crash | production POS orders Edge shadow-ის live availability-ზე არ არის დამოკიდებული | active Edge-ზე restart journal replay/epoch/cursor recovery; terminal-ებმა commit response დაკარგვისას იგივე request ID გამოიყენონ |
| ძველი primary დაბრუნდა replacement-ის შემდეგ | Cloud operational ingest deny; ძველი Hive მაინც locally sell/edit-ს შეძლებს | controlled handoff + durable fencing/lease policy; ძველი epoch ვერ ასრულებს committed mutations-ს; unreconciled local records quarantine/review |

### ქსელის მატრიცა

| გარემო | მიმდინარე ქცევა | აქტიური multi-POS მოთხოვნა |
| --- | --- | --- |
| Cloud up / LAN up | primary Hive+Cloud mirror; secondary independent; menu convergence | shared Venue-local operational authority, bounded observation latency |
| Cloud down / Edge reachable | ერთი primary აგრძელებს ლოკალურად; canonical edits pending. Edge-ის ხელმისაწვდომობა production coordination-ს დღეს არ რთავს | აქტიური Edge-მ shared orders/payments/day state LAN-ზე უნდა მართოს; Cloud sync გადაიდოს |
| Edge down | მიმდინარე primary local order paths აგრძელებს; shadow failure primary operation-ს არ კეტავს | წინასწარ გადაწყვეტილი safe degraded mode; shared authority unavailable-ზე exclusive operations უარყოფილი ან მხოლოდ fenced single writer |
| terminals partitioned | independent Hive-ები divergent სამუშაოს ქმნიან; strict global occupancy/settlement შეუძლებელია | disconnected მხარეს shared table/new settlement უარყოფა საჭიროა, თუ double action-ის მკაცრი აკრძალვა გვინდა |
| reconnect independent work-ის შემდეგ | canonical Menu explicit conflicts აქვს; operational Order/Table reconciliation არა | orphan/uncommitted intent reconciliation; payment outcome investigation; ავტომატური last-write-wins დაუშვებელია |

სიმულტანური **ნახვა** უნდა იყოს დაშვებული; ეკრანის გახსნით მაგიდის მუდმივი lock არ არის სწორი საწყისი მოდელი. Order creation ქმნის occupancy-ს. ჩვეულებრივ editing-ს optimistic revision შეუძლია მართოს. თუ settlement/გრძელი edit პროცესისთვის lease დაემატება, საჭიროა server-owned expiry, renew, explicit release, crash timeout, monotonic authority epoch/fencing და expiry-ის შემდეგ stale command reject. კონკრეტული lease ხანგრძლივობა product/load proof-ის შემდეგ უნდა აირჩეს. Unrestricted partitioned offline writers + strict global exclusivity ერთდროულად ვერ იქნება გარანტირებული.

### Edge rollout-ის წინაპირობები

1. დაფაროს ყველა production writer: ordinary/takeaway უკვე ნაწილობრივ observed; mobile/cloud upserts, status-only, layouts/reservations, packages/adjustments, transfer-close, payment/close/restore/Close Day ჯერ ერთ authority contract-ში არაა (`EDGE_PHASE2A_ORDERS_TABLES.md:107–127`).
2. separately authenticated active operational Edge selection, epoch handoff, old-primary fencing, migration/recovery plan; foundation grant არ გადაიქცეს ჩუმად authority grant-ად.
3. Venue-local durable command result + transactional order/table/settlement/day operations; production storage/index/retention/paging policy. Shadow store-ს 256-entity bound აქვს (`coordination.go:329`) და production capacity claim-ად არ გამოდგება.
4. რეალური 1→3→10 terminal qualification ყველა ზემოთ სცენარით; მხოლოდ zero unexpected shadow mismatch და explicit rollout approval-ის შემდეგ active gate.

## Windows installer/updater release gates

**EDGE-02 — native release qualification არასრულია.** `P1`, release-process gap; მიმდინარე implementation `CONFIRMED_BY_CODE`, ახალი Windows/hardware proof `NOT_TESTED`.

არსებული უსაფრთხოების კონტროლები:

- distinct Ed25519 signature domains, pinned keys, exact payload bytes (`updater/manifest.go:87–107`);
- product/OS/arch/channel/version/high-water/expiry/schema/data-policy checks (`manifest.go:122`), exact SHA-256/size (`:139`); HTTPS-only bootstrap/redirects (`setup/metadata.go:62–114`);
- POS updater only `127.0.0.1` + host token (`updater.go:83`); readiness/consent; no arbitrary downloaded script path;
- current/staging/rollback binary layout, known-path cleanup, signed repair policy; data rollback არ კეთდება;
- candidate health-ს PID, version, nonce, Hive schema და exact data path ევალება (`updater.go:791`); 30-second stabilization და recurring heartbeats (`:117,580–603`);
- Flutter freeze ბლოკავს ახალ tracked mutations-ს და failure-ზე frozen რჩება (`update_readiness.dart:61–73`);
- Edge self-update/helper არ არის ამ POS updater-ის ნაწილი; schema gate მხოლოდ `hive9-no-migration`/`edge2-no-migration` გზას უშვებს.

ამ ფაქტებისგან **არ გამომდინარეობს**, რომ ყოველი current binary არის production-signed/published, latest manifest მისაწვდომია, SmartScreen reputation მიღებულია ან Windows ACL/Defender/physical peripheral matrix გავლილია. ეს თითო release artifact-ის operational evidence-ით უნდა დადასტურდეს.

ისტორიული ცნობები განცალკევებით:

- `docs/WINDOWS_SETUP.md:429–435` აღწერს Windows 11 Parallels-ში signed bundle-ისა და legacy Hive-ის ასლების data-path/stabilization proof-ს. ეს current checkout-ის სრული install/update qualification არაა.
- `docs/WINDOWS_DEFENDER_REVIEW.md:11–24` ასახელებს 2026-09-22 lab clean scan-ს კონკრეტული Setup hashes/versions-ით. თავდაპირველი Bearfoos detection-ის exact artifact/verdict დაუდგენელი რჩება. „ყველა release უსაფრთხოა“ ამ ჩანაწერით ვერ ითქმის.
- `docs/POS_BINARY_RETENTION_VALIDATION.md:3–5` explicit macOS/synthetic Windows bundle proof-ია; `EDGE_PHASE2A_VALIDATION.md:49–61` explicit non-production/shadow proof-ია.

**Owner-run Windows checklist (სინთეზური მონაცემებით, release candidate-ის exact SHA/version-ით):**

1. clean Windows user install; no elevation workaround; path non-ASCII/spaces; shortcuts, logon startup, fullscreen, PIN/numeric/text keyboard at 1024×768 და 1440×900.
2. enrollment dedicated native origin-ით, canonical menu first pull, printer setup; Cloud disconnect და restart; existing Staff/PIN/Order/Sale შენარჩუნება.
3. open table + pending menu/sale ACK ფონზე update staging; active payment/close/restore/write/print დროს install refusal; deferred update/offline release check განმარტება.
4. signed healthy candidate → 30s stabilization; kill candidate; wrong Hive path; installer/host/POS restart ყოველ swap checkpoint-ზე; rollback data უცვლელი.
5. repair exact installed version; uninstall/reinstall retained data; stale rollback/staging cleanup; no unexpected automatic Edge upgrade.
6. Authenticode chain/timestamp, Defender current definitions scan exact downloaded+installed hashes-ზე, SmartScreen შედეგი; AV არ გაითიშოს. მტკიცებულება private evidence-ში.
7. რეალური kitchen/receipt models: paper-out, unplug, printer reboot, cable loss send-ისას, labeled reprint; ქართული glyph/ქაღალდის ზომა.
8. card payment მხოლოდ synthetic/manual recording; acquiring integration ცალკე certified sandbox/hardware proof-ამდე product UI-ს წარმატება bank authorization-ად არ ჩაითვალოს.
9. export backup→fresh isolated installation→restore; menu intents/closure recovery ახალი tests-ით; მხოლოდ შემდეგ supervised restaurant rehearsal.

## ტესტების ზუსტი საზღვარი და შემდეგი bounded proof

| სფერო | ამ reviewer-ის მიმდინარე შედეგი | შესაბამისი შემდგომი/ცენტრალური ბრძანება |
| --- | --- | --- |
| exact Menu retry | mocked actual service branch REPRODUCED; script/log private evidence-ში | `node -r ts-node/register/transpile-only .../menu-retry-repro.cjs`; შემდგომ isolated PostgreSQL HTTP integration |
| Flutter canonical/backup/closing | კოდი და ახლომდებარე tests წაკითხულია; ახალი execution გარემომ დაბლოკა | `flutter test test/unit/canonical_menu_sync_test.dart test/unit/backup_completeness_test.dart test/unit/closure_money_test.dart test/unit/closure_audit_integrity_test.dart test/unit/cancel_order_transaction_test.dart test/unit/order_item_transfer_apply_test.dart` მხოლოდ writable isolated SDK/env-ში |
| 3/10 menu test | fixture არსებობს `canonical_menu_sync_test.dart:611`; ეს live multi-POS არაა | isolated existing suite-ის შედეგი ცენტრალურ evidence-ში |
| Go Edge/updater/setup | current code proof; root-ის baseline-ზე Go PATH-ში არ იყო, ამიტომ ახალი Go execution BLOCKED_BY_ENVIRONMENT; Python tool tests-ის მიმდინარე შედეგები ცენტრალურ evidence-შია | შემდგომ `go test -race ./...`, `go vet ./...` disposable build/cache roots-ით |
| native Windows/hardware | NOT_TESTED; historical proof ცალკე | ზემოთ owner-run checklist |
| backup/restore power failure | DATA LOSS/INTEGRITY RISK code checkpoints-ით | ახალი disposable Hive fixtures, kill/write-failure ყოველი checkpoint-ის შემდეგ |
| representative capacity | NOT PROVEN; latency რიცხვი არ არის | 500/5,000 Menu nodes; 1/3/10 clients; 10k mutation history; 10-minute bounded lab run, hardware/concurrency/p50/p95/memory/error count ჩანაწერით |

DB/network resources ამ reviewer-ს არ შეუქმნია. მხოლოდ audit markdown და ორი private synthetic repro artifact შეიქმნა. Original WIP untouched; root reviewer-ის resource manifest/final Git comparison არის საერთო აუდიტის ავტორიტეტი. Private repro-ში არც credentials და არც customer data არ არის.

## ცენტრალური პრიორიტეტიზაცია

ერთიანი სამუშაო სიაა [MASTER_BACKLOG.md](MASTER_BACKLOG.md), ხოლო პირველი ხუთი ეტაპი და product release dependencies — [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md). `MENU-04` გაერთიანებულია `COM-01`-ში, `EDGE-02` — `OPS-01`-ში, `POS-04` — `PROD-01`-ის explicit limitation-ში. ჯერ single-terminal durability და hardware qualification, შემდეგ 3-terminal authority correctness, ბოლოს 10-terminal scale. ეს dependency-ებია და არა დამოუკიდებელი კონკურენტი roadmap. Application implementation არ დაწყებულა.
