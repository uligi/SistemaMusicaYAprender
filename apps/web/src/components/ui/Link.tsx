import type { AnchorHTMLAttributes } from 'react';

export type LinkProps = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href'> & {
  href: string;
};

export function Link({ className, href, ...props }: LinkProps) {
  const classes = ['ma-link', className].filter(Boolean).join(' ');

  return <a className={classes} href={href} {...props} />;
}
