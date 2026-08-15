import { useCallback, useEffect, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import { SynchronizedYouTubePreview } from '../../features/player/synchronization/SynchronizedYouTubePreview';
import type {
  LocalSynchronizationSnapshot,
  SynchronizationTimeline,
} from '../../features/player/synchronization/LocalSynchronizationEngine';
import type {
  YouTubePlayerController,
  YouTubePlayerState,
} from '../../integrations/youtube/YouTubeIframeAdapter';
import { EditorialKaraokePreview } from './EditorialKaraokePreview';
import {
  SynchronizationTimelineEditor,
  type TimingRevisionEditorSnapshot,
} from './SynchronizationTimelineEditor';
import './synchronization-structure.css';

const client = createHttpClient();

type TimingToken = {
  tokenId: string;
  tokenNo: number;
  surface: string;
  startMs: number;
  endMs: number;
};

type TimingLine = {
  lineId: string;
  sectionOrder: number;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
  precisionCode: string;
  startMs: number;
  endMs: number;
  tokens: TimingToken[];
};

type TimingRevision = {
  timingRevisionId: string;
  lyricsRevisionId: string;
  sourceId: string;
  revisionNo: number;
  offsetMs: number;
  statusCode: string;
  checksumSha256: string;
  lines: TimingLine[];
};

type SynchronizationSource = {
  sourceId: string;
  providerCode: string;
  externalRef: string;
  durationMs: number | null;
  sourceOffsetMs: number;
  statusCode: string;
  timingRevision: TimingRevision | null;
};

type SynchronizationContext = {
  recordingId: string;
  lyricsRevisionId: string | null;
  lyricsRevisionNo: number | null;
  sources: SynchronizationSource[];
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: SynchronizationContext }
  | { phase: 'failed'; problem: ClientProblem };

export type SynchronizationStructurePageProps = {
  recordingId: string;
};

type SourceWorkspaceProps = {
  recordingId: string;
  lyricsRevisionId: string;
  source: SynchronizationSource;
  onSaved: (revision: TimingRevisionEditorSnapshot) => void;
};

function milliseconds(value: number) {
  return `${value} ms`;
}

function displayCode(value: string) {
  return value.replaceAll('_', ' ');
}

function timelineForSource(source: SynchronizationSource): SynchronizationTimeline | null {
  const revision = source.timingRevision;
  if (!revision) return null;

  const maximumPrecision = revision.lines.some((line) => line.precisionCode === 'TOKEN')
    ? 'TOKEN'
    : revision.lines.length > 0
      ? 'LINE'
      : 'NONE';

  return {
    available: revision.lines.length > 0,
    maximumPrecision,
    offsetMs: revision.offsetMs,
    lines: revision.lines.map((line) => ({
      sectionOrder: line.sectionOrder,
      lineNo: line.lineNo,
      japaneseText: line.japaneseText,
      speakerLabel: line.speakerLabel,
      precisionCode: line.precisionCode,
      startMs: line.startMs,
      endMs: line.endMs,
      tokens: line.tokens.map((token) => ({
        tokenNo: token.tokenNo,
        surface: token.surface,
        startMs: token.startMs,
        endMs: token.endMs,
      })),
    })),
  };
}

function SourceSynchronizationWorkspace({
  recordingId,
  lyricsRevisionId,
  source,
  onSaved,
}: SourceWorkspaceProps) {
  const [playerController, setPlayerController] = useState<YouTubePlayerController | null>(null);
  const [playerState, setPlayerState] = useState<YouTubePlayerState>('unstarted');
  const [playbackPositionMs, setPlaybackPositionMs] = useState(0);

  const handleSnapshotChange = useCallback((snapshot: LocalSynchronizationSnapshot) => {
    setPlaybackPositionMs(snapshot.positionMs);
  }, []);

  return (
    <div className="synchronization-structure__workspace" data-editorial-sync-workspace>
      <div
        className="synchronization-structure__preview-panel"
        role="group"
        aria-label="Video y seguimiento"
      >
        <p className="eyebrow">BL-MVP-058 · VISTA PREVIA EDITORIAL · NO PUBLICA</p>
        <p className="eyebrow">BL-MVP-059 · SEGUIMIENTO LOCAL</p>
        <SynchronizedYouTubePreview
          externalRef={source.externalRef}
          title={`Fuente editorial ${source.externalRef}`}
          timeline={timelineForSource(source)}
          headingLevel={4}
          onControllerReady={setPlayerController}
          onSnapshotChange={handleSnapshotChange}
          onPlayerStateChange={setPlayerState}
        />
      </div>

      <div className="synchronization-structure__editor-panel">
        {source.durationMs === null ? (
          <StateMessage
            state="UI-EST-10"
            title="Duración pendiente"
            description="Puedes previsualizar la fuente, pero la edición temporal se habilita cuando exista una duración confirmada."
          />
        ) : (
          <SynchronizationTimelineEditor
            recordingId={recordingId}
            lyricsRevisionId={lyricsRevisionId}
            source={source}
            playerController={playerController}
            playerState={playerState}
            playbackPositionMs={playbackPositionMs}
            onSaved={onSaved}
          />
        )}
      </div>
    </div>
  );
}

export function SynchronizationStructurePage({ recordingId }: SynchronizationStructurePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [activePanel, setActivePanel] = useState<'synchronization' | 'karaoke'>('synchronization');

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<SynchronizationContext>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/synchronization-context`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;

      setState(
        result.ok
          ? { phase: 'ready', data: result.data }
          : { phase: 'failed', problem: result.problem },
      );
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  return (
    <article className="route-surface synchronization-structure" data-route-id="UI-MVP-022">
      <header className="synchronization-structure__header">
        <p className="eyebrow">BL-MVP-056–059 · UI-MVP-022</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Revisiones de sincronización
        </h1>
        <p>
          Trabaja con el video y la línea actual en una misma vista. Cada fuente conserva su propia
          revisión temporal y el borrador sigue separado de la publicación.
        </p>
      </header>

      {state.phase === 'ready' && state.data.lyricsRevisionId ? (
        <div
          className="synchronization-structure__view-switcher"
          role="group"
          aria-label="Vista de trabajo de sincronización"
        >
          <button
            type="button"
            aria-pressed={activePanel === 'synchronization'}
            onClick={() => setActivePanel('synchronization')}
          >
            Revisión de sincronización
          </button>
          <button
            type="button"
            aria-pressed={activePanel === 'karaoke'}
            onClick={() => setActivePanel('karaoke')}
          >
            Previsualización de Karaoke
          </button>
        </div>
      ) : null}

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando sincronización"
          description="Resolviendo la revisión de letra y las fuentes exactas de la grabación."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-04"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {state.phase === 'ready' && !state.data.lyricsRevisionId ? (
        <StateMessage
          state="UI-EST-12"
          title="Sin revisión de letra"
          description="Primero estructura y confirma una revisión de letra para poder asociar tiempos."
        />
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId && state.data.sources.length === 0 ? (
        <StateMessage
          state="UI-EST-12"
          title="Sin fuentes multimedia"
          description="La grabación todavía no tiene una fuente exacta disponible para sincronizar."
        />
      ) : null}

      {state.phase === 'ready' &&
      state.data.lyricsRevisionId &&
      activePanel === 'synchronization' ? (
        <section aria-labelledby="synchronization-sources">
          <header className="synchronization-structure__section-heading">
            <div>
              <h2 id="synchronization-sources">Fuentes y revisiones</h2>
              <p>
                Letra base: revisión {state.data.lyricsRevisionNo}. Selecciona una fuente y trabaja
                sin perder de vista el video.
              </p>
            </div>
          </header>

          <ol className="synchronization-structure__sources">
            {state.data.sources.map((source) => (
              <li key={source.sourceId}>
                <article className="synchronization-structure__source">
                  <header>
                    <div>
                      <p className="eyebrow">{source.providerCode}</p>
                      <h3>{source.externalRef}</h3>
                    </div>
                    <span>{displayCode(source.statusCode)}</span>
                  </header>

                  <dl className="synchronization-structure__source-meta">
                    <div>
                      <dt>Duración confirmada</dt>
                      <dd>
                        {source.durationMs === null
                          ? 'Sin confirmar'
                          : milliseconds(source.durationMs)}
                      </dd>
                    </div>
                    <div>
                      <dt>Offset de la fuente</dt>
                      <dd>{milliseconds(source.sourceOffsetMs)}</dd>
                    </div>
                    <div>
                      <dt>Revisión temporal</dt>
                      <dd>
                        {source.timingRevision
                          ? `${source.timingRevision.revisionNo} · ${displayCode(source.timingRevision.statusCode)}`
                          : 'Aún sin revisión'}
                      </dd>
                    </div>
                  </dl>

                  {source.providerCode === 'YOUTUBE' ? (
                    <SourceSynchronizationWorkspace
                      recordingId={recordingId}
                      lyricsRevisionId={state.data.lyricsRevisionId!}
                      source={source}
                      onSaved={(revision) =>
                        setState((current) =>
                          current.phase !== 'ready'
                            ? current
                            : {
                                phase: 'ready',
                                data: {
                                  ...current.data,
                                  sources: current.data.sources.map((candidate) =>
                                    candidate.sourceId === source.sourceId
                                      ? { ...candidate, timingRevision: revision }
                                      : candidate,
                                  ),
                                },
                              },
                        )
                      }
                    />
                  ) : source.durationMs === null ? (
                    <StateMessage
                      state="UI-EST-10"
                      title="Duración pendiente"
                      description="La fuente puede inspeccionarse, pero la edición temporal requiere una duración confirmada."
                    />
                  ) : (
                    <SynchronizationTimelineEditor
                      recordingId={recordingId}
                      lyricsRevisionId={state.data.lyricsRevisionId!}
                      source={source}
                      onSaved={(revision: TimingRevisionEditorSnapshot) =>
                        setState((current) =>
                          current.phase !== 'ready'
                            ? current
                            : {
                                phase: 'ready',
                                data: {
                                  ...current.data,
                                  sources: current.data.sources.map((candidate) =>
                                    candidate.sourceId === source.sourceId
                                      ? { ...candidate, timingRevision: revision }
                                      : candidate,
                                  ),
                                },
                              },
                        )
                      }
                    />
                  )}

                  {source.timingRevision ? (
                    <section
                      className="synchronization-structure__revision"
                      aria-label={`Revisión temporal ${source.timingRevision.revisionNo}`}
                    >
                      <header>
                        <div>
                          <h4>Revisión temporal {source.timingRevision.revisionNo}</h4>
                          <p>
                            {displayCode(source.timingRevision.statusCode)} · offset global{' '}
                            {milliseconds(source.timingRevision.offsetMs)}
                          </p>
                        </div>
                        <code>{source.timingRevision.checksumSha256.slice(0, 12)}…</code>
                      </header>

                      <ol className="synchronization-structure__lines">
                        {source.timingRevision.lines.map((line) => (
                          <li key={line.lineId}>
                            <article className="synchronization-structure__line">
                              <header>
                                <div>
                                  <strong>Línea {line.lineNo}</strong>
                                  {line.speakerLabel ? <span>{line.speakerLabel}</span> : null}
                                </div>
                                <span>{displayCode(line.precisionCode)}</span>
                              </header>

                              <p lang="ja">{line.japaneseText}</p>
                              <p>
                                {milliseconds(line.startMs)} → {milliseconds(line.endMs)}
                              </p>

                              {line.tokens.length > 0 ? (
                                <ul
                                  className="synchronization-structure__tokens"
                                  aria-label={`Tiempos por token de la línea ${line.lineNo}`}
                                >
                                  {line.tokens.map((token) => (
                                    <li key={token.tokenId}>
                                      <span lang="ja">{token.surface}</span>
                                      <small>
                                        {milliseconds(token.startMs)}–{milliseconds(token.endMs)}
                                      </small>
                                    </li>
                                  ))}
                                </ul>
                              ) : null}
                            </article>
                          </li>
                        ))}
                      </ol>
                    </section>
                  ) : (
                    <StateMessage
                      state="UI-EST-12"
                      title="Sin revisión de sincronización"
                      description="Esta fuente todavía no tiene marcas temporales para la revisión de letra seleccionada. Puedes crearlas en el editor sin publicar."
                    />
                  )}
                </article>
              </li>
            ))}
          </ol>
        </section>
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId && activePanel === 'karaoke' ? (
        <EditorialKaraokePreview recordingId={recordingId} sources={state.data.sources} />
      ) : null}

      {activePanel === 'synchronization' ? (
        <StateMessage
          state="UI-EST-11"
          title="Sincronización editable con seguimiento local"
          description="BL-MVP-057 guarda revisiones DRAFT y BL-MVP-059 puede seguirlas durante la previsualización. El editor mantiene video, línea y controles juntos; esta pantalla no publica."
        />
      ) : null}
    </article>
  );
}
