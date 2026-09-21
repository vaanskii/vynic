# Vynic — პროდუქტისა და ტექნიკური მდგომარეობის აუდიტი

შეფასების თარიღი: 2026-09-14. საფუძველი: სამუშაო ხე `ce1cbea`-ზე, არსებული შეცვლილი და ახალი ფაილების ჩათვლით. მოცვა: `apps/backend`, `apps/operations` (POS + Manager), `apps/platform-web` (საჯარო საიტი + Platform Admin + Customer Portal), მათთან დაკავშირებული contracts და ტესტები. მოცვიდან გამორიცხულია `apps/venue-web` და მისთვის განკუთვნილი backend-ის custom ვებრეზერვაციებისა და ონლაინ გადახდების ფუნქციები.

ეს არის კოდზე, სქემაზე, კონტრაქტებზე, შერჩეულ გაშვებულ შემოწმებებსა და კონკურენტების ოფიციალურ წყაროებზე დაფუძნებული შეფასება. ყველა ფაილის ხაზობრივი უსაფრთხოების აუდიტი, production ინფრასტრუქტურის შემოწმება, დატვირთვის ტესტი და ფიზიკური მოწყობილობების სერტიფიცირება არ ჩატარებულა. პროგრამის კოდი არ შეცვლილა; დაემატა მხოლოდ ეს ანგარიში.

მოცვა დაზუსტებულია 2026-09-17: არსებული `venue-web` მხოლოდ მომხმარებლის ერთი რესტორნის CUSTOM საიტია. მისი ერთრესტორნიანი კონფიგურაცია მიმდინარე SaaS-ის ხარვეზად არ ფასდება. რესტორნებისთვის SaaS ვებსაიტი ცალკე შესაქმნელი პროდუქტია. ტესტების შედეგები 2026-09-14-ის გაშვებას აღწერს; ახალი ტექნიკური აუდიტი ამ შესწორებისას არ ჩატარებულა.

## მთავარი შეფასება

Vynic-ს უკვე აქვს სერიოზული რესტორნის ოპერაციული ბირთვი: ოფლაინ POS, აღდგენადი დახურვა, გაყიდვების ცალკე ledger, Venue-ით იზოლაცია, Edge ბრძანებები, მარაგებისა და შესყიდვების ისტორია, Manager-ის ფინანსური ხედვები და SaaS-ის ადმინისტრაციული საფუძველი.

ამავე დროს, ეს ჯერ არ არის დასრულებული მრავალრესტორნიანი კომერციული პროდუქტი, რომლის მფლობელიც თვითონ მართავს ყველა ყოველდღიურ პროცესს. ყველაზე დიდი ჩამორჩენებია: ერთიანი Restaurant Backoffice, მართვადი უფლებები, ერთგვაროვანი ფინანსური მნიშვნელობები, ნაღდი ფულის კონტროლი, მარაგების ფიზიკურ რეალობასთან შეჯერება და უსაფრთხო კომერციული გაშვება.

| ნაწილი | შეფასება | მიზეზი |
|---|---|---|
| POS-ის ოპერაციული საფუძველი | ძლიერი | ლოკალური მუშაობა, დახურვის ჟურნალი, აღდგენა, გაყიდვისა და ავანსის გამიჯვნა |
| Backend-ის დომენური მოდელი | ძლიერი საფუძველი, დარჩენილი მნიშვნელოვანი რისკებით | tenancy, ledger, Edge კარგია; მრავალი POS-ის სცენარში დამატებითი დაცვაა საჭირო |
| Manager | ფუნქციურად მდიდარი, მაგრამ როლებით შეზღუდული | მარაგები, შესყიდვები, ფინანსები არსებობს; წვდომა მხოლოდ Manager კლასის Staff-ს აქვს |
| Platform Admin | კარგი საკონტროლო პანელი | გეგმები, მოწყობილობები, წვდომა, დომენები და აუდიტი; არ წარმოადგენს რესტორნის სრულ backoffice-ს |
| Customer Portal | პილოტური onboarding | ერთი რესტორანი, Manager-ის შექმნა, POS-ის მიერთება, პროფილი და პრინტერები |
| ფართო SaaS გაყიდვის მზადყოფნა | ამ აუდიტით არ დასტურდება | ოპერაციული შეზღუდვების აღსრულება, recovery, release და production მტკიცებულება დარჩენილია |

პრიორიტეტები: **P0** — დასახელებული სცენარის გაშვების ბლოკერი; **P1** — თანხის/მონაცემის/წვდომის ან მთავარი სამუშაო პროცესის მნიშვნელოვანი ხარვეზი; **P2** — მასშტაბირების, თანმიმდევრულობისა და მხარდაჭერის ვალი. ახალი ფუნქციის არქონა თავისთავად ბაგი არ არის.

## 1. დადასტურებული ხარვეზები და მაღალი რისკები

თავდაპირველი F01–F05 ეხებოდა გამორიცხულ CUSTOM ვებსაიტსა და მის ონლაინ გადახდებს. ისინი ამ შეფასებისა და პრიორიტეტების სიიდან ამოღებულია; დარჩენილი ნომრები შენარჩუნებულია წინა მითითებების გასარჩევად.

### F06 — რამდენიმე დამოუკიდებელი POS-ისთვის მონაცემის ავტორიტეტი ბოლომდე განსაზღვრული არ არის — P0 ამ რეჟიმის გაყიდვამდე

Enrollment ახალი installation-ისთვის ახალ Device-ს ქმნის. Venue-ზე მიუმართავი Edge ბრძანების აღება ნებისმიერ შესაბამის Device-ს შეუძლია. Queue-ის claim race დაცულია, მაგრამ ეს არ ნიშნავს, რომ მოწყობილობებს ერთი და იგივე Hive მონაცემი აქვთ.

Order snapshot reconciliation Venue/businessDate-ის ფარგლებში შემოსულ snapshot-ში არმყოფ შეკვეთებს შლის. შესაბამისად, ერთ Venue-ში ორი დამოუკიდებელი POS ბაზის გამოყენებისას ერთი ტერმინალის snapshot-მა შეიძლება მეორის Cloud mirror გააქროს. ეს კოდის გზებიდან მიღებული მაღალი სანდოობის რისკია; ორტერმინალიანი live ტესტი არ ჩატარებულა.

**უახლოესი უსაფრთხო ნაბიჯი:** ერთ Venue-ზე ერთი ოპერაციული primary Edge-ის მკაფიო აღსრულება, ჩანაცვლების პროცედურით. მრავალტერმინალიანი რეჟიმი ცალკე ფაზაა: საერთო ლოკალური ავტორიტეტი ან გამოკვეთილი partition/replication, command targeting, order identity და conflict წესები.

მტკიცებულება: [Device-ის შექმნა](/Users/vaanskii/Developer/vynic/apps/backend/src/edge/device-enrollment.service.ts:505), [ვის შეუძლია ბრძანების claim](/Users/vaanskii/Developer/vynic/apps/backend/src/edge/edge-command.service.ts:185), [snapshot reconciliation](/Users/vaanskii/Developer/vynic/apps/backend/src/pos/sync/snapshot/order-sync.service.ts:259).

### F07 — Platform authentication-ის დაცვა Customer/Manager დონეს არ ემთხვევა — P1

Customer login/signup-ზე rate limiter არსებობს, Manager-საც აქვს login throttle. Platform login-ში მცდელობების შეზღუდვა არ ჩანს; AppModule/PlatformModule-შიც საერთო throttle არ არის მიერთებული. Production reverse proxy-ის შესაძლო დაცვა ამ აუდიტში არ შემოწმებულა.

Platform/Customer authentication არის password + JWT. Customer signup ელფოსტას დაუდასტურებლად ტოვებს; თვითმომსახურების password reset, MFA და სესიების სრულფასოვანი მართვის ნაკადები განხილულ controller-ებში არ არის.

**გასწორება:** პირველ რიგში Platform login-ის rate limiting; შემდეგ Platform MFA, მფლობელის email verification/recovery, სესიების გაუქმება და უსაფრთხო credentials lifecycle. Argon2id და ცალკე principal/audience კარგია და შესანარჩუნებელია.

მტკიცებულება: [Platform login](/Users/vaanskii/Developer/vynic/apps/backend/src/platform/platform-auth.controller.ts:17), [Customer throttle/auth](/Users/vaanskii/Developer/vynic/apps/backend/src/customer/customer-auth.ts:47), [module wiring](/Users/vaanskii/Developer/vynic/apps/backend/src/platform/platform.module.ts:30).

### F08 — ფინანსურ ანგარიშებს განსხვავებული მნიშვნელობები აქვთ — P1 პროდუქტის სიზუსტისთვის

Manager-ის მთავარი ფინანსური ბარათი სწორად ამბობს „გაყიდვები − გასავლები“. Backend-ში იგივე სხვაობა ჯერ კიდევ `profit` ველშიც გადის. POS-ის monthly report სხვა მოდელს იყენებს: გაყიდვები × ხელით შერჩეული food profit ratio; staffDailyCost × დღეები; ხელით მითითებული ქირა. შემდეგ ეს გამოთვლა „წმინდა მოგებად“ ჩანს.

ეს ორი რიცხვი ერთი ფინანსური მაჩვენებელი არ არის. POS-ის გაანგარიშება არ კითხულობს Manager-ის რეალურ payroll/obligation/supplier payment ისტორიას. მიმდინარე მარაგის თვითღირებულებაც ისტორიული გაყიდვის დადასტურებულ COGS-ს ავტომატურად არ უდრის.

**გასწორება:** აშკარა სახელები და წყაროები: გაყიდვები; დღეს მიღებული თანხა; დღეს გადახდილი თანხა; გაყიდვები − გასავლები; მარაგის მიმდინარე ღირებულება; შეფასებითი მოგება; მომავალში — ისტორიულ ხარჯზე დათვლილი gross profit. Backend DTO-ებიც ამ ენას უნდა მიჰყვეს. POS monthly model უნდა დარჩეს აშკარად შეფასებითად მონიშნული ან Cloud-ის შესაბამის მოდელზე გადავიდეს.

**მიღების პირობა:** იგივე პერიოდის POS/Manager/Backoffice განსხვავება ახსნადია არჩეული მეტრიკით, completeness-ითა და წყაროთი; მომხმარებელი შეფასებით მოგებას რეალურ მოგებად ვერ აღიქვამს.

მტკიცებულება: [POS-ის ფორმულა](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/pos/monthly_report_service.dart:248), [POS-ის სათაური](/Users/vaanskii/Developer/vynic/apps/operations/lib/apps/windows_pos/widgets/admin/admin_financial_reports_panel.dart:491), [Backend profit ველი](/Users/vaanskii/Developer/vynic/apps/backend/src/mobile/services/mobile-dashboard.service.ts:639), [Manager-ის სწორი სათაური](/Users/vaanskii/Developer/vynic/apps/operations/lib/apps/mobile_app/presentation/screens/financials_screen.dart:460).

## 2. რა არ არის გაზიარებული აპებს შორის

**ერთი და იგივე ფუნქცია ყველგან საჭირო არ არის.** გასაზიარებელია ბიზნესწესი, მონაცემის მნიშვნელობა, იდენტობა და უფლებები. Platform Admin-ს რესტორნის ყოველდღიური სალარო არ უნდა დაემატოს მხოლოდ ეკრანების გასათანაბრებლად.

| ფუნქცია | POS / POS Admin | Manager | მფლობელის ვებპორტალი | Platform Admin |
|---|---|---|---|---|
| რესტორნის სახელი/მისამართი/ტელეფონი/legal ID | რედაქტირება, ოფლაინ cache და pending sync | რედაქტირება | რედაქტირება | Venue-ის ადმინისტრაციული მართვა; owner editor-ის სრული ეკვივალენტი არაა |
| ლოგო და ქვითრის განლაგება | ადგილობრივი კონფიგურაცია | ზოგადი ქვითრის preview; საერთო დიზაინის რედაქტორი არა | არა | არა |
| მენიუ/კატეგორია/ფასი/ვარიანტი | მთავარი writer | წაკითხვა და შეკვეთაში გამოყენება | POS-ში შექმნის checklist | პროდუქტის feature controls; მენიუს editor არა |
| მაგიდები/დარბაზის layout | რედაქტირება და ცოცხალი ოპერაცია | ცოცხალი ხედვა და ნებადართული მოქმედებები | checklist | არა |
| შეკვეთები/მიღება/დახურვა/ბეჭდვა | მთავარი ოპერაცია, ოფლაინ | დისტანციური ბრძანებები და მონიტორინგი; POS-ის სრული checkout არა | არა | არა |
| დღის დახურვა | ლოკალური ავტორიტეტი | შედეგების ნახვა | არა | არა |
| პერსონალი | როლზე დამოკიდებული CRUD/PIN | Manager-ის CRUD | Manager-ის შექმნა/reset/disable | Manager access-ის მხარდაჭერა და ცალკე Platform users |
| custom roles/permissions | არა | არა | არა | არა |
| მარაგის პროდუქტები/მომწოდებლები/მიღება/რეცეპტები | წაკითხვა/cache; close-time consumption snapshot | სრული ძირითადი მართვა feature-ის ფარგლებში | არა | მხოლოდ შესაბამისი feature-ის მართვა |
| supplier payment/debt | შეზღუდული inspection | ისტორია/გადახდა/reversal | არა | არა |
| payroll/ვალდებულებები/რეზერვები | Cloud მოდულის ეკვივალენტი არა | არსებობს | არა | feature-ის მართვა |
| გაყიდვები/ანგარიშები | ლოკალური ისტორია, exports, შეფასებითი monthly model | Cloud ledger და სხვა ფინანსური ხედვები | არა | პლატფორმის overview; რესტორნის სრული ანალიტიკა არა |
| მომსახურება/ოპერაციული switches | რედაქტირდება ადგილობრივად | ზოგის წაკითხვა | საერთო Venue Policy editor არა | საერთო Venue Policy არა |
| პრინტერების გამართვა | cache/LAN; ტექნიკური editor developer scope-ით | საერთო printer admin არა | kitchen/receipt config თითო Device-ზე | onboarding-ის printer config |
| გეგმები/feature overrides/subscription | cache/შესაბამისი შესაძლებლობის გამოყენება | effective features | trial/status-ის შეზღუდული ჩვენება | სრული არსებული კომერციული მართვა |
| რამდენიმე ფილიალის კონსოლიდირებული ანგარიშები | არა | არა | პილოტში ერთი Venue | Organizations/Venues directory არსებობს; ბიზნესანალიტიკა არა |

მტკიცებულება: [POS sections](/Users/vaanskii/Developer/vynic/apps/operations/lib/apps/windows_pos/screens/admin_screen.dart:50), [Manager shell](/Users/vaanskii/Developer/vynic/apps/operations/lib/apps/mobile_app/manager_app_shell.dart:153), [Manager routes](/Users/vaanskii/Developer/vynic/apps/backend/src/mobile/mobile.controller.ts:58), [Customer routes](/Users/vaanskii/Developer/vynic/apps/backend/src/customer/customer.controller.ts:42), [Web route map](/Users/vaanskii/Developer/vynic/apps/platform-web/src/App.tsx:48).

### ყველაზე დიდი პროდუქტის დანაკლისი — Restaurant Backoffice

Owner-ს ოპერაციული მართვისთვის Staff Manager ანგარიში და Manager App სჭირდება. Inventory და Finance controller-ები `MANAGER_APP`-საც მოითხოვს. მარტო `INVENTORY` feature-ის მიცემა სხვა owner-facing სამუშაო სივრცეს არ ქმნის.

მფლობელის პორტალი backend-ში ერთ Venue-ს უშვებს, ხოლო frontend `venues[0]`-ს ირჩევს. ეს თანმიმდევრული პილოტური შეზღუდვაა, თუმცა ქსელის მართვის გამოცდილება ჯერ არ არის.

Backoffice-ის რეკომენდებული მოცვა: ფილიალის არჩევა; მენიუ/ფასები; თანამშრომლები/უფლებები; შესყიდვები/მარაგი; ფინანსები/exports; Venue Policy; მოწყობილობები/პრინტერები; პრობლემების სია. ყოველდღიური checkout და ქსელის გარეშე მუშაობა POS-ზე უნდა დარჩეს. PlatformUser ამ ფუნქციებისთვის არ უნდა გამოიყენოთ.

მტკიცებულება: [Manager feature dependency](/Users/vaanskii/Developer/vynic/apps/backend/src/finance/finance.controller.ts:40), [ერთი Venue-ის backend წესი](/Users/vaanskii/Developer/vynic/apps/backend/src/customer/customer.service.ts:165), [პირველი Venue-ის UI](/Users/vaanskii/Developer/vynic/apps/platform-web/src/customer/CustomerPortal.tsx:167).

## 3. როლები — რა გაქვს და რა გაკლია

| მიმდინარე როლი/იდენტობა | რეალური დანიშნულება | შეზღუდვა |
|---|---|---|
| `PlatformUser/SUPER_ADMIN` | Vynic-ის ოპერატორი | cross-tenant უფლებები; რესტორნის მფლობელისთვის არ არის |
| `PlatformUser/SUPPORT_READONLY` | პლატფორმის მხოლოდ წაკითხვა | server guard კრძალავს mutation მეთოდებს |
| `CustomerAccount` | Organization-ის მფლობელი | onboarding-ის ნაკადები; მიმდინარე ოპერაციული Backoffice არ აქვს |
| `Staff/MANAGER` | რესტორნის ფართო მართვა, Manager App | თითქმის ყველა Manager დომენზე ერთი მსხვილი უფლებათა ჯგუფი |
| `Staff/SUPERVISOR` | POS-ზე შეზღუდული მართვა, waiter staff, reservations, close-day | Manager App-ში ვერ შედის |
| `Staff/WAITER` | ჩვეულებრივი მომსახურება და გადახდის დაფიქსირებით დახურვა | discounts/admin/ფინანსებზე შეზღუდვები |
| legacy `ADMIN` | ძველი მონაცემების თავსებადობა | ნორმალიზდება `MANAGER`-ში; ცალკე ახალი ბიზნესროლი არ არის |
| `Device` | Edge/POS ტექნიკური იდენტობა | არ არის თანამშრომლის როლი |

მტკიცებულება: [Backend StaffRole](/Users/vaanskii/Developer/vynic/apps/backend/src/staff/staff-role.ts:1), [Flutter StaffRole](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/models/staff_role.dart:1), [POS permission facade](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/models/pos_permission.dart:1), [Supervisor sections](/Users/vaanskii/Developer/vynic/apps/operations/lib/apps/windows_pos/screens/admin_screen.dart:190), [Support guard](/Users/vaanskii/Developer/vynic/apps/backend/src/platform/platform-auth.guard.ts:46).

რეკომენდებული შემდეგი მოდელია **Vynic-ის ფიქსირებული permission vocabulary + რესტორნის მიერ შექმნილი role templates**. OWNER/MANAGER/CASHIER/WAITER-ის ახალი დიდი enum მარტო პრობლემას არ აგვარებს.

საწყისი უფლებების ჯგუფები: `orders.create/edit/void`, `payments.record/refund`, `discounts.apply/approve`, `day.close`, `cash.drawer.manage`, `menu.edit/publish`, `inventory.receive/count/waste`, `suppliers.pay`, `payroll.view/pay`, `reports.sales/profitability/export`, `staff.manage`, `permissions.manage`, `device.configure`.

მფლობელმა უნდა შეძლოს საწყობის თანამშრომელს საქონლის მიღება მიანდოს ხელფასებისა და მოგების ჩვენების გარეშე; ბუღალტერს მისცეს ფინანსები მენიუს/შეკვეთების შეცვლის გარეშე; ჰოსტესს — რეზერვაციები; სუპერვაიზერს — მისთვის საჭირო Manager ხედები. ეს უსაფრთხო დელეგირება დღეს ზედმეტად მსხვილ Manager როლზეა დამოკიდებული.

უფლება უნდა შემოწმდეს backend-ში და POS action boundary-ზე, UI მხოლოდ იმეორებდეს შედეგს. ოფლაინ POS-ს სჭირდება ვერსირებული permissions snapshot. `Feature` განსაზღვრავს შეძენილ მოდულს, `Permission` — თანამშრომლის მოქმედებას, `VenuePolicy` — რესტორნის ოპერაციულ წესს. მათი შერევა უნდა აირიდოთ.

## 4. Hardcoded ნაწილები — რა შეიცვალოს და რა დარჩეს

| ნაწილი | არსებული ფაქტი | მოქმედება / პრიორიტეტი |
|---|---|---|
| Staff როლები და უფლებათა boolean-ები | MANAGER/SUPERVISOR/WAITER, ორ ენაში გამეორებული წესები | permission catalogue + role config + generated contract — P1 |
| პილოტის ერთი Venue | backend existing Venue-ს აბრუნებს, UI `venues[0]` | product capability/მკაფიო ლიმიტი; შემდეგ Venue switcher — P1 ქსელისთვის |
| ვალუტა | Venue იღებს სამასოიან currency-ს; ბევრი POS/Manager თანხა მაინც ₾/GEL-ით ჩანს | თუ მხოლოდ საქართველოა სამიზნე, backend-შიც GEL შეზღუდვა; სხვა შემთხვევაში სრული currency propagation/precision — P1 სანამ სხვა ვალუტა დაიშვება |
| timezone | Venue-ზე არის, მაგრამ ძველი date helper-ები server-local `new Date/setHours`-ს იყენებს; POS საათი OS-დან მოდის | businessDate და რეალური timestamp-ის ცალკე კონტრაქტი; Venue timezone-ის თანმიმდევრული გამოყენება — P2, სხვა ზონებზე P1 |
| Bank POS-ის არჩევანი | UI-ში TBC/BOG და default TBC | Venue-ის tender configuration; ძველი keys ისტორიისთვის დარჩეს — P2 |
| პრინტერების კონფიგურაცია | runtime ფორმაში ორი როლი: kitchen/receipt | შემდეგში printer stations/routing per category; ჯერ არსებული ორი პრინტერის საიმედო setup — P2 |
| trial/subscription | სტატუსი ხელით იმართება; თარიღები access-ს ავტომატურად არ წყვეტს | ოპერატორის overdue queue ახლა, ავტომატური billing ცალკე ფაზად — P2 |
| login rollout `vankisi`, legacy callbacks | თავსებადობის კოდი და bootstrap სპეციფიკა | ამოღება მხოლოდ fleet rollout-ის მტკიცებულების შემდეგ |
| `Asia/Tbilisi` default, demo IP, 9100 port, FeatureKeys | default/example/protocol vocabulary | თავისთავად ბაგი არ არის; მხოლოდ business-specific წესები უნდა გახდეს მონაცემი |

მტკიცებულება: [currency input](/Users/vaanskii/Developer/vynic/apps/backend/src/customer/customer.service.ts:154), [GEL output](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/pos/monthly_report_service.dart:93), [date helpers](/Users/vaanskii/Developer/vynic/apps/backend/src/mobile/util/mobile-date.util.ts:9), [Venue-aware finance date](/Users/vaanskii/Developer/vynic/apps/backend/src/finance/finance-common.ts:11), [bank choices](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/pos/table_payment_service.dart:513), [printer roles](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/edge/runtime_config_sync.dart:96), [subscription policy](/Users/vaanskii/Developer/vynic/apps/backend/src/entitlements/subscription-policy.ts:1).

Vankisi-ის სახელის ყველა occurrence მოსაშორებელი არ არის: ნაწილი comment, test fixture, development host ან legacy migration-ია. ახალი POS-ის ბრენდინგი უკვე Venue-ის identity-ზეა გადაყვანილი და fresh-install regression ტესტები გადის. Generated contract ფაილები ხელით არ უნდა გასწორდეს.

## 5. რა გაკლია ყოველდღიური რესტორნის მართვისთვის

### 5.1 ნაღდი ფული და refund — მაღალი ბიზნესპრიორიტეტი

გაყიდვების cash/card breakdown უკვე არსებობს. ცალკე სალაროს session მოდელი — საწყისი თანხა, შემოტანა/გატანა, დათვლილი ნაშთი, მოსალოდნელი ნაშთი, სხვაობა და პასუხისმგებელი თანამშრომელი — განხილულ სქემასა და ოპერაციულ მოდელებში არ ჩანს. დახურული გაყიდვის restore/cancel ფინანსური დაბრუნების სრულფასოვანი workflow არ არის; `refundPayment` permission-ის კომენტარიც ამბობს, რომ მოქმედება ჯერ არ არსებობს.

საჭიროა: cash drawer session; cash movement reasons; cash count; variance approval; append-only full/partial refund; original sale/payment reference; მარაგის დაბრუნების აშკარა არჩევანი; აუდიტი. ეს ფუნქციები POS-ზე ოფლაინ უნდა მუშაობდეს, Cloud-ზე კი შედეგები უნდა ირეკლებოდეს.

მტკიცებულება: [refund scaffold](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/models/pos_permission.dart:45), [ოპერაციული payment model](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/pos/table_payment_service.dart:10), [მიმდინარე სქემა](/Users/vaanskii/Developer/vynic/apps/backend/prisma/schema.prisma:604).

### 5.2 მარაგი — კარგი ledger, არასრული კონტროლის ციკლი

არსებობს stock items, suppliers, purchase units, receiving/post/cancel, supplier payments, moving valuation, recipes, გაყიდვიდან consumption და ზუსტი reversal. ეს საფუძველი შესანარჩუნებელია.

აკლია ფიზიკური ინვენტარიზაცია, waste, თანამშრომლის მოხმარება/complimentary consumption-ის ცალკე მიზეზი, discrepancy approval, expected yield/pour loss, საწყობებს/ფილიალებს შორის transfer, purchase order და receiving-ის შედარება. `StockMovementType` ამჟამად მხოლოდ receiving/consumption და მათ reversals-ს შეიცავს.

განსაკუთრებული gap: არაფისკალური/internal close inventory snapshot-ში `INTERNAL_EXCLUDED`-ია. ეს მიმდინარე დიზაინში შეგნებული შეზღუდვაა, რადგან bookkeeping close და რეალურად მოხმარებული პროდუქტი ერთმანეთისგან არ გამოირჩევა. თუ გუნდი ფიზიკურ უფასო მოხმარებას ამ გზით აღრიცხავს, მარაგი რეალობას ჩამორჩება. გამოსავალია მოხმარების მიზეზის ცალკე მოდელი და მოძრაობა; ყველა non-fiscal ისტორიაზე ავტომატური stock write არ შეიძლება.

მტკიცებულება: [movement types](/Users/vaanskii/Developer/vynic/apps/backend/prisma/schema.prisma:386), [internal exclusion](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/pos/sale_consumption_snapshot.dart:34), [Cloud acceptance](/Users/vaanskii/Developer/vynic/apps/backend/src/inventory/sale-consumption.service.ts:139).

პირველი დამატებები უნდა იყოს stocktake + waste + internal consumption. OCR/ავტომატური supplier ordering შემდეგ მოდის. Stock balance პირდაპირ რედაქტირებად რიცხვად არ უნდა გადაიქცეს.

### 5.3 მენიუ და სამზარეულო

მენიუს სტაბილური identity, კატეგორიები, ქვეკატეგორიები, ვარიანტები და kitchen routing-ის საწყისი flag გაქვს. აკლია Manager/Backoffice menu authoring, draft/publish revision, დაგეგმილი ფასი, channel availability/stop-list, სტრუქტურირებული modifier groups და მინიმუმ/მაქსიმუმ არჩევანი.

ზომის ვარიანტი სრულ modifier სისტემას არ უდრის: „აუცილებლად აირჩიე გარნირი“, „ორი დამატება მაქსიმუმ“, „დამატებითი ყველი +2 GEL“ ცალკე მოდელია. ასევე განხილულ მოდელებში არ ჩანს სრული allergens/dietary catalogue ან KDS workflow.

KDS-ის საწყისი საზღვრები: მიღება → მზადება → მზადაა → გატანა; station routing; ticket timing; recall; აუდიტი. დღეს `preparing`/`served` ძველი parseable statuses-ია, არა დასრულებული სამზარეულოს სამუშაო პროცესი. მხოლოდ ძველი enum-ის ღილაკებად გამოტანა საკმარისი არ იქნება.

მტკიცებულება: [მენიუს სქემა](/Users/vaanskii/Developer/vynic/apps/backend/prisma/schema.prisma:116), [Manager-ის menu reader](/Users/vaanskii/Developer/vynic/apps/backend/src/mobile/services/mobile-menu.service.ts:37), [მოქმედი სტატუსების მდგომარეობა](/Users/vaanskii/Developer/vynic/docs/agent-state/VYNIC_PROJECT_STATE.md:671).

### 5.4 პერსონალი, სტუმრები, ინტეგრაციები

Payroll არის დარიცხვებისა და გადახდების კარგი საფუძველი, მაგრამ ცვლის დაგეგმვა, საათების clock-in/out, შესვენებები, tip distribution და შრომის საათებზე დაფუძნებული ანალიზი დასრულებულად არ ჩანს. ხელით მონიშნული payable day attendance სისტემის ეკვივალენტი არ არის.

შემდეგი დონის დანაკლისებია რესტორნის სტუმრის ერთიანი ისტორია, visits/preferences, loyalty/gift cards, waitlist/no-show მართვა და ინტეგრაციები delivery/accounting პროდუქტებთან. ესენი გაყიდვის სეგმენტზე უნდა შეირჩეს. ბანქეტი/დარბაზი/ქართული ოფლაინ POS თუ არის ძირითადი შეთავაზება, loyalty/OCR/Kiosk-მდე ფული, უფლებები და მარაგის შეჯერება უფრო მნიშვნელოვანია.

`Bank POS`-ის არჩევანი და `isFiscal`/Z-report სახელები ამ კოდით ადასტურებს პროგრამულ აღრიცხვას. განხილულ payment path-ში ვერ დადასტურდა საბანკო ტერმინალიდან ავტომატური capture confirmation ან გარე ფისკალურ მოწყობილობასთან ინტეგრაცია. მათი კომერციული დაპირება მოითხოვს ცალკე adapter-სა და რეალურ მოწყობილობაზე მტკიცებულებას; ეს ანგარიში სამართლებრივ შესაბამისობას არ ადგენს.

## 6. შედარება წამყვან მსგავს პროდუქტებთან

შედარებისთვის შერჩეულია Toast, Square for Restaurants, Lightspeed Restaurant და Oracle Simphony — სხვადასხვა ზომის რესტორნებზე ორიენტირებული ცნობილი პროდუქტები. ეს არ არის ბაზრის წილის რეიტინგი. ქვემოთ მითითებული შესაძლებლობები მოდულის, ქვეყნისა და პაკეტის მიხედვით შეიძლება განსხვავდებოდეს; მათი საქართველოში გაყიდვის ან ადგილობრივი payment მხარდაჭერის შეფასება არ ჩატარებულა.

| შესადარებელი პროდუქტი | ოფიციალურად დოკუმენტირებული ძლიერი მხარე | Vynic-ის განსხვავება / გასაკეთებელი |
|---|---|---|
| Toast — permissions | job-based და ინდივიდუალური permissions POS/Web-ზე, როლების რედაქტირება web-ში | Vynic-ს ფიქსირებული სამი Staff როლი აქვს; დაამატე Venue-owned roles და წვრილი permissions |
| Toast / xtraCHEF | invoice automation, recipe costing, physical inventory counts, actual-vs-theoretical და COGS reporting | receiving/recipes/valuation უკვე გაქვს; აკლია stocktake/waste/variance და დასრულებული ისტორიული მოგების ანალიზი |
| Square | cash drawer sessions: starting cash, sales/refunds, paid-in/out, expected vs counted cash | შექმენი სალაროს ცალკე ledger/session; Close Day მარტო საკმარისი არ არის |
| Square for Restaurants | შეკვეთების/სამზარეულოს ორგანიზება და coursing, სხვა restaurant modules | Vynic-ის kitchen printing საწყისი საფუძველია; შემდეგი ნაბიჯია KDS/course workflow შესაბამისი სეგმენტისთვის |
| Lightspeed Restaurant | მენიუ, modifiers/combos, თანამშრომლის მორგებული წვდომა, kitchen display | menu authoring და permissions ბიზნესმომხმარებლის Backoffice-ში გადაიტანე კონტროლირებული publish-ით |
| Lightspeed K-Series | ფილიალების კონსოლიდირებული ანგარიშები | Organization/Venue სქემა უკვე გაქვს, მაგრამ Owner-ის operational multi-location UI/reporting აკლია |
| Oracle Simphony | ცენტრალიზებული menu management, KDS, inventory და labor მართვა | არქიტექტურული ორიენტირი ქსელისთვის; ჯერ ერთი რესტორნის primary Edge და უსაფრთხო მართვა დაასრულე |

წყაროები შესაბამისი პრეტენზიებისთვის: [Toast permissions](https://support.toasttab.com/en/article/Assigning-User-Access-Permissions), [Toast inventory](https://pos.toasttab.com/products/inventory-management), [Toast xtraCHEF](https://pos.toasttab.com/products/xtrachef), [Square cash sessions](https://squareup.com/help/us/en/article/8344-start-and-end-a-cash-drawer-session), [Square restaurant product](https://squareup.com/us/en/point-of-sale/restaurants), [Lightspeed restaurant features](https://www.lightspeedhq.com/pos/restaurant/features/), [Lightspeed consolidated reporting](https://k-series-support.lightspeedhq.com/hc/en-us/articles/4403164165915-About-Location-Reports), [Oracle table service](https://www.oracle.com/food-beverage/restaurant-pos-systems/table-service-pos/).

კონკურენტებისგან მთავარი გაკვეთილი ერთ ეკრანში ყველაფრის ჩატევა არ არის: მფლობელს აქვს თავისი backoffice, უფლებები სამუშაოს მიხედვით ნაწილდება, მენიუსა და ფინანსურ მონაცემებს შეთანხმებული მნიშვნელობა აქვთ და ოპერაციული ჩანაწერები რეალურ ფულსა და ფიზიკურ მარაგს ებმის.

## 7. რაც უკვე კარგია და არ უნდა დაიშალოს

1. **Offline-first საზღვარი.** POS-ის ძირითადი მუშაობა Cloud-ს არ ელოდება. ახალი backoffice/ბილინგი ამ თვისებას არ უნდა ცვლიდეს.
2. **დახურვის durability.** close intent, sale write და შემდგომი ეფექტები journal-ითა და recovery-ითაა დაცული. ეს უფრო ღირებულია, ვიდრე ზედაპირული ახალი dashboard.
3. **გაყიდვა და შემოსული თანხა ცალკე ფაქტებია.** ავანსის გამოყენება ახალი შემოსავლის გამოგონებად არ უნდა გადაიქცეს; არსებული ledger ამ გამიჯვნის კარგ საფუძველს ქმნის.
4. **Tenant authority სერვერზეა.** Staff/Device/Host-ის გზები გამიჯნულია; Platform principal-ს რესტორნის Staff არ ენაცვლება.
5. **Edge pull და შესრულების ჟურნალი.** Cloud → LAN დამოკიდებულების მოხსნა სწორია. queue/claim/ack და print ambiguity-ის მართვა უნდა შენარჩუნდეს.
6. **მარაგი append-only მოძრაობებით.** მიღება, consumption და ზუსტი reversal უკეთესი საფუძველია, ვიდრე editable currentStock. supplier payment და მიღების თანხა გამიჯნულია.
7. **სტაბილური menu identity და contracts generator.** რენეიმი/კატეგორიის ცვლილება პროდუქტის ხელახლა შექმნას არ უნდა უდრიდეს. TypeScript/Dart command/table contracts-ის შემოწმება გადის.
8. **Onboarding პროგრესია.** Venue profile, POS self-enrollment, customer principal და printer config უკვე შექმნილია; პროექტის „ყველაფერი Vankisi-ზეა hardcoded“ დახასიათება არასწორი იქნებოდა.
9. **რეალური regression ტესტების ბაზა.** შესრულებული ტესტები გადის; repository-ში tenancy/concurrency/inventory DB suites-ც არსებობს, თუმცა მათი გავლა ამ აუდიტს არ დაუდასტურებია.

საყრდენი კოდი: [close journal](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/database/transactions/close_table_transaction.dart:79), [sale ledger ingestion](/Users/vaanskii/Developer/vynic/apps/backend/src/pos/sync/snapshot/sale-ledger-sync.service.ts), [manager tenancy tests](/Users/vaanskii/Developer/vynic/apps/backend/src/auth/manager-tenant.service.spec.ts:37), [inventory transaction](/Users/vaanskii/Developer/vynic/apps/backend/src/inventory/sale-consumption.service.ts:102), [supplier payment lock](/Users/vaanskii/Developer/vynic/apps/backend/src/inventory/supplier-payments.ts:90).

## 8. ტექნიკური გაწმენდა

### 8.1 Lint-ის დიდი არსებული ვალი — P1 განვითარების პროცესისთვის

| შემოწმება | შედეგი |
|---|---|
| Backend lint | 2,945 პრობლემა: 2,533 error + 412 warning |
| Platform-web lint | 24 პრობლემა: 23 error + 1 warning |

Backend-ის ყველაზე ხშირი კატეგორიებია `no-unsafe-member-access` (1,279), `no-unsafe-assignment` (795), `no-unsafe-argument` (411), `no-unsafe-call` (269). ეს lint-ის სხვადასხვა ტიპის ჩანაწერებია და არა დადასტურებული დამოუკიდებელი ბაგები. Backend lint-ში ტესტებიც შედის. Backend lint/test რაოდენობები თავდაპირველი ფართო გაშვების შედეგებია და გამორიცხული custom-website მოდულის ფაილებსაც შეიძლება მოიცავდეს; შევიწროებული მოცვისთვის ცალკე არ გადათვლილა. Platform-ზე 20 `no-explicit-any`, 3 `set-state-in-effect` და ერთი hooks dependency გაფრთხილებაა.

**გეგმა:** არსებული debt-ის baseline → ახალი პრობლემების აკრძალვა → auth/tenant/sync/finance payload ტიპები → CustomerPortal/Finance DTO-ები → სხვა დომენები. ფართო `eslint-disable` ან ყველა `any`-ს უბრალოდ `unknown`-ით შეცვლა პრობლემას არ აგვარებს. კონტრაქტში ვერ შემოწმებული რიცხვის/role/date-ის მოხვედრა runtime validation-ითაც უნდა დაიბლოკოს.

### 8.2 დიდი ფაილები და გაერთიანებული პასუხისმგებლობები — P2

აუდიტის მომენტში: POS `admin_screen.dart` — 3,977 ხაზი; `admin_menu_section.dart` — 3,351; `order_detail_screen.dart` — 3,347; Manager `dashboard_screen.dart` — 3,132; `menu_screen.dart` — 2,982; Manager inventory tab — 2,561. ეს თავისთავად ბაგი არ არის, მაგრამ ცვლილებების ზემოქმედების გაგებასა და დამოუკიდებელ შემოწმებას ართულებს.

გამოყავით დომენური controller/view-model, ფორმის state, API mapping და ვიზუალური ნაწილები. არსებული Dart `part`-ებად დაყოფა ფაილებს ამცირებს, თუმცა იგივე დიდი library-ის დამოკიდებულებებს ტოვებს. არ არის საჭირო ერთდროული rewrite ან მიკროსერვისებზე გადასვლა.

### 8.3 Payload-ები და ისტორიის კითხვები — P2

`MobileReportsService.getAuditLog` იღებს report-ებს ყველა event-ით pagination-ის გარეშე; `all=true` ვადასაც ხსნის. `InventoryCostService.bases` არჩეული stock item-ების ყველა movement-ს კითხულობს და JS-ში აკუმულირებს. POS-ის tables/orders/menu/staff payload-ების ნაწილი კვლავ ფართო snapshot-ია; main HTTP JSON limit 50 MB-ია.

**გეგმა:** audit list/detail განცალკევდეს და keyset pagination დაემატოს; stock valuation-ს ჰქონდეს ტრანზაქციულად განახლებადი summary/checkpoint, რომლის ledger-დან შემოწმება შესაძლებელია; catalog/runtime pull-ს revision/conditional response. პირველ რიგში გაზომეთ row count, payload size და P95 latency. დიდი ახალი infrastructure გაზომვის გარეშე საჭირო არ არის.

მტკიცებულება: [unpaged audit](/Users/vaanskii/Developer/vynic/apps/backend/src/mobile/services/mobile-reports.service.ts:57), [full movement scan](/Users/vaanskii/Developer/vynic/apps/backend/src/inventory/inventory-cost.service.ts:15), [body limit](/Users/vaanskii/Developer/vynic/apps/backend/src/main.ts:44).

### 8.4 Web bundle — P2

Production build გადის, მაგრამ მთავარი JS chunk 1,011.76 kB-ია, gzip 288.07 kB. Vite აფრთხილებს >500 kB chunk-ზე. App route-ები პირდაპირ import-დება; public site, admin და customer portal ერთ მთავარ dependency graph-შია.

**გასწორება:** route-level lazy imports; public/admin/customer-ის code splitting; დიდი სურათების ადეკვატური ფორმატი/ზომა. ეს latency-ის გაზომილ აუდიტს არ უდრის — ამ ეტაპზე დადასტურებულია artifact-ის ზომა.

მტკიცებულება: [eager imports](/Users/vaanskii/Developer/vynic/apps/platform-web/src/App.tsx:1), გაშვებული `npm run build`.

### 8.5 Credentials, diagnostics და მხარდაჭერა — P1/P2

Device credential ინახება JSON ფაილში მომხმარებლის data directory-ში, Unix-ზე 0600 permissions-ით; Manager JWT ჩვეულებრივ Hive box-შია. ეს ქსელური გამჟღავნების მტკიცებულება არ არის, თუმცა OS-backed secure storage უკეთესი ზღვარია. საჭიროა credentials-ის rotation/re-enrollment პროცედურა და უსაფრთხო backup/restore.

Owner-ს printer config უკვე შეუძლია, მაგრამ ეს არ ადასტურებს ფაქტობრივ ბეჭდვას. POS-ის ადგილობრივი printer/diagnostic controls developer-gated-ია. ტექნიკური გუნდის მონაწილეობის შემცირებისთვის საჭიროა უსაფრთხო customer troubleshooting: printer connectivity, test job/result, ბოლო წარმატებული sync, რიგში დარჩენილი ბრძანებები, exportable support bundle. wipe/restore და სხვა სახიფათო მოქმედებებს ცალკე უფლებები და კონტროლი უნდა დარჩეს.

მტკიცებულება: [Device file storage](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/edge/edge_device_credential_store.dart:214), [Manager Hive token](/Users/vaanskii/Developer/vynic/apps/operations/lib/core/services/auth/auth_token_service.dart:15), [developer sections](/Users/vaanskii/Developer/vynic/apps/operations/lib/apps/windows_pos/screens/admin_screen.dart:73), [owner printer form](/Users/vaanskii/Developer/vynic/apps/platform-web/src/customer/CustomerPortal.tsx:6).

### 8.6 Production და release მტკიცებულება — გაშვების gate

ამ repository-ში განხილული წყაროებით არ დადასტურდა production deployment-ის ჯანმრთელობა, გარე backup/PITR-ის მუშაობა, რეალური restore rehearsal, runtime metrics/alerts ან ყველა აპის release pipeline. root `.github` directory არ არსებობს; ეს არ გამორიცხავს სხვა სერვისში გარე CI-ის არსებობას.

მოთხოვნილი მტკიცებულება: disposable PostgreSQL-ზე migrations/integration; staging-ზე ორი იზოლირებული Venue; Windows POS + Manager coexistence; რეალური პრინტერი და კავშირის გათიშვა; upgrade/re-enrollment/restore; HTTPS/origins/secrets და production access; error rate/queue age/sync lag/backup failure alerts. UI-ში ოპერაციული გაფრთხილება უნდა გამოჩნდეს მოქმედების საჭიროებისას, არა ყველა ტექნიკურ heartbeat-ზე.

Legacy callback/shared key უნდა დარჩეს მხოლოდ რეალური ძველი კლიენტების საჭიროების ფარგლებში; მათი მოცილება მხოლოდ კოდში enrollment-ის არსებობაზე დაყრდნობით არ შეიძლება.

## 9. SaaS packaging და billing

მოდულის შეძენა, თანამშრომლის უფლება და POS-ის სიცოცხლისუნარიანობა სწორად უნდა გაიმიჯნოს. არსებული subscription policy შეგნებულად manual-ია: `TRIAL`, `ACTIVE`, `PAST_DUE` access-ს უშვებს; trialEndsAt/currentPeriodEndsAt თავისით შეწყვეტას არ იწვევს. ეს აღწერილი policy-ა და არა დამალული ავტომატური billing.

უახლოესი საჭიროებებია ვადაგასული trial-ის ოპერატორის სია, შეცვლის audit, feature dependency-ის მკაფიო ახსნა, customer-facing გეგმა/საფასურის ინფორმაცია და entitlement გამორთვისას მონაცემის შენარჩუნება. შემდეგ მოდის invoice/payment/subscription webhook lifecycle. რესტორნის სტუმრის გადახდა და Vynic-ის subscription გადახდა ცალკე დომენებად უნდა დარჩეს.

რესტორნებისთვის SaaS ვებსაიტი ცალკე შესაქმნელი პროდუქტია: Venue-ის კონტენტი, ბრენდინგი, დომენი და მენიუს გამოქვეყნება. არსებული CUSTOM `venue-web`-ის გადაკეთება ან მისი ონლაინ გადახდების შეცვლა ამ შეფასების რეკომენდაცია არ არის. თუ ახალ SaaS საიტში ონლაინ გადახდები შევა, merchant-ების განცალკევება მისი დიზაინის მოთხოვნა იქნება.

Generic SaaS venue website ჯერ ცალკე frontend/provisioning ფუნქციაა. `WebsiteMode=SAAS` ან WEBSITE feature-ის ჩართვა მზა რესტორნის საიტს არ ქმნის. შეფუთვაში ეს პირობა უკვე უფრო ზუსტადაა ახსნილი და იგივე სიზუსტე უნდა დარჩეს გაყიდვაშიც.

## 10. რეკომენდებული სამუშაო რიგი

| ფაზა | კონკრეტული შედეგი | დასრულების პირობა |
|---|---|---|
| A — წვდომა და ანგარიშების სიზუსტე | Platform throttle/recovery; POS/Manager ფინანსური მეტრიკების შეთანხმება | Platform login დაცულია; შეფასებითი და რეალური ფინანსური მაჩვენებლები აშკარად გამიჯნულია |
| B — უსაფრთხო ოპერაციული rollout | ერთი primary Edge, Device replacement; staging/Windows/printer/restore validation | ორი დამოუკიდებელი writer უნებართვოდ ვერ მუშაობს; crash/retry/re-enrollment ტესტდება |
| C — Restaurant Backoffice + RBAC + Venue Policy | Owner-ის მართვის სივრცე, Staff permissions, პარამეტრების ვერსირება | warehouse/accountant/host როლები მხოლოდ საჭირო მოქმედებებს აკეთებს; MANAGER_APP-ის გარეშე owner administration ხელმისაწვდომია შეთანხმებული პაკეტით |
| D — ფინანსური და მარაგის სრული ციკლი | cash drawer/refund, stocktake/waste/internal use, მეტრიკების შეთანხმება | ფიზიკური cash/stock discrepancy აღრიცხულია; POS/Manager ანგარიშები მნიშვნელობით თავსებადია |
| E — ზრდა | menu publish/modifiers/KDS; multi-location reports; billing/ინტეგრაციები სეგმენტის მიხედვით | ცვლილებები ვერსირებულად ვრცელდება; მოწყობილობის ACK ჩანს; თითო რესტორნის data/permissions იზოლაცია შენარჩუნებულია |

Lint baseline, typed DTO-ები, UI ფაილების თანმიმდევრული გაყოფა და route splitting პარალელური ტექნიკური სამუშაოებია. ყველა ახალი feature-ის გაჩერება ყველა არსებული lint შეცდომის ერთდროულად გასაქრობად არ არის საჭირო; ახალი debt-ის დამატება უნდა გაჩერდეს.

დროის ზუსტი შეფასება ამ აუდიტიდან სანდოდ ვერ განისაზღვრება: deployment გარემო, Windows მოწყობილობები და rollout-ის ფაქტობრივი მდგომარეობა დამატებით სამუშაოს განსაზღვრავს. ფაზების დასრულების პირობები დროის დაუსაბუთებელ დაპირებაზე გამოსადეგია.

## 11. შესრულებული შემოწმებები

| შემოწმება | ფაქტობრივი შედეგი |
|---|---|
| Backend `tsc --noEmit --incremental false` | წარმატებით დასრულდა |
| Backend Jest, `integration.spec.ts` გამორიცხული | 42 suite, 386 ტესტი — ყველა გავიდა |
| Platform-web Vitest | 11 ფაილი, 34 ტესტი — ყველა გავიდა |
| Platform-web production build | წარმატებით; დიდი chunk-ის გაფრთხილება |
| Flutter შერჩეული unit tests | 7 ფაილი, 67 ტესტი — ყველა გავიდა |
| Generated contracts `--check` | ყველა ნაჩვენები TS/Dart output შეესაბამება schema-ს |
| Backend lint | ვერ გაიარა: 2,533 error / 412 warning |
| Platform-web lint | ვერ გაიარა: 23 error / 1 warning |
| `git diff --check` | საწყის სამუშაო ცვლილებებზე სუფთა |

Flutter ფაილები: `pos_permission_test`, `money_guardrails_test`, `sale_consumption_test`, `runtime_config_test`, `venue_identity_draft_test`, `sale_visibility_test`, `fresh_install_test`. Flutter-ის პირველ გაშვებას SDK cache-ის sandbox შეზღუდვა შეხვდა; უფლებამოსილი ხელახალი გაშვება წარმატებით დასრულდა.

**არ ჩატარებულა:** real PostgreSQL integration/migration run, full Flutter test suite/analyze, Windows release/hardware testing, live browser journeys, production/network/backup inspection, security penetration/load testing. არსებული DB suites-ის ფაილების არსებობა მათი წარმატებული გაშვების მტკიცებულებად არ არის გამოყენებული.

**საბოლოო მიმართულება:** შეინარჩუნე ძლიერი ოფლაინ/ledger/tenant საფუძველი; პირველ რიგში გაასწორე ფულისა და პარამეტრების წინააღმდეგობები, დაასრულე Owner Backoffice/permissions და დაუკავშირე აღრიცხვა ფიზიკურ cash/stock კონტროლს. ამის შემდეგ ახალი არხები და მრავალფილიალიანი ზრდა გაცილებით ნაკლებ რისკს შექმნის.
