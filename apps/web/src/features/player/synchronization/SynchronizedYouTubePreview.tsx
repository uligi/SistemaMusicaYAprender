import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  YouTubeIframeAdapter,
  type YouTubeAdapterEvent,
  type YouTubePlayerController,
  type YouTubePlayerState,
} from '../../../integrations/youtube/YouTubeIframeAdapter';
import {
  createLocalSynchronizationIndex,
  emptySynchronizationTimeline,
  locateSynchronization,
  type LocalSynchronizationSnapshot,
  type SynchronizationTimeline,
} from './LocalSynchronizationEngine';
import './local-synchronization.css';

const playbackPollMs = 100;
const pausedPollMs = 250;

export type SynchronizedYouTubePreviewProps = {
  externalRef: string;
  title: string;
  timeline: SynchronizationTimeline | null;
  headingLevel?: 2 | 3 | 4;
  presentation?: 'technical' | 'learning';
  onControllerReady?: (controller: YouTubePlayerController | null) => void;
  onSnapshotChange?: (snapshot: LocalSynchronizationSnapshot) => void;
  onPlayerStateChange?: (state: YouTubePlayerState) => void;
};

function noneSnapshot(): LocalSynchronizationSnapshot {
  return {
    positionMs: 0,
    level: 'NONE',
    line: null,
    token: null,
  };
}

function useLocalSynchronization(
  timeline: SynchronizationTimeline | null,
  controller: YouTubePlayerController | null,
) {
  const index = useMemo(
    () => createLocalSynchronizationIndex(timeline ?? emptySynchronizationTimeline()),
    [timeline],
  );
  const [snapshot, setSnapshot] = useState<LocalSynchronizationSnapshot>(noneSnapshot);
  const [playerState, setPlayerState] = useState<YouTubePlayerState>('unstarted');
  const controllerRef = useRef<YouTubePlayerController | null>(controller);
  const indexRef = useRef(index);

  const resynchronize = useCallback(() => {
    const currentController = controllerRef.current;
    if (!currentController) {
      setSnapshot(noneSnapshot());
      return;
    }

    try {
      const seconds = currentController.getCurrentTime();
      setSnapshot(locateSynchronization(indexRef.current, Math.max(0, seconds) * 1000));
    } catch {
      setSnapshot(noneSnapshot());
    }
  }, []);

  const onPlayerEvent = useCallback(
    (event: YouTubeAdapterEvent) => {
      if (event.type === 'state') {
        setPlayerState(event.state);
      }

      window.setTimeout(resynchronize, 0);
    },
    [resynchronize],
  );

  useEffect(() => {
    controllerRef.current = controller;
    indexRef.current = index;
    resynchronize();
  }, [controller, index, resynchronize]);

  useEffect(() => {
    if (!controller) return;

    const intervalMs =
      playerState === 'playing' ? playbackPollMs : playerState === 'paused' ? pausedPollMs : null;

    if (intervalMs === null) return;

    resynchronize();
    const timer = window.setInterval(resynchronize, intervalMs);
    return () => window.clearInterval(timer);
  }, [controller, playerState, resynchronize]);

  return { snapshot, playerState, onPlayerEvent };
}

export function SynchronizedYouTubePreview({
  externalRef,
  title,
  timeline,
  headingLevel = 2,
  presentation = 'technical',
  onControllerReady,
  onSnapshotChange,
  onPlayerStateChange,
}: SynchronizedYouTubePreviewProps) {
  const [controller, setController] = useState<YouTubePlayerController | null>(null);
  const { snapshot, playerState, onPlayerEvent } = useLocalSynchronization(timeline, controller);
  const Heading = headingLevel === 4 ? 'h4' : headingLevel === 3 ? 'h3' : 'h2';
  const available = Boolean(timeline?.available && timeline.lines.length > 0);
  const learningPresentation = presentation === 'learning';

  const handleControllerReady = useCallback(
    (nextController: YouTubePlayerController | null) => {
      setController(nextController);
      onControllerReady?.(nextController);
    },
    [onControllerReady],
  );

  useEffect(() => {
    onSnapshotChange?.(snapshot);
  }, [onSnapshotChange, snapshot]);

  useEffect(() => {
    onPlayerStateChange?.(playerState);
  }, [onPlayerStateChange, playerState]);

  useEffect(
    () => () => {
      onControllerReady?.(null);
    },
    [onControllerReady],
  );

  return (
    <div className="local-synchronization">
      <YouTubeIframeAdapter
        externalRef={externalRef}
        title={title}
        headingLevel={headingLevel}
        onControllerReady={handleControllerReady}
        onEvent={onPlayerEvent}
      />

      <section
        className="local-synchronization__status"
        aria-live="off"
        data-local-synchronization
        data-presentation={presentation}
        data-sync-level={snapshot.level}
        data-sync-position-ms={snapshot.positionMs}
      >
        <p className="eyebrow">
          {learningPresentation
            ? 'SEGUIMIENTO DE LETRA'
            : 'BL-MVP-059 · MOTOR LOCAL DE SINCRONIZACIÓN'}
        </p>
        <Heading>
          {learningPresentation ? 'Seguimiento de reproducción' : 'Sincronización local'}
        </Heading>

        {!available ? (
          <p>
            Sin marcas temporales compatibles. El reproductor puede seguir disponible sin activar
            una línea inventada.
          </p>
        ) : learningPresentation ? (
          <p>
            La línea activa se actualiza con la reproducción sin mover el foco ni interrumpir tus
            controles.
          </p>
        ) : (
          <p>
            Precisión máxima disponible:{' '}
            <strong>{timeline?.maximumPrecision === 'TOKEN' ? 'token' : 'línea'}</strong>.
          </p>
        )}

        {available && snapshot.line ? (
          <>
            {!learningPresentation ? (
              <p>
                Nivel activo: <strong>{snapshot.level === 'TOKEN' ? 'token' : 'línea'}</strong> ·{' '}
                {snapshot.positionMs} ms
              </p>
            ) : null}
            <p className="local-synchronization__line">
              Línea {snapshot.line.lineNo}: <span lang="ja">{snapshot.line.japaneseText}</span>
            </p>
            {snapshot.token ? (
              <p className="local-synchronization__token">
                Token {snapshot.token.tokenNo}: <span lang="ja">{snapshot.token.surface}</span>
              </p>
            ) : null}
          </>
        ) : available ? (
          <p>Esperando una posición que pertenezca a un segmento temporal disponible.</p>
        ) : null}
      </section>
    </div>
  );
}
