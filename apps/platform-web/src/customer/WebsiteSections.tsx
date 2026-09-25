import { HostnameRequest } from "./HostnameRequest";
import { CatalogEditor } from "./CatalogEditor";
import { useState, type ReactNode } from "react";
import { customerApi } from "./api";
import { WebsiteImageUpload } from "./WebsiteImageUpload";
import { WebsiteMenuEditor } from "./WebsiteMenuEditor";
import { normalizeLink, websiteAddress, type Website } from "./useWebsite";

/**
 * Dashboard sections that edit the website draft.
 *
 * They share one draft: edits made in any of them are saved together from the
 * dashboard's save bar, and nothing reaches visitors until the owner publishes.
 */
export const days = [
  "ორშაბათი",
  "სამშაბათი",
  "ოთხშაბათი",
  "ხუთშაბათი",
  "პარასკევი",
  "შაბათი",
  "კვირა",
];
const themeNames: Record<string, string> = { classic: "კლასიკური" };

export function SectionHeader({
  title,
  lead,
  children,
}: {
  title: string;
  lead?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <header className="portal-section__header">
      <div>
        <h2>{title}</h2>
        {lead && <p>{lead}</p>}
      </div>
      {children && <div className="portal-section__actions">{children}</div>}
    </header>
  );
}

const notices = {
  NOT_ENTITLED: [
    "ვებსაიტი თქვენს პაკეტში ჯერ არ არის ჩართული",
    "ჩასართავად დაუკავშირდით Vynic-ს.",
  ],
  SETUP_PENDING: [
    "ვებსაიტის მომზადება მიმდინარეობს",
    "ვებსაიტი თქვენს პაკეტშია. Vynic-ის გუნდი ასრულებს მის გამართვას.",
  ],
  CUSTOM: [
    "თქვენი ინდივიდუალური ვებსაიტი ცალკე იმართება",
    "ცვლილებებისთვის დაუკავშირდით Vynic-ს.",
  ],
} as const;

/** The server's website state, never re-derived from mode or features here. */
export function WebsiteStateNotice({ state }: { state: keyof typeof notices }) {
  const [title, detail] = notices[state];
  return (
    <div className="portal-empty" data-website-state={state}>
      <strong>{title}</strong>
      <p>{detail}</p>
    </div>
  );
}

/** What to show when the generic SaaS editor does not apply. */
export function WebsiteUnavailable({ website }: { website: Website }) {
  if (!website.loaded) return <p role="status">იტვირთება…</p>;
  if (!website.settings)
    return (
      <p role="alert">
        {website.error}{" "}
        <button onClick={() => void website.load()}>ხელახლა ცდა</button>
      </p>
    );
  const state = website.settings.state;
  return (
    <WebsiteStateNotice state={state === "SAAS" ? "SETUP_PENDING" : state} />
  );
}
const editable = (website: Website) =>
  website.settings?.mode === "SAAS" && !!website.draft;

export function WebsiteStatus({ website }: { website: Website }) {
  const s = website.settings;
  if (!s || s.mode !== "SAAS") return null;
  const [tone, text] =
    s.status !== "PUBLISHED"
      ? ["draft", "მონახაზი"]
      : s.hasUnpublishedChanges
        ? ["pending", "გამოქვეყნებულია · არის ახალი ცვლილებები"]
        : ["live", "გამოქვეყნებულია"];
  return <span className={`portal-pill portal-pill--${tone}`}>{text}</span>;
}

/** Preview and publish, always acting on the saved draft. */
export function PublishActions({ website }: { website: Website }) {
  const s = website.settings;
  if (!s || s.mode !== "SAAS") return null;
  return (
    <div className="customer-row portal-publish">
      <button
        className="secondary"
        disabled={website.busy || website.dirty || !s.revision}
        onClick={() => void website.preview()}
      >
        ვებსაიტის ნახვა
      </button>
      <button
        disabled={
          website.busy ||
          website.dirty ||
          !s.entitled ||
          !s.hasUnpublishedChanges
        }
        onClick={() => void website.publish()}
      >
        გამოქვეყნება
      </button>
    </div>
  );
}

// ---------------------------------------------------------------- profile

type Profile = {
  id: string;
  name: string;
  branchName?: string | null;
  address?: string | null;
  phone?: string | null;
  legalId?: string | null;
};
export function ProfileSection({
  venue,
  website,
  onSaved,
}: {
  venue: Profile;
  website: Website;
  onSaved: () => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  return (
    <>
      <SectionHeader
        title="რესტორნის პროფილი"
        lead="ეს მონაცემები ჩანს ვებსაიტზე, POS-სა და მენეჯერის აპში."
      />
      <div className="portal-grid">
        <section className="portal-card">
          <h3>ძირითადი ინფორმაცია</h3>
          <form
            key={`${venue.id}-${venue.name}-${venue.address}`}
            onSubmit={(e) => {
              e.preventDefault();
              const data = Object.fromEntries(new FormData(e.currentTarget));
              setBusy(true);
              setError("");
              setMessage("");
              void customerApi(`venues/${venue.id}/profile`, data, "PUT")
                .then(onSaved)
                .then(() => setMessage("პროფილი შენახულია."))
                .catch(() => setError("პროფილი ვერ შეინახა. შეამოწმეთ ველები."))
                .finally(() => setBusy(false));
            }}
          >
            <fieldset disabled={busy}>
              <label>
                რესტორნის სახელი
                <input
                  name="name"
                  defaultValue={venue.name}
                  required
                  maxLength={100}
                />
              </label>
              {(
                [
                  [
                    "address",
                    "მისამართი",
                    300,
                    "მაგ. რუსთაველის გამზ. 12, თბილისი",
                  ],
                  ["phone", "ტელეფონი", 50, "+995 5XX XX XX XX"],
                  ["branchName", "ფილიალის სახელი", 100, ""],
                  ["legalId", "საიდენტიფიკაციო ნომერი", 50, ""],
                ] as const
              ).map(([key, text, max, placeholder]) => (
                <label key={key}>
                  {text} <small>არასავალდებულო</small>
                  <input
                    name={key}
                    defaultValue={venue[key] ?? ""}
                    maxLength={max}
                    placeholder={placeholder}
                  />
                </label>
              ))}
              <button>პროფილის შენახვა</button>
            </fieldset>
            {error && <p role="alert">{error}</p>}
            <p role="status">{message}</p>
          </form>
        </section>
        {editable(website) && website.settings?.mediaUploadAllowed && (
          <section className="portal-card">
            <h3>ლოგო</h3>
            <p>ჩანს ვებსაიტის თავში და ბრაუზერის ჩანართზე.</p>
            <WebsiteImageUpload
              venueId={venue.id}
              value={website.draft!.logoUrl}
              onChange={(logoUrl) => website.edit({ logoUrl })}
              onBusy={website.setBusy}
            />
          </section>
        )}
      </div>
    </>
  );
}

// ---------------------------------------------------------------- website

const websiteTabs = [
  ["address", "მისამართი და გამოქვეყნება"],
  ["home", "მთავარი გვერდი"],
  ["about", "ჩვენ შესახებ"],
  ["contact", "კონტაქტი და ბმულები"],
  ["design", "დიზაინი"],
] as const;
type WebsiteTab = (typeof websiteTabs)[number][0];

export function WebsiteSection({
  website,
  address,
  onEditProfile,
}: {
  website: Website;
  address?: string | null;
  onEditProfile: () => void;
}) {
  const [tab, setTab] = useState<WebsiteTab>("address");
  if (!editable(website))
    return (
      <>
        <SectionHeader title="ვებსაიტი" />
        <WebsiteUnavailable website={website} />
      </>
    );
  const settings = website.settings!;
  const draft = website.draft!;
  const edit = website.edit;
  return (
    <>
      <SectionHeader
        title="ვებსაიტი"
        lead={
          <>
            {websiteAddress(settings)} · <WebsiteStatus website={website} />
          </>
        }
      >
        <PublishActions website={website} />
      </SectionHeader>
      {!settings.entitled && (
        <p className="portal-note">
          საჯარო ვებსაიტი თქვენს პაკეტში გამორთულია. ცვლილებების შენახვა
          შესაძლებელია; გამოსაქვეყნებლად დაუკავშირდით Vynic-ს.
        </p>
      )}
      <nav className="portal-tabs" aria-label="ვებსაიტის განყოფილებები">
        {websiteTabs.map(([key, label]) => (
          <button
            key={key}
            type="button"
            aria-current={tab === key ? "true" : undefined}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      <section className="portal-card">
        <fieldset disabled={website.busy}>
          {tab === "address" && <AddressField website={website} />}
          {tab === "home" && (
            <>
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
                ქვესათაური <small>არასავალდებულო</small>
                <input
                  maxLength={400}
                  placeholder="მაგ. ქართული სამზარეულო ძველი თბილისის გულში"
                  value={draft.heroSubtitle}
                  onChange={(e) => edit({ heroSubtitle: e.target.value })}
                />
              </label>
              <p className="portal-hint">
                მთავარი ფოტო იცვლება განყოფილებაში „ფოტოები“.
              </p>
            </>
          )}
          {tab === "about" && (
            <>
              <label>
                რესტორნის შესახებ
                <textarea
                  rows={9}
                  maxLength={5000}
                  value={draft.about}
                  onChange={(e) => edit({ about: e.target.value })}
                />
              </label>
              <small>
                ცარიელი ხაზი ყოფს აბზაცებს. პირველი მოკლე ხაზი გამოჩნდება
                სათაურად.
              </small>
            </>
          )}
          {tab === "contact" && (
            <ContactFields
              website={website}
              address={address}
              onEditProfile={onEditProfile}
            />
          )}
          {tab === "design" && (
            <>
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
              <label>
                ტექსტი გვერდის ბოლოში <small>არასავალდებულო</small>
                <input
                  maxLength={240}
                  value={draft.footerNote}
                  onChange={(e) => edit({ footerNote: e.target.value })}
                />
              </label>
              <details>
                <summary>Google-ში გამოჩენა</summary>
                <label>
                  სათაური ძიების შედეგებში
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
                <p className="portal-hint">
                  გამოუქვეყნებელი საიტი ძიებაში არ ჩანს.
                </p>
              </details>
            </>
          )}
        </fieldset>
      </section>
    </>
  );
}

function AddressField({ website }: { website: Website }) {
  return <HostnameRequest website={website} />;
}

function ContactFields({
  website,
  address,
  onEditProfile,
}: {
  website: Website;
  address?: string | null;
  onEditProfile: () => void;
}) {
  const draft = website.draft!;
  const edit = website.edit;
  const known = ["instagram", "facebook", "tiktok", "ვებსაიტი"];
  return (
    <>
      <div className="portal-inset">
        <strong>რესტორნის მისამართი</strong>
        <p>{address || "მისამართი ჯერ არ არის დამატებული."}</p>
        <button type="button" className="secondary" onClick={onEditProfile}>
          {address ? "პროფილში შეცვლა" : "მისამართის დამატება"}
        </button>
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
        <details>
          <summary>რუკაზე მდებარეობის დაზუსტება</summary>
          <label>
            Google Maps-ის ბმული
            <input
              maxLength={2048}
              value={draft.mapUrl}
              onChange={(e) => edit({ mapUrl: e.target.value })}
              onBlur={(e) => edit({ mapUrl: normalizeLink(e.target.value) })}
            />
          </label>
          <small>
            ცარიელი ველის შემთხვევაში რუკა რესტორნის მისამართით გაიხსნება.
          </small>
        </details>
      )}
      <label>
        საკონტაქტო ელფოსტა <small>არასავალდებულო</small>
        <input
          type="email"
          maxLength={254}
          value={draft.contactEmail}
          onChange={(e) => edit({ contactEmail: e.target.value })}
        />
      </label>
      {["Instagram", "Facebook", "TikTok", "ვებსაიტი"].map((label) => {
        const social = draft.socials.find(
          (s) => s.label.toLowerCase() === label.toLowerCase(),
        );
        const update = (url: string) =>
          edit({
            socials: social
              ? draft.socials
                  .map((s) => (s === social ? { ...s, url } : s))
                  .filter((s) => s.url)
              : [...draft.socials, { label, url }].filter((s) => s.url),
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
      })}
      <details>
        <summary>სხვა ბმულები</summary>
        {draft.socials.map((social, i) =>
          known.includes(social.label.toLowerCase()) ? null : (
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
                          ? { ...s, url: normalizeLink(e.target.value) }
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
                  edit({ socials: draft.socials.filter((_, j) => i !== j) })
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
              socials: [...draft.socials, { label: "კონტაქტი", url: "" }],
            })
          }
        >
          ბმულის დამატება
        </button>
      </details>
    </>
  );
}

// ---------------------------------------------------------------- menu

export function MenuSection({
  website,
  onCatalogSaved,
}: {
  website: Website;
  onCatalogSaved?: () => void;
}) {
  const [catalogVersion, setCatalogVersion] = useState(0);
  const draft = website.draft;
  const saas = editable(website);
  return (
    <>
      <SectionHeader
        title="მენიუ"
        lead="მართეთ მენიუ და ვებსაიტზე მისი ჩვენება."
      />
      <CatalogEditor
        venueId={website.venueId}
        onSaved={() => {
          setCatalogVersion((v) => v + 1);
          onCatalogSaved?.();
        }}
      />
      {saas && draft && (
        <section className="portal-card portal-card--inline">
          <label>
            <input
              type="checkbox"
              checked={draft.showMenu}
              onChange={(e) => website.edit({ showMenu: e.target.checked })}
            />
            მენიუ გამოჩნდეს ვებსაიტზე
          </label>
          <details>
            <summary>მენიუს სათაური და ტექსტი</summary>
            <label>
              სათაური
              <input
                maxLength={80}
                placeholder="მენიუ"
                value={draft.menuHeading}
                onChange={(e) => website.edit({ menuHeading: e.target.value })}
              />
            </label>
            <label>
              მოკლე ტექსტი
              <input
                maxLength={400}
                value={draft.menuIntro}
                onChange={(e) => website.edit({ menuIntro: e.target.value })}
              />
            </label>
          </details>
        </section>
      )}
      <section className="portal-card">
        <WebsiteMenuEditor
          key={catalogVersion}
          venueId={website.venueId}
          disabled={website.busy}
          canUpload={saas}
        />
      </section>
    </>
  );
}

// ---------------------------------------------------------------- photos

export function PhotosSection({ website }: { website: Website }) {
  if (!website.settings?.mediaUploadAllowed)
    return (
      <section className="portal-card">
        <h2>ფოტოები</h2>
        <p>ფოტოების ატვირთვა ხელმისაწვდომია აქტიური ვებსაიტის პაკეტით.</p>
      </section>
    );
  if (!editable(website))
    return (
      <>
        <SectionHeader title="ფოტოები" />
        <WebsiteUnavailable website={website} />
      </>
    );
  const draft = website.draft!;
  const edit = website.edit;
  const upload = (
    value: string,
    onChange: (url: string) => void,
    labels?: Partial<Record<"label" | "alt" | "remove", string>>,
  ) => (
    <WebsiteImageUpload
      kind="hero"
      venueId={website.venueId}
      value={value}
      onChange={onChange}
      onBusy={website.setBusy}
      labels={labels}
    />
  );
  return (
    <>
      <SectionHeader
        title="ფოტოები"
        lead="კარგი ფოტოები სტუმარს რესტორნის შეგრძნებას აძლევს. ყველა ფოტო არასავალდებულოა."
      />
      <div className="portal-grid">
        <section className="portal-card">
          <h3>მთავარი ფოტო</h3>
          <p>ჩანს ვებსაიტის ზედა ნაწილში.</p>
          {upload(draft.heroImageUrl, (heroImageUrl) => edit({ heroImageUrl }))}
        </section>
        <section className="portal-card">
          <h3>„ჩვენ შესახებ“ ფოტო</h3>
          <p>ჩანს რესტორნის აღწერის გვერდით.</p>
          {upload(
            draft.aboutImageUrl,
            (aboutImageUrl) => edit({ aboutImageUrl }),
            {
              label: "ფოტოს ატვირთვა",
              alt: "ჩვენ შესახებ",
              remove: "ფოტოს წაშლა",
            },
          )}
        </section>
      </div>
      <section className="portal-card">
        <h3>გალერეა</h3>
        <p>{draft.gallery.length} / 20 ფოტო</p>
        <div className="portal-gallery">
          {draft.gallery.map((photo, i) => (
            <figure key={`${photo.url}-${i}`}>
              <img src={mediaSource(photo.url)} alt={photo.alt} />
              <figcaption>
                <label>
                  აღწერა
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
                    edit({ gallery: draft.gallery.filter((_, j) => i !== j) })
                  }
                >
                  ფოტოს წაშლა
                </button>
              </figcaption>
            </figure>
          ))}
        </div>
        {draft.gallery.length < 20 &&
          upload(
            "",
            (url) =>
              url && edit({ gallery: [...draft.gallery, { url, alt: "" }] }),
            { label: "ფოტოს დამატება გალერეაში" },
          )}
        <GalleryLink
          disabled={draft.gallery.length >= 20}
          onAdd={(url) =>
            edit({ gallery: [...draft.gallery, { url, alt: "" }] })
          }
        />
      </section>
    </>
  );
}
function mediaSource(value: string) {
  return value.startsWith("/media/")
    ? `${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}${value}`
    : value;
}
function GalleryLink({
  disabled,
  onAdd,
}: {
  disabled: boolean;
  onAdd: (url: string) => void;
}) {
  const [value, setValue] = useState("");
  return (
    <details>
      <summary>ფოტოს დამატება ბმულით</summary>
      <div className="customer-row">
        <input
          aria-label="ფოტოს ბმული"
          placeholder="https://…"
          maxLength={2048}
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
        <button
          type="button"
          className="secondary"
          disabled={disabled || !value.trim()}
          onClick={() => {
            onAdd(normalizeLink(value));
            setValue("");
          }}
        >
          დამატება
        </button>
      </div>
    </details>
  );
}

// ---------------------------------------------------------------- hours

export function HoursSection({ website }: { website: Website }) {
  if (!editable(website))
    return (
      <>
        <SectionHeader title="სამუშაო საათები" />
        <WebsiteUnavailable website={website} />
      </>
    );
  const draft = website.draft!;
  const edit = website.edit;
  const hours = draft.workingHours;
  const copyToAll = (from: { opens: string; closes: string }) =>
    edit({
      workingHours: days.map((_, i) => ({ day: i + 1, ...from })),
    });
  return (
    <>
      <SectionHeader
        title="სამუშაო საათები"
        lead="ჩანს ვებსაიტზე. ღამის საათები შეიძლება შემდეგ დღეს დასრულდეს; მოუნიშნავი დღე დაკეტილია."
      />
      <section className="portal-card">
        <fieldset disabled={website.busy} className="portal-hours">
          {days.map((day, i) => {
            const h = hours.find((row) => row.day === i + 1);
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
                              ...hours,
                              { day: i + 1, opens: "10:00", closes: "22:00" },
                            ]
                          : hours.filter((row) => row.day !== i + 1),
                      })
                    }
                  />
                  {day}
                </label>
                {h ? (
                  (["opens", "closes"] as const).map((key) => (
                    <label key={key}>
                      {key === "opens" ? "გახსნა" : "დახურვა"}
                      <input
                        type="time"
                        required
                        value={h[key]}
                        onChange={(e) =>
                          edit({
                            workingHours: hours.map((row) =>
                              row.day === h.day
                                ? { ...row, [key]: e.target.value }
                                : row,
                            ),
                          })
                        }
                      />
                    </label>
                  ))
                ) : (
                  <span className="portal-hint">დაკეტილია</span>
                )}
              </div>
            );
          })}
        </fieldset>
        {hours.length > 0 && hours.length < 7 && (
          <button
            type="button"
            className="secondary"
            onClick={() => copyToAll(hours[0])}
          >
            ყველა დღეზე იგივე საათები
          </button>
        )}
      </section>
    </>
  );
}
