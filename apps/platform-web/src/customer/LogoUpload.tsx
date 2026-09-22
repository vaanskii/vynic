import { useEffect, useRef, useState } from "react";
import { customerApi } from "./api";

export function LogoUpload({
  venueId,
  value,
  onChange,
  onBusy,
}: {
  venueId: string;
  value: string;
  onChange: (url: string) => void;
  onBusy: (busy: boolean) => void;
}) {
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
          className="website-logo-preview"
          src={source}
          alt="რესტორნის ლოგო"
        />
      )}
      <label className="website-upload-picker">
        ლოგოს ატვირთვა
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
                `venues/${venueId}/website/logo`,
                data,
              );
              if (alive.current) onChange(result.url);
            } catch {
              if (alive.current)
                setError(
                  "ლოგო ვერ აიტვირთა. სცადეთ სხვა ფოტო ან გაიმეორეთ ატვირთვა.",
                );
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
      {uploading && <p role="status">ლოგო იტვირთება…</p>}
      {error && <p role="alert">{error}</p>}
      {value && (
        <button
          type="button"
          className="secondary"
          disabled={uploading}
          onClick={() => onChange("")}
        >
          ლოგოს წაშლა
        </button>
      )}
    </div>
  );
}
