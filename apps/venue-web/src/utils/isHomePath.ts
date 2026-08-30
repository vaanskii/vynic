import type { Language } from '../contexts/LanguageContext';

const HOME_PATH = /^\/(en|ka|ru)\/?$/;

export function isHomePath(pathname: string): boolean {
  return pathname === '/' || HOME_PATH.test(pathname);
}

export function languageFromPath(pathname: string): Language | null {
  const match = pathname.match(/^\/(en|ka|ru)(\/|$)/);
  return match ? (match[1] as Language) : null;
}
