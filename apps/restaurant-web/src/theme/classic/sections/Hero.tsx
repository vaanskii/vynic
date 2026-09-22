import type { WebsiteSite } from "../../../api/types";
import { absolute } from "../../../seo/documentHead";

/**
 * The opening statement.
 *
 * Without a hero image it becomes a shorter typographic panel instead of a
 * tall empty frame, so a restaurant that has not uploaded a photograph yet
 * still opens on something deliberate rather than on blank space.
 */
export function Hero({ site, origin }: { site: WebsiteSite; origin: string }) {
  const { content, profile } = site;
  const image = absolute(content.heroImageUrl, origin);
  const title = content.heroTitle || profile.name;
  return (
    <section id="top" className={`hero${image ? "" : " hero--plain"}`}>
      {image && <img className="hero__image" src={image} alt="" />}
      <div className="shell hero__inner on-dark">
        <h1>{title}</h1>
        <div className="hero__rule" aria-hidden="true" />
        {content.heroSubtitle && <p>{content.heroSubtitle}</p>}
      </div>
    </section>
  );
}
