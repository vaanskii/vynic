# Vynic — პროდუქტისა და გამოშვების მზადყოფნის აუდიტი

**2026-09-29 · Asia/Tbilisi · `f7bb982` + აუდიტის დასაწყისში არსებული WIP.** ეს არის აუდიტი და დაგეგმვა. აპლიკაციის კოდი, ბიზნესწესები, migrations და dependencies არ შეცვლილა. მომხმარებლის მონაცემთა ბაზები, ანგარიშები, პაროლები, stash და deployment ხელუხლებელია.

## მთავარი დასკვნა

Vynic უკვე შეიცავს რესტორნის პროდუქტის მნიშვნელოვან საფუძველს: ადგილობრივად მომუშავე Windows POS, Manager, ოპერატორისა და მფლობელის ვებპანელები, საერთო NestJS/PostgreSQL backend, SaaS და CUSTOM ვებსაიტები, კომერციული უფლებები, canonical Menu და Edge-ის ინფრასტრუქტურა. ეს მხოლოდ მაკეტი არ არის. ამავე დროს, არსებული მტკიცებულება **რეალურ რესტორანში სრული პაკეტის უსაფრთხო გაშვებას ჯერ არ ამართლებს**.

მთავარი პრობლემა ფუნქციების რაოდენობა არ არის: რამდენიმე გზაზე პროგრამა წარმატებას აჩვენებს მანამდე, სანამ მოქმედება საიმედოდ შესრულდება; ავარიისას შესაძლებელია ცვლილების დაკარგვა; ვებსაიტის ორი უსაფრთხოების დეფექტი რეალური service კოდით სინთეზურად გამეორდა. გაშვებული Docker image-ის ვერსია და მონაცემთა ბაზის მდგომარეობა წყაროს ვერსიასთან ვერ დავაკავშირეთ. ეს შეზღუდვა წყაროში ფუნქციის არქონას არ ნიშნავს.

## როგორ მუშაობს სისტემა

**Platform Admin** არჩევს მომხმარებლის პროდუქტებს, trial/paid სტატუსს, დომენსა და website mode-ს. **Customer Dashboard** რესტორნის მფლობელს აძლევს საკუთარ Venue-ზე დაშვებულ კონტენტსა და პარამეტრებს. **Windows POS** ადგილობრივ Hive-ში მართავს მაგიდებს, შეკვეთებს, გადახდის აღრიცხვასა და დღიურ ოპერაციას; Cloud-თან კავშირი შემდგომი სინქრონიზაციისთვის გამოიყენება. **Manager** Cloud-ის მონაცემებს კითხულობს, მარაგისა და ფინანსების ნაწილს პირდაპირ Cloud-ში წერს, ხოლო POS-ის ოპერაციული ცვლილება მოწყობილობამ უნდა შეასრულოს და დაადასტუროს.

**SaaS და CUSTOM** ორი frontend არჩევანია ერთი რესტორნის საერთო backend-ზე. Host → VenueDomain → Venue განსაზღვრავს მონაცემის მფლობელს. Go Edge-ის foundation/updater/shadow არსებობს, მაგრამ live Order/Table ოპერაციების სრული მრავალკასიანი ავტორიტეტი ჯერ ჩართული არ არის. დეტალური რუკა და ექვსივე end-to-end გზა: [SYSTEM_AND_ARCHITECTURE.md](SYSTEM_AND_ARCHITECTURE.md).

## რა არის დამტკიცებული

- იზოლირებულ წყაროს ასლში backend-ის **536 ტესტი წარმატებულია 543-დან**; დარჩენილი 7 შემთხვევა HTTP listener-ის ნებართვის შეზღუდვამ დაბლოკა. ეს არც წარმატებად და არც აპლიკაციის 7 დადასტურებულ bug-ად არ ითვლება.
- Platform/customer web: **158**, SaaS: **19**, shared client: **6**, template: **3** წარმატებული ტესტი. Vankisi-ს test script არ აქვს. backend/platform/SaaS/Vankisi/template build და shared-client typecheck წარმატებულია.
- contract generation check და Python release tooling-ის **31 ტესტი** წარმატებულია. ეს Windows executable-ისა და ფიზიკური პრინტერის მტკიცება არ არის.
- კოდში არსებობს Venue-scoped guards, ცალკე Platform identity, explicit trial activation, server-time expiry, NO_PLAN შეზღუდვა, default-off NON_FISCAL_CLOSE, signed BOG callback verification, integration credential revisions, mutation identity და POS closure journal.
- ნამდვილი ბრაუზერით ნანახია საჯარო გვერდი, access request და login ეკრანები; დადასტურებული mobile viewport არის 390×844. ავტორიზებული workflow-ების სრული browser proof არ გვაქვს.

**არ შესრულებულა:** 38 PostgreSQL integration suite, migration replay/upgrade/restore, მიმდინარე Flutter/Go suite, Windows/პრინტერი/payment hardware, ბანკის sandbox, წარმოების capacity benchmark. Docker socket, PostgreSQL shared memory, SDK cache და registry DNS შეზღუდვები ცალ-ცალკე აღრიცხულია. ძველი ანგარიშები ახალ proof-ად არ ჩათვლილა. სრული შედეგები: [EVIDENCE_AND_MATRICES.md](EVIDENCE_AND_MATRICES.md).

## ყველაზე მნიშვნელოვანი რისკები

| საკითხი | მტკიცებულება და ზიანი | რომელ გამოშვებას ბლოკავს |
|---|---|---|
| SEC-01 | synthetic 110 GEL preorder-ის persisted/provider თანხა client-ის მიერ 1 GEL-მდე შემცირდა; mocked DB/network, რეალური service | ონლაინ გადახდებიანი booking |
| SEC-02 | დაუდასტურებელი email-ით შექმნილ account-ს შესაბამისი guest booking-ის პირადი ველები გამოუჩნდა | website accounts + guest bookings |
| WEB-01/03/04 | booking race, paid booking dispatch-ის დაკარგვის ფანჯარა, callback-ის უკუღმა მდგომარეობის ცვლილება | reservation/payment და POS delivery |
| WEB-02 | migration draft-ს public shared ველებად ირჩევს | არსებული საიტების უსაფრთხო upgrade |
| MENU-01/02/06 | backup-ში მნიშვნელოვანი journals აკლია; projection rewrite/live edit race; recipe deletion offline consumption-ს აფერხებს | canonical Menu POS, აღდგენა, დაკავშირებული inventory |
| POS-01/03/05 | Close Day, transfer და მაგიდაზე ერთდროული order creation-ის crash/concurrency საზღვრები არასაკმარისია | ერთი POS-ის შესაბამისი ძირითადი workflow-ებიც |
| MGR-02/05; MGR-03 | Cloud-only table release, order-ის ნაწილობრივი rewrite, queued მოთხოვნის დასრულებულად ჩვენება | Manager-ის ოპერაციული ჩაწერები |
| EDGE-01 | რამდენიმე enrolled Device ≠ რამდენიმე სინქრონული operational writer | 3 და 10 ტერმინალი |

P0 არის დასახელებული scope-ის blocker და ყველა პროდუქტს ავტომატურად არ კეტავს. მაგალითად, paid booking-ის bug თავისთავად menu-only საიტს არ ბლოკავს; მრავალკასიანი პრობლემა ერთკასიანი რეჟიმის ცალკე შემოწმებას არ ცვლის. სრული, დუბლირებისგან გაწმენდილი ბარათები: [MASTER_BACKLOG.md](MASTER_BACKLOG.md).

## პროდუქტების მზადყოფნა

შეფასება ეხება **რეალურ რესტორანში მხარდაჭერად გაშვებას**, არა ლოკალურ დემონსტრაციას. `BLOCKED` შეიძლება ნიშნავდეს კონკრეტულ დეფექტს ან სავალდებულო მტკიცებულების არქონას; ქვემოთ მიზეზი მითითებულია. ამ ჭრილში არც ერთ სრულ end-to-end პაკეტს არ ვანიჭებთ `READY FOR CONTROLLED PILOT` სტატუსს. ვიწრო სამომავლო scope არ არის უკვე მინიჭებული ნებართვა.

| პროდუქტი | სტატუსი | რატომ / დარჩენილი gate |
|---|---|---|
| ერთი POS | **BLOCKED** | POS-01/03/05; canonical რეჟიმში MENU-01/02/06; Windows restart/print/install/restore proof. Legacy venue-ს canonical cutover არ სჭირდება, მაგრამ POS core gates რჩება |
| 3 ტერმინალი | **BLOCKED** | EDGE-01; ერთიანი operational authority, fencing, conflict/partition და uncertain settlement proof |
| 10 ტერმინალი | **BLOCKED** | 3-terminal correctness gates + გაზომილი contention/load/latency; მოცულობითი capacity დაუდასტურებელია |
| Manager | **BLOCKED** | MGR-01/02/03/05; ნამდვილი Venue layout, POS ACK, ზუსტი pending/stale states; narrow read-only mode შეიძლება შემდგომი scope იყოს |
| Website-only SaaS | **BLOCKED** | menu/contact-only ყველაზე ვიწრო კანდიდატია; ჯერ WEB-02 upgrade/publication და OPS-01 deployment/cross-Venue proof; accounts/reservations/payments სერვერით გათიშული უნდა იყოს თუ scope-ში არ შედის |
| Website-only CUSTOM | **BLOCKED** | SaaS-ის საერთო gates + სწორი frontend build/binding proof, WEB-05/07; ერთჯერადი ACTIVE მონიშვნა deployment არ არის |
| POS + Manager / POS + Website / სრული პაკეტი | **BLOCKED** | თითო ჩართული ნაწილის gates + command/consumption end-to-end; მეტი plan flag მტკიცებულებას არ ქმნის |
| Inventory | **BLOCKED** სრული საწყობის პროდუქტისთვის | receipt/debt/payment/sale consumption არსებობს; MENU-06; locations/transfer/waste/count/returns/production აკლია. მხოლოდ არსებული subset-ის მიწოდებაც მისივე integrity proof-ს მოითხოვს |
| Commercial lifecycle | **BLOCKED** რეალური activation-ის საბოლოო gate-ზე | explicit lifecycle და guards კოდში არსებობს; PostgreSQL/open-session/upgrade matrices ამ გაშვებაში არ შესრულებულა. დადასტურებული missing automatic billing ამ შეფასების მიზეზი არ არის |
| Website payments | **BLOCKED** | SEC-01, WEB-01/03/04/06; თანხა, replay/order, reconciliation და provider sandbox |
| Subscription billing | **BLOCKED** live end-to-end დამტკიცებამდე | manual verified payment გზა არსებობს; DB/quote/replay proof საჭიროა. Automatic checkout/recurring collection განხორციელებული პროდუქტი არაა; manual pilot-ისათვის მისი დამატება აუცილებელი არ არის |
| Security | **BLOCKED** accounts/paid-booking scope-ში | SEC-01/02; სხვა scope-ს tenant/session/upload/host negatives და შესაბამისი hardening სჭირდება; სრული assurance არ გაიცემა |
| Deployment | **NOT ASSESSED** მიმდინარე გაშვებულ არტეფაქტებზე | Docker image/revision/migration state ვერ შემოწმდა; source foundation განხილულია, native ingress არის WIP; OPS-01 |
| Backup/restore | **BLOCKED** | MENU-01 known journal omission; fresh restore + keys + native/schema compatibility დაუმტკიცებელია |

Manager-only და Website + Manager პროდუქტები არ უნდა გაიყიდოს როგორც დამოუკიდებელი live-restaurant replacement: plan/feature კომბინაციის ტექნიკური დაშვება POS-ის operational source-ს არ ქმნის. [კომბინაციებისა და subscription states-ის მატრიცა](WEB_COMMERCIAL_SECURITY.md) განმარტავს აქტიურ, expired, missing, past-due და scheduled მდგომარეობებს.

## Inventory-ის მთავარი გასასწორებელი ნაწილი

დღევანდელი UI ერთმანეთთან ახლოს აჩვენებს ინგრედიენტს, მიღებას, მიმწოდებლის ვალს, გადახდასა და ხარჯს, ხოლო საწყობის რამდენიმე რეალური მოქმედება საერთოდ არ არსებობს. მომხმარებელი ვერ ხედავს მარტივ ჯაჭვს: **რა მივიღე → სად დევს → რა დაიხარჯა → რომელი საბუთით შეიცვალა → რამდენი მაქვს გადასახდელი**.

სინთეზური მაგალითი: 20 kg ფქვილი × 3 GEL = 60 GEL; მიმწოდებელზე 30 GEL გადახდის შემდეგ ვალი 30 GEL-ია, მარაგი კვლავ 20 kg. 4 kg შიდა გადაადგილება საერთო რაოდენობას არ ცვლის. გაყიდვა მოიხმარს 2.5 kg-ს, დანაკარგი 0.5 kg-ს: მოსალოდნელია 17 kg. აღწერა 16.6 kg ნიშნავს −0.4 kg დოკუმენტირებულ სხვაობას; საბოლოო ღირებულება, უცვლელი 3 GEL/kg დაშვებით, **49.80 GEL**. მიმდინარე კოდი მთელ ჯაჭვს არ ასრულებს: locations, waste და stocktake აკლია. ამიტომ ეს არის expected-domain example, არა წარმატებით შესრულებული DB workflow.

შემოთავაზებული სამუშაოები: „მარაგი“, „მიღებები“, „მიმწოდებლები და ვალდებულებები“, „გადაადგილება“, „დანაკარგი“, „აღწერა“, „რეცეპტები“, „მოძრაობების ისტორია“. გადახდას საკუთარი ფინანსური ქმედება ჰქონდეს; მიღების რედაქტირებით ვალი/ფული ჩუმად არ შეიცვალოს. დეტალური screen-by-screen გეგმა: [INVENTORY_MANAGER_UX.md](INVENTORY_MANAGER_UX.md).

## პირველი სამი მოქმედება

1. დასამტკიცებლად აირჩიეთ ვიწრო pilot contract: ერთი primary POS ან menu/contact-only website; manual billing; ზუსტად ჩამოთვლილი გამორთული შესაძლებლობები. ეს scope-ის გადაწყვეტილებაა და release approval არ არის.
2. პირველი დამოუკიდებელი implementation task იყოს **SEC-01 — booking თანხის გამოთვლა მხოლოდ სერვერზე**, ორივე entrypoint-ის ერთნაირი წესით და თანხის შეცვლის უარყოფითი ტესტებით. ამ აუდიტში არ შესრულებულა.
3. შეთანხმდეს OPS-01-ის იზოლირებული verification გარემო და Windows/hardware პასუხისმგებელი; შემდგომი ყველა ცვლილებისას მოიპოვეთ დღეს დაბლოკილი DB/restore/native მტკიცებულება. მომხმარებლის ჩვეულებრივი dataset არ გამოიყენოთ.

შემდეგი ხუთი reviewable milestone და შემდგომი release dependencies მოცემულია [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md). KDS, automatic subscription collection, delivery integrations და მეტი theme ამ გზაზე წინ არ დგას.

## ანგარიშების გზამკვლევი

| დოკუმენტი | შინაარსი |
|---|---|
| [SYSTEM_AND_ARCHITECTURE.md](SYSTEM_AND_ARCHITECTURE.md) | აპლიკაციები, ავტორიტეტები, A–F journeys, folders, binding |
| [INVENTORY_MANAGER_UX.md](INVENTORY_MANAGER_UX.md) | სრული domain trace, ფქვილის მაგალითი, Manager metrics და ახალი სამუშაო გზები |
| [INVENTORY_MANAGER_FINDINGS.md](INVENTORY_MANAGER_FINDINGS.md) | Inventory/Manager-ის დეტალური მტკიცებულების ბარათები |
| [POS_MENU_EDGE.md](POS_MENU_EDGE.md) | POS lifecycle, canonical durability, 1/3/10 ტერმინალი, Windows checklist |
| [WEB_COMMERCIAL_SECURITY.md](WEB_COMMERCIAL_SECURITY.md) | product/state/access მატრიცები, ვებსაიტები, billing/payment findings |
| [UI_UX_AUDIT.md](UI_UX_AUDIT.md) | ეკრანების რეესტრი, დადასტურებული UI პრობლემები და მიუღებელი proof gaps |
| [SECURITY_AND_RELIABILITY.md](SECURITY_AND_RELIABILITY.md) | threat model, ASVS, privacy, recovery, dependency scan შეზღუდვები |
| [EVIDENCE_AND_MATRICES.md](EVIDENCE_AND_MATRICES.md) | baseline, commands/results, manual proof, გარემოს ყველა შეზღუდვა |
| [MARKET_BENCHMARK.md](MARKET_BENCHMARK.md) | სამი ქართული შეთავაზების პირველწყაროები და სამი გასაზომი უპირატესობა |
| [MASTER_BACKLOG.md](MASTER_BACKLOG.md) | ერთი ცენტრალური backlog, scope, acceptance, rollback და dependencies |
| [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md) | პირველი ხუთი ეტაპი და მომდევნო release gates |
| [RESOURCE_MANIFEST.md](RESOURCE_MANIFEST.md) | შექმნილი/გასუფთავებული რესურსები, private evidence |
| [AUDIT_CHECKLIST.md](AUDIT_CHECKLIST.md) | შესრულების კონტროლი და საბოლოო WIP დადასტურება |

## გასვლის კრიტერიუმი

შერჩეულ scope-ში P0 აღარ არსებობს; შესაბამისი A–F journey და cross-Venue negative tests წარმატებულია; acknowledged ცვლილების ჩუმი დაკარგვის გზა დახურულია; upgrade და fresh restore დამტკიცებულია; hardware claim-ს რეალური hardware proof ახლავს; შეზღუდვები server/UI/product contract-ით enforceable-ა. არც build success, არც დამალული ღილაკი და არც ძველი ანგარიში ამ პირობებს არ ანაცვლებს.

**STOP — implementation არ დაწყებულა.** აუდიტის ანგარიშები ცალკე ახალი საქაღალდეშია; პირველი task-ის განხორციელებას ცალკე დავალება სჭირდება.
