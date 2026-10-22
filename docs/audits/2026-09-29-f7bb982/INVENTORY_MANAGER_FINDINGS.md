# Inventory / Manager — შემოწმებადი დასკვნები

კოდის დასკვნები ეხება HEAD+WIP checkout-ს. REPRODUCED ქვემოთ მხოლოდ პირდაპირ მითითებულ synthetic proof-ს ნიშნავს; PostgreSQL/HTTP/რეალური აპი ამ მტკიცებულებაში არ მონაწილეობდა.

საბოლოო release scope, სიმძიმე და რიგი შეჯერებულია [MASTER_BACKLOG.md](MASTER_BACKLOG.md)-ში: `INV-03` არის `MENU-06`-ის alias და canonical Menu + offline consumption scope-ში P0-ა. ქვემოთ domain cards დამატებითი მტკიცებულებაა, ცალკე task list არ არის.

## INV-01 — მარაგების სრული ციკლი ვერ სრულდება: ადგილი, გადატანა, დანაკარგი და დათვლა არ არსებობს

**P1 · missing functionality · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** სრული Inventory შეთავაზება; შეზღუდული receipt/payment/consumption pilot მხოლოდ აშკარად შეთანხმებული ფარგლებით

**პროდუქტი და მომხმარებელი:** Inventory; საწყობის თანამშრომელი და Manager

**დაკვირვება / ფაქტობრივი შედეგი:** StockMovementType მხოლოდ RECEIVING/RECEIVING_REVERSAL/CONSUMPTION/CONSUMPTION_REVERSAL-ს შეიცავს; არც ადგილები და transfer/waste/stocktake/adjustment საბუთებია. NON_FISCAL_CLOSE INTERNAL_EXCLUDED მარაგს არ აკლებს.

**მოსალოდნელი შედეგი:** სავალდებულო სცენარში 4კგ გადაადგილდება ჯამის შეუცვლელად, 0.5კგ დანაკარგი და −0.4კგ სხვაობა ცალკე საბუთით იწერება.

**მოთხოვნის წყარო:** User request §10; project state Deferred Work; schema stock movement comment

**endpoint / UI / მოდელი:** /mobile/inventory/*; Manager მარაგები; StockMovement

**შემოწმება:** rg -n 'enum StockMovementType|model .*Stocktake|model .*Warehouse|model .*Transfer|WASTE' apps/backend/prisma/schema.prisma; inspect Inventory routes. No runtime scenario executed.

**გავლენა:** რეალური დანაკარგი დაურეგისტრირებელია; 17კგ-ის ნაცვლად სისტემა 17.5კგ-ს აჩვენებს; სწორი ფიზიკური ნაშთის მიღწევის გზა არ არსებობს.

**რეკომენდაცია:** ჯერ დააზუსტეთ Inventory pilot-ის შეთავაზება; შექმენით location ledger/transfer, შემდეგ waste/internal და count+approval adjustment; მოძრაობები არ გადაწეროთ.

**გამოსწორების მიღება:** სინთეტიკური flour სცენარი სრულდება 16.6კგ/49.80GEL, supplier debt 30GEL და payment 30GEL; transfer total zero, every difference has immutable document and idempotency key; trading cutoff/late POS behavior tested.

**კოდის მითითებები:** apps/backend/prisma/schema.prisma:404; apps/backend/prisma/schema.prisma:419; apps/operations/lib/core/services/pos/sale_consumption_snapshot.dart:34; apps/backend/src/mobile/mobile.controller.ts:86

## INV-02 — მიმდინარე მოძრავი საშუალო არ უდრის ისტორიულ COGS-სა და რეალიზებულ მოგებას

**P2 · intentional limitation · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** Profitability/COGS მარკეტინგი და სრული ფინანსური შეთავაზება

**პროდუქტი და მომხმარებელი:** Inventory/Financials; მფლობელი

**დაკვირვება / ფაქტობრივი შედეგი:** ღირებულება იყინება Cloud-ის acceptance რიგით; late offline sale შეიძლება მოგვიანებით შეცვლილ average-ს იყენებდეს. recipe cost current estimate-ია; financial difference revenue−actual outflows-ია.

**მოსალოდნელი შედეგი:** ანგარიშის სახელმა და provenance-მ ზუსტად თქვას, არის შეფასებითი/current cost, historical issue valuation, cash movement თუ realized profit.

**მოთხოვნის წყარო:** VYNIC_DECISIONS D015; user request §10/15; FINANCIALS_STEP47.md limitations

**endpoint / UI / მოდელი:** StockItem currentCost, recipe cost, /mobile/financials profit/differenceExact

**შემოწმება:** Inspect trigger lines 24-59 and service calculations; root inventory quantity/finance rules unit suites passed; late PostgreSQL valuation is NOT_TESTED in this run.

**გავლენა:** მენეჯერი შეიძლება შესყიდვის თანხას, მომწოდებლის გადახდას, გასაყიდ ღირებულებას და მოგებას აურიოს.

**რეკომენდაცია:** მარკეტინგში/ეკრანზე განმარტეთ მეთოდი და PROVISIONAL; historical COGS/margin ცალკე მოთხოვნად დაგეგმეთ; არც current cost და არც gross-minus-payments მოგებად არ გაყიდოთ.

**გამოსწორების მიღება:** ერთი სცენარი late sale/new price/reversal-ზე აჩვენებს original frozen issue value-ს და წყაროს; gross revenue, collected money, supplier debt, current stock cost ცალკე იკითხება.

**კოდის მითითებები:** apps/backend/prisma/migrations/20260916120000_inventory_procurement/migration.sql:24; apps/backend/src/inventory/inventory-cost.service.ts:82; apps/backend/src/inventory/inventory-cost.service.ts:120; apps/backend/src/mobile/services/mobile-dashboard.service.ts:630; apps/backend/src/mobile/services/mobile-dashboard.service.ts:639

## INV-03 — მენიუს წაშლა ბლოკავს მანამდე დახურული offline გაყიდვის მარაგის ჩამოწერას

**P1 · production defect · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** Canonical menu + Inventory + offline POS

**პროდუქტი და მომხმარებელი:** POS/Inventory; ოფლაინ მოლარე და Manager

**დაკვირვება / ფაქტობრივი შედეგი:** Canonical remove physically deletes MenuItem/Variant; recipe FK cascades; pending SaleConsumption validator requires that live recipe row. Historical snapshot remains immutable but missing recipe produces 400.

**მოსალოდნელი შედეგი:** გაყიდვის დახურვაზე უკვე შენახული consumption intent მოგვიანებით მენიუს წაშლამ არ უნდა გააუქმოს.

**მოთხოვნის წყარო:** D014 Sale owns consumption intent; user request §8/10 offline durability

**endpoint / UI / მოდელი:** canonical item/variant DELETE; POST /edge/inventory/consumption; MenuConsumptionRecipe

**შემოწმება:** Isolated DB: create menu+recipe, freeze fiscal close snapshot while offline, canonical delete item/variant, submit original snapshot. Expected one consumption; current validator rejects missing recipe. DB run blocked in this audit.

**გავლენა:** გაყიდვა ფინანსურად არსებობს, მაგრამ მარაგი ზედმეტად რჩება და durable retry ვერ სრულდება.

**რეკომენდაცია:** შეინახეთ retired identities/historical recipe authority, ან historical intent-ის უსაფრთხო validator; მიმდინარე უცხო Venue-ს references არ დაუშვათ.

**გამოსწორების მიღება:** delete-before-upload, delete-after-first-ACK, exact retry, changed payload და cross-Venue სცენარები; რაოდენობა/ღირებულება ერთხელ აისახება და history არ იშლება.

**დუბლირების მართვა:** იგივე root cause, რაც canonical-menu reviewer-ის destructive recipe deletion finding; გლობალურ ჯამში ერთხელ დაითვალოს

**კოდის მითითებები:** apps/backend/src/menu-catalog/menu-catalog.service.ts:895; apps/backend/src/menu-catalog/menu-catalog.service.ts:909; apps/backend/prisma/schema.prisma:505; apps/backend/src/inventory/sale-consumption.service.ts:179; apps/backend/src/inventory/sale-consumption.service.ts:194

## INV-04 — გაყიდვიდან ჩამოწერის ისტორია ჩუმად წყდება 100 ჩანაწერზე

**P2 · UX problem · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** Inventory რეალური დატვირთვით და მარაგის გამოკვლევა

**პროდუქტი და მომხმარებელი:** Manager; ნაშთის აუდიტორი

**დაკვირვება / ფაქტობრივი შედეგი:** list take:100-ს იყენებს, არ აბრუნებს nextCursor/total/truncated flag; UI მხოლოდ თარიღის და unmapped ფილტრებს აჩვენებს. ერთ დღეში 100-ზე მეტი close-ისას ძველ ჩანაწერამდე ვერ მიდის.

**მოსალოდნელი შედეგი:** ნაშთის ცვლილების ყველა საბუთი უნდა მოიძებნოს; შეზღუდვა აშკარა იყოს.

**მოთხოვნის წყარო:** User request §10: Which document explains this balance? movement history

**endpoint / UI / მოდელი:** GET /mobile/inventory/consumptions; ConsumptionHistoryScreen

**შემოწმება:** Seed 101+ same-business-date consumption records in isolated DB; request date-filtered list and inspect absence of cursor. Not executed; deterministic take bound inspected.

**გავლენა:** დღის არასრული ისტორია სრულად გამოიყურება და ნაშთის მიზეზის მოძიება რთულდება.

**რეკომენდაცია:** Keyset pagination stable closedAt/id ordering, nextCursor და load-more UI; export იმავე ფილტრით.

**გამოსწორების მიღება:** 101+ same-day rows სრულად გვერდდება დუბლიკატის/გამოტოვების გარეშე; newly arriving rows არ არღვევს გამოკვლევას.

**კოდის მითითებები:** apps/backend/src/inventory/sale-consumption.service.ts:337; apps/backend/src/inventory/sale-consumption.service.ts:350; apps/operations/lib/apps/mobile_app/presentation/screens/consumption_history_screen.dart:37; apps/operations/lib/apps/mobile_app/presentation/screens/consumption_history_screen.dart:70

## MGR-01 — Manager მალავს Venue-ს მაგიდებს ფიქსირებული 9+4 განლაგების გარეთ

**P1 · production defect · REPRODUCED · confidence: high**

**გამოშვების ფარგლები:** ზოგადი რესტორნების POS+Manager pilot

**პროდუქტი და მომხმარებელი:** Manager; მენეჯერი ნებისმიერი სხვა განლაგების რესტორანში

**დაკვირვება / ფაქტობრივი შედეგი:** first floor მხოლოდ 1..9, second მხოლოდ 1..4. სინთეტიკური 4 მაგიდიდან API method-მა 2 დააბრუნა; first/10 და terrace/1 გამოტოვა.

**მოსალოდნელი შედეგი:** Venue-ს რეალური მაგიდები და occupancy/open payable სრულად იკითხებოდეს.

**მოთხოვნის წყარო:** User request §4/11/13: generic Venue system, hardcoded customer-specific data; Table is Venue-owned

**endpoint / UI / მოდელი:** GET /mobile/tables, GET /mobile/dashboard; Table/Order

**შემოწმება:** node /private/tmp/vynic-audit-20260929-f7bb982-180325/manager-synthetic-repro.cjs

**მტკიცებულების ზღვარი:** Unchanged service methods transpiled from isolated copied checkout, synthetic mocked Prisma seam; no HTTP/PostgreSQL/native UI proof

**გავლენა:** მაგიდები და მათი გადასახდელი თანხა dashboard-იდან ქრება; ოპერატორი ხედავს არასწორ დატვირთვას.

**რეკომენდაცია:** განლაგება აიღეთ Venue-ს სინქრონიზებული table/floor კონფიგურაციიდან; virtual carriers გამოყავით explicit type-ით, არა სახელთა allowlist-ით.

**გამოსწორების მიღება:** HTTP+UI fixtures first/10, terrace/1, custom Georgian floor, merged tables; count/payable agrees with authoritative POS snapshot; virtual rows excluded explicitly.

**კოდის მითითებები:** apps/backend/src/mobile/services/mobile-dashboard.service.ts:34; apps/backend/src/mobile/services/mobile-dashboard.service.ts:149; apps/backend/src/mobile/services/mobile-dashboard.service.ts:264; apps/backend/src/mobile/services/mobile-dashboard.service.ts:459

## MGR-02 — მაგიდის გათავისუფლება ცვლის მხოლოდ Cloud-ს და მაინც დასრულებულად ჩანს

**P1 · production defect · REPRODUCED · confidence: high**

**გამოშვების ფარგლები:** Manager მაგიდების write-actions

**პროდუქტი და მომხმარებელი:** Manager და მოლარე

**დაკვირვება / ფაქტობრივი შედეგი:** Cloud Table currentBill/activeOrderId ნულდება; POS command არ იქმნება, Order არ იცვლება. Flutter ნებისმიერი 2xx-ისას true-ს აბრუნებს, backend-ის success:false-საც არ ამოწმებს.

**მოსალოდნელი შედეგი:** ოპერატიული მაგიდის ცვლილება POS/Edge ავტორიტეტმა უნდა დაადასტუროს; missing table შეცდომა უნდა იყოს.

**მოთხოვნის წყარო:** D001/D002, user request §9/11 authority and queued/completed boundary

**endpoint / UI / მოდელი:** POST /mobile/tables/:tableNumber/free; tables emergency action

**შემოწმება:** node /private/tmp/vynic-audit-20260929-f7bb982-180325/manager-synthetic-repro.cjs; additional synthetic missing-table response should be HTTP error, not 2xx success body

**მტკიცებულების ზღვარი:** Actual freeTable method with synthetic Prisma seam: success true, cloud activeOrderId null, dispatch count 0; no real POS execution

**გავლენა:** Manager თავისუფალ მაგიდას ხედავს მაშინ, როცა POS-ს აქტიური შეკვეთა აქვს; დაბრუნებულ sync-ზე შედეგი შეიძლება შეიცვალოს.

**რეკომენდაცია:** განსაზღვრეთ repair intent და POS-authoritative guarded command; Cloud mirror only on ACK/projection; მიუწვდომლობა/უარყოფა არ დაიმალოს.

**გამოსწორების მიღება:** POS offline → pending/unavailable; active order → explicit guard; missing table → failure; command success+next snapshot → consistent table/order; retry once.

**კოდის მითითებები:** apps/backend/src/mobile/services/mobile-dashboard.service.ts:482; apps/backend/src/mobile/services/mobile-dashboard.service.ts:494; apps/backend/src/mobile/services/mobile-dashboard.service.ts:513; apps/operations/lib/core/services/manager_app/mobile_api_service.dart:244; apps/operations/lib/apps/mobile_app/presentation/screens/live_status_screen/views/live_status_tables_part.dart:124; apps/operations/lib/apps/mobile_app/presentation/screens/order_editor_screen.dart:565

## MGR-03 — შეკვეთის/რეზერვაციის UI უგულებელყოფს POS delivery სტატუსს

**P1 · UX problem · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** Manager remote operations

**პროდუქტი და მომხმარებელი:** Manager და ადგილზე მომუშავე პერსონალი

**დაკვირვება / ფაქტობრივი შედეგი:** Backend update/cancel/create returns posDelivery, მაგრამ updateOrder/cancelOrder void API მხოლოდ 2xx-ს ამოწმებს. editor ამბობს შეკვეთა წარმატებით შეინახა. Reservation create caller ასევე ignores delivery. Print order დეტალი უკვე იყენებს pending ტექსტს.

**მოსალოდნელი შედეგი:** QUEUED/CLAIMED ნიშნავს მოთხოვნა მიღებულია; SUCCEEDED ნიშნავს POS-ის მიერ შესრულებულია; FAILED/UNAVAILABLE უნდა ჩანდეს.

**მოთხოვნის წყარო:** User request §11 explicit UI completion requirement; PosCommandDelivery contract

**endpoint / UI / მოდელი:** POST /mobile/order/:id, /cancel, /mobile/reservations; order editor and reservations

**შემოწმება:** Synthetic API response {success:true,posDelivery:{status:'QUEUED'}} to current Flutter method; inspect void return and success toast. Flutter execution blocked by SDK cache permissions in this run.

**გავლენა:** მენეჯერს ჰგონია, რომ ოფლაინ POS-ში ცვლილება შესრულდა; თანამშრომელი ძველი შეკვეთით მუშაობს.

**რეკომენდაცია:** ერთიანი pending operation model, commandId tracking, ACK/failure notification, retry identity; Cloud mirror არ გამოაცხადოს authoritative completed state წინასწარ.

**გამოსწორების მიღება:** QUEUED/CLAIMED/SUCCEEDED/FAILED/UNAVAILABLE და lost ACK widget+HTTP+Edge flow; pending action survives screen reopen and timeout is not false success.

**კოდის მითითებები:** apps/backend/src/mobile/services/mobile-orders.service.ts:358; apps/backend/src/mobile/services/mobile-orders.service.ts:518; apps/backend/src/mobile/services/mobile-reservations.service.ts:164; apps/operations/lib/core/services/manager_app/mobile_api_service.dart:628; apps/operations/lib/core/services/manager_app/mobile_api_service.dart:647; apps/operations/lib/apps/mobile_app/presentation/screens/order_editor_screen.dart:387; apps/operations/lib/apps/mobile_app/presentation/screens/staff_performance_screen.dart:297

## MGR-04 — ქეშიდან/ძველი POS snapshot-იდან მიღებული რიცხვები წყაროს სიძველეს არ აჩვენებს

**P2 · UX problem · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** Manager dashboard/operations ყველა კომბინაციაში

**პროდუქტი და მომხმარებელი:** Manager/Owner

**დაკვირვება / ფაქტობრივი შედეგი:** getDashboard returns cache on failure; refreshMetrics clears apiError on returned cache; MobileCacheService.isStale has no callers. API snapshotAt is now, not POS time, and ManagerDashboardMetrics drops it. Some subrequests failures become empty lists.

**მოსალოდნელი შედეგი:** API connectivity, data source, cache age და POS source age ცალ-ცალკე უნდა იყოს ნაჩვენები; incomplete/error არ უდრის zero/empty.

**მოთხოვნის წყარო:** User request §11 numbers freshness/error/stale states

**endpoint / UI / მოდელი:** Dashboard, Tables, cached manager reads

**შემოწმება:** rg -n 'isStale' apps/operations/lib; warm-cache then API error; Cloud available with POS stopped. Runtime UI cases NOT_TESTED; return paths inspected.

**გავლენა:** თანამედროვე კავშირის ნიშნულის მიუხედავად ჩანს ძველი შემოსავალი/დაკავებულობა ან მცდარი ცარიელი რეზერვაციები.

**რეკომენდაცია:** typed data envelope source/sourceUpdatedAt/fetchedAt/completeness; stale banner, per-block errors; preserve last known data without claiming fresh success.

**გამოსწორების მიღება:** warm cache/API down, API up/POS down, partial ledger, one failing subrequest, resumed app; exact source time and limited operations shown.

**კოდის მითითებები:** apps/operations/lib/core/services/manager_app/mobile_api_service.dart:197; apps/operations/lib/apps/mobile_app/presentation/controllers/dashboard_controller.dart:34; apps/operations/lib/core/services/manager_app/mobile_cache_service.dart:60; apps/backend/src/mobile/services/mobile-dashboard.service.ts:446; apps/operations/lib/core/models/monitoring.dart:61; apps/operations/lib/apps/mobile_app/data/services/dashboard_remote_service.dart:26

## MGR-05 — Manager order edit Cloud-ის ხაზებს არატრანზაქციულად შლის და ხელახლა ქმნის

**P1 · production defect · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** Manager order edits

**პროდუქტი და მომხმარებელი:** Manager და POS ოპერატორი

**დაკვირვება / ფაქტობრივი შედეგი:** updateOrder ჯერ deletes all lines, შემდეგ creates თითო ხაზს და ბოლოს total/audit/dispatch-ს. Transaction ან durable command intent ამ მეთოდში არ არის; მოგვიანებით შეცდომა ნაწილობრივ mirror-ს ტოვებს.

**მოსალოდნელი შედეგი:** არავალიდური/ჩავარდნილი ცვლილება უცვლელ ძველ შეკვეთას ტოვებდეს, ან durable pending intent-ით სრულად აღდგებოდეს.

**მოთხოვნის წყარო:** User request §7/11 durability and current Cloud/POS authority; AGENTS no false success

**endpoint / UI / მოდელი:** POST /mobile/order/:id; Order/OrderItem

**შემოწმება:** Isolated DB: valid existing two-line order, submit payload whose second line fails database type validation; query prior items/total and command outbox. Not executed due blocked PostgreSQL.

**გავლენა:** UI მოთხოვნის შეცდომის შემდეგ Cloud order lines ნაწილობრივია; POS სხვას ინახავს; დაკარგული intent ან audit ცვლილება გამოკვლევას ართულებს.

**რეკომენდაცია:** validate full DTO first; persist command intent/outbox atomically and reconcile only authoritative result; if mirror editing retained, line replacement+total+audit one transaction.

**გამოსწორების მიღება:** fault injection after delete/first line/total/before dispatch; no partial state; retry cannot duplicate or lose command; source POS rejection visible.

**კოდის მითითებები:** apps/backend/src/mobile/services/mobile-orders.service.ts:177; apps/backend/src/mobile/services/mobile-orders.service.ts:192; apps/backend/src/mobile/services/mobile-orders.service.ts:196; apps/backend/src/mobile/services/mobile-orders.service.ts:237; apps/backend/src/mobile/services/mobile-orders.service.ts:358

## MGR-06 — Payroll/ვალდებულების შეცდომით ჩაწერილ გადახდას კორექტირების გზა არ აქვს

**P1 · intentional limitation · CONFIRMED_BY_CODE · confidence: high**

**გამოშვების ფარგლები:** რეალური PAYROLL/FINANCIAL_PLANNING ფინანსური ჩანაწერები; core POS არა

**პროდუქტი და მომხმარებელი:** Manager/ბუღალტერი

**დაკვირვება / ფაქტობრივი შედეგი:** Entries immutableა; payment/reserve create endpoints არსებობს, reversal/refund/correction არა. Payroll day signed adjustment განხორციელებულია, მაგრამ სხვა payment-ის შეცდომას ვერ ასწორებს. ეს შეზღუდვა FINANCIALS_STEP47.md-ში პირდაპირაა აღწერილი.

**მოსალოდნელი შედეგი:** შეცდომა გასწორდეს linked signed reversal/correction-ით, original history-ის წაშლის გარეშე.

**მოთხოვნის წყარო:** User request §15 finance integrity and §10 correction principle; FINANCIALS_STEP47.md:214

**endpoint / UI / მოდელი:** /mobile/finance/payroll/:id/payments, /cycles/:id/payments, /reserves; PayrollPayment/ObligationPayment

**შემოწმება:** Inspect full finance controller + positive money create service; create incorrect payment on disposable fixture then look for supported correction. No DB test executed.

**გავლენა:** ერთჯერადი შეცდომა სამუდამოდ ზრდის recorded outflow/paid-ს; payroll overpaid-ის ჩვენება შეცდომის გამოსწორებას არ ცვლის.

**რეკომენდაცია:** linked immutable reversal with reason/actor/date/idempotency and balance guards; UI original+correction history; reserve reversal must respect consumed allocation.

**გამოსწორების მიღება:** wrong payment corrected without delete; duplicate reversal once; historical period source totals reconcile; forbidden cross-Venue; reserve already consumed cannot silently be removed.

**კოდის მითითებები:** apps/backend/src/finance/finance.controller.ts:71; apps/backend/src/finance/finance.controller.ts:125; apps/backend/src/finance/payroll.service.ts:296; apps/backend/src/finance/obligations.service.ts:301; docs/FINANCIALS_STEP47.md:214
