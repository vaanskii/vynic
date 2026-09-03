import * as DialogPrimitive from "@radix-ui/react-dialog";
import { X } from "@phosphor-icons/react";
import type { ReactNode } from "react";

export function Dialog({
  open,
  onOpenChange,
  title,
  description,
  children,
  footer,
}: {
  open: boolean;
  onOpenChange(open: boolean): void;
  title: string;
  description?: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <DialogPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="platform-dialog__overlay" />
        <DialogPrimitive.Content className="platform-dialog__content">
          <div className="platform-dialog__header">
            <div>
              <DialogPrimitive.Title>{title}</DialogPrimitive.Title>
              {description ? (
                <DialogPrimitive.Description>{description}</DialogPrimitive.Description>
              ) : null}
            </div>
            <DialogPrimitive.Close className="platform-icon-button" aria-label="Close dialog">
              <X size={18} />
            </DialogPrimitive.Close>
          </div>
          <div className="platform-dialog__body">{children}</div>
          {footer ? <div className="platform-dialog__footer">{footer}</div> : null}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
