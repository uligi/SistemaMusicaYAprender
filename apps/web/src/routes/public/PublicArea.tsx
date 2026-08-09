import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';

export type PublicAreaProps = {
  match: RouteMatch;
};

export default function PublicArea({ match }: PublicAreaProps) {
  return (
    <RoutePlaceholder
      areaLabel="Área pública"
      description="La ruta pública está preparada para su historia funcional. Solo mostrará revisiones publicadas y nunca persistirá progreso anónimo como hecho confirmado."
      match={match}
      showJapaneseReference={match.route.id === 'UI-MVP-001'}
    />
  );
}
