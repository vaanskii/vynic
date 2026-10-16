import type { Locale } from "../../lib/i18n";

/**
 * Homepage-only copy for the motion redesign. Shared strings (hero title and
 * body, floor, product tour, reservations, local fit, form) still come from
 * `lib/i18n.tsx`; this file holds the new section voice.
 *
 * Headlines are split as [before, accent, after]: the accent renders in the
 * italic serif. Numbers on illustrative panels are labelled as samples.
 */
export type Accented = [string, string, string];

export type HomeCopy = {
  nav: { product: string; how: string; manager: string; floor: string; reservations: string; contact: string; status: string };
  hero: { pill: string; accent: string; cta: string; secondary: string; footnote: string };
  panel: {
    title: string;
    meta: string;
    floor: string;
    tables: string;
    now: string;
    seated: string;
    reserved: string;
    paying: string;
    free: string;
    events: string;
    feed: string[];
    offline: string;
    online: string;
    queued: string;
    synced: string;
    check: string;
    total: string;
  };
  rail: { label: string; surfaces: string[]; more: string };
  flow: {
    kicker: string;
    title: Accented;
    body: string;
    rows: Array<{ title: string; body: string }>;
    trace: { head: string; done: string; steps: string[]; unit: string };
    close: { head: string; today: string; ask: string; checks: Array<[string, string]>; review: string; hold: string; waiting: string };
    week: { head: string; average: string; days: string[] };
  };
  floor: { kicker: string; title: Accented };
  portal: { label: string; statement: Accented };
  reliable: {
    kicker: string;
    title: Accented;
    body: string;
    offline: { title: string; body: string; nodes: string[]; footer: string; state: [string, string] };
    payments: { title: string; body: string; head: string; rows: Array<[string, number]>; footer: string };
  };
  daily: {
    kicker: string;
    title: Accented;
    body: string;
    sample: string;
    heat: { head: string; next: string; days: string[] };
    ring: { head: string; caption: string };
    guests: { head: string; count: string; caption: string };
    pay: { head: string; cash: string; card: string };
    room: { head: string; caption: string };
  };
  screens: { kicker: string; title: Accented; auto: string };
  numbers: {
    kicker: string;
    title: Accented;
    body: string;
    stats: Array<{ value: number; suffix: string; label: string; tag: string }>;
  };
  reservations: { kicker: string; booking: string };
  manager: { kicker: string; title: Accented; tabs: string[]; hint: string; soon: string };
  words: { kicker: string; text: string; marquee: string[] };
  contact: { kicker: string; title: Accented; requestTitle: string; requestBody: string; requestCta: string };
  footer: { line: string; rights: string };
};

const en: HomeCopy = {
  nav: { product: "Product", how: "How it works", manager: "Manager app", floor: "Floor plan", reservations: "Reservations", contact: "Contact", status: "service ready" },
  hero: {
    pill: "offline-first · Georgian & English",
    accent: "as it runs",
    cta: "Try Vynic",
    secondary: "Watch the screens",
    footnote: "orders keep going offline / GEL and service fee built in / one record for POS, Manager and website",
  },
  panel: {
    title: "Floor 1",
    meta: "9 tables · live",
    floor: "Service right now",
    tables: "tables",
    now: "now",
    seated: "seated",
    reserved: "reserved",
    paying: "paying",
    free: "free",
    events: "last events",
    feed: [
      "Table 4 · order sent to kitchen",
      "Table 2 · paid 106.70 ₾ · Bank POS",
      "Takeaway #TA-1753 · ready",
      "Table 8 · reservation seated · 4 guests",
      "Table 1 · service 10% added",
      "Table 6 + 7 · merged for 12",
    ],
    offline: "connection dropped",
    online: "online",
    queued: "still taking orders",
    synced: "synced",
    check: "Table 1 · check",
    total: "payable",
  },
  rail: {
    label: "one venue record behind every surface",
    surfaces: ["POS", "Kitchen", "Manager", "Website", "Booking", "Bank POS", "Z report"],
    more: "custom site",
  },
  flow: {
    kicker: "service flow",
    title: ["Most of a shift is ", "handoffs", "."],
    body: "Table to kitchen, kitchen to bill, bill to close. Vynic carries each handoff so the team can stay on the floor.",
    rows: [
      { title: "One check, every step", body: "Open the table, send the order, add the service fee, take the payment. Every step lands on the same check, in order." },
      { title: "Close-day guardrails", body: "Before the business date moves, Vynic shows the open tables and unfinished takeaways that still need a look." },
      { title: "Every shift is on the record", body: "Cancels, closes, staff and manager actions stay attached to the restaurant record." },
    ],
    trace: { head: "check #1756 · Table 1", done: "closed in 58 min", steps: ["table opened", "23 items sent", "service 10%", "payment · Bank POS"], unit: "min" },
    close: {
      head: "Close day",
      today: "today",
      ask: "Close the business day? A few things still need a look.",
      checks: [["open tables", "Table 4, Table 9"], ["takeaways", "#TA-1753 not finished"], ["Z report", "ready"]],
      review: "Review tables",
      hold: "Hold",
      waiting: "waiting on manager",
    },
    week: { head: "closed orders per day", average: "sample week", days: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] },
  },
  floor: { kicker: "floor plan", title: ["Draw the floor ", "once", ". Run service from it every day."] },
  portal: { label: "[ what we build for ]", statement: ["The best shift is the one ", "nobody talks about", " the next morning."] },
  reliable: {
    kicker: "reliability",
    title: ["", "Boring", " in the ways that matter."],
    body: "Offline service, guarded close-day and an action log. The parts nobody demos, and the parts that decide a Saturday night.",
    offline: {
      title: "Every terminal keeps working offline",
      body: "Keep taking orders when the connection drops, then sync service state when it returns.",
      nodes: ["POS 1", "POS 2", "Kitchen", "Manager"],
      footer: "orders, payments, prints, sync",
      state: ["online", "offline · queued"],
    },
    payments: {
      title: "Payments closed the local way",
      body: "Cash, Bank POS and split payment, counted in GEL, with the service fee on the check.",
      head: "where tonight's total came from",
      rows: [["Cash", 46], ["Bank POS", 38], ["Split", 16]],
      footer: "sample evening · GEL",
    },
  },
  daily: {
    kicker: "daily view",
    title: ["A ", "Friday", ", seen from Vynic."],
    body: "The view managers actually keep open: who is seated, what is paid, and what still owes an answer.",
    sample: "sample evening",
    heat: { head: "this week, covers by hour", next: "next booking in 12 min", days: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] },
    ring: { head: "tables seated", caption: "of the floor seated at 21:00" },
    guests: { head: "reservations tonight", count: "bookings", caption: "Next: 20:30 · 4 guests · Table 8" },
    pay: { head: "payments", cash: "cash", card: "Bank POS" },
    room: { head: "floor right now", caption: "Every table shows its own state" },
  },
  screens: { kicker: "the real screens", title: ["The POS, ", "screen by screen", "."], auto: "auto" },
  numbers: {
    kicker: "local fit",
    title: ["Built for the details owners ", "actually", " handle."],
    body: "No vanity metrics. Just the things a Georgian restaurant floor runs on every night.",
    stats: [
      { value: 0, suffix: "", label: "internet needed to take an order", tag: "offline-first" },
      { value: 2, suffix: "", label: "languages across POS and Manager", tag: "Georgian · English" },
      { value: 1, suffix: "", label: "venue record behind POS, Manager and website", tag: "one platform" },
    ],
  },
  reservations: { kicker: "reservations", booking: "Table 8 · 20:30 · 4 guests" },
  manager: {
    kicker: "manager app",
    title: ["The business day, ", "in your pocket", "."],
    tabs: ["Today", "Tables", "Bookings", "Staff", "Close day"],
    hint: "tap, swipe or use the arrow keys",
    soon: "new screens in progress",
  },
  words: {
    kicker: "one shift",
    text: "Vynic follows the shift from the first table to the last receipt — on the floor, in the kitchen, in the owner's pocket and on the restaurant's own website.",
    marquee: ["offline-first", "Georgian & English", "GEL native", "service fee", "Z report", "banquet tables", "close-day guardrails", "manager app", "online bookings"],
  },
  contact: {
    kicker: "demo", title: ["See how Vynic would run ", "your", " floor."],
    requestTitle: "Start with your restaurant.",
    requestBody: "Fill in a short application on the next page. Once it is received, our team will contact you to arrange a demo.",
    requestCta: "Request a demo",
  },
  footer: { line: "Restaurant POS and operations for tables, reservations, payments, close-day and manager visibility.", rights: "Vynic" },
};

const ka: HomeCopy = {
  nav: { product: "პროდუქტი", how: "როგორ მუშაობს", manager: "მენეჯერის აპი", floor: "დარბაზის გეგმა", reservations: "ჯავშნები", contact: "კონტაქტი", status: "სერვისი მზადაა" },
  hero: {
    pill: "ოფლაინ მუშაობა · ქართული და ინგლისური",
    accent: "დარბაზის მართვა",
    cta: "გამოსცადე Vynic",
    secondary: "ეკრანების ნახვა",
    footnote: "შეკვეთები ოფლაინაც გრძელდება / GEL და მომსახურების საფასური / ერთი ჩანაწერი POS-ის, მენეჯერისა და საიტისთვის",
  },
  panel: {
    title: "სართული 1",
    meta: "9 მაგიდა · ცოცხლად",
    floor: "მიმდინარე სერვისი",
    tables: "მაგიდა",
    now: "ახლა",
    seated: "დაკავებული",
    reserved: "დაჯავშნილი",
    paying: "იხდის",
    free: "თავისუფალი",
    events: "ბოლო მოვლენები",
    feed: [
      "მაგიდა 4 · შეკვეთა სამზარეულოში გაიგზავნა",
      "მაგიდა 2 · გადახდილია 106.70 ₾ · ტერმინალი",
      "გატანა #TA-1753 · მზადაა",
      "მაგიდა 8 · ჯავშანი დასხდა · 4 სტუმარი",
      "მაგიდა 1 · მომსახურება 10% დაემატა",
      "მაგიდა 6 + 7 · გაერთიანდა 12-ზე",
    ],
    offline: "კავშირი გაწყდა",
    online: "ონლაინ",
    queued: "შეკვეთები გრძელდება",
    synced: "დასინქრონდა",
    check: "მაგიდა 1 · ჩეკი",
    total: "გადასახდელი",
  },
  rail: {
    label: "ობიექტის ერთი ჩანაწერი ყველა ეკრანის უკან",
    surfaces: ["POS", "სამზარეულო", "მენეჯერი", "ვებსაიტი", "ჯავშანი", "ტერმინალი", "Z-რეპორტი"],
    more: "საკუთარი საიტი",
  },
  flow: {
    kicker: "სერვისის ნაკადი",
    title: ["ცვლის უმეტესი ნაწილი ", "გადაცემებია", "."],
    body: "მაგიდიდან სამზარეულომდე, სამზარეულოდან ანგარიშამდე, ანგარიშიდან დახურვამდე. Vynic თითოეულ ნაბიჯს ატარებს, გუნდი კი დარბაზში რჩება.",
    rows: [
      { title: "ერთი ჩეკი, ყველა ნაბიჯი", body: "გახსენი მაგიდა, გაგზავნე შეკვეთა, დაამატე მომსახურება, მიიღე გადახდა. ყოველი ნაბიჯი იმავე ჩეკზე, თანმიმდევრობით აისახება." },
      { title: "დღის დახურვის კონტროლი", body: "სამუშაო თარიღის შეცვლამდე Vynic გაჩვენებს ღია მაგიდებს და დაუსრულებელ გატანის შეკვეთებს." },
      { title: "ყოველი ცვლა ჩანაწერშია", body: "გაუქმება, დახურვა, თანამშრომლებისა და მენეჯერის მოქმედებები რესტორნის ჩანაწერს რჩება." },
    ],
    trace: { head: "ჩეკი #1756 · მაგიდა 1", done: "დაიხურა 58 წუთში", steps: ["მაგიდა გაიხსნა", "23 პოზიცია გაიგზავნა", "მომსახურება 10%", "გადახდა · ტერმინალი"], unit: "წთ" },
    close: {
      head: "დღის დახურვა",
      today: "დღეს",
      ask: "დავხუროთ სამუშაო დღე? რამდენიმე საკითხი ჯერ ყურადღებას ითხოვს.",
      checks: [["ღია მაგიდები", "მაგიდა 4, მაგიდა 9"], ["გატანის შეკვეთები", "#TA-1753 დაუსრულებელია"], ["Z-რეპორტი", "მზადაა"]],
      review: "მაგიდების ნახვა",
      hold: "მოცდა",
      waiting: "მენეჯერს ელოდება",
    },
    week: { head: "დახურული შეკვეთები დღეში", average: "სანიმუშო კვირა", days: ["ორშ", "სამ", "ოთხ", "ხუთ", "პარ", "შაბ", "კვი"] },
  },
  floor: { kicker: "დარბაზის გეგმა", title: ["დარბაზის გეგმა ", "ერთხელ", " შექმენი — სერვისი კი ყოველდღე მისით მართე."] },
  portal: { label: "[ რისთვის ვქმნით ]", statement: ["საუკეთესო ცვლა ის არის, ", "რომელზეც მეორე დილით არავინ ლაპარაკობს", "."] },
  reliable: {
    kicker: "საიმედოობა",
    title: ["", "მოსაწყენი", " იქ, სადაც ეს მნიშვნელოვანია."],
    body: "ოფლაინ სერვისი, დაცული დღის დახურვა და მოქმედებების ჟურნალი. ის, რასაც დემოზე არავინ აჩვენებს, მაგრამ შაბათ საღამოს სწორედ ეს წყვეტს.",
    offline: {
      title: "ყოველი ტერმინალი ოფლაინაც მუშაობს",
      body: "ინტერნეტის გათიშვისას შეკვეთები გრძელდება, კავშირის აღდგენისას კი ყველაფერი სინქრონდება.",
      nodes: ["POS 1", "POS 2", "სამზარეულო", "მენეჯერი"],
      footer: "შეკვეთები, გადახდები, ბეჭდვა, სინქრონი",
      state: ["ონლაინ", "ოფლაინ · რიგში"],
    },
    payments: {
      title: "გადახდები ადგილობრივად",
      body: "ნაღდი, საბანკო ტერმინალი და გაყოფილი გადახდა — GEL-ში, მომსახურების საფასურით ჩეკზე.",
      head: "საიდან შედგა დღევანდელი ჯამი",
      rows: [["ნაღდი", 46], ["ტერმინალი", 38], ["გაყოფილი", 16]],
      footer: "სანიმუშო საღამო · GEL",
    },
  },
  daily: {
    kicker: "დღის ხედი",
    title: ["", "პარასკევი", " Vynic-ის თვალით."],
    body: "ხედი, რომელსაც მენეჯერები ღიად ტოვებენ: ვინ ზის, რა არის გადახდილი და რა ელოდება პასუხს.",
    sample: "სანიმუშო საღამო",
    heat: { head: "ამ კვირაში, სტუმრები საათების მიხედვით", next: "შემდეგი ჯავშანი 12 წუთში", days: ["ორშ", "სამ", "ოთხ", "ხუთ", "პარ", "შაბ", "კვი"] },
    ring: { head: "დაკავებული მაგიდები", caption: "დარბაზის დაკავება 21:00-ზე" },
    guests: { head: "დღევანდელი ჯავშნები", count: "ჯავშანი", caption: "შემდეგი: 20:30 · 4 სტუმარი · მაგიდა 8" },
    pay: { head: "გადახდები", cash: "ნაღდი", card: "ტერმინალი" },
    room: { head: "დარბაზი ახლა", caption: "ყოველი მაგიდა თავის მდგომარეობას აჩვენებს" },
  },
  screens: { kicker: "ნამდვილი ეკრანები", title: ["POS, ", "ეკრანი ეკრანზე", "."], auto: "ავტო" },
  numbers: {
    kicker: "ადგილობრივი მორგება",
    title: ["შექმნილია იმ დეტალებისთვის, რომლებსაც მფლობელები ", "რეალურად", " მართავენ."],
    body: "გაბერილი მეტრიკების გარეშე. მხოლოდ ის, რაზეც ქართული რესტორნის დარბაზი ყოველ საღამოს დგას.",
    stats: [
      { value: 0, suffix: "", label: "ინტერნეტი, რომელიც შეკვეთის მისაღებად გჭირდება", tag: "ოფლაინ მუშაობა" },
      { value: 2, suffix: "", label: "ენა POS-სა და მენეჯერის აპში", tag: "ქართული · ინგლისური" },
      { value: 1, suffix: "", label: "ობიექტის ჩანაწერი POS-ის, მენეჯერისა და საიტის უკან", tag: "ერთი პლატფორმა" },
    ],
  },
  reservations: { kicker: "ჯავშნები", booking: "მაგიდა 8 · 20:30 · 4 სტუმარი" },
  manager: {
    kicker: "მენეჯერის აპი",
    title: ["სამუშაო დღე ", "შენს ჯიბეში", "."],
    tabs: ["დღეს", "მაგიდები", "ჯავშნები", "პერსონალი", "დახურვა"],
    hint: "დააჭირე, გადაფურცლე ან ისრებით მართე",
    soon: "ახალი ეკრანები მზადდება",
  },
  words: {
    kicker: "ერთი ცვლა",
    text: "Vynic ცვლას პირველი მაგიდიდან ბოლო ჩეკამდე მიჰყვება — დარბაზში, სამზარეულოში, მფლობელის ჯიბეში და რესტორნის საკუთარ ვებსაიტზე.",
    marquee: ["ოფლაინ მუშაობა", "ქართული და ინგლისური", "GEL", "მომსახურების საფასური", "Z-რეპორტი", "ბანკეტის მაგიდები", "დღის დახურვის კონტროლი", "მენეჯერის აპი", "ონლაინ ჯავშნები"],
  },
  contact: {
    kicker: "დემო", title: ["ნახე, როგორ იმუშავებს Vynic ", "შენს", " დარბაზში."],
    requestTitle: "დავიწყოთ შენი რესტორნით.",
    requestBody: "შემდეგ გვერდზე შეავსე მოკლე განაცხადი. მიღების შემდეგ ჩვენი გუნდი დაგიკავშირდება დემოს დასაგეგმად.",
    requestCta: "დემოსთვის განაცხადი",
  },
  footer: { line: "რესტორნის POS და ოპერაციები მაგიდებისთვის, ჯავშნებისთვის, გადახდებისთვის, დღის დახურვისა და მენეჯერის ხედვისთვის.", rights: "Vynic" },
};

export function getHomeCopy(locale: Locale): HomeCopy {
  return locale === "ka" ? ka : en;
}
