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
  georgian = false,
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
  georgian?: boolean;
}) {
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => { if (!pending) onOpenChange(next); }}
      title={title}
      description={description}
      footer={
        <>
          <Button disabled={pending} onClick={() => onOpenChange(false)}>
            {georgian ? "გაუქმება" : "Cancel"}
          </Button>
          <Button
            tone={danger ? "danger" : "primary"}
            onClick={onConfirm}
            loading={pending}
          >
            {pending ? (georgian ? "ინახება…" : "Working…") : confirmLabel}
          </Button>
        </>
      }
    >
      <div
        className={`platform-confirm${danger ? " platform-confirm--danger" : ""}`}
      >
        <strong>
          {georgian
            ? "გაგრძელებამდე გადაამოწმეთ ცვლილება."
            : "Review the impact before continuing."}
        </strong>
        <p>{description}</p>
      </div>
      {error ? (
        <p className="platform-form-error platform-confirm-error" role="alert">
          {error}
        </p>
      ) : null}
    </Dialog>
  );
}
