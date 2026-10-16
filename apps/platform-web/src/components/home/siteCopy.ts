import type { Locale } from "../../lib/i18n";
import type { Accented } from "./homeCopy";

/** Copy for the multi-page site: page heroes, the home "shift" scene, doors and hand-offs. */
export type PageKey = "home" | "pos" | "manager" | "floor" | "reservations";

export type SiteCopy = {
  pages: Record<Exclude<PageKey, "home">, { path: string; nav: string; kicker: string; title: Accented; body: string; door: string; preview: string }>;
  shift: { kicker: string; words: string[]; captions: string[] };
  explore: { kicker: string; title: Accented; open: string };
  next: string;
  backHome: string;
  floorScene: { kicker: string; steps: string[] };
  booking: {
    kicker: string;
    title: Accented;
    body: string;
    site: string;
    open: string;
    guests: string;
    time: string;
    table: string;
    name: string;
    book: string;
    sent: string;
    pos: string;
    incoming: string;
    seat: string;
    preorder: string;
  };
};

const en: SiteCopy = {
  pages: {
    pos: {
      path: "pos",
      nav: "POS",
      kicker: "vynic pos",
      title: ["Built for ", "the rush", "."],
      body: "Tables, orders, payments and day close on one offline-first POS. Every screen below is the real app.",
      door: "Run the room from the real floor, then close the day without surprises.",
      preview: "5 real screens",
    },
    manager: {
      path: "manager",
      nav: "Manager app",
      kicker: "manager app",
      title: ["The business day, ", "in your pocket", "."],
      body: "Owners and managers follow tables, bookings, staff and close-day from their phone.",
      door: "Tables, bookings, staff and close-day — from the phone in your pocket.",
      preview: "5 views",
    },
    floor: {
      path: "floor-plan",
      nav: "Floor plan",
      kicker: "floor plan",
      title: ["Draw the room ", "once", ". Run every shift from it."],
      body: "Tables, objects and zones in one editor. The same layout becomes the working floor on the POS.",
      door: "Draw the real room once. The POS runs service on it every day.",
      preview: "live editor",
    },
    reservations: {
      path: "reservations",
      nav: "Reservations",
      kicker: "reservations",
      title: ["Online bookings that land ", "as work", "."],
      body: "Guests book on the restaurant's website; the booking arrives on the POS with the table, time and any preorder.",
      door: "From the guest's phone to the POS floor, with the table already chosen.",
      preview: "try a booking",
    },
  },
  shift: {
    kicker: "one shift, four moves",
    words: ["Seat.", "Order.", "Pay.", "Close."],
    captions: [
      "The floor shows every table's state before anyone opens a check.",
      "Items, service fee and the running total stay on one check.",
      "Cash, Bank POS or split — chosen on the same screen.",
      "Open tables and the Z report are checked before the date moves.",
    ],
  },
  explore: { kicker: "explore vynic", title: ["Four parts of ", "one platform", "."], open: "Open" },
  next: "Next",
  backHome: "Vynic home",
  floorScene: { kicker: "from room to screen", steps: ["The real room", "Seen from above", "Ready for service"] },
  booking: {
    kicker: "try it",
    title: ["Book a table — ", "watch it arrive", "."],
    body: "This is the guest side of a Vynic restaurant website. Pick a time and a table and send it to the POS.",
    site: "Demo Bistro",
    open: "Open today 12:00–23:00",
    guests: "Guests",
    time: "Time",
    table: "Table",
    name: "Nino",
    book: "Book the table",
    sent: "Sent to the restaurant",
    pos: "Vynic POS · reservations",
    incoming: "New reservation",
    seat: "Seat guests",
    preorder: "Preorder attached",
  },
};

const ka: SiteCopy = {
  pages: {
    pos: {
      path: "pos",
      nav: "POS",
      kicker: "vynic pos",
      title: ["შექმნილია ", "დატვირთული სერვისისთვის", "."],
      body: "მაგიდები, შეკვეთები, გადახდები და დღის დახურვა ერთ ოფლაინ POS-ში. ქვემოთ ყველა ეკრანი ნამდვილი აპიდანაა.",
      door: "მართე დარბაზი ნამდვილი გეგმიდან და დახურე დღე სიურპრიზების გარეშე.",
      preview: "5 ნამდვილი ეკრანი",
    },
    manager: {
      path: "manager",
      nav: "მენეჯერის აპი",
      kicker: "მენეჯერის აპი",
      title: ["სამუშაო დღე ", "შენს ჯიბეში", "."],
      body: "მფლობელები და მენეჯერები ტელეფონიდან ადევნებენ თვალს მაგიდებს, ჯავშნებს, პერსონალს და დღის დახურვას.",
      door: "მაგიდები, ჯავშნები, პერსონალი და დახურვა — ჯიბეში არსებული ტელეფონიდან.",
      preview: "5 ხედი",
    },
    floor: {
      path: "floor-plan",
      nav: "დარბაზის გეგმა",
      kicker: "დარბაზის გეგმა",
      title: ["დარბაზი ", "ერთხელ", " დახატე — ყველა ცვლა მისით მართე."],
      body: "მაგიდები, ობიექტები და ზონები ერთ რედაქტორში. იგივე გეგმა POS-ზე სამუშაო დარბაზი ხდება.",
      door: "ნამდვილი დარბაზი ერთხელ დახატე — POS მასზე ყოველდღე იმუშავებს.",
      preview: "ცოცხალი რედაქტორი",
    },
    reservations: {
      path: "reservations",
      nav: "ჯავშნები",
      kicker: "ჯავშნები",
      title: ["ონლაინ ჯავშანი, რომელიც ", "სამუშაოდ", " ჩამოდის."],
      body: "სტუმარი რესტორნის საიტზე ჯავშნის; ჯავშანი POS-ში მაგიდით, დროით და წინასწარი შეკვეთით ჩამოდის.",
      door: "სტუმრის ტელეფონიდან POS-ის დარბაზამდე, უკვე არჩეული მაგიდით.",
      preview: "სცადე ჯავშანი",
    },
  },
  shift: {
    kicker: "ერთი ცვლა, ოთხი ნაბიჯი",
    words: ["დასვი.", "შეუკვეთე.", "გადაიხადე.", "დახურე."],
    captions: [
      "დარბაზი ყველა მაგიდის მდგომარეობას აჩვენებს, სანამ ჩეკს გახსნი.",
      "პოზიციები, მომსახურება და ჯამი ერთ ჩეკზე რჩება.",
      "ნაღდი, ტერმინალი თუ გაყოფილი — იმავე ეკრანზე.",
      "ღია მაგიდები და Z-რეპორტი თარიღის შეცვლამდე მოწმდება.",
    ],
  },
  explore: { kicker: "გაიცანი vynic", title: ["", "ერთი პლატფორმის", " ოთხი ნაწილი."], open: "გახსნა" },
  next: "შემდეგი",
  backHome: "Vynic მთავარი",
  floorScene: { kicker: "დარბაზიდან ეკრანამდე", steps: ["ნამდვილი დარბაზი", "ზემოდან დანახული", "მზადაა სერვისისთვის"] },
  booking: {
    kicker: "სცადე",
    title: ["დაჯავშნე მაგიდა — ", "ნახე, როგორ ჩამოვა", "."],
    body: "ეს Vynic-ის რესტორნის საიტის სტუმრის მხარეა. აირჩიე დრო და მაგიდა და გაგზავნე POS-ში.",
    site: "Demo Bistro",
    open: "ღიაა დღეს 12:00–23:00",
    guests: "სტუმარი",
    time: "დრო",
    table: "მაგიდა",
    name: "ნინო",
    book: "მაგიდის დაჯავშნა",
    sent: "რესტორანს გაეგზავნა",
    pos: "Vynic POS · ჯავშნები",
    incoming: "ახალი ჯავშანი",
    seat: "სტუმრების დასმა",
    preorder: "წინასწარი შეკვეთა თან ერთვის",
  },
};

export function getSiteCopy(locale: Locale): SiteCopy {
  return locale === "ka" ? ka : en;
}

export const PAGE_ORDER: Array<Exclude<PageKey, "home">> = ["pos", "manager", "floor", "reservations"];
