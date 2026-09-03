export function formatDateTime(value: string | null | undefined) {
  if (!value) return "Not available";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Not available";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

export function formatRelativeTime(value: string | null) {
  if (!value) return "Never connected";
  const date = new Date(value);
  const delta = date.getTime() - Date.now();
  if (Number.isNaN(delta)) return "Last seen time unavailable";
  const abs = Math.abs(delta);
  const formatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });
  if (abs < 60_000) return "Last seen just now";
  if (abs < 3_600_000) return `Last seen ${formatter.format(Math.round(delta / 60_000), "minute")}`;
  if (abs < 86_400_000) return `Last seen ${formatter.format(Math.round(delta / 3_600_000), "hour")}`;
  return `Last seen ${formatter.format(Math.round(delta / 86_400_000), "day")}`;
}

export function humanize(value: string) {
  return value
    .replace(/[._-]+/g, " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

export function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Something went wrong. Please try again.";
}
