import type { WebsiteMenu, WebsiteSite } from "../api/types";

/** Two restaurants that must never appear on each other's page. */
export const siteA: WebsiteSite = {
  schemaVersion: 2,
  mode: "SAAS",
  preview: false,
  revision: 3,
  publishedAt: "2026-09-22T10:00:00.000Z",
  profile: {
    name: "Tabla",
    branchName: "Rustaveli",
    address: "12 Rustaveli Avenue, Tbilisi",
    phone: "+995 322 000 111",
    timezone: "Asia/Tbilisi",
    currency: "GEL",
  },
  content: {
    slug: "restaurant-a",
    themeKey: "classic",
    logoUrl: "/media/sample/logo-a.svg",
    heroTitle: "ტაბლა",
    heroSubtitle: "Georgian cooking in old Tbilisi",
    heroImageUrl: "/media/sample/hero-a.svg",
    about: "ოჯახური რესტორანი.\n\nA family kitchen.",
    aboutImageUrl: "",
    showMenu: true,
    menuHeading: "მენიუ",
    menuIntro: "",
    seoTitle: "Tabla — Georgian restaurant",
    seoDescription: "Khinkali and local wine.",
    contactEmail: "hello@tabla.test.invalid",
    mapUrl: "https://maps.example.invalid/tabla",
    footerNote: "Open every day",
    workingHours: [{ day: 1, opens: "11:00", closes: "01:00" }],
    socials: [{ label: "Instagram", url: "https://instagram.com/example" }],
    gallery: [{ url: "/media/sample/gallery-a-1.svg", alt: "Dining room" }],
  },
};

export const menuA: WebsiteMenu = {
  schemaVersion: 2,
  currency: "GEL",
  enabled: true,
  categories: [
    {
      id: "cat-1",
      slug: "khinkali",
      name: { ka: "ხინკალი", en: "Khinkali" },
      items: [
        {
          id: "item-1",
          name: { ka: "ხორცის ხინკალი", en: "Meat khinkali" },
          displayName: "Signature khinkali",
          description: "Hand folded",
          imageUrl: null,
          price: 2.5,
          variants: [],
        },
      ],
      subcategories: [
        {
          id: "sub-1",
          slug: "red",
          name: { ka: "წითელი", en: "Red" },
          items: [
            {
              id: "item-2",
              name: { ka: "საფერავი", en: "Saperavi" },
              displayName: null,
              description: null,
              imageUrl: null,
              price: 11,
              variants: [
                { id: "v1", size: 0.15, price: 6.6 },
                { id: "v2", size: 0.75, price: 33 },
              ],
            },
          ],
        },
      ],
    },
  ],
};

export const siteB: WebsiteSite = {
  ...siteA,
  revision: 1,
  profile: {
    ...siteA.profile,
    name: "Zghva",
    branchName: null,
    address: "4 Seaside Road, Batumi",
    phone: "+995 322 000 222",
  },
  content: {
    ...siteA.content,
    slug: "restaurant-b",
    heroTitle: "ზღვა",
    heroSubtitle: "Seafood in Batumi",
    about: "Harbour fish.",
    seoTitle: "Zghva — seafood",
    gallery: [],
    socials: [],
    logoUrl: "",
    heroImageUrl: "",
  },
};
