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
  kind: "loading" | "custom" | "unavailable" | "unsupported" | "error";
  strings: Strings;
  onRetry?: () => void;
}) {
  if (kind === "loading")
    return (
      <div className="state">
        <p role="status">{strings.loading}</p>
      </div>
    );
  const copy =
    kind === "custom"
      ? strings.custom
      : kind === "unsupported"
        ? strings.unsupported
        : kind === "error"
          ? strings.error
          : strings.unavailable;
  return (
    <div className="state">
      <h1>{copy.title}</h1>
      <p>{copy.body}</p>
      {kind === "error" && onRetry && (
        <button type="button" onClick={onRetry}>
          {strings.error.retry}
        </button>
      )}
    </div>
  );
}
