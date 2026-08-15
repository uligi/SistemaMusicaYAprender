import { useEffect, useMemo, useRef, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import {
  emptySynchronizationTimeline,
  type LocalSynchronizationSnapshot,
  type SynchronizationTimeline,
} from '../../features/player/synchronization/LocalSynchronizationEngine';
import { SynchronizedYouTubePreview } from '../../features/player/synchronization/SynchronizedYouTubePreview';
import {
  defaultVisibleEducationalLayers,
  EducationalKaraoke,
  type EducationalAnalysisSelection,
  type EducationalLayers,
  type VisibleEducationalLayers,
} from './EducationalKaraoke';
import { ContextualAnalysisPanel } from './ContextualAnalysisPanel';
import './educational-player.css';

const httpClient = createHttpClient();
const territory = 'CR';
const language = 'es';

type PublicEducationalSource = {
  slug: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  recordingDurationMs: number | null;
  artistName: string;
  providerCode: string;
  territoryCode: string;
  languageTag: string | null;
  availableComponents: string[];
  sourceExternalRef: string;
};

type PlayerState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicEducationalSource }
  | { phase: 'unavailable' }
  | { phase: 'failed'; problem: ClientProblem };

type LearningLayersState =
  { phase: 'loading' } | { phase: 'ready'; data: EducationalLayers } | { phase: 'degraded' };

export type EducationalPlayerPageProps = {
  slug: string;
};

function emptySnapshot(): LocalSynchronizationSnapshot {
  return {
    positionMs: 0,
    level: 'NONE',
    line: null,
    token: null,
  };
}

function fallbackLayers(timeline: SynchronizationTimeline | null): EducationalLayers {
  if (!timeline?.available || timeline.lines.length === 0) {
    return {
      available: false,
      targetLanguage: language,
      hasFurigana: false,
      hasRomaji: false,
      hasSpanish: false,
      lines: [],
    };
  }

  return {
    available: true,
    targetLanguage: language,
    hasFurigana: false,
    hasRomaji: false,
    hasSpanish: false,
    lines: timeline.lines.map((line) => ({
      sectionOrder: line.sectionOrder,
      sectionLabel: null,
      lineNo: line.lineNo,
      japaneseText: line.japaneseText,
      speakerLabel: line.speakerLabel,
      tokens: [],
      translations: [],
    })),
  };
}

export function EducationalPlayerPage({ slug }: EducationalPlayerPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PlayerState>({ phase: 'loading' });
  const [timeline, setTimeline] = useState<SynchronizationTimeline | null>(null);
  const [layersState, setLayersState] = useState<LearningLayersState>({ phase: 'loading' });
  const [snapshot, setSnapshot] = useState<LocalSynchronizationSnapshot>(emptySnapshot);
  const [visibleLayers, setVisibleLayers] = useState<VisibleEducationalLayers>({
    ...defaultVisibleEducationalLayers,
  });
  const [analysisSelection, setAnalysisSelection] = useState<EducationalAnalysisSelection | null>(
    null,
  );

  useEffect(() => {
    const controller = new AbortController();
    setState({ phase: 'loading' });
    setTimeline(null);
    setLayersState({ phase: 'loading' });
    setSnapshot(emptySnapshot());
    setVisibleLayers({ ...defaultVisibleEducationalLayers });
    setAnalysisSelection(null);

    const load = async () => {
      const params = new URLSearchParams({ territory, language });
      const detail = await httpClient.get<PublicEducationalSource>(
        `/public/catalog/songs/${encodeURIComponent(slug)}?${params.toString()}`,
        { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
      );

      if (detail.kind === 'cancelled') return;

      if (!detail.ok) {
        if (detail.problem.status === 404) {
          setState({ phase: 'unavailable' });
        } else {
          setState({ phase: 'failed', problem: detail.problem });
        }
        return;
      }

      setState({ phase: 'ready', data: detail.data });

      const [synchronization, layers] = await Promise.all([
        httpClient.get<SynchronizationTimeline>(
          `/public/catalog/songs/${encodeURIComponent(slug)}/synchronization?${params.toString()}`,
          { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
        ),
        httpClient.get<EducationalLayers>(
          `/public/catalog/songs/${encodeURIComponent(slug)}/layers?${params.toString()}`,
          { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
        ),
      ]);

      if (synchronization.kind === 'cancelled' || layers.kind === 'cancelled') return;

      setTimeline(synchronization.ok ? synchronization.data : emptySynchronizationTimeline());
      setLayersState(layers.ok ? { phase: 'ready', data: layers.data } : { phase: 'degraded' });
    };

    void load();
    return () => controller.abort();
  }, [slug]);

  useEffect(() => {
    headingRef.current?.focus();
  }, [state.phase]);

  const learningLayers = useMemo(
    () => (layersState.phase === 'ready' ? layersState.data : fallbackLayers(timeline)),
    [layersState, timeline],
  );

  return (
    <article className="route-surface educational-player" data-route-id="UI-MVP-009">
      <header className="educational-player__header">
        <p className="eyebrow">APRENDER CON LA CANCIÓN</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Reproductor educativo
        </h1>
        <p>
          Sigue la letra sincronizada y activa japonés, furigana, romaji o español sin reiniciar la
          reproducción.
        </p>
      </header>

      <AppLink href={`/canciones/${encodeURIComponent(slug)}`}>Volver a la ficha pública</AppLink>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando la canción"
          description="Comprobando la publicación y preparando el contenido educativo propio."
        />
      ) : null}

      {state.phase === 'unavailable' ? (
        <StateMessage
          state="UI-EST-06"
          title="Canción no disponible"
          description="La publicación no está vigente para esta ruta o territorio."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-06"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {state.phase === 'ready' ? (
        <>
          <section className="educational-player__owned" aria-labelledby="owned-content">
            <p className="eyebrow">CONTENIDO PROPIO</p>
            <h2 id="owned-content" lang="ja">
              {state.data.canonicalTitle}
            </h2>
            <p>
              {state.data.artistName} · {state.data.recordingTitle ?? 'Grabación principal'}
            </p>
            <p>
              Esta informaci&oacute;n, la letra y las dem&aacute;s capas educativas no dependen del
              estado del reproductor externo.
            </p>
          </section>

          <div className="educational-player__learning-layout">
            <EducationalKaraoke
              layers={learningLayers}
              snapshot={snapshot}
              visibleLayers={visibleLayers}
              onVisibleLayersChange={setVisibleLayers}
              selectedAnalysisKey={analysisSelection?.analysisKey ?? null}
              onTokenAnalysis={setAnalysisSelection}
            />

            <ContextualAnalysisPanel
              slug={slug}
              tokenKey={analysisSelection?.analysisKey ?? null}
              surfaceHint={analysisSelection?.surface ?? null}
              onClose={() => setAnalysisSelection(null)}
            />
          </div>

          {layersState.phase === 'loading' ? (
            <p className="educational-player__layer-status" role="status">
              Preparando furigana, romaji y traducción compatibles…
            </p>
          ) : null}

          {layersState.phase === 'degraded' ? (
            <p className="educational-player__layer-status" role="status">
              Las ayudas adicionales no pudieron cargarse. La letra sincronizada disponible se
              conserva sin mezclar revisiones.
            </p>
          ) : null}

          {state.data.providerCode === 'YOUTUBE' ? (
            <SynchronizedYouTubePreview
              externalRef={state.data.sourceExternalRef}
              title={state.data.canonicalTitle}
              timeline={timeline}
              presentation="learning"
              onSnapshotChange={setSnapshot}
            />
          ) : (
            <StateMessage
              state="UI-EST-06"
              title="Fuente no compatible"
              description="La letra educativa permanece disponible, pero esta fuente no puede reproducirse en el adaptador actual."
            />
          )}
        </>
      ) : null}
    </article>
  );
}
