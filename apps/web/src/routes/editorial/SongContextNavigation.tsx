import { useVisibleAccess } from '../../app/access/AccessContext';
import { AppLink } from '../../app/router/navigation';
import { routeManifest, type AppRoute } from '../../app/router/route-manifest';
import './song-context-navigation.css';

type SongContextItem = {
  routeId: AppRoute['id'];
  label: string;
  href: (recordingId: string) => string;
};

const routeById = new Map(routeManifest.map((route) => [route.id, route]));

const songHref =
  (suffix = '') =>
  (recordingId: string) =>
    `/editorial/canciones/${encodeURIComponent(recordingId)}${suffix}`;

const songItems: readonly SongContextItem[] = [
  { routeId: 'UI-MVP-019', label: 'Expediente', href: songHref() },
  {
    routeId: 'UI-MVP-020',
    label: 'Derechos y procedencia',
    href: songHref('/derechos'),
  },
  { routeId: 'UI-MVP-021', label: 'Letra', href: songHref('/letra') },
  {
    routeId: 'UI-MVP-022',
    label: 'Sincronización',
    href: songHref('/sincronizacion'),
  },
  {
    routeId: 'UI-MVP-023',
    label: 'Traducción',
    href: songHref('/traduccion'),
  },
  {
    routeId: 'UI-MVP-024',
    label: 'Análisis lingüístico',
    href: songHref('/analisis'),
  },
  {
    routeId: 'UI-MVP-025',
    label: 'Ejercicios',
    href: songHref('/ejercicios'),
  },
  {
    routeId: 'UI-MVP-026',
    label: 'Paquete y revisión',
    href: (recordingId) => `/editorial/paquetes/${encodeURIComponent(recordingId)}`,
  },
];

function canOpen(routeId: AppRoute['id'], capabilities: readonly string[]): boolean {
  const route = routeById.get(routeId);
  if (!route) return false;
  if (route.access !== 'capability') return true;

  const required = route.requiredCapabilities ?? [];
  if (required.length === 0) return false;

  return route.capabilityMode === 'all'
    ? required.every((capability) => capabilities.includes(capability))
    : required.some((capability) => capabilities.includes(capability));
}

export type SongContextNavigationProps = {
  recordingId: string;
  currentRouteId: AppRoute['id'];
};

export function SongContextNavigation({ recordingId, currentRouteId }: SongContextNavigationProps) {
  const access = useVisibleAccess();
  const visibleItems = songItems.filter((item) => canOpen(item.routeId, access.capabilities));

  if (!recordingId || visibleItems.length === 0) return null;

  return (
    <nav className="song-context-nav" aria-label="Opciones de la canción">
      <div className="song-context-nav__heading">
        <span className="song-context-nav__eyebrow">Canción seleccionada</span>
        <strong>Opciones de la canción</strong>
      </div>
      <div className="song-context-nav__links">
        {visibleItems.map((item) => (
          <AppLink
            className="song-context-nav__link"
            current={currentRouteId === item.routeId}
            href={item.href(recordingId)}
            key={item.routeId}
          >
            {item.label}
          </AppLink>
        ))}
      </div>
    </nav>
  );
}
