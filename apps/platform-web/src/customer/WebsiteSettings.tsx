import { useEffect, useState } from "react";
import { customerApi } from "./api";
import { WebsiteMenuEditor } from "./WebsiteMenuEditor";

/**
 * The owner's website workspace.
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
  footerNote: string;
  workingHours: { day: number; opens: string; closes: string }[];
  socials: { label: string; url: string }[];
  gallery: { url: string; alt: string }[];
};
type Settings = {
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

const days = [
  "ორშაბათი",
  "სამშაბათი",
  "ოთხშაბათი",
  "ხუთშაბათი",
  "პარასკევი",
  "შაბათი",
  "კვირა",
];
const themeNames: Record<string, string> = { classic: "კლასიკური" };

/**
 * One section at a time.
 *
 * The whole website is too much for a single form, and a wizard would force an
 * order that does not match how a restaurant actually fills a site in, so the
 * sections are addressable and the draft is shared across all of them.
 */
const sections = [
  ["general", "ზოგადი"],
  ["hero", "მთავარი ბლოკი"],
  ["about", "ჩვენ შესახებ"],
  ["theme", "თემა"],
  ["menu", "მენიუ"],
  ["gallery", "გალერეა"],
  ["hours", "სამუშაო საათები"],
  ["socials", "ბმულები"],
  ["seo", "საძიებო სისტემები"],
  ["publishing", "პუბლიკაცია"],
] as const;
type SectionKey = (typeof sections)[number][0];

export function WebsiteSettings({ venueId }: { venueId: string }) {
  const [settings, setSettings] = useState<Settings>();
  const [draft, setDraft] = useState<WebsiteContent>();
  const [section, setSection] = useState<SectionKey>("general");
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const path = `venues/${venueId}/website`;

  const accept = (s: Settings) => {
    setSettings(s);
    setDraft(s.draft);
    setDirty(false);
  };
  const load = async () => {
    setBusy(true);
    setError("");
    try {
      accept(await customerApi<Settings>(path));
    } catch {
      setError("ვებსაიტის მონაცემები ვერ ჩაიტვირთა. სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, [venueId]);

  const edit = (patch: Partial<WebsiteContent>) => {
    setDraft((d) => d && { ...d, ...patch });
    setDirty(true);
    setMessage("");
  };

  const act = async (kind: "save" | "publish") => {
    if (!settings || !draft) return;
    setBusy(true);
    setError("");
    setMessage("");
    try {
      accept(
        await customerApi<Settings>(
          `${path}/${kind === "save" ? "draft" : "publish"}`,
          {
            expectedRevision: settings.revision,
            ...(kind === "save" ? { content: draft } : {}),
          },
          kind === "save" ? "PUT" : "POST",
        ),
      );
      setMessage(
        kind === "save"
          ? "მონახაზი შენახულია. საჯარო გვერდი არ შეცვლილა."
          : "ვებსაიტი გამოქვეყნებულია.",
      );
    } catch {
      setError(
        "მოქმედება ვერ შესრულდა. შეამოწმეთ ველები, მისამართის ხელმისაწვდომობა და ვებსაიტის წვდომა. თუ სხვა სესიაში შეცვალეთ მონაცემები, გადატვირთეთ ფორმა.",
      );
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
          "წინასწარი ნახვის მისამართი ამ გარემოში არ არის კონფიგურირებული. დაუკავშირდით Vynic-ს.",
        );
        return;
      }
      window.open(
        `${session.previewOrigin}/preview#token=${encodeURIComponent(session.token)}`,
        "_blank",
        "noopener,noreferrer",
      );
      setMessage("მონახაზი გაიხსნა ახალ ფანჯარაში.");
    } catch {
      setError("წინასწარი ნახვა ვერ გაიხსნა. სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
    }
  };

  const saas = settings?.mode === "SAAS" && !!draft;
  return (
    <section aria-labelledby="website-settings-title">
      <h2 id="website-settings-title">ვებსაიტი</h2>
      {!settings && !error && <p role="status">იტვირთება…</p>}
      {settings && <Status settings={settings} />}

      {saas && draft && settings && (
        <>
          <nav aria-label="ვებსაიტის პარამეტრების განყოფილებები">
            {sections.map(([key, label]) => (
              <button
                key={key}
                type="button"
                aria-current={section === key ? "true" : undefined}
                className={section === key ? "" : "secondary"}
                onClick={() => setSection(key)}
              >
                {label}
              </button>
            ))}
          </nav>

          <form
            onSubmit={(e) => {
              e.preventDefault();
              void act("save");
            }}
          >
            {section === "general" && (
              <fieldset disabled={busy}>
                <legend>ზოგადი</legend>
                <label>
                  მისამართის სახელი
                  <input
                    required
                    maxLength={48}
                    pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
                    value={draft.slug}
                    onChange={(e) => edit({ slug: e.target.value })}
                  />
                </label>
                <small>
                  {draft.slug || "restaurant"}.{settings.baseDomain || "…"}
                </small>
                <label>
                  საკონტაქტო ელფოსტა
                  <input
                    type="email"
                    maxLength={254}
                    value={draft.contactEmail}
                    onChange={(e) => edit({ contactEmail: e.target.value })}
                  />
                </label>
                <label>
                  რუკის ბმული (https://)
                  <input
                    type="url"
                    maxLength={2048}
                    value={draft.mapUrl}
                    onChange={(e) => edit({ mapUrl: e.target.value })}
                  />
                </label>
                <label>
                  ქვედა კოლონტიტულის ტექსტი
                  <input
                    maxLength={240}
                    value={draft.footerNote}
                    onChange={(e) => edit({ footerNote: e.target.value })}
                  />
                </label>
                <p>
                  რესტორნის სახელი, ფილიალი, მისამართი და ტელეფონი აღებულია
                  რესტორნის პროფილიდან და აქ არ დუბლირდება.
                </p>
              </fieldset>
            )}

            {section === "hero" && (
              <fieldset disabled={busy}>
                <legend>მთავარი ბლოკი</legend>
                <label>
                  მთავარი სათაური
                  <input
                    required
                    maxLength={160}
                    value={draft.heroTitle}
                    onChange={(e) => edit({ heroTitle: e.target.value })}
                  />
                </label>
                <label>
                  ქვესათაური
                  <input
                    maxLength={400}
                    value={draft.heroSubtitle}
                    onChange={(e) => edit({ heroSubtitle: e.target.value })}
                  />
                </label>
                <MediaField
                  label="მთავარი ფოტო"
                  value={draft.heroImageUrl}
                  onChange={(heroImageUrl) => edit({ heroImageUrl })}
                />
              </fieldset>
            )}

            {section === "about" && (
              <fieldset disabled={busy}>
                <legend>ჩვენ შესახებ</legend>
                <label>
                  ტექსტი
                  <textarea
                    rows={8}
                    maxLength={5000}
                    value={draft.about}
                    onChange={(e) => edit({ about: e.target.value })}
                  />
                </label>
                <small>
                  ცარიელი ხაზი ყოფს აბზაცებს. პირველი მოკლე ხაზი გამოჩნდება
                  სათაურად.
                </small>
                <MediaField
                  label="ფოტო"
                  value={draft.aboutImageUrl}
                  onChange={(aboutImageUrl) => edit({ aboutImageUrl })}
                />
              </fieldset>
            )}

            {section === "theme" && (
              <fieldset disabled={busy}>
                <legend>თემა</legend>
                <label>
                  თემა
                  <select
                    value={draft.themeKey}
                    onChange={(e) => edit({ themeKey: e.target.value })}
                  >
                    {settings.themeKeys.map((key) => (
                      <option key={key} value={key}>
                        {themeNames[key] ?? key}
                      </option>
                    ))}
                  </select>
                </label>
                <MediaField
                  label="ლოგო"
                  value={draft.logoUrl}
                  onChange={(logoUrl) => edit({ logoUrl })}
                />
              </fieldset>
            )}

            {section === "menu" && (
              <fieldset disabled={busy}>
                <legend>მენიუ</legend>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.showMenu}
                    onChange={(e) => edit({ showMenu: e.target.checked })}
                  />
                  მენიუ გამოჩნდეს საიტზე
                </label>
                <label>
                  განყოფილების სათაური
                  <input
                    maxLength={80}
                    value={draft.menuHeading}
                    onChange={(e) => edit({ menuHeading: e.target.value })}
                  />
                </label>
                <label>
                  მოკლე ტექსტი
                  <input
                    maxLength={400}
                    value={draft.menuIntro}
                    onChange={(e) => edit({ menuIntro: e.target.value })}
                  />
                </label>
              </fieldset>
            )}

            {section === "gallery" && (
              <fieldset disabled={busy}>
                <legend>გალერეა</legend>
                {draft.gallery.map((photo, i) => (
                  <div className="website-entry" key={i}>
                    <MediaField
                      label="ფოტო"
                      value={photo.url}
                      required
                      onChange={(url) =>
                        edit({
                          gallery: draft.gallery.map((p, j) =>
                            i === j ? { ...p, url } : p,
                          ),
                        })
                      }
                    />
                    <label>
                      ფოტოს აღწერა
                      <input
                        maxLength={200}
                        value={photo.alt}
                        onChange={(e) =>
                          edit({
                            gallery: draft.gallery.map((p, j) =>
                              i === j ? { ...p, alt: e.target.value } : p,
                            ),
                          })
                        }
                      />
                    </label>
                    <button
                      type="button"
                      className="secondary"
                      onClick={() =>
                        edit({
                          gallery: draft.gallery.filter((_, j) => i !== j),
                        })
                      }
                    >
                      ფოტოს წაშლა
                    </button>
                  </div>
                ))}
                <button
                  type="button"
                  className="secondary"
                  disabled={draft.gallery.length >= 20}
                  onClick={() =>
                    edit({ gallery: [...draft.gallery, { url: "", alt: "" }] })
                  }
                >
                  ფოტოს დამატება
                </button>
              </fieldset>
            )}

            {section === "hours" && (
              <fieldset disabled={busy}>
                <legend>სამუშაო საათები</legend>
                <p>
                  ღამის საათები შეიძლება შემდეგ დღეს დასრულდეს. მოუნიშნავი დღე
                  დაკეტილია.
                </p>
                {days.map((day, i) => {
                  const h = draft.workingHours.find((h) => h.day === i + 1);
                  return (
                    <div className="website-hours" key={day}>
                      <label>
                        <input
                          type="checkbox"
                          checked={!!h}
                          onChange={(e) =>
                            edit({
                              workingHours: e.target.checked
                                ? [
                                    ...draft.workingHours,
                                    {
                                      day: i + 1,
                                      opens: "10:00",
                                      closes: "22:00",
                                    },
                                  ]
                                : draft.workingHours.filter(
                                    (h) => h.day !== i + 1,
                                  ),
                            })
                          }
                        />
                        {day}
                      </label>
                      {h &&
                        (["opens", "closes"] as const).map((key) => (
                          <label key={key}>
                            {key === "opens" ? "გახსნა" : "დახურვა"}
                            <input
                              type="time"
                              required
                              value={h[key]}
                              onChange={(e) =>
                                edit({
                                  workingHours: draft.workingHours.map((row) =>
                                    row.day === h.day
                                      ? { ...row, [key]: e.target.value }
                                      : row,
                                  ),
                                })
                              }
                            />
                          </label>
                        ))}
                    </div>
                  );
                })}
              </fieldset>
            )}

            {section === "socials" && (
              <fieldset disabled={busy}>
                <legend>სოციალური ბმულები</legend>
                {draft.socials.map((social, i) => (
                  <div className="website-entry" key={i}>
                    <label>
                      ბმულის სახელი
                      <input
                        required
                        maxLength={40}
                        value={social.label}
                        onChange={(e) =>
                          edit({
                            socials: draft.socials.map((s, j) =>
                              i === j ? { ...s, label: e.target.value } : s,
                            ),
                          })
                        }
                      />
                    </label>
                    <label>
                      ბმული (https://)
                      <input
                        type="url"
                        required
                        maxLength={2048}
                        value={social.url}
                        onChange={(e) =>
                          edit({
                            socials: draft.socials.map((s, j) =>
                              i === j ? { ...s, url: e.target.value } : s,
                            ),
                          })
                        }
                      />
                    </label>
                    <button
                      type="button"
                      className="secondary"
                      onClick={() =>
                        edit({
                          socials: draft.socials.filter((_, j) => i !== j),
                        })
                      }
                    >
                      ბმულის წაშლა
                    </button>
                  </div>
                ))}
                <button
                  type="button"
                  className="secondary"
                  disabled={draft.socials.length >= 8}
                  onClick={() =>
                    edit({ socials: [...draft.socials, { label: "", url: "" }] })
                  }
                >
                  ბმულის დამატება
                </button>
              </fieldset>
            )}

            {section === "seo" && (
              <fieldset disabled={busy}>
                <legend>საძიებო ინფორმაცია</legend>
                <label>
                  სათაური საძიებო სისტემისთვის
                  <input
                    maxLength={160}
                    value={draft.seoTitle}
                    onChange={(e) => edit({ seoTitle: e.target.value })}
                  />
                </label>
                <label>
                  მოკლე აღწერა
                  <textarea
                    maxLength={320}
                    value={draft.seoDescription}
                    onChange={(e) => edit({ seoDescription: e.target.value })}
                  />
                </label>
                <p>
                  მონახაზის წინასწარი ნახვა ყოველთვის დახურულია საძიებო
                  სისტემებისთვის. გამოუქვეყნებელი საიტი არ იძებნება.
                </p>
              </fieldset>
            )}

            {section !== "publishing" && (
              <button disabled={busy || !dirty}>მონახაზის შენახვა</button>
            )}
          </form>

          {section === "menu" && (
            <WebsiteMenuEditor venueId={venueId} disabled={busy} />
          )}

          {section === "publishing" && (
            <div className="website-publishing">
              {dirty && (
                <p role="status">
                  ჯერ შეინახეთ ცვლილებები, შემდეგ ნახეთ ან გამოაქვეყნეთ.
                </p>
              )}
              <div className="customer-row">
                <button
                  disabled={busy || !dirty}
                  onClick={() => void act("save")}
                >
                  მონახაზის შენახვა
                </button>
                <button
                  className="secondary"
                  disabled={busy || dirty || !settings.revision}
                  onClick={() => void preview()}
                >
                  მონახაზის ნახვა
                </button>
                <button
                  disabled={
                    busy ||
                    dirty ||
                    !settings.entitled ||
                    !settings.hasUnpublishedChanges
                  }
                  onClick={() => void act("publish")}
                >
                  გამოქვეყნება
                </button>
              </div>
              <p>
                „მონახაზის ნახვა“ გახსნის რეალურ საიტს ახალ ფანჯარაში — ზუსტად
                ისე, როგორც გამოქვეყნების შემდეგ გამოჩნდება. საჯარო გვერდი ამით
                არ იცვლება.
              </p>
            </div>
          )}
        </>
      )}

      {error && (
        <p role="alert">
          {error}{" "}
          <button disabled={busy} onClick={() => void load()}>
            {settings ? "ფორმის გადატვირთვა" : "ხელახლა ცდა"}
          </button>
        </p>
      )}
      <p role="status">{busy ? "მუშავდება…" : message}</p>
    </section>
  );
}

/** Saved state, public state and the difference between them, always visible. */
function Status({ settings }: { settings: Settings }) {
  return (
    <>
      <p>
        ტიპი:{" "}
        {
          {
            NONE: "გამორთული",
            CUSTOM: "ინდივიდუალური",
            SAAS: "Vynic ვებსაიტი",
          }[settings.mode]
        }
      </p>
      {settings.mode === "SAAS" ? (
        <>
          <p>
            სტატუსი:{" "}
            {settings.status === "PUBLISHED" ? "გამოქვეყნებულია" : "მონახაზი"}
            {settings.hasUnpublishedChanges && " · გამოუქვეყნებელი ცვლილებები"}
          </p>
          <p>შენახული ვერსია: {settings.revision}</p>
          {settings.publishedRevision && (
            <p>
              გამოქვეყნებული ვერსია: {settings.publishedRevision} ·{" "}
              {new Date(settings.publishedAt!).toLocaleString("ka-GE")}
            </p>
          )}
          {!settings.entitled && (
            <p>
              საჯარო ვებსაიტი გამორთულია. ჩასართავად დაუკავშირდით Vynic-ს.
              მონახაზის შენახვა შესაძლებელია.
            </p>
          )}
          {settings.domains.length > 0 && (
            <p>მისამართები: {settings.domains.join(", ")}</p>
          )}
          <p>
            რესტორნის სახელი, მისამართი და ტელეფონი აღებულია რესტორნის
            პროფილიდან.
          </p>
        </>
      ) : (
        <p>
          {settings.mode === "CUSTOM"
            ? "ინდივიდუალური ვებსაიტი ცალკე იმართება."
            : "ვებსაიტის ჩასართავად დაუკავშირდით Vynic-ს."}
        </p>
      )}
    </>
  );
}

/**
 * A media reference: an HTTPS address or a Vynic-hosted `/media/...` path.
 *
 * Deliberately a reference and not a file picker — no upload pipeline exists
 * yet, and storing image bytes in website content is exactly what the media
 * contract forbids. See `docs/WEBSITE_PHASE_W3.md`.
 */
function MediaField({
  label,
  value,
  onChange,
  required,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
}) {
  return (
    <label>
      {label} (https:// ან /media/…)
      <input
        maxLength={2048}
        required={required}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </label>
  );
}
