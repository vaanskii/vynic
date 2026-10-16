# POS / Manager onboarding — proposal awaiting approval

ეს არის source-ზე და read-only შემოწმებაზე დაფუძნებული წინადადება. ახალი flow,
configuration ცვლილება, credential issuance ან activation არ განხორციელებულა.

## დადასტურებული მიმდინარე მდგომარეობა

| ნაწილი | მიმდინარე flow | რეკომენდებული flow |
| --- | --- | --- |
| პირველი POS | მოწყობილობის enrollment კოდი → Venue ავტომატურად → ცალკე პირველი Manager-ის activation კოდი → სახელი და ახალი PIN | ერთი უფლებამოსილი POS setup/enrollment კოდი → Venue ავტომატურად → სახელი და ახალი PIN ერთხელ |
| უკვე არსებული Manager / დამატებითი POS | Device enrollment და არსებული Staff-ის მიწოდება/აღდგენა; Manager-ის ხელახლა შექმნა აკრძალულია | იგივე დაცვა; დამატებითი POS კოდი პირველ Manager-ს ვერ შექმნის და არსებულ PIN-ს ვერ აღადგენს |
| Manager აპი | რესტორნის კოდით ერთხელ არჩევა → არჩევანი ამ origin-ზე ინახება → PIN | ერთხელ „რესტორანთან დაკავშირება“ არსებული იდენტიფიკატორით → შემდეგ PIN; QR/deep link შეიძლება მოგვიანებით დაემატოს |
| Backend | production-ში build-ის URL; debug/development-ში ხილული override და loopback fallback | production-ში იგივე fixed HTTPS origin და დამალული controls; ამ Mac-ის developer default Docker native origin, explicit developer override |

**POS enrollment უკვე განსაზღვრავს Venue-ს.** `/edge/enroll` არ იღებს client
`venueId`-ს. Venue მოდის სერვერის enrollment ჩანაწერიდან. POS-ის პირველი
Manager-ის მიმდინარე ფორმაც არ ითხოვს რესტორნის კოდს — ის ითხოვს ცალკე
**activation invitation**-ს. ეს ორი განსხვავებული ნებართვაა: Device enrollment
აერთებს მოწყობილობას, ხოლო invitation აძლევს მხოლოდ პირველი Manager-ის შექმნის
უფლებას. მათი გაერთიანება მხოლოდ UI-ში ველების წაშლა ვერ იქნება.

Manager უკვე იმახსოვრებს რესტორანს: `ManagerVenueSelection` ინახება backend
origin-თან ერთად. შემდგომ login-ს PIN და შენახული Venue code აქვს. Backend ისევ
PIN-ის ნამდვილ Staff/Venue კავშირს ამოწმებს; client selection ავტორიზაცია არ არის.
სრული app-data reset-ის შემდეგ ამ არჩევნის ერთხელ ხელახლა მითითება მოსალოდნელია.
მხოლოდ logout-მა ეს reset არ უნდა მოითხოვოს.

## ზუსტი backend / env შედეგი

- სწორი local hostname არის **`api.vynic.localhost`**. მისი `/healthz` არის 200.
  `api.vyinc.localhost` და `api.vyinic.localhost` არის 404. `.localhost` ამ Mac-ზე
  loopback-ზე resolve-დება; hostname Docker-ის Host routing-ს განსაზღვრავს.
  ეს განსხვავდება დახურული `127.0.0.1:3000` პირდაპირი Nest listener-ისგან.
- გაშვებული Manager-ის UI ამ შემოწმების დროს აჩვენებს
  `http://api.vynic.localhost`, დამახსოვრებულ `Restaurant Vankisi`-ს და PIN pad-ს.
  PIN, login, activation ან enrollment არ გაგზავნილა.
- ორივე detached macOS developer build-ის generated metadata შეიცავს
  `VYNIC_ENV=development`-ს და არ შეიცავს `VYNIC_API_URL`-ს. Source-ის მიხედვით,
  შენახული backend override-ის არქონისას Mac fallback არის `127.0.0.1:3000`.
  ამიტომ reset-ის შემდეგ ადრინდელი ასეთი ქცევა source-ს შეესაბამება. მიმდინარე
  live UI უკვე სწორ URL-ს აჩვენებს; earlier reset-ის ზუსტი მოქმედება აქ არ დამიდასტურებია.
- `apps/operations/.env` და `.env.example` არსებობს, მაგრამ მათში legacy
  `BACKEND_URL_*` keys არის; `ApiConfig` მათ არ კითხულობს. `VYNIC_ENV` და
  `VYNIC_API_URL` Dart compile-time defines-ია. მხოლოდ `.env`-ის შეცვლა გაშვებულ
  აპს ვერ გადააკონფიგურირებს. Manager-ის კომენტარი „bundled .env default“ obsolete-ია.
- არსებული dev wrapper `VYNIC_DEV_API_URL` shell variable-ს `--dart-define`-ად
  გადასცემს; თუ variable აკლია, URL define არ ემატება. Flutter-ის ამ SDK-ში
  `--dart-define-from-file` იღებს `.env` ან JSON-ს build/run დროს. ეს runtime
  dotenv loading არ არის.
- Production/staging startup მოითხოვს configured HTTPS origin-ს. მომხმარებლის
  backend controls უკვე გამორთულია `kDebugMode && development`-ის გარეთ; ეს
  მიმდინარე ლეპტოპის developer build-ში ჩანს. Production URL-ის მაგალითი უკვე
  `.env.production.example`-შია; მისი deployment ამ proof-ში არ დამოწმებულა.
- სავსე legacy `.env`-ის build defines-ში გადატანა არ უნდა მოხდეს: ახალი build
  example უნდა შეიცავდეს მხოლოდ public endpoint/environment-ს. Backend/credential
  secrets client-ში არ გადადის და `.env` app asset არ გახდება.

ეს local hostname მხოლოდ იმავე Mac-ისთვისაა სწორი. სხვა ფიზიკურ ტელეფონზე
`.localhost` თვით ტელეფონს ნიშნავს; developer device-ს თავისი ხელმისაწვდომი,
ავტორიზებული LAN/HTTPS origin სჭირდება. Production-ში ყველა რესტორანი ერთ fixed
API deployment-ს იყენებს; Venue Device/Staff authority-დან მოდის და არა API URL-დან.

## ერთი POS კოდი — უსაფრთხო ვარიანტი

1. Platform Admin ქმნის/ამოწმებს Organization/Venue-ს და შესაბამის უფლებებს.
   საპორტი ადამიანს აწვდის უფლებამოსილად გაცემულ **პირველი POS setup კოდს**.
   წერილის ავტომატური გაგზავნა ცალკე capability-ია და აქ არ შესრულებულა.
2. POS იღებს ამ ერთ კოდს. სერვერი ადგენს Venue-ს და მომხმარებელს აჩვენებს მის
   სახელს. URL ჩვეულებრივ მომხმარებელთან არ ჩანს და არ ივსება.
3. მხოლოდ თუ Venue-ს **არ აქვს Manager-ის ისტორია** და ეს setup უფლებამოსილია,
   Primary POS აჩვენებს სახელს, ახალ PIN-ს და დადასტურებას. საჭირო one-use grant
   გადადის enrollment handoff-ში შიდა გზით; ადამიანს მეორე activation კოდი არ
   შეჰყავს. შესაძლო implementation reuse არის არსებული ManagerActivation-ის
   გამოყენება და ახალი Device-bound handoff, სრული retry/persistence კონტროლით.
4. სერვერი ატომურად ქმნის Staff-ს და არსებულ Edge delivery-ს. მიღების/მიწოდების
   მდგომარეობა ნაჩვენებია ზუსტად; ადგილობრივი ავტორიზაცია მხოლოდ Staff-ის
   მიღების შემდეგ იხსნება. საერთო/default PIN არ იქმნება.
5. ჩვეულებრივი დამატებითი/repair POS enrollment არ ანიჭებს ახალ Manager-ის
   შექმნის უფლებას. არსებულ Manager-ის PIN recovery მხოლოდ Vynic Platform Admin-ს
   რჩება. არსებული users/history/business data არ იშლება და სხვა Venue-ს არ მიეწერება.

შენარჩუნდება Device → Venue და Staff → Venue authority, Primary fencing, მოქმედი
issuer/entitlements, grant expiry/single-use, atomic duplicate PIN checks,
idempotent retries, revocation/disabled-Venue denial, existing-manager/history
exclusion და audit-ის confidentiality. SUPPORT_READONLY-ის უფლებები არ გაიზრდება.
Enrollment-ის აღდგენა თავისთავად ბიზნეს-მონაცემების wipe/handover არ გახდება.

**დასამტკიცებელი product ცვლილება:** სპეციალურად პირველი POS setup-სთვის გაცემული
ერთი enrollment კოდი მოიცავს ასევე პირველი Manager-ის შექმნის უფლებას. ჩვეულებრივი
enrollment ამას არ მოიცავს. ეს D016-ის არსებული ორმაგი ნებართვის human flow-ს
ცვლის და approval-ის შემდეგ ცალკე decision უნდა დაფიქსირდეს.

## უმცირესი განხორციელების გეგმა / effort

1. **S — developer configuration:** ახალი non-secret build-config examples;
   dev wrapper-ის Docker default; developer override-ის მკაფიო precedence და
   production-ის immutable configured URL. არსებული real `.env` არ გადაიწეროს.
   Reset/URL switching/cache isolation და release control hiding regression.
2. **M — scoped bootstrap handoff:** Admin-issued first-setup purpose/grant;
   არსებული enrollment და ManagerActivation services-ის უსაფრთხო შეკავშირება;
   Device/Venue-bound short-lived handoff, persistent retry identity და transaction.
   სავარაუდოდ საჭიროა ერთი additive migration ახალი nullable/closed-by-default
   grant linkage/purpose metadata-სთვის; ისტორიული Staff/PIN/IDs არ გადაიწერება.
   ძველი clients-ის ცალკე activation route რჩება თავსებადი, სანამ rollout დასრულდება.
3. **S/M — POS wizard:** ერთკოდიანი შემოსვლა და კონტექსტის მიხედვით name/PIN ან
   არსებული წვდომის მიღება; cancel/reconnect/error/expiry/retry გზა. Backend,
   credential handling და current print/identity admission ისევ ახორციელებს დაცვას.
4. **S — Manager wording/setup:** არსებული ერთხელ Venue selection მკაფიოდ
   გამოჩნდეს როგორც დაკავშირება, შემდეგ PIN. QR/deep link არ არის საჭირო პირველ
   მინიმალურ ნაბიჯში და მისი დამატება ცალკე შეფასდება.

Configuration/Manager UX მცირე სამუშაოა. პირველი POS-ის ორი authorization proof-ის
ერთი human code-ით გამართვა **საშუალო ზომის cross-stack ცვლილებაა**, რამდენიმე
ფოკუსირებული implementation/qualification ეტაპით; მხოლოდ ერთი ღილაკის შესწორება
არ არის. ზუსტი კალენდარული დაპირება grant/retry დიზაინის დამტკიცებამდე არ გაკეთდეს.

სავალდებულო regression: reset-ზე სწორი default; production override ignored;
first vs additional POS; expired/used/wrong-Venue/revoked/secondary Device; no
Manager-history bootstrap; concurrent creation და duplicate PIN; lost reply/restart
retry; existing Manager recovery Admin-only; legacy compatibility; Edge-delivery
failure; no local business-data/credential loss და no client secret leak.
მრავალPOS ოპერაციული cutover/printing qualification ცალკე POS-02.C-ად რჩება.

## Paused work და ჩატვირთვის საზღვარი

- `pos_first_run.dart`-ში მცირე reconnect navigation patch უკვე დაწყებულია:
  waiting → existing enrollment form; cancel; successful-return state; optional
  test service/client seams. **Untested WIP**, user priority change-მდე regression
  არ დამატებულა/გაშვებულა. მიმდინარე აპში hot restart ან rebuild არ გაკეთებულა.
  ის არის `../POS_RECONNECT_UI_3463ee40_2026-10-14/partial-navigation.patch`.
- Dart-only navigation ცვლილებისთვის debug hot restart საკმარისია ტესტების შემდეგ;
  ახალი compile-time URL defines-ისთვის flutter run უნდა ხელახლა გაეშვას ახალი
  პარამეტრებით. იგივე პარამეტრებით hot restart defines-ს არ ცვლის.
  გამოშვებული binary-ისთვის საჭიროა ახალი build/update.
- OPS-01 შეჩერებულია და მისი დროებითი cluster გაჩერებულია. უარყოფილი restore
  არ განმეორებულა. ძველი WEB06 intermediate 403 კვლავ დაუდგენელი დაკვირვებაა.
- ამ proposal-ის ეტაპზე source flow, `.env`, authorization policy, მონაცემები,
  credentials, რეალური activation და live სერვისები არ შეცვლილა. Source-ში მხოლოდ
  მანამდე ავტორიზებული, ახლა შეჩერებული navigation WIP არის შენარჩუნებული.

Read-only configuration evidence: `configuration-evidence.json`.
Source snapshot hashes: `source-hashes.json`.
წინა აქტივაციის root-cause proof:
`../POS_ACTIVATION_DIAGNOSIS_3463ee40_2026-10-14/diagnosis.json`.
