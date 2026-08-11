import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { ConfigurationAdministrationPage } from './ConfigurationAdministrationPage';
import { RoleManagementPage } from './RoleManagementPage';

export type AdministrationAreaProps = {
  match: RouteMatch;
};

export default function AdministrationArea({ match }: AdministrationAreaProps) {
  if (match.route.id === 'UI-MVP-029') {
    return <RoleManagementPage />;
  }

  if (match.route.id === 'UI-MVP-030') {
    return <ConfigurationAdministrationPage />;
  }

  return (
    <RoutePlaceholder
      areaLabel="Área administración"
      description="Las operaciones privilegiadas conservan mínimo privilegio y segregación. La navegación visible nunca sustituye reautenticación, autorización ni auditoría del servidor."
      match={match}
    />
  );
}
