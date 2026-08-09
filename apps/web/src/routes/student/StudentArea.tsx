import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';

export type StudentAreaProps = {
  match: RouteMatch;
};

export default function StudentArea({ match }: StudentAreaProps) {
  return (
    <RoutePlaceholder
      areaLabel="Área estudiante"
      description="La experiencia de estudiante conserva la frontera entre contenido público y datos privados. Persistir preferencias, respuestas o progreso requiere una sesión confirmada por el servidor."
      match={match}
    />
  );
}
