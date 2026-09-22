import { useEffect, useState } from "react";
import { customerApi } from "./api";
export type WebsiteContent = {
  slug: string;
  themeKey: "classic";
  heroTitle: string;
  heroSubtitle: string;
  about: string;
  seoTitle: string;
  seoDescription: string;
  workingHours: { day: number; opens: string; closes: string }[];
  socials: { label: string; url: string }[];
  gallery: { url: string; alt: string }[];
};
type Settings = {
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
type Preview = {
  content: WebsiteContent;
  revision: number;
  profile: { name: string; address: string | null; phone: string | null };
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
export function WebsiteSettings({ venueId }: { venueId: string }) {
  const [settings, setSettings] = useState<Settings>();
  const [draft, setDraft] = useState<WebsiteContent>();
  const [preview, setPreview] = useState<Preview>();
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const path = `venues/${venueId}/website`;
  const accept = (s: Settings) => {
    setSettings(s);
    setDraft(s.draft);
    setDirty(false);
    setPreview(undefined);
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
    setPreview(undefined);
    setMessage("");
  };
  const act = async (kind: "save" | "preview" | "publish") => {
    if (!settings || !draft) return;
    setBusy(true);
    setError("");
    setMessage("");
    try {
      if (kind === "preview")
        setPreview(await customerApi<Preview>(`${path}/preview`));
      else {
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
      }
    } catch {
      setError(
        "მოქმედება ვერ შესრულდა. შეამოწმეთ ველები, მისამართის ხელმისაწვდომობა და ვებსაიტის წვდომა. თუ სხვა სესიაში შეცვალეთ მონაცემები, გადატვირთეთ ფორმა.",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <section aria-labelledby="website-settings-title">
      <h2 id="website-settings-title">ვებსაიტი</h2>
      {!settings && !error && <p role="status">იტვირთება…</p>}
      {settings && (
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
                {settings.status === "PUBLISHED"
                  ? "გამოქვეყნებულია"
                  : "მონახაზი"}
                {settings.hasUnpublishedChanges &&
                  " · გამოუქვეყნებელი ცვლილებები"}
              </p>
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
      )}
      {settings?.mode === "SAAS" && draft && (
        <>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void act("save");
            }}
          >
            <fieldset disabled={busy}>
              <legend>გვერდის შინაარსი</legend>
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
                თემა
                <select value={draft.themeKey} onChange={() => {}}>
                  <option value="classic">კლასიკური</option>
                </select>
              </label>
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
              <label>
                ჩვენ შესახებ
                <textarea
                  rows={5}
                  maxLength={5000}
                  value={draft.about}
                  onChange={(e) => edit({ about: e.target.value })}
                />
              </label>
            </fieldset>
            <details>
              <summary>სამუშაო საათები, ბმულები და ფოტოები</summary>
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
                      {h && (
                        <>
                          {(["opens", "closes"] as const).map((key) => (
                            <label key={key}>
                              {key === "opens" ? "გახსნა" : "დახურვა"}
                              <input
                                type="time"
                                required
                                value={h[key]}
                                onChange={(e) =>
                                  edit({
                                    workingHours: draft.workingHours.map(
                                      (row) =>
                                        row.day === h.day
                                          ? { ...row, [key]: e.target.value }
                                          : row,
                                    ),
                                  })
                                }
                              />
                            </label>
                          ))}
                        </>
                      )}
                    </div>
                  );
                })}
              </fieldset>
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
                    edit({
                      socials: [...draft.socials, { label: "", url: "" }],
                    })
                  }
                >
                  ბმულის დამატება
                </button>
              </fieldset>
              <fieldset disabled={busy}>
                <legend>გალერეა</legend>
                {draft.gallery.map((photo, i) => (
                  <div className="website-entry" key={i}>
                    <label>
                      ფოტოს ბმული (https://)
                      <input
                        type="url"
                        required
                        maxLength={2048}
                        value={photo.url}
                        onChange={(e) =>
                          edit({
                            gallery: draft.gallery.map((p, j) =>
                              i === j ? { ...p, url: e.target.value } : p,
                            ),
                          })
                        }
                      />
                    </label>
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
            </details>
            <details>
              <summary>საძიებო სისტემებში ჩვენება</summary>
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
              </fieldset>
            </details>
            <button disabled={busy || !dirty}>მონახაზის შენახვა</button>
          </form>
          {dirty && (
            <p>ჯერ შეინახეთ ცვლილებები, შემდეგ ნახეთ ან გამოაქვეყნეთ.</p>
          )}
          <div className="customer-row">
            <button
              className="secondary"
              disabled={busy || dirty || !settings.revision}
              onClick={() => void act("preview")}
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
          {preview && (
            <div className="website-preview" aria-label="მონახაზის შინაარსი">
              <h3>მონახაზის შინაარსი · ვერსია {preview.revision}</h3>
              <p>ეს არის შინაარსის წინასწარი ნახვა.</p>
              <p>
                {preview.profile.name} · {preview.profile.address} ·{" "}
                {preview.profile.phone}
              </p>
              <h4>{preview.content.heroTitle}</h4>
              <p>{preview.content.heroSubtitle}</p>
              <p className="website-prose">{preview.content.about}</p>
              <p>
                მისამართი: {preview.content.slug}.{settings.baseDomain}
              </p>
              <p>საძიებო სათაური: {preview.content.seoTitle}</p>
              <p>{preview.content.seoDescription}</p>
              <ul>
                {preview.content.workingHours.map((h) => (
                  <li key={h.day}>
                    {days[h.day - 1]}: {h.opens}–{h.closes}
                  </li>
                ))}
              </ul>
              <ul>
                {preview.content.socials.map((s) => (
                  <li key={s.url}>
                    {s.label}: {s.url}
                  </li>
                ))}
              </ul>
              <ul>
                {preview.content.gallery.map((p, i) => (
                  <li key={i}>
                    {p.alt || "ფოტო"}: {p.url}
                  </li>
                ))}
              </ul>
              <button
                className="secondary"
                onClick={() => setPreview(undefined)}
              >
                დახურვა
              </button>
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
