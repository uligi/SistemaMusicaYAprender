import type { VisibleAccessSnapshot } from '../access/AccessContext';
import { AppLink } from '../router/navigation';

export type PublicHeaderProps = {
  access: VisibleAccessSnapshot;
  pathname: string;
};

export function PublicHeader({ access, pathname }: PublicHeaderProps) {
  return (
    <header className="app-public-header">
      <div className="app-public-header__inner">
        <AppLink className="app-brand" href="/" current={pathname === '/'}>
          <span aria-hidden="true" className="app-brand__mark">
            音
          </span>
          <span>Música y Aprender</span>
        </AppLink>

        <nav aria-label="Navegación pública" className="app-public-nav">
          <AppLink href="/" current={pathname === '/'}>
            Inicio
          </AppLink>
          <AppLink href="/canciones" current={pathname.startsWith('/canciones')}>
            Canciones
          </AppLink>
          {access.isAuthenticated ? (
            <span className="app-session-label">Sesión confirmada</span>
          ) : (
            <>
              <AppLink href="/registro" current={pathname === '/registro'}>
                Registro
              </AppLink>
              <AppLink href="/acceso" current={pathname === '/acceso'}>
                Acceso
              </AppLink>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}
