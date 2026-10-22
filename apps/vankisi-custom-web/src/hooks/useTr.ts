import { useLanguage } from '../contexts/LanguageContext';

/**
 * Inline translation helper for one-off component strings.
 * Usage: const tr = useTr(); tr('English', 'ქართული', 'Русский')
 * Falls back to English for any unhandled language.
 */
export function useTr() {
  const { language } = useLanguage();
  return (en: string, ka: string, ru: string): string =>
    language === 'ka' ? ka : language === 'ru' ? ru : en;
}
