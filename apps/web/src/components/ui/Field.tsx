import type { InputHTMLAttributes } from 'react';

export type FieldProps = Omit<
  InputHTMLAttributes<HTMLInputElement>,
  'id' | 'aria-describedby' | 'aria-invalid'
> & {
  id: string;
  label: string;
  helpText?: string;
  error?: string;
};

export function Field({
  className,
  error,
  helpText,
  id,
  label,
  required,
  ...inputProps
}: FieldProps) {
  const helpId = `${id}-help`;
  const errorId = `${id}-error`;
  const describedBy =
    [helpText ? helpId : undefined, error ? errorId : undefined].filter(Boolean).join(' ') ||
    undefined;
  const classes = ['ma-field__control', className].filter(Boolean).join(' ');

  return (
    <div className="ma-field">
      <label className="ma-field__label" htmlFor={id}>
        {label}
        {required ? <span aria-hidden="true"> *</span> : null}
      </label>
      {helpText ? (
        <span className="ma-field__help" id={helpId}>
          {helpText}
        </span>
      ) : null}
      <input
        {...inputProps}
        aria-describedby={describedBy}
        aria-invalid={error ? true : undefined}
        className={classes}
        id={id}
        required={required}
      />
      {error ? (
        <span className="ma-field__error" id={errorId} role="alert">
          {error}
        </span>
      ) : null}
    </div>
  );
}
