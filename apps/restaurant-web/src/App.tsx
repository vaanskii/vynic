import {
  createElement,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";
import { clearPreviewToken, loadSite, readPreviewToken } from "./api/client";
import type { SiteState } from "./api/types";
import {
  rememberLanguage,
  storedLanguage,
  strings as catalogue,
  type Language,
  type Strings,
} from "./i18n";
import { applyDocumentHead } from "./seo/documentHead";
import { themeFor } from "./theme/registry";
import { PageState } from "./components/PageState";

/**
 * One frontend, many restaurants.
 *
 * The Venue is never chosen here. A public visit is resolved by the backend
 * from the request host; an owner preview is resolved from a short-lived
 * preview token. There is no demo Venue, no query parameter and no fallback
 * restaurant, so a request that cannot prove which restaurant it belongs to is
 * shown the unavailable page instead of somebody else's site.
 */
const PREVIEW_PATH = "/preview";

/** The tab title must say the same thing the page says. */
function fallbackTitleFor(kind: SiteState["kind"], strings: Strings) {
  if (kind === "custom") return strings.custom.title;
  if (kind === "unsupported") return strings.unsupported.title;
  if (kind === "error") return strings.error.title;
  if (kind === "loading") return strings.loading;
  if (kind === "missing" || kind === "pending" || kind === "address")
    return strings[kind].title;
  return strings.unavailable.title;
}

export function App() {
  const previewAttempt =
    window.location.pathname === PREVIEW_PATH ||
    window.location.pathname.startsWith(`${PREVIEW_PATH}/`);
  const preview =
    (window.location.pathname === PREVIEW_PATH ||
      window.location.pathname === `${PREVIEW_PATH}/`) && !window.location.search;
  const [language, setLanguage] = useState<Language>(() =>
    storedLanguage(window.localStorage),
  );
  const [state, setState] = useState<SiteState>({ kind: "loading" });
  const [attempt, setAttempt] = useState(0);
  const strings = catalogue[language];
  const origin = window.location.origin;

  // Read once per mount: the token is moved out of the address bar immediately.
  const token = useMemo(
    () =>
      preview ? readPreviewToken(window.location, window.sessionStorage) : null,
    [preview],
  );

  useEffect(() => {
    let live = true;
    void (
      previewAttempt && !preview
        ? Promise.resolve<SiteState>({ kind: "unavailable" })
        : loadSite(preview, token)
    ).then((next) => {
      if (live) setState(next);
    });
    return () => {
      live = false;
    };
  }, [preview, previewAttempt, token, attempt]);

  useEffect(() => {
    applyDocumentHead({
      document,
      state,
      language,
      origin,
      fallbackTitle: fallbackTitleFor(state.kind, strings),
    });
  }, [state, language, origin, strings]);

  const choose = useCallback((next: Language) => {
    setLanguage(next);
    rememberLanguage(window.localStorage, next);
  }, []);

  if (state.kind !== "site")
    return (
      <PageState
        kind={state.kind}
        strings={strings}
        onRetry={() => {
          setState({ kind: "loading" });
          setAttempt((value) => value + 1);
        }}
      />
    );

  // `createElement` rather than a capitalised local: the theme comes from a
  // module-level registry, so it is a stable reference being looked up, not a
  // component being defined during render.
  const theme = themeFor(state.site.content.themeKey);
  return (
    <>
      {state.site.preview && (
        <div className="preview-banner">
          <strong>{strings.preview.badge}</strong>
          <span>{strings.preview.explanation}</span>
          <button
            type="button"
            onClick={() => {
              clearPreviewToken(window.sessionStorage);
              window.location.assign("/");
            }}
          >
            {strings.preview.exit}
          </button>
        </div>
      )}
      {createElement(theme, {
        site: state.site,
        menu: state.menu,
        strings,
        language,
        onLanguage: choose,
        origin,
      })}
    </>
  );
}
