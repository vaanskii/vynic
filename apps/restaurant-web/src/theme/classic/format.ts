import type { Language } from "../../i18n";
import type { WebsiteHours } from "../../api/types";

const locales: Record<Language, string> = { ka: "ka-GE", en: "en-GB" };

/**
 * A published price in the restaurant's own currency.
 *
 * The currency comes from the Venue, never from the page, and an unfamiliar
 * code falls back to the plain number rather than throwing and taking the menu
 * section down with it.
 */
export function formatPrice(
  value: number,
  currency: string,
  language: Language,
) {
  try {
    return new Intl.NumberFormat(locales[language], {
      style: "currency",
      currency,
      maximumFractionDigits: 2,
    }).format(value);
  } catch {
    return `${value.toFixed(2)} ${currency}`;
  }
}

/** A variant size as authored, without inventing a unit the POS never sent. */
export function formatSize(size: number) {
  return Number.isInteger(size) ? String(size) : String(Number(size.toFixed(3)));
}

/**
 * One week of opening hours, closed days included.
 *
 * A day the owner left out is closed, and a closing time at or before the
 * opening time belongs to the following day — the same rule the content
 * contract validates against, so the page cannot disagree with what was saved.
 */
export function week(hours: WebsiteHours[]) {
  return [1, 2, 3, 4, 5, 6, 7].map((day) => {
    const row = hours.find((entry) => entry.day === day);
    if (!row) return { day, closed: true as const };
    return {
      day,
      closed: false as const,
      opens: row.opens,
      closes: row.closes,
      overnight: row.closes < row.opens,
    };
  });
}

/** Paragraphs from owner-authored plain text; never interpreted as markup. */
export function paragraphs(text: string) {
  return text
    .split(/\n{2,}/)
    .map((block) => block.trim())
    .filter(Boolean);
}
