import type { ReactNode } from 'react';
import type { VisibleAccessSnapshot } from '../access/AccessContext';
import { AppLink } from '../router/navigation';

type BackofficeItem = {
  label: string;
  href: string;
  capability: string;
};

const editorialItems: readonly BackofficeItem[] = [
  { label: 'Bandeja', href: '/editorial', capability: 'editorial:access' },
  { label: 'Contenido', href: '/editorial/canciones/nueva', capability: 'catalog:edit' },
  { label: 'Revisiones', href: '/editorial/paquetes/ejemplo', capability: 'package:review' },
];

const administrationItems: readonly BackofficeItem[] = [
  {
    label: 'Publicar',
    href: '/administracion/publicaciones/ejemplo',
    capability: 'publication:review',
  },
  {
    label: 'Corregir',
    href: '/administracion/correcciones/ejemplo',
    capability: 'publication:correct',
  },
  { label: 'Roles', href: '/administracion/roles', capability: 'security:roles' },
  {
    label: 'Configuración',
    href: '/administracion/configuracion',
    capability: 'configuration:manage',
  },
  { label: 'Auditoría', href: '/administracion/auditoria', capability: 'audit:read' },
];

export type BackofficeShellProps = {
  access: VisibleAccessSnapshot;
  pathname: string;
  children: ReactNode;
};

export function BackofficeShell({ access, children, pathname }: BackofficeShellProps) {
  const items = [...editorialItems, ...administrationItems].filter((item) =>
    access.capabilities.includes(item.capability),
  );

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
        <nav aria-label="Navegación interna por capacidades" className="backoffice-nav">
          {items.map((item) => (
            <AppLink
              className="backoffice-nav__link"
              current={pathname === item.href || pathname.startsWith(`${item.href}/`)}
              href={item.href}
              key={`${item.capability}:${item.href}`}
            >
              {item.label}
            </AppLink>
          ))}
        </nav>
        {children}
      </div>
    </div>
  );
}
