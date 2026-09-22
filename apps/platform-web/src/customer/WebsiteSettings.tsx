import { useEffect, useState } from "react";
import { customerApi } from "./api";
import { WebsiteImageUpload } from "./WebsiteImageUpload";
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
  showMap?: boolean;
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
  ["hero", "მთავარი"],
  ["about", "ჩვენ შესახებ"],
  ["menu", "მენიუ"],
  ["gallery", "ფოტოები"],
  ["hours", "სამუშაო საათები"],
  ["contact", "კონტაქტი"],
  ["theme", "დიზაინი"],
  ["publishing", "გამოქვეყნება"],
] as const;
type SectionKey = (typeof sections)[number][0];

export function WebsiteSettings({
  venueId,
  address,
  onEditProfile,
}: {
  venueId: string;
  address?: string | null;
  onEditProfile?: () => void;
}) {
  const [settings, setSettings] = useState<Settings>();
  const [draft, setDraft] = useState<WebsiteContent>();
  const [section, setSection] = useState<SectionKey>("hero");
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
        return;
      }
    }
    setBusy(true);
    setError("");
    setMessage("");
    try {
      accept(
        await customerApi<Settings>(
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
    <section
      className="website-workspace"
      aria-labelledby="website-settings-title"
    >
      <h2 id="website-settings-title">ვებსაიტი</h2>
      {!settings && !error && <p role="status">იტვირთება…</p>}
      {settings && <Status settings={settings} />}
      {dirty && (
        <p className="website-unsaved" role="status">
          შეუნახავი ცვლილებები
        </p>
      )}

      {saas && draft && settings && (
        <>
          <nav aria-label="ვებსაიტის პარამეტრების განყოფილებები">
            {sections.map(([key, label]) => (
              <button
                key={key}
                disabled={busy}
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
            {section === "hero" && (
              <fieldset disabled={busy}>
                <legend>მთავარი</legend>
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
                <WebsiteImageUpload
                  kind="hero"
                  venueId={venueId}
                  value={draft.heroImageUrl}
                  onChange={(heroImageUrl) => edit({ heroImageUrl })}
                  onBusy={setBusy}
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
                <legend>დიზაინი</legend>
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
                <WebsiteImageUpload
                  venueId={venueId}
                  value={draft.logoUrl}
                  onChange={(logoUrl) => edit({ logoUrl })}
                  onBusy={setBusy}
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
                <legend>ფოტოები</legend>
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
                  ფოტოების დამატება
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

            {section === "contact" && (
              <fieldset disabled={busy}>
                <legend>კონტაქტი</legend>
                <div className="website-profile-address">
                  <strong>რესტორნის მისამართი</strong>
                  <p>{address || "მისამართი ჯერ არ არის დამატებული."}</p>
                  {onEditProfile && (
                    <button
                      type="button"
                      className="secondary"
                      onClick={onEditProfile}
                    >
                      პროფილში შეცვლა
                    </button>
                  )}
                </div>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.showMap !== false}
                    onChange={(e) => edit({ showMap: e.target.checked })}
                  />
                  რუკის ჩვენება
                </label>
                {draft.showMap !== false && (
                  <>
                    <p>რუკა რესტორნის მისამართის მიხედვით გაიხსნება.</p>
                    <details>
                      <summary>რუკაზე მდებარეობის დაზუსტება</summary>
                      <label>
                        Google Maps-ის ბმული
                        <input
                          maxLength={2048}
                          value={draft.mapUrl}
                          onChange={(e) => edit({ mapUrl: e.target.value })}
                          onBlur={(e) =>
                            edit({ mapUrl: normalizeLink(e.target.value) })
                          }
                        />
                      </label>
                      <small>
                        ჩასვით Google Maps-იდან დაკოპირებული ბმული. ცარიელი ველი
                        გამოიყენებს რესტორნის მისამართს.
                      </small>
                    </details>
                  </>
                )}
                <label>
                  საკონტაქტო ელფოსტა
                  <input
                    type="email"
                    maxLength={254}
                    value={draft.contactEmail}
                    onChange={(e) => edit({ contactEmail: e.target.value })}
                  />
                </label>
                {["Instagram", "Facebook", "TikTok", "ვებსაიტი"].map(
                  (label) => {
                    const social = draft.socials.find(
                      (s) => s.label.toLowerCase() === label.toLowerCase(),
                    );
                    const update = (url: string) =>
                      edit({
                        socials: social
                          ? draft.socials
                              .map((s) => (s === social ? { ...s, url } : s))
                              .filter((s) => s.url)
                          : [...draft.socials, { label, url }].filter(
                              (s) => s.url,
                            ),
                      });
                    return (
                      <label key={label}>
                        {label}
                        <input
                          maxLength={2048}
                          value={social?.url ?? ""}
                          disabled={!social && draft.socials.length >= 8}
                          onChange={(e) => update(e.target.value)}
                          onBlur={(e) => update(normalizeLink(e.target.value))}
                        />
                      </label>
                    );
                  },
                )}
                <details>
                  <summary>სხვა საკონტაქტო ბმულები</summary>
                  {draft.socials.map((social, i) =>
                    ["instagram", "facebook", "tiktok", "ვებსაიტი"].includes(
                      social.label.toLowerCase(),
                    ) ? null : (
                      <div className="website-entry" key={i}>
                        <label>
                          სახელი
                          <input
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
                          ბმული
                          <input
                            maxLength={2048}
                            value={social.url}
                            onChange={(e) =>
                              edit({
                                socials: draft.socials.map((s, j) =>
                                  i === j ? { ...s, url: e.target.value } : s,
                                ),
                              })
                            }
                            onBlur={(e) =>
                              edit({
                                socials: draft.socials.map((s, j) =>
                                  i === j
                                    ? {
                                        ...s,
                                        url: normalizeLink(e.target.value),
                                      }
                                    : s,
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
                    ),
                  )}
                  <button
                    type="button"
                    className="secondary"
                    disabled={draft.socials.length >= 8}
                    onClick={() =>
                      edit({
                        socials: [
                          ...draft.socials,
                          { label: "კონტაქტი", url: "" },
                        ],
                      })
                    }
                  >
                    ბმულის დამატება
                  </button>
                </details>
              </fieldset>
            )}

            {section === "publishing" && (
              <div className="website-publish-settings">
                <label>
                  ვებსაიტის მისამართი
                  <input
                    required
                    maxLength={48}
                    pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
                    disabled={busy}
                    value={draft.slug}
                    onChange={(e) => edit({ slug: e.target.value })}
                  />
                </label>
                <small>
                  {draft.slug || "restaurant"}.{settings.baseDomain || "…"}
                </small>

                <details>
                  <summary>დამატებითი პარამეტრები</summary>
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
                        onChange={(e) =>
                          edit({ seoDescription: e.target.value })
                        }
                      />
                    </label>
                    <p>
                      მონახაზის წინასწარი ნახვა ყოველთვის დახურულია საძიებო
                      სისტემებისთვის. გამოუქვეყნებელი საიტი არ იძებნება.
                    </p>
                    <label>
                      ტექსტი გვერდის ბოლოში
                      <input
                        maxLength={240}
                        value={draft.footerNote}
                        onChange={(e) => edit({ footerNote: e.target.value })}
                      />
                    </label>
                  </fieldset>
                </details>
              </div>
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
                  საიტის ნახვა
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
                „საიტის ნახვა“ გახსნის რეალურ საიტს ახალ ფანჯარაში — ზუსტად ისე,
                როგორც გამოქვეყნების შემდეგ გამოჩნდება. საჯარო გვერდი ამით არ
                იცვლება.
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
  if (settings.mode !== "SAAS")
    return (
      <p>
        {settings.mode === "CUSTOM"
          ? "ინდივიდუალური ვებსაიტი ცალკე იმართება."
          : "ვებსაიტის ჩასართავად დაუკავშირდით Vynic-ს."}
      </p>
    );
  return (
    <div className="website-status">
      <strong>
        {settings.status === "PUBLISHED" ? "გამოქვეყნებულია" : "მონახაზი"}
      </strong>
      {settings.hasUnpublishedChanges && (
        <span> · გამოუქვეყნებელი ცვლილებები</span>
      )}
      {!settings.entitled && (
        <p>
          საჯარო ვებსაიტი გამორთულია. ჩასართავად დაუკავშირდით Vynic-ს. მონახაზის
          შენახვა შესაძლებელია.
        </p>
      )}
    </div>
  );
}

function normalizeLink(value: string) {
  const trimmed = value.trim();
  if (
    !trimmed ||
    trimmed.startsWith("/media/") ||
    /^[a-z][a-z0-9+.-]*:/i.test(trimmed)
  )
    return trimmed;
  return `https://${trimmed}`;
}

/**
 * A media reference: an HTTPS address or a Vynic-hosted `/media/...` path.
 *
 * Gallery/about images remain references. Logo and main-photo file pickers
 * use WebsiteImageUpload; website content stores only their returned references.
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
  const [failedImage, setFailedImage] = useState<string>();
  return (
    <label>
      {label}
      {value &&
        (failedImage === value ? (
          <small>ფოტო ვერ ჩაიტვირთა. შეამოწმეთ ფოტოს ბმული.</small>
        ) : (
          <img
            className="website-photo-preview"
            src={value}
            alt=""
            onError={() => setFailedImage(value)}
          />
        ))}
      <input
        placeholder="ჩასვით ფოტოს ბმული"
        maxLength={2048}
        required={required}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onBlur={(e) => onChange(normalizeLink(e.target.value))}
      />
    </label>
  );
}
