import type { VisibleAccessSnapshot } from '../access/AccessContext';
import { AppLink } from '../router/navigation';
import { routeManifest, type AppRoute } from '../router/route-manifest';
import './backoffice-sidebar.css';

type SidebarItem = {
  routeId: AppRoute['id'];
  label: string;
  href: string;
};

const routeById = new Map(routeManifest.map((route) => [route.id, route]));

function canOpen(routeId: AppRoute['id'], access: VisibleAccessSnapshot): boolean {
  const route = routeById.get(routeId);
  if (!route) return false;
  if (route.access !== 'capability') return true;

  const required = route.requiredCapabilities ?? [];
  if (required.length === 0) return false;

  return route.capabilityMode === 'all'
    ? required.every((capability) => access.capabilities.includes(capability))
    : required.some((capability) => access.capabilities.includes(capability));
}

function isCurrent(pathname: string, href: string): boolean {
  if (href === '/editorial') return pathname === href;
  if (href === '/administracion/auditoria') {
    return pathname === href || pathname.startsWith(`${href}/`);
  }
  return pathname === href;
}

function recordingIdFrom(pathname: string): string | null {
  const match = pathname.match(
    /^\/editorial\/canciones\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:\/|$)/i,
  );
  return match?.[1] ?? null;
}

function dynamicIdFrom(pathname: string, prefix: string): string | null {
  const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = pathname.match(
    new RegExp(
      `^${escaped}/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:/|$)`,
      'i',
    ),
  );
  return match?.[1] ?? null;
}

function SidebarGroup({
  access,
  items,
  label,
  pathname,
}: {
  access: VisibleAccessSnapshot;
  items: readonly SidebarItem[];
  label: string;
  pathname: string;
}) {
  const visible = items.filter((item) => canOpen(item.routeId, access));
  if (visible.length === 0) return null;

  return (
    <section className="backoffice-sidebar__group" aria-label={label}>
      <h2 className="backoffice-sidebar__heading">{label}</h2>
      <div className="backoffice-sidebar__links">
        {visible.map((item) => (
          <AppLink
            className="backoffice-sidebar__link"
            current={isCurrent(pathname, item.href)}
            href={item.href}
            key={`${item.routeId}:${item.href}`}
          >
            {item.label}
          </AppLink>
        ))}
      </div>
    </section>
  );
}

export type BackofficeSidebarProps = {
  access: VisibleAccessSnapshot;
  pathname: string;
};

export function BackofficeSidebar({ access, pathname }: BackofficeSidebarProps) {
  const recordingId = recordingIdFrom(pathname);
  const packageId = dynamicIdFrom(pathname, '/editorial/paquetes');
  const publicationId = dynamicIdFrom(pathname, '/administracion/publicaciones');
  const correctionId = dynamicIdFrom(pathname, '/administracion/correcciones');

  const editorialItems: SidebarItem[] = [
    { routeId: 'UI-MVP-017', label: 'Bandeja editorial', href: '/editorial' },
    { routeId: 'UI-MVP-018', label: 'Nueva canción', href: '/editorial/canciones/nueva' },
  ];

  if (recordingId) {
    editorialItems.push(
      {
        routeId: 'UI-MVP-019',
        label: 'Expediente',
        href: `/editorial/canciones/${recordingId}`,
      },
      {
        routeId: 'UI-MVP-020',
        label: 'Créditos y procedencia',
        href: `/editorial/canciones/${recordingId}/derechos`,
      },
      {
        routeId: 'UI-MVP-021',
        label: 'Letra',
        href: `/editorial/canciones/${recordingId}/letra`,
      },
      {
        routeId: 'UI-MVP-022',
        label: 'Sincronización',
        href: `/editorial/canciones/${recordingId}/sincronizacion`,
      },
      {
        routeId: 'UI-MVP-023',
        label: 'Traducción',
        href: `/editorial/canciones/${recordingId}/traduccion`,
      },
      {
        routeId: 'UI-MVP-024',
        label: 'Análisis lingüístico',
        href: `/editorial/canciones/${recordingId}/analisis`,
      },
      {
        routeId: 'UI-MVP-025',
        label: 'Ejercicios',
        href: `/editorial/canciones/${recordingId}/ejercicios`,
      },
    );
  }

  if (packageId) {
    editorialItems.push({
      routeId: 'UI-MVP-026',
      label: 'Paquete editorial',
      href: `/editorial/paquetes/${packageId}`,
    });
  }

  const administrationItems: SidebarItem[] = [
    { routeId: 'UI-MVP-029', label: 'Roles y accesos', href: '/administracion/roles' },
    {
      routeId: 'UI-MVP-030',
      label: 'Catálogos y parámetros',
      href: '/administracion/configuracion',
    },
    { routeId: 'UI-MVP-031', label: 'Auditoría', href: '/administracion/auditoria' },
  ];

  if (publicationId) {
    administrationItems.unshift({
      routeId: 'UI-MVP-027',
      label: 'Revisión y publicación',
      href: `/administracion/publicaciones/${publicationId}`,
    });
  }

  if (correctionId) {
    administrationItems.unshift({
      routeId: 'UI-MVP-028',
      label: 'Corrección o reversión',
      href: `/administracion/correcciones/${correctionId}`,
    });
  }

  return (
    <aside className="backoffice-sidebar" aria-label="Panel lateral del backoffice">
      <p className="backoffice-sidebar__eyebrow">Panel interno</p>
      <SidebarGroup access={access} items={editorialItems} label="Editorial" pathname={pathname} />
      <SidebarGroup
        access={access}
        items={administrationItems}
        label="Administración"
        pathname={pathname}
      />
      <div className="backoffice-sidebar__footer">
        <AppLink className="backoffice-sidebar__link" href="/">
          Volver al sitio
        </AppLink>
        <p>El menú orienta la navegación; el servidor vuelve a validar cada permiso y ámbito.</p>
      </div>
    </aside>
  );
}
