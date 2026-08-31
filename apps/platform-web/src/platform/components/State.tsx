import { ArrowClockwise, WarningCircle } from "@phosphor-icons/react";
import type { ReactNode } from "react";
import { Button } from "./Button";

export function LoadingState({ label = "Loading" }: { label?: string }) {
  return (
    <div className="platform-state" aria-live="polite" aria-busy="true">
      <span className="platform-spinner" aria-hidden="true" />
      <p>{label}…</p>
    </div>
  );
}

export function ErrorState({ error, retry }: { error: string; retry?: () => void }) {
  return (
    <div className="platform-state platform-state--error" role="alert">
      <WarningCircle size={24} weight="duotone" />
      <strong>Couldn’t load this view</strong>
      <p>{error}</p>
      {retry ? (
        <Button type="button" onClick={retry}>
          <ArrowClockwise size={16} /> Retry
        </Button>
      ) : null}
    </div>
  );
}

export function EmptyState({ title, body, action }: { title: string; body: string; action?: ReactNode }) {
  return (
    <div className="platform-state platform-state--empty">
      <strong>{title}</strong>
      <p>{body}</p>
      {action}
    </div>
  );
}
