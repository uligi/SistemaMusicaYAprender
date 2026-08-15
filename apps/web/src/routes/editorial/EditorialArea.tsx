import type { ReactNode } from 'react';
import type { RouteMatch } from '../../app/router/match-route';
import { RoutePlaceholder } from '../shared/RoutePlaceholder';
import { NewSongAssistantPage } from './NewSongAssistantPage';
import { EditorialInboxPage } from './EditorialInboxPage';
import { RightsProvenancePage } from './RightsProvenancePage';
import { LyricsStructurePage } from './LyricsStructurePage';
import { SynchronizationStructurePage } from './SynchronizationStructurePage';
import { TranslationStructurePage } from './TranslationStructurePage';
import { LinguisticAnalysisStructurePage } from './LinguisticAnalysisStructurePage';
import { ExerciseBankPage } from './ExerciseBankPage';
import { SongContextNavigation } from './SongContextNavigation';
import { SongEditorialDossierPage } from './SongEditorialDossierPage';

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
  if (match.route.id === 'UI-MVP-017') {
    return <EditorialInboxPage />;
  }

  if (match.route.id === 'UI-MVP-018') {
    return <NewSongAssistantPage />;
  }

  if (match.route.id === 'UI-MVP-019') {
    return (
      <SongWorkspace match={match}>
        <SongEditorialDossierPage recordingId={match.params.id ?? ''} />
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

  if (match.route.id === 'UI-MVP-021') {
    return (
      <SongWorkspace match={match}>
        <LyricsStructurePage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (match.route.id === 'UI-MVP-022') {
    return (
      <SongWorkspace match={match}>
        <SynchronizationStructurePage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (match.route.id === 'UI-MVP-023') {
    return (
      <SongWorkspace match={match}>
        <TranslationStructurePage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (match.route.id === 'UI-MVP-024') {
    return (
      <SongWorkspace match={match}>
        <LinguisticAnalysisStructurePage recordingId={match.params.id ?? ''} />
      </SongWorkspace>
    );
  }

  if (match.route.id === 'UI-MVP-025') {
    return (
      <SongWorkspace match={match}>
        <ExerciseBankPage recordingId={match.params.id ?? ''} />
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
