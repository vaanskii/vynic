import { useEffect, useRef, useState } from "react";
import { customerApi } from "./api";
import type { WebsiteSettings } from "./useWebsite";

/**
 * The first-run step confirms the restaurant name and its assigned address.
 *
 * Everything else — street address, hours, photos, menu, POS — is optional and lives
 * in its own dashboard section. Each write here is convergent (restaurant creation
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
  const existingLogo = website?.draft.logoUrl ?? "";
  const domain = baseDomain ?? website?.baseDomain;

  const logoSource =
    preview ??
    (existingLogo.startsWith("/media/")
      ? `${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}${existingLogo}`
      : existingLogo);

  async function submit() {
    setError("");
    const trimmed = name.trim();
    if (!trimmed) return setError("შეიყვანეთ რესტორნის სახელი.");
    setBusy(true);
    try {
      let venueId = venue?.id;
      if (!venueId) {
        venueId = (
          await customerApi<{ id: string }>("venues", { name: trimmed })
        ).id;
      } else if (trimmed !== venue!.name) {
        // A profile write replaces every field, so carry the prepared ones.
        const { branchName, address, phone, legalId } = venue!;
        await customerApi(
          `venues/${venueId}/profile`,
          { name: trimmed, branchName, address, phone, legalId },
          "PUT",
        );
      }
      const settings = website;
      if (settings?.mode === "SAAS") {
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
        დაამატეთ რესტორნის სახელი. ჩართული პროდუქტების გამართვას შემდეგ
        გააგრძელებთ.
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
              }}
            />
          </label>

          {website?.mediaUploadAllowed && (
            <div className="first-run__field">
              <span id="first-run-logo">ლოგო · არასავალდებულო</span>
              <div className="first-run__logo">
                <div
                  className="first-run__logo-frame"
                  aria-hidden={!logoSource}
                >
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
          )}

          {website?.mode === "SAAS" && (
            <div className="first-run__field">
              <span>თქვენი ვებსაიტის მისამართი</span>
              <strong>
                {website.draft.slug}
                {domain ? `.${domain}` : ""}
              </strong>
              {website.commercialStatus === "TRIAL" && (
                <p>
                  საცდელი პერიოდის განმავლობაში მისამართის შეცვლა შეუძლებელია.
                </p>
              )}
            </div>
          )}

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
