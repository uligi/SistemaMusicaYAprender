import type { ReactNode } from 'react';
import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { ArtistAdministrationPage } from './ArtistAdministrationPage';
import { RightsProvenancePage } from './RightsProvenancePage';
import { SongContextNavigation } from './SongContextNavigation';
import { SongDraftDetailPage } from './SongDraftDetailPage';

export type EditorialAreaProps = {
  match: RouteMatch;
};

function SongWorkspace({ children, match }: { children: ReactNode; match: RouteMatch }) {
  const recordingId = match.params.id ?? '';

  return (
    <div className="song-workspace">
      <SongContextNavigation recordingId={recordingId} currentRouteId={match.route.id} />
      {children}
    </div>
  );
}

export default function EditorialArea({ match }: EditorialAreaProps) {
  if (match.route.id === 'UI-MVP-018') {
    return <ArtistAdministrationPage />;
  }

  if (match.route.id === 'UI-MVP-019') {
    return (
      <SongWorkspace match={match}>
        <SongDraftDetailPage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (match.route.id === 'UI-MVP-020') {
    return (
      <SongWorkspace match={match}>
        <RightsProvenancePage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (
    match.route.id === 'UI-MVP-021' ||
    match.route.id === 'UI-MVP-022' ||
    match.route.id === 'UI-MVP-023' ||
    match.route.id === 'UI-MVP-024' ||
    match.route.id === 'UI-MVP-025'
  ) {
    return (
      <SongWorkspace match={match}>
        <RoutePlaceholder
          areaLabel="Área editorial"
          description="Esta función pertenece a la canción seleccionada. El servidor vuelve a comprobar capacidad y alcance antes de cualquier operación."
          match={match}
        />
      </SongWorkspace>
    );
  }

  return (
    <RoutePlaceholder
      areaLabel="Área editorial"
      description="El backoffice editorial se carga únicamente tras una capacidad visible compatible. La autorización por objeto y el alcance real se vuelven a comprobar en el servidor."
      match={match}
    />
  );
}
