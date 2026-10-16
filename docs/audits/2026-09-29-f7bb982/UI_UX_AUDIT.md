# ეკრანები, სამუშაო გზები და გამოყენებადობა

ჭრილი: 2026-09-29, `f7bb982` + საწყისი WIP. გამოყენებულია პროექტის skill routing და `web-design-guidelines`; შემოქმედებითი redesign ან ახალი design სისტემა არ განხორციელებულა. ვების სამიზნეა [WCAG 2.2 AA](https://www.w3.org/TR/WCAG22/); შესაბამისობა ამ აუდიტით არ დასტურდება. ქვემოთ კოდის, browser-ისა და native proof მკაფიოდ განსხვავდება.

## ეკრანების რეესტრი

| ზედაპირი / სამუშაო | მტკიცებულება | სიმძიმე / რეალური პრობლემა | შემოთავაზებული შესწორება / დარჩენილი შემოწმება |
|---|---|---|---|
| Public Vynic `/ka`, `/en` | ნამდვილი browser DOM/screenshot; მიმდინარე image parity უცნობია | პირველი ეკრანის მუდმივი layout blocker არ გამეორებულა; DemoForm UX-01 P1 | CTA უნდა მიდიოდეს ერთ სანდო request workflow-ში; ქართული/ინგლისური გზისა და success persistence-ის სრული ტესტი |
| Public demo form `#contact` | `DemoForm.tsx:39–53` კოდი; ფორმა არ გაგზავნილა | UX-01 P1: timeout-only success, არც storage და არც HTTP | რეალური durable AccessRequest-ს გამოყენება ან მკაფიო navigation; network fail-ზე success არ ჩანს |
| Customer `/request-access` | browser 390×844; field required/type/name/autocomplete და ხილული პირველი Tab focus | ამ შემოწმებულ ნაწილში blocker არ დადასტურდა; submit/unhappy paths NOT_TESTED | server validation, duplicate submit/retry, confirmation/reference, focus-to-error და screen-reader announcement |
| Customer `/login` | ნამდვილი browser; synthetic account არ შექმნილა | login/revoke/expired invitation რეალური flow NOT_TESTED | keyboard-only login, expired/used invite, generic auth error; success-ის შემდეგ სწორი Venue selection |
| Platform `admin.vynic.localhost/login` | ნამდვილი browser; authenticated screens source/component tests | commercial/detail pages-ის live workflow NOT_TESTED; WEB-05 P1 promised onboarding-ისთვის | operator review: პაკეტი, mode, domain, deployed build, publication — ცალკე ფაქტები და მოქმედებები |
| Platform subscription/venue panels | `SubscriptionPanel.tsx`, operator actions და component tests | ტექნიკური სტატუსი არ უდრის launch readiness-ს; manual payment ≠ bank verification | თანხა/ვადა/ცვლილების ძალაში შესვლის დრო; explicit operator proof/reference; UI-ში pending upgrade უფლებას არ ხსნის |
| Customer menu/profile/publish | `OwnerDashboard.tsx:96–98`, `restaurant-foundation.service.ts:38–66` | COM-01 P1 POS-only owner-ს WEBSITE gate აფერხებს; draft/public semantics WEB-02 | menu authoring თავისი product authority-ით; live shared info და private presentation draft მკაფიო დახმარების ტექსტით |
| Customer device/Manager setup | source + component suites; native enrollment runtime blocked | enrollment URL-ის WIP არსებობს; running origin უტყუარად არ დადასტურებულა | საჭირო code/origin და სურვილისამებრ setup განცალკევდეს; invalid/expired code და არსებული device-ის ქცევა შემოწმდეს |
| SaaS restaurant Menu/site | source + 19 tests + build; tenant browser workflow NOT_TESTED | public data publication migration P0; frontend capability ≠ backend entitlement | მხოლოდ რეალურად მხარდაჭერილი controls; empty menu, disabled site, partial media და host mismatch states |
| Vankisi custom site | source + build/lint; live customer DB განზრახ არ გამოყენებულა | WEB-07 P1 hardcoded hours/contact; paid booking SEC-01/WEB P0; privacy link SEC-06 | shared info-ზე მიბმა standalone frontend-ის შენარჩუნებით; reservation hold/payment/delivery მდგომარეობები ცალსახა |
| POS first run / Venue setup | `pos_first_run.dart`, `venue_setup_screen.dart`; source | OPS-01 native proof gap | პირველ setup-ზე ქსელი საჭიროა; შემდეგ offline მუშაობა. error-ში origin/code/connection განსხვავდეს, secret არ გამოჩნდეს |
| POS tables/order/split/transfer/close | source trace [POS_MENU_EDGE.md](POS_MENU_EDGE.md) | POS-01/03/05 P0; ეს მხოლოდ visual polish არ არის | durable ოპერაცია, duplicate-submit guard, amount/tender review; uncertain state-ს რეალური recovery action |
| POS text/numeric/PIN input | shared `PosKeyboard`, `PosNumberPad`, sheet/controller wiring; `test/widget/pos_input_test.dart` არსებობს, არ გაშვებულა | native input/accessibility/1024×768 NOT_TESTED | Georgian/English text, external keyboard, selection/backspace, decimals, max amount, masked PIN; field value და controller live sync |
| POS menu/conflict editor | source canonical writer/projection | MENU-02 P0 durability; MENU-05/08 P2 restore/discard audit | active/inactive filter და same-ID restore; local/current comparison; reapply/discard შედეგი restart-ს უძლებს |
| POS quit/update UI | source readiness barrier და Python source-wrapper test | Windows/hardware OPS-01 unverified | busy payment/write/recovery დროს გასაგები blocker; clean quit და forced kill განსხვავებული ტექსტი/proof |
| Manager setup/login/restaurant selection | source; widget suites არსებობს, არ გაშვებულა | actual phone/desktop login/revocation NOT_TESTED | origin-bound selection, clear account/restaurant context, session expiry, cross-Venue cache reset |
| Manager dashboard/financials | UI→API→service→ledger trace | MGR-04 P2 stale/completeness; INV-02 P2 gross/debt/cost/profit confusion | თითო block-ის source/fetchedAt/businessDate/completeness; დაუტვირთავი მონაცემი ნულად არ გამოჩნდეს |
| Manager tables/orders/reservations | actual service mocks + source | MGR-01 P1 layout filter; MGR-02/05 P0; MGR-03 P1 false completion | Venue-ის რეალური floor plan; command status: „გაიგზავნა“, „POS-ს ელოდება“, „შესრულდა“, „ვერ შესრულდა“ |
| Manager Inventory | სრული source/model/service walkthrough, რეალური app არა | INV-01 promised full product P1; UX-02 P2; MENU-06 P0 | receipt/payment/debt/stock დოკუმენტური კავშირი; locations/waste/count domain ჯერ, შემდეგ შესაბამისი screens |
| Manager finance/payroll/team/settings | source trace და შესაბამისი backend unit coverage | MGR-06 P1 correction gap; permission/freshness native proof აკლია | payment reversal/adjustment audit; direct Cloud vs POS delivery; read/create/approve/pay უფლება ცალსახა |
| Windows installer/update wizard | `apps/edge/cmd/setup/wizard_windows.go`, `internal/setup/*`; Python mocked tooling | OPS-01 P1 release qualification; actual UI NOT_TESTED | install/update/retry/rollback destination, non-ASCII path, standard user, invalid signature, low disk, failed health — რეალურ Windows-ზე |

Manager-ის თითოეული მაჩვენებლის მონაცემის წყარო და თითო შემოთავაზებული ეკრანის ამოცანა სრულად არის [INVENTORY_MANAGER_UX.md](INVENTORY_MANAGER_UX.md)-ში. ამ ცხრილში მათ ახალი issue ID არ ენიჭება.

## UX-01 — მოთხოვნის მიღების ცრუ დადასტურება

**P1 · BUG FIX · CONFIRMED_BY_CODE · confidence high.** Scope: Vynic public acquisition; მომხმარებელი — რესტორნის დაინტერესებული მფლობელი.

`apps/platform-web/src/components/sections/DemoForm.tsx:39` `handleSubmit` required ველებს ამოწმებს; `:51–53` 700 ms-ის შემდეგ success state-ს აყენებს. ამ handler-ში HTTP/storage მოქმედება არ არის. UI route: საჯარო გვერდის `#contact`; მოდელი: მხოლოდ React local `LeadForm`. ცალკე `/request-access` რეალური request flow-ა და არ უნდა აირიოს ამ ფორმაში.

**მოსალოდნელი:** მოთხოვნის მიღება დადასტურდეს მას შემდეგ, რაც სისტემა მას შეინახავს და ოპერატორს შემდგომ მისი პოვნა შეუძლია. მოთხოვნის წყაროა user request §4 journey A და §12 task completion, ასევე თავად success copy-ის დაპირება. **ფაქტი:** ფორმის data მხოლოდ component state-ში რჩება, წარმატება დროს ეფუძნება. ზიანი: დაკარგული lead და მცდარი მომხმარებლის მოლოდინი.

შემოწმება: `nl -ba apps/platform-web/src/components/sections/DemoForm.tsx` და `handleSubmit`-ის call graph; controlled future browser test-ში network/storage-ის გარეშე synthetic submit. ამ აუდიტში ფორმა არ გაგზავნილა, ამიტომ runtime submit proof არ ითქმის.

**გამოსწორება:** ერთი canonical onboarding/request destination. არსებული AccessRequest reuse უმცირესი არჩევანია; success მხოლოდ durable backend acceptance-ზე, retry identity და გასაგები failure. Migration საჭირო არ უნდა იყოს; rollback UI routing ცვლილებით; effort S. Owner decision: ყველა demo CTA ერთ request flow-ზე გადადის თუ განსხვავებული lead contract რჩება.

**მიღება:** required invalid → error; server/network failure → success არ ჩანს; accepted request → reference და operator-ში ერთი ჩანაწერი; double click/retry → duplicate არ იქმნება; keyboard/focus announcement; ქართული/ინგლისური copy ერთნაირ შედეგს ჰპირდება.

## ზომები, accessibility და workflow proof

რეალურად დადასტურებულია **390×844**. სხვა requested viewport-ებზე tool response წარმატებული ჩანდა, მაგრამ page-ის ფაქტობრივი ზომა 390 დარჩა; ამიტომ 375/768/1280/1440 შემოწმებულად არ ითვლება. პირველ screenshot-ზე entrance animation-ის დასრულებამდე form არ ჩანდა; შემდგომ გამოჩნდა, მუდმივი blank-form bug არ დადასტურებულა. `/ka` floor-demo AX სახელებში ინგლისური `Zoom in/Zoom out/Fit canvas` დარჩა — მცირე localization follow-up, ამ აუდიტში task completion-ის blocker არ დადასტურდა.

ბოლო release QA უნდა მოიცავდეს:

1. Web 375/390, 768, 1280/1440 **ფაქტობრივად გაზომილ** viewport-ს; 200%/400% zoom/reflow, contrast, focus visibility/order, escape/modal return-focus, landmarks/headings და screen reader labels/errors/status announcements.
2. თითო workflow-ს success, empty, loading, offline, stale, forbidden, expired და pending delivery მდგომარეობებს. ტექნიკური queue status-ს მომხმარებლის შედეგის ქართული ახსნა ახლდეს.
3. Date/time/currency: Venue businessDate და მიმდინარე საათი განსხვავდება; 00:00/expiry boundary; ₾/decimals და fiscal receipt ზუსტი თანხა; language switch შეყვანილ form state-ს არ კარგავს.
4. Destructive actions: რას ცვლის, რომელ დოკუმენტს ეხება, შეიძლება თუ არა reversal; double-tap დაცვა და რეალური server authorization. მხოლოდ dialog დადასტურება atomicity-ს არ ქმნის.
5. POS რეალურ Windows-ზე 1024×768 და supported desktop size; touch, external keyboard, PIN/numeric/text, controller-ის live synchronization, scroll/focus როცა keyboard ღიაა. Native semantics და screen-reader proof ცალკე.
6. Manager supported phone/tablet/desktop builds-ზე portrait/landscape, დიდი font, back navigation და long Georgian labels; რეალური notifications/reconnect/cached source age. Build target-ების ჩამონათვალი ოთხივე პლატფორმაზე მხარდაჭერის მტკიცება არ არის.

კოსმეტიკური spacing/color/theme ცვლილება P0 მონაცემის მთლიანობას ვერ გამოასწორებს. ჯერ მომხმარებლისთვის სწორი შედეგი და საიმედო მდგომარეობა, შემდეგ მიზნობრივი IA და ვიზუალური გასუფთავება. ახალ screenshots-ს მხოლოდ რეალურად გაშვებული ეკრანის evidence უნდა ერქვას; ამ ანგარიშში source inspection screenshot-ად არ არის წარმოდგენილი.
