import type { CustomSiteBootstrap } from "../../../../packages/website-client/src/types";
export function vankisiSite(): CustomSiteBootstrap {
  return {
    schemaVersion: 1,
    mode: "CUSTOM",
    site: { key: "vankisi-web", status: "ACTIVE" },
    profile: {
      name: "Synthetic venue",
      branchName: null,
      address: "Synthetic Street 1",
      phone: "+995 599 98 93 76",
      timezone: "Asia/Tbilisi",
      currency: "GEL",
    },
    info: {
      contactEmail: "owner@test.invalid",
      mapUrl: "https://maps.test.invalid/owner",
      workingHours: [
        { day: 1, opens: "10:00", closes: "01:00" },
        { day: 5, opens: "12:00", closes: "23:00" },
      ],
      socials: [
        { label: "Instagram", url: "https://social.test.invalid/owner" },
      ],
      gallery: [{ url: "/media/synthetic-one.jpg", alt: "Owner photo one" }],
    },
    capabilities: {
      profile: true,
      menu: true,
      hours: true,
      gallery: true,
      customerAccounts: true,
      onlinePayments: true,
      reservations: true,
    },
  };
}
