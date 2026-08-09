import { useId, useRef, type ReactNode } from 'react';

import { Button } from './Button';

export type DialogProps = {
  triggerLabel: string;
  title: string;
  description: string;
  children?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
  onConfirm?: () => void;
};

export function Dialog({
  cancelLabel = 'Cancelar',
  children,
  confirmLabel = 'Confirmar',
  danger = false,
  description,
  onConfirm,
  title,
  triggerLabel,
}: DialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const titleId = useId();
  const descriptionId = useId();

  const openDialog = () => {
    dialogRef.current?.showModal();
  };

  const closeDialog = () => {
    dialogRef.current?.close();
  };

  const handleConfirm = () => {
    onConfirm?.();
    closeDialog();
  };

  const restoreTriggerFocus = () => {
    triggerRef.current?.focus();
  };

  return (
    <>
      <Button ref={triggerRef} variant={danger ? 'danger' : 'secondary'} onClick={openDialog}>
        {triggerLabel}
      </Button>

      <dialog
        ref={dialogRef}
        aria-describedby={descriptionId}
        aria-labelledby={titleId}
        aria-modal="true"
        className="ma-dialog"
        onClose={restoreTriggerFocus}
      >
        <div className="ma-dialog__content">
          <h2 id={titleId}>{title}</h2>
          <p id={descriptionId}>{description}</p>
          {children}
          <div className="ma-dialog__actions">
            <Button autoFocus variant="secondary" onClick={closeDialog}>
              {cancelLabel}
            </Button>
            <Button variant={danger ? 'danger' : 'primary'} onClick={handleConfirm}>
              {confirmLabel}
            </Button>
          </div>
        </div>
      </dialog>
    </>
  );
}
