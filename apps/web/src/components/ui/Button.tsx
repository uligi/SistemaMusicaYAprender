import { forwardRef, type ButtonHTMLAttributes } from 'react';

export type ButtonVariant = 'primary' | 'secondary' | 'danger';

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { className, type = 'button', variant = 'primary', ...props },
  ref,
) {
  const classes = ['ma-button', `ma-button--${variant}`, className].filter(Boolean).join(' ');

  return <button ref={ref} type={type} className={classes} {...props} />;
});
