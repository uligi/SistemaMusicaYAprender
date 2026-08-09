import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';

export type AdministrationAreaProps = {
  match: RouteMatch;
};

export default function AdministrationArea({ match }: AdministrationAreaProps) {
  return (
    <RoutePlaceholder
      areaLabel="Área administración"
      description="Las operaciones privilegiadas conservan mínimo privilegio y segregación. La navegación visible nunca sustituye reautenticación, autorización ni auditoría del servidor."
      match={match}
    />
  );
}
