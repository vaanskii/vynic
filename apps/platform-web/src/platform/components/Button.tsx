import type { ButtonHTMLAttributes, ReactNode } from "react";

type Tone = "primary" | "secondary" | "danger" | "quiet";

export function Button({
  children,
  tone = "secondary",
  className = "",
  loading = false,
  loadingLabel,
  disabled,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode;
  tone?: Tone;
  loading?: boolean;
  loadingLabel?: string;
}) {
  return (
    <button className={`platform-button platform-button--${tone} ${className}`} {...props}
      disabled={disabled || loading} aria-busy={loading || undefined}>
      {loading && <span className="platform-button__spinner" aria-hidden="true" />}
      {loading && loadingLabel ? loadingLabel : children}
    </button>
  );
}
