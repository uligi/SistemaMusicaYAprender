import type { ReactNode } from 'react';
import type { VisibleAccessSnapshot } from '../access/AccessContext';
import { AppLink } from '../router/navigation';
import { BackofficeSidebar } from './BackofficeSidebar';

export type BackofficeShellProps = {
  access: VisibleAccessSnapshot;
  pathname: string;
  children: ReactNode;
};

export function BackofficeShell({ access, children, pathname }: BackofficeShellProps) {
  return (
    <div className="backoffice-shell">
      <header className="backoffice-header">
        <AppLink className="app-brand" href="/">
          <span aria-hidden="true" className="app-brand__mark">
            音
          </span>
          <span>Música y Aprender</span>
        </AppLink>
        <span className="backoffice-header__label">Backoffice por capacidades</span>
      </header>

      <div className="backoffice-layout">
        <BackofficeSidebar access={access} pathname={pathname} />
        {children}
      </div>
    </div>
  );
}
