import { useCallback, useEffect, useState } from "react";
import { customerApi } from "./api";

/**
 * The owner's website draft, shared by every dashboard section that edits it.
 *
 * Saving, reviewing and publishing stay three separate acts: a save changes
 * only the private draft, preview renders that draft in the real public
 * frontend, and publishing is the one explicit step that changes what visitors
 * see. `expectedRevision` travels with every write, so an edit made in another
 * session is refused instead of being silently overwritten.
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
export type WebsiteSettings = {
  mediaUploadAllowed?: boolean;
  schemaVersion: number;
  themeKeys: string[];
  mode: "NONE" | "CUSTOM" | "SAAS";
  entitled: boolean;
  status: "DRAFT" | "PUBLISHED";
  revision: number;
  publishedRevision: number | null;
  publishedAt: string | null;
  hasUnpublishedChanges: boolean;
  draft: WebsiteContent;
  baseDomain: string | null;
  domains: string[];
  publishedSlug: string | null;
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

export function websiteAddress(settings: WebsiteSettings, slug?: string) {
  return `${slug || settings.draft.slug || "…"}.${settings.baseDomain || "…"}`;
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
    setDraft(s.draft);
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
    if (settings) setDraft(settings.draft);
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
      accept(
        await customerApi<WebsiteSettings>(
          `${path}/${kind === "save" ? "draft" : "publish"}`,
          {
            expectedRevision: settings.revision,
            ...(kind === "save"
              ? {
                  content: {
                    ...draft,
                    mapUrl: normalizeLink(draft.mapUrl),
                    socials: draft.socials.map((s) => ({
                      ...s,
                      url: normalizeLink(s.url),
                    })),
                  },
                }
              : {}),
          },
          kind === "save" ? "PUT" : "POST",
        ),
      );
      setMessage(
        kind === "save"
          ? "ცვლილებები შენახულია. საჯარო გვერდი შეიცვლება გამოქვეყნების შემდეგ."
          : "ვებსაიტი გამოქვეყნებულია.",
      );
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
