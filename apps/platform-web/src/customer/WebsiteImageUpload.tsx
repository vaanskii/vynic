import { useEffect, useRef, useState } from "react";
import { customerApi } from "./api";

export function WebsiteImageUpload({
  kind = "logo",
  venueId,
  value,
  onChange,
  onBusy,
}: {
  kind?: "logo" | "hero";
  venueId: string;
  value: string;
  onChange: (url: string) => void;
  onBusy: (busy: boolean) => void;
}) {
  const copy =
    kind === "hero"
      ? {
          label: "მთავარი ფოტოს ატვირთვა",
          alt: "მთავარი ფოტო",
          remove: "მთავარი ფოტოს წაშლა",
          loading: "ფოტო იტვირთება…",
          error: "ფოტო ვერ აიტვირთა. სცადეთ სხვა ფოტო ან გაიმეორეთ ატვირთვა.",
        }
      : {
          label: "ლოგოს ატვირთვა",
          alt: "რესტორნის ლოგო",
          remove: "ლოგოს წაშლა",
          loading: "ლოგო იტვირთება…",
          error: "ლოგო ვერ აიტვირთა. სცადეთ სხვა ფოტო ან გაიმეორეთ ატვირთვა.",
        };
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);
  const source = value.startsWith("/media/website-logos/")
    ? `${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}${value}`
    : value;
  return (
    <div className="website-logo-upload">
      {value && (
        <img
          className={
            kind === "hero" ? "website-hero-preview" : "website-logo-preview"
          }
          src={source}
          alt={copy.alt}
        />
      )}
      <label className="website-upload-picker">
        {copy.label}
        <input
          type="file"
          accept="image/png,image/jpeg,image/webp"
          disabled={uploading}
          onChange={async (e) => {
            const file = e.currentTarget.files?.[0];
            e.currentTarget.value = "";
            if (!file) return;
            setError("");
            if (
              !["image/png", "image/jpeg", "image/webp"].includes(file.type) ||
              file.size > 5 * 1024 * 1024 ||
              !file.size
            ) {
              setError("აირჩიეთ PNG, JPG ან WebP ფოტო, მაქსიმუმ 5 მბ.");
              return;
            }
            const data = new FormData();
            data.append("file", file);
            setUploading(true);
            onBusy(true);
            try {
              const result = await customerApi<{ url: string }>(
                `venues/${venueId}/website/${kind}`,
                data,
              );
              if (alive.current) onChange(result.url);
            } catch {
              if (alive.current) setError(copy.error);
            } finally {
              if (alive.current) {
                setUploading(false);
                onBusy(false);
              }
            }
          }}
        />
      </label>
      <small>PNG, JPG ან WebP · მაქსიმუმ 5 მბ</small>
      {uploading && <p role="status">{copy.loading}</p>}
      {error && <p role="alert">{error}</p>}
      {value && (
        <button
          type="button"
          className="secondary"
          disabled={uploading}
          onClick={() => onChange("")}
        >
          {copy.remove}
        </button>
      )}
    </div>
  );
}
