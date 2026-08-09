import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';

export type EditorialAreaProps = {
  match: RouteMatch;
};

export default function EditorialArea({ match }: EditorialAreaProps) {
  return (
    <RoutePlaceholder
      areaLabel="Área editorial"
      description="El backoffice editorial se carga únicamente tras una capacidad visible compatible. La autorización por objeto y el alcance real se vuelven a comprobar en el servidor."
      match={match}
    />
  );
}
