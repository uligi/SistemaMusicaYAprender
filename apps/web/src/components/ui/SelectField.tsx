import type { ReactNode, SelectHTMLAttributes } from 'react';

export type SelectFieldProps = Omit<
  SelectHTMLAttributes<HTMLSelectElement>,
  'id' | 'aria-describedby' | 'aria-invalid' | 'children'
> & {
  id: string;
  label: string;
  children: ReactNode;
  helpText?: string;
  error?: string;
};

export function SelectField({
  children,
  className,
  error,
  helpText,
  id,
  label,
  required,
  ...selectProps
}: SelectFieldProps) {
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
      <select
        {...selectProps}
        aria-describedby={describedBy}
        aria-invalid={error ? true : undefined}
        className={classes}
        id={id}
        required={required}
      >
        {children}
      </select>
      {error ? (
        <span className="ma-field__error" id={errorId} role="alert">
          {error}
        </span>
      ) : null}
    </div>
  );
}
