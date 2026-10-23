import type { Strings } from "../i18n";

/**
 * Everything that is not a published restaurant page.
 *
 * These are deliberately plain and deliberately distinct: a CUSTOM Venue, an
 * unpublished site and a transport failure are different facts, and none of
 * them may be dressed up as restaurant content.
 */
export function PageState({
  kind,
  strings,
  onRetry,
}: {
  kind:
    | "loading"
    | "custom"
    | "unavailable"
    | "unsupported"
    | "error"
    | "missing"
    | "pending"
    | "address";
  strings: Strings;
  onRetry?: () => void;
}) {
  if (kind === "loading")
    return (
      <div className="state">
        <p role="status">{strings.loading}</p>
      </div>
    );
  const copy = strings[kind];
  return (
    <main className="state" aria-live="polite">
      <a className="state-brand" href="https://vynic.ge">
        Vynic
      </a>
      <h1>{copy.title}</h1>
      <p>{copy.body}</p>
      <div className="state-actions">
        {kind === "error" && onRetry && (
          <button type="button" onClick={onRetry}>
            {strings.error.retry}
          </button>
        )}
        <a className="state-link" href="https://vynic.ge">
          {strings.goToVynic}
        </a>
      </div>
    </main>
  );
}
