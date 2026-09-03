import type { ButtonHTMLAttributes, ReactNode } from "react";

type Tone = "primary" | "secondary" | "danger" | "quiet";

export function Button({
  children,
  tone = "secondary",
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { children: ReactNode; tone?: Tone }) {
  return (
    <button className={`platform-button platform-button--${tone} ${className}`} {...props}>
      {children}
    </button>
  );
}
