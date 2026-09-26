import { useCallback, useEffect, useState } from "react";
import { customerApi } from "./api";

/**
 * The owner's website edits, shared by every dashboard section that makes them.
 *
 * Two kinds of data are edited together but saved apart. Venue public
 * information (hours, contact, socials, gallery) is restaurant data every
 * website reads, SAAS or CUSTOM: saving it is live. The SAAS page (hero, about,
 * design, SEO) is a private draft: preview renders it in the real frontend and
 * publishing is the one step that shows it. Both writes carry their own
 * expected revision, so an edit made in another session is refused instead of
 * being silently overwritten.
 */
export type WebsiteContent = {
  slug: string;
  themeKey: string;
  logoUrl: string;
  heroTitle: string;
  heroSubtitle: string;
  heroImageUrl: string;
  about: string;
  aboutImageUrl: string;
  showMenu: boolean;
  menuHeading: string;
  menuIntro: string;
  seoTitle: string;
  seoDescription: string;
  contactEmail: string;
  mapUrl: string;
  showMap?: boolean;
  footerNote: string;
  workingHours: { day: number; opens: string; closes: string }[];
  socials: { label: string; url: string }[];
  gallery: { url: string; alt: string }[];
};
/** Venue public information: saved live, identical for SAAS and CUSTOM. */
export const sharedKeys = [
  "workingHours",
  "contactEmail",
  "mapUrl",
  "socials",
  "gallery",
] as const;
type SharedKey = (typeof sharedKeys)[number];
export type WebsiteShared = Pick<WebsiteContent, SharedKey> & {
  revision: number;
};
export type WebsiteCapabilityKey =
  | "MENU"
  | "HOURS"
  | "RESERVATIONS"
  | "GALLERY"
  | "CUSTOMER_ACCOUNTS"
  | "ONLINE_PAYMENTS"
  | "EVENTS"
  | "BANQUETS"
  | "ONLINE_ORDERING";
export type WebsiteCapability = {
  key: WebsiteCapabilityKey;
  label: string;
  built: boolean;
  /** Included in the package and switched on for this Venue. */
  available: boolean;
  ready: boolean;
  live: boolean;
};
export type WebsiteSettings = {
  commercialStatus?: string;
  /** The server-owned SaaS address; null outside SAAS. */
  hostname?: string | null;
  pendingHostnameRequest?: { hostname: string; createdAt: string } | null;
  hostnameChangeAllowed?: boolean;
  mediaUploadAllowed?: boolean;
  schemaVersion: number;
  themeKeys: string[];
  mode: "NONE" | "CUSTOM" | "SAAS";
  entitled: boolean;
  state: "NOT_ENTITLED" | "SETUP_PENDING" | "SAAS" | "CUSTOM";
  status: "DRAFT" | "PUBLISHED";
  revision: number;
  publishedRevision: number | null;
  publishedAt: string | null;
  hasUnpublishedChanges: boolean;
  /** The SAAS page document; Venue public information lives in `shared`. */
  draft: Omit<WebsiteContent, SharedKey>;
  shared: WebsiteShared;
  capabilities: WebsiteCapability[];
  baseDomain: string | null;
  domains: string[];
  publishedSlug: string | null;
  /** Operator-tracked setup of a CUSTOM site; null outside CUSTOM. */
  custom?: {
    status: "NOT_CONFIGURED" | "SETUP_PENDING" | "READY" | "ACTIVE" | "ERROR";
  } | null;
};
type PreviewSession = {
  token: string;
  expiresAt: string;
  previewOrigin: string | null;
};
export type Website = ReturnType<typeof useWebsite>;

export function normalizeLink(value: string) {
  const trimmed = value.trim();
  if (
    !trimmed ||
    trimmed.startsWith("/media/") ||
    /^[a-z][a-z0-9+.-]*:/i.test(trimmed)
  )
    return trimmed;
  return `https://${trimmed}`;
}

/** Whether the owner still has to finish the three first-run essentials. */
export function needsFirstRun(settings?: WebsiteSettings) {
  return (
    settings?.mode === "SAAS" && (!settings.revision || !settings.draft.slug)
  );
}

export function websiteAddress(settings: WebsiteSettings) {
  return (
    settings.hostname ??
    `${settings.draft.slug || "…"}.${settings.baseDomain || "…"}`
  );
}

/** The one editable view of a settings answer: page draft plus public info. */
function editable(s: WebsiteSettings): WebsiteContent {
  const shared = Object.fromEntries(sharedKeys.map((k) => [k, s.shared[k]]));
  return { ...s.draft, ...shared } as WebsiteContent;
}

/** Order-insensitive equality of JSON values: key order is not a change. */
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((k) => [k, canonical((value as Record<string, unknown>)[k])]),
    );
  return value;
}
const same = (a: unknown, b: unknown) =>
  JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));

/** Whether a shared website capability can be managed for this Venue now. */
export function capabilityAvailable(
  settings: WebsiteSettings | undefined,
  key: WebsiteCapabilityKey,
) {
  // No website provisioned yet: nothing to manage for it, in either mode.
  if (!settings || settings.mode === "NONE") return false;
  return !!settings.capabilities?.some((c) => c.key === key && c.available);
}

export function useWebsite(venueId: string | undefined) {
  const [settings, setSettings] = useState<WebsiteSettings>();
  const [draft, setDraft] = useState<WebsiteContent>();
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  // Which restaurant the held state belongs to; anything else reads as unloaded.
  const [loadedFor, setLoadedFor] = useState<string>();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const path = `venues/${venueId}/website`;

  const accept = (s: WebsiteSettings) => {
    setSettings(s);
    setDraft(editable(s));
    setDirty(false);
    setMessage("");
  };
  const load = useCallback(async () => {
    if (!venueId) return;
    setBusy(true);
    setError("");
    try {
      accept(await customerApi<WebsiteSettings>(path));
    } catch {
      setError("ვებსაიტის მონაცემები ვერ ჩაიტვირთა. სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
      setLoadedFor(venueId);
    }
  }, [path, venueId]);
  useEffect(() => {
    void load();
  }, [load]);
  const current = !!venueId && loadedFor === venueId;

  const edit = (patch: Partial<WebsiteContent>) => {
    setDraft((d) => d && { ...d, ...patch });
    setDirty(true);
    setMessage("");
  };
  const discard = () => {
    if (settings) setDraft(editable(settings));
    setDirty(false);
    setError("");
  };

  const act = async (kind: "save" | "publish") => {
    if (!settings || !draft) return false;
    if (kind === "save") {
      const links = [draft.mapUrl, ...draft.socials.map((s) => s.url)].filter(
        Boolean,
      );
      const valid = links.every((value) => {
        try {
          const url = new URL(normalizeLink(value));
          return url.protocol === "https:" && !url.username && !url.password;
        } catch {
          return false;
        }
      });
      if (!valid) {
        setError(
          "ბმული ვერ ამოვიცანით. გახსენით გვერდი და ხელახლა დააკოპირეთ მისი ბმული.",
        );
        return false;
      }
    }
    setBusy(true);
    setError("");
    setMessage("");
    try {
      if (kind === "publish") {
        accept(
          await customerApi<WebsiteSettings>(
            `${path}/publish`,
            { expectedRevision: settings.revision },
            "POST",
          ),
        );
        setMessage("ვებსაიტი გამოქვეყნებულია.");
      } else {
        const normalized: WebsiteContent = {
          ...draft,
          mapUrl: normalizeLink(draft.mapUrl),
          socials: draft.socials.map((s) => ({
            ...s,
            url: normalizeLink(s.url),
          })),
        };
        let latest = settings;
        const shared: Partial<WebsiteContent> = {};
        for (const key of sharedKeys)
          if (!same(normalized[key], settings.shared[key]))
            Object.assign(shared, { [key]: normalized[key] });
        const sharedChanged = Object.keys(shared).length > 0;
        if (sharedChanged) {
          latest = await customerApi<WebsiteSettings>(
            `${path}/public-info`,
            { expectedRevision: settings.shared.revision, ...shared },
            "PUT",
          );
          // Already live: a failing page save below must not resend it.
          setSettings(latest);
        }
        const page = Object.fromEntries(
          Object.entries(normalized).filter(
            ([key]) => !(sharedKeys as readonly string[]).includes(key),
          ),
        );
        const pageChanged =
          settings.mode === "SAAS" && !same(page, settings.draft);
        if (pageChanged)
          latest = await customerApi<WebsiteSettings>(
            `${path}/draft`,
            { expectedRevision: latest.revision, content: page },
            "PUT",
          );
        accept(latest);
        setMessage(
          pageChanged
            ? sharedChanged
              ? "ცვლილებები შენახულია. საათები, კონტაქტები და გალერეა საიტზე უკვე ჩანს; დანარჩენი — გამოქვეყნების შემდეგ."
              : "ცვლილებები შენახულია. საჯარო გვერდი შეიცვლება გამოქვეყნების შემდეგ."
            : "ცვლილებები შენახულია და საიტზე უკვე ჩანს.",
        );
      }
      // A confirmation, not a state: it should not linger over later work.
      setTimeout(() => setMessage(""), 4000);
      return true;
    } catch {
      setError(
        "მოქმედება ვერ შესრულდა. შეამოწმეთ ველები და ვებსაიტის მისამართი. თუ სხვა ფანჯარაში შეცვალეთ მონაცემები, განაახლეთ გვერდი.",
      );
      return false;
    } finally {
      setBusy(false);
    }
  };

  /**
   * Open the saved draft in the real restaurant frontend.
   *
   * The short-lived token goes in the URL fragment, which browsers never send
   * to a server, so preview authority does not end up in request logs.
   */
  const preview = async () => {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      const session = await customerApi<PreviewSession>(
        `${path}/preview-session`,
        {},
      );
      if (!session.previewOrigin) {
        setError(
          "წინასწარი ნახვა ამ გარემოში არ არის ხელმისაწვდომი. დაუკავშირდით Vynic-ს.",
        );
        return;
      }
      window.open(
        `${session.previewOrigin}/preview#token=${encodeURIComponent(session.token)}`,
        "_blank",
        "noopener,noreferrer",
      );
      setMessage("ვებსაიტი გაიხსნა ახალ ფანჯარაში.");
    } catch {
      setError("ვებსაიტის ნახვა ვერ მოხერხდა. სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
    }
  };

  return {
    venueId: venueId ?? "",
    settings: current ? settings : undefined,
    draft: current ? draft : undefined,
    dirty: current && dirty,
    busy,
    loaded: current,
    error: current ? error : "",
    message: current ? message : "",
    setBusy,
    load,
    edit,
    discard,
    save: () => act("save"),
    publish: () => act("publish"),
    preview,
  };
}
