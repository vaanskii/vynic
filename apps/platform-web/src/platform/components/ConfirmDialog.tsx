import { Button } from "./Button";
import { Dialog } from "./Dialog";

export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  danger = false,
  pending = false,
  error,
  onConfirm,
}: {
  open: boolean;
  onOpenChange(open: boolean): void;
  title: string;
  description: string;
  confirmLabel: string;
  danger?: boolean;
  pending?: boolean;
  error?: string;
  onConfirm(): void;
}) {
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      title={title}
      description={description}
      footer={
        <>
          <Button onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button tone={danger ? "danger" : "primary"} onClick={onConfirm} disabled={pending}>
            {pending ? "Working…" : confirmLabel}
          </Button>
        </>
      }
    >
      <div className={`platform-confirm${danger ? " platform-confirm--danger" : ""}`}>
        <strong>Review the impact before continuing.</strong>
        <p>{description}</p>
      </div>
      {error ? <p className="platform-form-error platform-confirm-error" role="alert">{error}</p> : null}
    </Dialog>
  );
}
