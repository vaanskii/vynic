import { useEffect, useRef, useState } from "react";
import { customerApi } from "./api";
import type { WebsiteSettings } from "./useWebsite";

/**
 * The only blocking step before the owner portal: name, logo and address.
 *
 * Everything else — address, hours, photos, menu, POS — is optional and lives
 * in its own portal section. Each write here is convergent (restaurant creation
 * returns the existing one), so a failed step is retried from this same form
 * without creating duplicates.
 */
type Venue = {
  id: string;
  name: string;
  branchName?: string | null;
  address?: string | null;
  phone?: string | null;
  legalId?: string | null;
};

const georgian: Record<string, string> = {
  ა: "a", ბ: "b", გ: "g", დ: "d", ე: "e", ვ: "v", ზ: "z", თ: "t", ი: "i",
  კ: "k", ლ: "l", მ: "m", ნ: "n", ო: "o", პ: "p", ჟ: "zh", რ: "r", ს: "s",
  ტ: "t", უ: "u", ფ: "p", ქ: "k", ღ: "gh", ყ: "q", შ: "sh", ჩ: "ch", ც: "ts",
  ძ: "dz", წ: "ts", ჭ: "ch", ხ: "kh", ჯ: "j", ჰ: "h",
};
const SLUG = /^[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?$/;

/** A readable Latin address suggestion from a Georgian or Latin name. */
export function suggestAddress(name: string) {
  return [...name.toLowerCase()]
    .map((c) => georgian[c] ?? c)
    .join("")
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48)
    .replace(/-+$/, "");
}
/** Keep only what an address may contain while the owner types. */
function cleanAddress(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "")
    .replace(/-{2,}/g, "-")
    .slice(0, 48);
}

export function FirstRunSetup({
  venue,
  website,
  baseDomain,
  onComplete,
}: {
  venue?: Venue;
  website?: WebsiteSettings;
  /** Known only once a restaurant exists; shown as a hint before that. */
  baseDomain?: string | null;
  onComplete: () => Promise<void>;
}) {
  const [name, setName] = useState(venue?.name ?? "");
  const [slug, setSlug] = useState(
    website?.draft.slug || suggestAddress(venue?.name ?? ""),
  );
  const [slugTouched, setSlugTouched] = useState(!!website?.draft.slug);
  const [logo, setLogo] = useState<{ file: File; preview?: string }>();
  const file = logo?.file;
  const preview = logo?.preview;
  // Object URLs are released when replaced and when the form goes away.
  const previewRef = useRef<string>(undefined);
  useEffect(
    () => () => {
      if (previewRef.current) URL.revokeObjectURL(previewRef.current);
    },
    [],
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [addressError, setAddressError] = useState("");
  const existingLogo = website?.draft.logoUrl ?? "";
  const domain = baseDomain ?? website?.baseDomain;



  const logoSource =
    preview ??
    (existingLogo.startsWith("/media/")
      ? `${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}${existingLogo}`
      : existingLogo);

  async function submit() {
    setError("");
    setAddressError("");
    const trimmed = name.trim();
    if (!trimmed) return setError("შეიყვანეთ რესტორნის სახელი.");
    if (!file && !existingLogo) return setError("ატვირთეთ რესტორნის ლოგო.");
    if (!SLUG.test(slug))
      return setAddressError(
        "გამოიყენეთ ლათინური ასოები და ციფრები. სიტყვები შეგიძლიათ გამოყოთ ტირით.",
      );
    setBusy(true);
    try {
      let venueId = venue?.id;
      if (!venueId) {
        venueId = (await customerApi<{ id: string }>("venues", { name: trimmed }))
          .id;
      } else if (trimmed !== venue!.name) {
        // A profile write replaces every field, so carry the prepared ones.
        const { branchName, address, phone, legalId } = venue!;
        await customerApi(
          `venues/${venueId}/profile`,
          { name: trimmed, branchName, address, phone, legalId },
          "PUT",
        );
      }
      const settings =
        website ??
        (await customerApi<WebsiteSettings>(`venues/${venueId}/website`));
      if (settings.mode === "SAAS") {
        const address = await customerApi<{ valid: boolean; available: boolean }>(
          `venues/${venueId}/website/address/${slug}`,
        );
        if (!address.valid || !address.available) {
          setAddressError(
            address.valid
              ? "ეს მისამართი უკვე დაკავებულია. სცადეთ სხვა."
              : "ეს მისამართი ვერ გამოიყენება. სცადეთ სხვა.",
          );
          return;
        }
        let logoUrl = existingLogo;
        if (file) {
          const data = new FormData();
          data.append("file", file);
          logoUrl = (
            await customerApi<{ url: string }>(
              `venues/${venueId}/website/logo`,
              data,
            )
          ).url;
        }
        await customerApi(
          `venues/${venueId}/website/draft`,
          {
            expectedRevision: settings.revision,
            content: {
              ...settings.draft,
              slug,
              logoUrl,
              heroTitle: settings.draft.heroTitle || trimmed,
            },
          },
          "PUT",
        );
      }
      await onComplete();
    } catch {
      setError("გამართვა ვერ დასრულდა. შეამოწმეთ ველები და სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="first-run" aria-labelledby="first-run-title">
      <p className="first-run__eyebrow">Vynic · პირველი ნაბიჯი</p>
      <h1 id="first-run-title">შექმენით თქვენი რესტორანი</h1>
      <p className="first-run__lead">
        სამი რამ და მზად ხართ. დანარჩენს — მენიუს, ფოტოებს, სამუშაო საათებს —
        მოგვიანებით დაამატებთ.
      </p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <fieldset disabled={busy}>
          <label className="first-run__field">
            რესტორნის სახელი
            <input
              value={name}
              required
              maxLength={100}
              autoComplete="organization"
              onChange={(e) => {
                setName(e.target.value);
                if (!slugTouched) setSlug(suggestAddress(e.target.value));
              }}
            />
          </label>

          <div className="first-run__field">
            <span id="first-run-logo">ლოგო</span>
            <div className="first-run__logo">
              <div className="first-run__logo-frame" aria-hidden={!logoSource}>
                {logoSource ? (
                  <img src={logoSource} alt="რესტორნის ლოგო" />
                ) : (
                  <span>{name.trim().slice(0, 1).toUpperCase() || "V"}</span>
                )}
              </div>
              <div>
                <label className="website-upload-picker">
                  {logoSource ? "ლოგოს შეცვლა" : "ლოგოს ატვირთვა"}
                  <input
                    type="file"
                    aria-describedby="first-run-logo"
                    accept="image/png,image/jpeg,image/webp"
                    onChange={(e) => {
                      const next = e.currentTarget.files?.[0];
                      e.currentTarget.value = "";
                      if (!next) return;
                      if (
                        !["image/png", "image/jpeg", "image/webp"].includes(
                          next.type,
                        ) ||
                        next.size > 5 * 1024 * 1024 ||
                        !next.size
                      )
                        return setError(
                          "აირჩიეთ PNG, JPG ან WebP ფოტო, მაქსიმუმ 5 მბ.",
                        );
                      setError("");
                      if (previewRef.current)
                        URL.revokeObjectURL(previewRef.current);
                      previewRef.current = URL.createObjectURL?.(next);
                      setLogo({ file: next, preview: previewRef.current });
                    }}
                  />
                </label>
                <small>PNG, JPG ან WebP · მაქსიმუმ 5 მბ</small>
              </div>
            </div>
          </div>

          <div className="first-run__field">
            <label htmlFor="first-run-address">ვებსაიტის მისამართი</label>
            <span className="first-run__address">
              <input
                id="first-run-address"
                value={slug}
                required
                maxLength={48}
                inputMode="url"
                autoCapitalize="none"
                spellCheck={false}
                aria-invalid={!!addressError}
                aria-describedby="first-run-address-hint"
                onChange={(e) => {
                  setSlugTouched(true);
                  setAddressError("");
                  setSlug(cleanAddress(e.target.value));
                }}
              />
              {domain && <span aria-hidden="true">.{domain}</span>}
            </span>
          </div>
          <p id="first-run-address-hint" className="first-run__hint">
            {addressError ? (
              <span role="alert">{addressError}</span>
            ) : (
              <>
                თქვენი საიტი იქნება:{" "}
                <strong>
                  {slug || "restaurant"}
                  {domain ? `.${domain}` : ""}
                </strong>
              </>
            )}
          </p>

          {error && (
            <p role="alert" className="customer-error">
              {error}
            </p>
          )}
          <button className="first-run__submit">
            {busy ? "მუშავდება…" : "გაგრძელება"}
          </button>
        </fieldset>
      </form>
    </section>
  );
}
