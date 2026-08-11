import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { PersonalPreferencesPage } from './PersonalPreferencesPage';
import './student-area.css';

export type StudentAreaProps = {
  match: RouteMatch;
};

export default function StudentArea({ match }: StudentAreaProps) {
  if (match.route.id === 'UI-MVP-008') {
    return <PersonalPreferencesPage />;
  }

  return (
    <RoutePlaceholder
      areaLabel="Área estudiante"
      description="La experiencia de estudiante conserva la frontera entre contenido público y datos privados. Persistir preferencias, respuestas o progreso requiere una sesión confirmada por el servidor."
      match={match}
    />
  );
}
