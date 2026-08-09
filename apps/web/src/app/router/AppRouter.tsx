import { lazy, Suspense, useEffect } from 'react';
import { StateMessage } from '../../components/ui';
import { AccessBoundary, evaluateVisibleAccess } from '../access/AccessBoundary';
import { useVisibleAccess } from '../access/AccessContext';
import { AppShell } from '../shell/AppShell';
import { matchRoute } from './match-route';
import { useBrowserLocation } from './navigation';
import type { AppArea } from './route-manifest';

const PublicArea = lazy(() => import('../../routes/public/PublicArea'));
const StudentArea = lazy(() => import('../../routes/student/StudentArea'));
const EditorialArea = lazy(() => import('../../routes/editorial/EditorialArea'));
const AdministrationArea = lazy(() => import('../../routes/administration/AdministrationArea'));

const areaComponents = {
  public: PublicArea,
  student: StudentArea,
  editorial: EditorialArea,
  administration: AdministrationArea,
} satisfies Record<AppArea, typeof PublicArea>;

export function AppRouter() {
  const location = useBrowserLocation();
  const access = useVisibleAccess();
  const match = matchRoute(location.pathname, location.search);

  useEffect(() => {
    document.title = match
      ? `${match.route.title} · Música y Aprender`
      : 'Ruta no disponible · Música y Aprender';
  }, [match]);

  if (!match) {
    return (
      <AppShell access={access} allowed={false} route={null}>
        <StateMessage
          state="UI-EST-03"
          title="Ruta no disponible"
          description="La dirección no coincide con una pantalla vigente. No se redirige silenciosamente a otro contenido."
        />
      </AppShell>
    );
  }

  const decision = evaluateVisibleAccess(match.route, access);
  const AreaComponent = areaComponents[match.route.area];

  return (
    <AppShell access={access} allowed={decision.allowed} route={match.route}>
      <AccessBoundary access={access} route={match.route}>
        <Suspense
          fallback={
            <StateMessage
              state="UI-EST-01"
              title="Cargando área"
              description="La interfaz reserva el contenido principal mientras carga únicamente el bundle de esta ruta."
            />
          }
        >
          <AreaComponent match={match} />
        </Suspense>
      </AccessBoundary>
    </AppShell>
  );
}
