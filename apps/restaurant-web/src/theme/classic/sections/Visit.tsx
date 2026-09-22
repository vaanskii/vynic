import type { Strings } from "../../../i18n";
import type { WebsiteSite } from "../../../api/types";
import { week } from "../format";

/**
 * Where and when: opening hours beside address, phone, email and links.
 *
 * Identity here is the Venue profile the restaurant already maintains for the
 * POS, not a second copy kept in website content, so correcting a phone number
 * once corrects it everywhere.
 *
 * The section renders whenever any part of it exists; empty states are stated
 * rather than left blank, because "hours coming soon" is information and a gap
 * is not.
 */
export function Visit({
  site,
  strings,
}: {
  site: WebsiteSite;
  strings: Strings;
}) {
  const { profile, content } = site;
  const mapUrl =
    content.showMap === false
      ? ""
      : content.mapUrl ||
        (profile.address
          ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(profile.address)}`
          : "");
  const rows = week(content.workingHours);
  const anyHours = content.workingHours.length > 0;
  const contacts = [
    profile.address && { key: "address", value: profile.address },
    profile.phone && {
      key: "phone",
      value: profile.phone,
      href: `tel:${profile.phone.replace(/[^\d+]/g, "")}`,
    },
    content.contactEmail && {
      key: "email",
      value: content.contactEmail,
      href: `mailto:${content.contactEmail}`,
    },
  ].filter(Boolean) as { key: string; value: string; href?: string }[];

  if (!anyHours && contacts.length === 0 && content.socials.length === 0)
    return null;

  return (
    <section
      className="section section--dark on-dark"
      aria-labelledby="visit-title"
    >
      <div className="shell">
        <h2 id="visit-title" className="visually-hidden">
          {strings.contact.title}
        </h2>
        <div className="info__grid">
          <div id="hours">
            <p className="section__eyebrow">{strings.hours.title}</p>
            {anyHours ? (
              <dl className="hours__list">
                {rows.map((row) => (
                  <div
                    className={`hours__row${row.closed ? " hours__row--closed" : ""}`}
                    key={row.day}
                  >
                    <dt>{strings.days[row.day - 1]}</dt>
                    <dd>
                      {row.closed ? (
                        strings.hours.closed
                      ) : (
                        <>
                          {row.opens}–{row.closes}
                          {row.overnight && (
                            <span className="hours__next">
                              {" "}
                              ({strings.hours.nextDay})
                            </span>
                          )}
                        </>
                      )}
                    </dd>
                  </div>
                ))}
              </dl>
            ) : (
              <p className="section__intro">{strings.hours.empty}</p>
            )}
          </div>

          <div id="contact">
            <p className="section__eyebrow">{strings.contact.title}</p>
            <dl className="contact__list">
              {contacts.map((entry) => (
                <div key={entry.key}>
                  <dt>
                    {
                      strings.contact[
                        entry.key as "address" | "phone" | "email"
                      ]
                    }
                  </dt>
                  <dd>
                    {entry.href ? (
                      <a href={entry.href}>{entry.value}</a>
                    ) : (
                      entry.value
                    )}
                  </dd>
                </div>
              ))}
              {mapUrl && (
                <div>
                  <dt>{strings.contact.directions}</dt>
                  <dd>
                    <a href={mapUrl} target="_blank" rel="noopener noreferrer">
                      {strings.contact.directions}
                    </a>
                  </dd>
                </div>
              )}
              {content.socials.length > 0 && (
                <div>
                  <dt>{strings.contact.follow}</dt>
                  <dd className="contact__socials">
                    {content.socials.map((social) => (
                      <a
                        key={social.url}
                        href={social.url}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        {social.label}
                      </a>
                    ))}
                  </dd>
                </div>
              )}
            </dl>
          </div>
        </div>
      </div>
    </section>
  );
}
