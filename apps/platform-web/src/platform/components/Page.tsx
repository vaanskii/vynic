import type { ReactNode } from "react";

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <header className="platform-page-header">
      <div>
        {eyebrow ? <p className="platform-eyebrow">{eyebrow}</p> : null}
        <h1>{title}</h1>
        {description ? <p>{description}</p> : null}
      </div>
      {actions ? <div className="platform-page-header__actions">{actions}</div> : null}
    </header>
  );
}

export function Panel({ title, description, action, children, className = "" }: {
  title?: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`platform-panel ${className}`}>
      {title || action ? (
        <header className="platform-panel__header">
          <div>
            {title ? <h2>{title}</h2> : null}
            {description ? <p>{description}</p> : null}
          </div>
          {action}
        </header>
      ) : null}
      {children}
    </section>
  );
}

export function Detail({ label, children, mono = false }: { label: string; children: ReactNode; mono?: boolean }) {
  return (
    <div className="platform-detail">
      <dt>{label}</dt>
      <dd className={mono ? "platform-mono" : undefined}>{children}</dd>
    </div>
  );
}
