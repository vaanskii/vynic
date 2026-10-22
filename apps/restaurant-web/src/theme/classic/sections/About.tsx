import type { Strings } from "../../../i18n";
import type { WebsiteSite } from "../../../api/types";
import { absolute } from "../../../seo/documentHead";
import { paragraphs } from "../format";

/**
 * The restaurant's own words, rendered as text and never as markup.
 *
 * The section disappears entirely when the owner has written nothing, rather
 * than leaving a heading over empty space.
 */
export function About({
  site,
  strings,
  origin,
}: {
  site: WebsiteSite;
  strings: Strings;
  origin: string;
}) {
  const { content } = site;
  const blocks = paragraphs(content.about);
  const image = absolute(content.aboutImageUrl, origin);
  if (!blocks.length) return null;
  // A short opening line reads as a statement and becomes the heading; a long
  // one stays body text so the section never turns into a wall of display type.
  const lead = blocks[0].length <= 120;
  const heading = lead ? blocks[0] : strings.about.title;
  const body = lead ? blocks.slice(1) : blocks;
  return (
    <section className="section" id="about" aria-labelledby="about-title">
      <div className="shell">
        <div className={`about__grid${image ? "" : " about__grid--solo"}`}>
          <div>
            {lead && <p className="section__eyebrow">{strings.about.title}</p>}
            <h2 id="about-title">{heading}</h2>
            {body.length > 0 && (
              <div className="about__body section__intro">
                {body.map((block, index) => (
                  <p key={index}>{block}</p>
                ))}
              </div>
            )}
          </div>
          {image && <img className="about__image" src={image} alt="" />}
        </div>
      </div>
    </section>
  );
}
