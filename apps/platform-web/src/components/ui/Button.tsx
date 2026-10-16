import { ArrowDown, ArrowRight } from "@phosphor-icons/react";
import type { Icon } from "@phosphor-icons/react";
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";
import { Link } from "react-router-dom";

type ButtonVariant = "primary" | "secondary" | "plain";

type CommonButtonProps = {
  children: ReactNode;
  variant?: ButtonVariant;
  icon?: Icon;
};

type ButtonProps =
  | (CommonButtonProps &
      ButtonHTMLAttributes<HTMLButtonElement> & {
        href?: undefined;
      })
  | (CommonButtonProps &
      AnchorHTMLAttributes<HTMLAnchorElement> & {
        href: string;
      });

const baseClass =
  "group inline-flex min-h-11 items-center justify-center gap-2 rounded-[8px] px-5 py-3 text-sm font-semibold leading-none transition-[translate,scale,background-color,border-color,color,box-shadow] duration-200 ease-[cubic-bezier(0.16,1,0.3,1)] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-vynic-plum motion-safe:not-disabled:hover:-translate-y-px motion-safe:not-disabled:active:translate-y-0 motion-safe:not-disabled:active:scale-[0.98] disabled:opacity-60";

const variantClass: Record<ButtonVariant, string> = {
  primary:
    "vynic-neu-primary bg-vynic-plum text-vynic-background shadow-[0_14px_30px_color-mix(in_srgb,var(--vynic-plum)_24%,transparent)] hover:bg-vynic-plum-dark hover:shadow-[0_18px_36px_color-mix(in_srgb,var(--vynic-plum)_32%,transparent)]",
  secondary:
    "vynic-neu-control border border-vynic-border bg-vynic-surface text-vynic-charcoal hover:border-vynic-plum hover:text-vynic-plum",
  plain:
    "px-0 text-vynic-charcoal hover:text-vynic-plum",
};

export function Button({
  children,
  href,
  variant = "primary",
  icon,
  className = "",
  ...props
}: ButtonProps) {
  const IconComponent = icon ?? (variant === "secondary" ? ArrowDown : ArrowRight);
  const classes = `${baseClass} ${variantClass[variant]} ${className}`;

  if (href) {
    const anchorProps = props as AnchorHTMLAttributes<HTMLAnchorElement>;

    return (
      <a className={classes} href={href} {...anchorProps}>
        <span className="whitespace-nowrap">{children}</span>
        <IconComponent
          className="shrink-0 transition-transform duration-200 group-hover:translate-x-0.5"
          size={17}
          weight="bold"
        />
      </a>
    );
  }

  const buttonProps = props as ButtonHTMLAttributes<HTMLButtonElement>;

  return (
    <button className={classes} {...buttonProps}>
      <span className="whitespace-nowrap">{children}</span>
      <IconComponent
        className="shrink-0 transition-transform duration-200 group-hover:translate-x-0.5"
        size={17}
        weight="bold"
      />
    </button>
  );
}

/** A primary/secondary button that navigates inside the app without a reload. */
export function ButtonLink({
  children,
  to,
  variant = "primary",
  icon,
  className = "",
  iconClassName = "",
  onClick,
}: CommonButtonProps & {
  to: string;
  className?: string;
  iconClassName?: string;
  onClick?: () => void;
}) {
  const IconComponent = icon ?? ArrowRight;
  return (
    <Link
      className={`${baseClass} ${variantClass[variant]} ${className}`}
      to={to}
      onClick={onClick}
    >
      <span className="whitespace-nowrap">{children}</span>
      <IconComponent
        className={`shrink-0 transition-transform duration-200 group-hover:translate-x-0.5 ${iconClassName}`}
        size={17}
        weight="bold"
      />
    </Link>
  );
}
