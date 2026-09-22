import type { Language, Strings } from "../../../i18n";
import { localized } from "../../../i18n";
import type { MenuGroup, MenuItem, WebsiteMenu, WebsiteSite } from "../../../api/types";
import { absolute } from "../../../seo/documentHead";
import { formatPrice, formatSize } from "../format";

/**
 * The restaurant's live menu, as the website is allowed to present it.
 *
 * Every name, price and variant here belongs to the operational POS/Cloud menu;
 * the only website-owned values are the optional public name, description,
 * image and order the owner set in the portal. Nothing is cached or copied, so
 * an item that stops being sold stops appearing.
 */
export function Menu({
  site,
  menu,
  strings,
  language,
  origin,
}: {
  site: WebsiteSite;
  menu: WebsiteMenu | null;
  strings: Strings;
  language: Language;
  origin: string;
}) {
  const { content, profile } = site;
  if (!content.showMenu) return null;
  const heading = content.menuHeading || strings.menu.title;
  const currency = menu?.currency ?? profile.currency;
  const categories = menu?.categories ?? [];

  return (
    <section
      className="section section--raised"
      id="menu"
      aria-labelledby="menu-title"
    >
      <div className="shell">
        {heading !== strings.menu.title && (
          <p className="section__eyebrow">{strings.menu.title}</p>
        )}
        <h2 id="menu-title">{heading}</h2>
        {content.menuIntro && (
          <p className="section__intro">{content.menuIntro}</p>
        )}
        {!menu ? (
          <p className="section__intro" role="status">
            {strings.menu.unavailable}
          </p>
        ) : categories.length === 0 ? (
          <p className="section__intro">{strings.menu.empty}</p>
        ) : (
          <div className="menu__categories">
            {categories.map((category) => (
              <div className="menu__category" key={category.id}>
                <h3>{localized(category.name, language)}</h3>
                {category.items.length > 0 && (
                  <Items
                    items={category.items}
                    currency={currency}
                    strings={strings}
                    language={language}
                    origin={origin}
                  />
                )}
                {category.subcategories.map((sub: MenuGroup) => (
                  <div key={sub.id}>
                    <h4 className="menu__subheading">
                      {localized(sub.name, language)}
                    </h4>
                    <Items
                      items={sub.items}
                      currency={currency}
                      strings={strings}
                      language={language}
                      origin={origin}
                    />
                  </div>
                ))}
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function Items({
  items,
  currency,
  strings,
  language,
  origin,
}: {
  items: MenuItem[];
  currency: string;
  strings: Strings;
  language: Language;
  origin: string;
}) {
  return (
    <ul className="menu__items">
      {items.map((item) => {
        const image = absolute(item.imageUrl, origin);
        // A sized product's headline price is its cheapest pour/portion; the
        // exact prices follow, so nothing is rounded away or invented.
        const cheapest = item.variants.length
          ? Math.min(...item.variants.map((variant) => variant.price))
          : item.price;
        return (
          <li className="menu__item" key={item.id}>
            {image && <img src={image} alt="" loading="lazy" />}
            <div className="menu__item-body">
              <p className="menu__item-line">
                <span className="menu__item-name">
                  {item.displayName || localized(item.name, language)}
                </span>
                <span className="menu__leader" aria-hidden="true" />
                <span className="menu__price">
                  {item.variants.length > 0 && language === "en"
                    ? `${strings.menu.from} `
                    : ""}
                  {formatPrice(cheapest, currency, language)}
                  {item.variants.length > 0 && language === "ka"
                    ? strings.menu.from
                    : ""}
                </span>
              </p>
              {item.description && (
                <p className="menu__item-description">{item.description}</p>
              )}
              {item.variants.length > 0 && (
                <p className="menu__variants">
                  {item.variants.map((variant) => (
                    <span key={variant.id}>
                      {formatSize(variant.size)} ·{" "}
                      {formatPrice(variant.price, currency, language)}
                    </span>
                  ))}
                </p>
              )}
            </div>
          </li>
        );
      })}
    </ul>
  );
}
