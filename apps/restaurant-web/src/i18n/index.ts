/**
 * Two languages, one page.
 *
 * Restaurant-authored content (hero, about, menu overrides) is written once by
 * the owner and shown as written; only the frame around it — navigation,
 * labels, day names, states — is translated. Georgian is the default because
 * that is the market these restaurants serve, with English available for
 * visitors.
 */
export const languages = ["ka", "en"] as const;
export type Language = (typeof languages)[number];
export const defaultLanguage: Language = "ka";
const STORAGE_KEY = "vynic-website-language";

export interface Strings {
  nav: {
    about: string;
    menu: string;
    gallery: string;
    hours: string;
    contact: string;
  };
  skipToContent: string;
  openMenu: string;
  closeMenu: string;
  languageLabel: string;
  languageNames: Record<Language, string>;
  hours: { title: string; closed: string; nextDay: string; empty: string };
  menu: { title: string; empty: string; from: string; unavailable: string };
  gallery: { title: string };
  about: { title: string };
  contact: {
    title: string;
    address: string;
    phone: string;
    email: string;
    directions: string;
    follow: string;
  };
  days: string[];
  preview: {
    badge: string;
    explanation: string;
    exit: string;
  };
  missing: { title: string; body: string };
  pending: { title: string; body: string };
  address: { title: string; body: string };
  goToVynic: string;
  unavailable: { title: string; body: string };
  custom: { title: string; body: string };
  unsupported: { title: string; body: string };
  error: { title: string; body: string; retry: string };
  loading: string;
}

const ka: Strings = {
  nav: {
    about: "ჩვენ შესახებ",
    menu: "მენიუ",
    gallery: "გალერეა",
    hours: "სამუშაო საათები",
    contact: "კონტაქტი",
  },
  skipToContent: "გადასვლა მთავარ შინაარსზე",
  openMenu: "ნავიგაციის გახსნა",
  closeMenu: "ნავიგაციის დახურვა",
  languageLabel: "ენა",
  languageNames: { ka: "ქართული", en: "English" },
  hours: {
    title: "სამუშაო საათები",
    closed: "დაკეტილია",
    nextDay: "მეორე დღეს",
    empty: "სამუშაო საათები მალე დაემატება.",
  },
  menu: {
    title: "მენიუ",
    empty: "მენიუ მალე დაემატება.",
    from: "-დან",
    unavailable: "მენიუ ამჟამად ვერ ჩაიტვირთა.",
  },
  gallery: { title: "გალერეა" },
  about: { title: "ჩვენ შესახებ" },
  contact: {
    title: "კონტაქტი",
    address: "მისამართი",
    phone: "ტელეფონი",
    email: "ელფოსტა",
    directions: "რუკაზე ნახვა",
    follow: "სოციალური ქსელები",
  },
  days: [
    "ორშაბათი",
    "სამშაბათი",
    "ოთხშაბათი",
    "ხუთშაბათი",
    "პარასკევი",
    "შაბათი",
    "კვირა",
  ],
  preview: {
    badge: "მონახაზის წინასწარი ნახვა",
    explanation:
      "ეს არის შენახული მონახაზი. საჯარო გვერდი არ შეცვლილა, სანამ არ გამოაქვეყნებთ.",
    exit: "წინასწარი ნახვიდან გასვლა",
  },
  missing: {
    title: "მითითებული რესტორანი ვერ მოიძებნა",
    body: "გადაამოწმეთ მისამართი. ამ მისამართზე ხელმისაწვდომი რესტორნის გვერდი არ არის.",
  },
  pending: {
    title: "გვერდი ჯერ არ გამოქვეყნებულა",
    body: "რესტორნის გვერდი მზადდება. გთხოვთ, მოგვიანებით სცადოთ.",
  },
  address: {
    title: "გახსენით რესტორნის მისამართი",
    body: "რესტორნის სანახავად გამოიყენეთ მისი პირადი ვებმისამართი. ეს Vynic-ის საერთო მისამართია.",
  },
  goToVynic: "Vynic-ზე გადასვლა",
  unavailable: {
    title: "გვერდი ხელმისაწვდომი არ არის",
    body: "წინასწარი ნახვის ბმული მიუწვდომელია ან ვადა გაუვიდა. გახსენით ახალი ბმული თქვენი პანელიდან.",
  },
  custom: {
    title: "ინდივიდუალური ვებსაიტი",
    body: "ამ რესტორანს ინდივიდუალური ვებსაიტი აქვს და ის ცალკე იმართება.",
  },
  unsupported: {
    title: "გვერდი ვერ გამოისახა",
    body: "ვებსაიტის ვერსია ამ აპლიკაციას არ შეესაბამება.",
  },
  error: {
    title: "სერვისი დროებით მიუწვდომელია",
    body: "გვერდი ვერ ჩაიტვირთა.",
    retry: "ხელახლა ცდა",
  },
  loading: "იტვირთება…",
};

const en: Strings = {
  nav: {
    about: "About",
    menu: "Menu",
    gallery: "Gallery",
    hours: "Hours",
    contact: "Contact",
  },
  skipToContent: "Skip to main content",
  openMenu: "Open navigation",
  closeMenu: "Close navigation",
  languageLabel: "Language",
  languageNames: { ka: "ქართული", en: "English" },
  hours: {
    title: "Opening hours",
    closed: "Closed",
    nextDay: "next day",
    empty: "Opening hours are coming soon.",
  },
  menu: {
    title: "Menu",
    empty: "The menu is coming soon.",
    from: "from",
    unavailable: "The menu could not be loaded right now.",
  },
  gallery: { title: "Gallery" },
  about: { title: "About" },
  contact: {
    title: "Contact",
    address: "Address",
    phone: "Phone",
    email: "Email",
    directions: "View on map",
    follow: "Follow",
  },
  days: [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ],
  preview: {
    badge: "Draft preview",
    explanation:
      "This is the saved draft. The public page does not change until you publish.",
    exit: "Leave preview",
  },
  missing: {
    title: "Restaurant not found",
    body: "No restaurant website is available at this address. Please check the address.",
  },
  pending: {
    title: "This website is not published yet",
    body: "The restaurant website is being prepared. Please check back later.",
  },
  address: {
    title: "Open the restaurant’s address",
    body: "Use the restaurant’s own web address to visit its website. This is the shared Vynic address.",
  },
  goToVynic: "Go to Vynic",
  unavailable: {
    title: "This page is not available",
    body: "This preview link is unavailable or has expired. Open a new preview from your dashboard.",
  },
  custom: {
    title: "Custom website",
    body: "This restaurant runs a custom website, managed separately.",
  },
  unsupported: {
    title: "This page could not be rendered",
    body: "The published website version does not match this application.",
  },
  error: {
    title: "Service temporarily unavailable",
    body: "The page could not be loaded.",
    retry: "Try again",
  },
  loading: "Loading…",
};

export const strings: Record<Language, Strings> = { ka, en };

export function storedLanguage(storage: Storage | undefined): Language {
  try {
    const value = storage?.getItem(STORAGE_KEY);
    if (value && (languages as readonly string[]).includes(value))
      return value as Language;
  } catch {
    // A visitor who blocks storage simply gets the default language.
  }
  return defaultLanguage;
}
export function rememberLanguage(
  storage: Storage | undefined,
  value: Language,
) {
  try {
    storage?.setItem(STORAGE_KEY, value);
  } catch {
    // Not remembering the choice is better than failing to apply it.
  }
}

/** The visitor's language, used only to pick between the two authored names. */
export function localized(
  name: { ka: string; en: string },
  language: Language,
) {
  return (language === "ka" ? name.ka : name.en) || name.en || name.ka;
}
