import type { Strings } from "../../../i18n";
import type { WebsiteSite } from "../../../api/types";
import { absolute } from "../../../seo/documentHead";

/**
 * Published photographs.
 *
 * A reference without a description is decorative rather than mislabelled: an
 * empty `alt` keeps a screen reader from reading out a filename-shaped string.
 */
export function Gallery({
  site,
  strings,
  origin,
}: {
  site: WebsiteSite;
  strings: Strings;
  origin: string;
}) {
  const photos = site.content.gallery;
  if (!photos.length) return null;
  return (
    <section className="section" id="gallery" aria-labelledby="gallery-title">
      <div className="shell">
        <h2 id="gallery-title">{strings.gallery.title}</h2>
        <div className="gallery__grid">
          {photos.map((photo, index) => (
            <img
              key={`${photo.url}-${index}`}
              src={absolute(photo.url, origin) ?? photo.url}
              alt={photo.alt}
              loading="lazy"
            />
          ))}
        </div>
      </div>
    </section>
  );
}
