import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { PersonalAccountLoginPage } from './PersonalAccountLoginPage';
import { PersonalAccountRegistrationPage } from './PersonalAccountRegistrationPage';
import { PersonalAccountVerificationPage } from './PersonalAccountVerificationPage';
import { PublicSongCatalogPage } from './PublicSongCatalogPage';
import { PublicSongDetailPage } from './PublicSongDetailPage';
import './public-area.css';

export type PublicAreaProps = {
  match: RouteMatch;
};

export default function PublicArea({ match }: PublicAreaProps) {
  if (match.route.id === 'UI-MVP-002' || match.route.id === 'UI-MVP-003') {
    return <PublicSongCatalogPage routeId={match.route.id} />;
  }

  if (match.route.id === 'UI-MVP-004') {
    return <PublicSongDetailPage slug={match.params.slug ?? ''} />;
  }

  if (match.route.id === 'UI-MVP-005') {
    return <PersonalAccountRegistrationPage />;
  }

  if (match.route.id === 'UI-MVP-006') {
    return <PersonalAccountVerificationPage />;
  }

  if (match.route.id === 'UI-MVP-007') {
    return <PersonalAccountLoginPage />;
  }

  return (
    <RoutePlaceholder
      areaLabel="Área pública"
      description="La ruta pública está preparada para su historia funcional. Solo mostrará revisiones publicadas y nunca persistirá progreso anónimo como hecho confirmado."
      match={match}
      showJapaneseReference={match.route.id === 'UI-MVP-001'}
    />
  );
}
