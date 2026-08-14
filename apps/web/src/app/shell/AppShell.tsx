import { useEffect, useState, type ReactNode } from 'react';
import type { VisibleAccessSnapshot } from '../access/AccessContext';
import type { AppRoute } from '../router/route-manifest';
import { BackofficeShell } from './BackofficeShell';
import { PublicHeader } from './PublicHeader';
import { StudentNav } from './StudentNav';

export type AppShellProps = {
  access: VisibleAccessSnapshot;
  allowed: boolean;
  route: AppRoute | null;
  children: ReactNode;
};

function BackToTopButton() {
  const [visible, setVisible] = useState(() => window.scrollY > 360);

  useEffect(() => {
    const update = () => setVisible(window.scrollY > 360);
    update();
    window.addEventListener('scroll', update, { passive: true });
    return () => window.removeEventListener('scroll', update);
  }, []);

  if (!visible) return null;

  const goToTop = () => {
    const main = document.getElementById('main-content');
    main?.focus({ preventScroll: true });

    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({
      top: 0,
      left: 0,
      behavior: reducedMotion ? 'auto' : 'smooth',
    });
  };

  return (
    <button
      type="button"
      className="ma-button ma-button--secondary app-back-to-top"
      onClick={goToTop}
      aria-label="Volver al inicio de la página"
    >
      <span aria-hidden="true">↑</span>
      Volver arriba
    </button>
  );
}

export function AppShell({ access, allowed, children, route }: AppShellProps) {
  const pathname = window.location.pathname;
  const protectedBackoffice =
    route && (route.area === 'editorial' || route.area === 'administration');

  const content = (
    <main className="app-main" data-design-tokens="v1" id="main-content" tabIndex={-1}>
      {children}
    </main>
  );

  if (protectedBackoffice && allowed) {
    return (
      <>
        <a className="skip-link" href="#main-content">
          Saltar al contenido
        </a>
        <BackofficeShell access={access} pathname={pathname}>
          {content}
        </BackofficeShell>
        <BackToTopButton />
      </>
    );
  }

  return (
    <div className="app-shell" data-app-shell="bl-mvp-020">
      <a className="skip-link" href="#main-content">
        Saltar al contenido
      </a>
      <PublicHeader access={access} pathname={pathname} />
      {access.isAuthenticated ? <StudentNav pathname={pathname} /> : null}
      {content}
      <BackToTopButton />
      <footer className="app-footer">
        <p>
          La navegación visible orienta; la autorización de datos y acciones pertenece al servidor.
        </p>
      </footer>
    </div>
  );
}
