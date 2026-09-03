import type { ReactNode } from "react";

export function StatusBadge({ value, children }: { value: string; children?: ReactNode }) {
  const normalized = value.toLowerCase().replace(/[^a-z]+/g, "-");
  return (
    <span className={`platform-badge platform-badge--${normalized}`}>
      <span className="platform-badge__dot" aria-hidden="true" />
      {children ?? value.replaceAll("_", " ")}
    </span>
  );
}
