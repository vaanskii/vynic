import type { ComponentType } from "react";
import type { Language, Strings } from "../i18n";
import type { WebsiteMenu, WebsiteSite } from "../api/types";
import { ClassicTheme } from "./classic/ClassicTheme";

/**
 * Themes the generic frontend can render.
 *
 * `themeKey` travels in the published content, so adding a presentation is one
 * entry here plus its components — the public data model, the owner editor and
 * the tenancy path stay untouched. An unknown key falls back to the default
 * rather than rendering nothing: a restaurant whose theme was retired keeps a
 * working site until its owner chooses another.
 */
export interface ThemeProps {
  site: WebsiteSite;
  menu: WebsiteMenu | null;
  strings: Strings;
  language: Language;
  onLanguage: (language: Language) => void;
  origin: string;
}

export const DEFAULT_THEME_KEY = "classic";
const themes: Record<string, ComponentType<ThemeProps>> = {
  classic: ClassicTheme,
};

export function themeFor(themeKey: string) {
  return themes[themeKey] ?? themes[DEFAULT_THEME_KEY];
}
