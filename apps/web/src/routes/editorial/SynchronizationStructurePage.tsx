import { useEffect, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import { YouTubeIframeAdapter } from '../../integrations/youtube/YouTubeIframeAdapter';
import {
  SynchronizationTimelineEditor,
  type TimingRevisionEditorSnapshot,
} from './SynchronizationTimelineEditor';
import type { ClientProblem } from '../../data/http/types';
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

function milliseconds(value: number) {
  return `${value} ms`;
}

function displayCode(value: string) {
  return value.replaceAll('_', ' ');
}

export function SynchronizationStructurePage({ recordingId }: SynchronizationStructurePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });

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

      if (result.kind === 'cancelled') {
        return;
      }

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
        <p className="eyebrow">BL-MVP-056–057 · UI-MVP-022</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Revisiones de sincronización
        </h1>
        <p>
          Cada fuente multimedia conserva una revisión temporal independiente sobre una revisión
          exacta de la letra. Los intervalos se expresan en milisegundos y el editor permite marcar,
          desplazar, previsualizar y guardar borradores sin publicar.
        </p>
      </header>

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

      {state.phase === 'ready' && state.data.lyricsRevisionId ? (
        <section aria-labelledby="synchronization-sources">
          <header className="synchronization-structure__section-heading">
            <div>
              <h2 id="synchronization-sources">Fuentes y revisiones</h2>
              <p>
                Letra base: revisión {state.data.lyricsRevisionNo}. Cambiar de fuente no reutiliza
                silenciosamente sus marcas temporales.
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
                  </dl>

                  {source.providerCode === 'YOUTUBE' ? (
                    <div className="synchronization-structure__external-preview">
                      <p className="eyebrow">BL-MVP-058 · VISTA PREVIA EDITORIAL · NO PUBLICA</p>
                      <YouTubeIframeAdapter
                        externalRef={source.externalRef}
                        title={`Fuente editorial ${source.externalRef}`}
                        headingLevel={4}
                      />
                    </div>
                  ) : null}

                  {source.durationMs === null ? (
                    <StateMessage
                      state="UI-EST-10"
                      title="Duración pendiente"
                      description="Los segmentos pueden modelarse, pero no se confirma una revisión temporal válida hasta conocer la duración exacta."
                    />
                  ) : null}

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
                      description="Esta fuente todavía no tiene marcas temporales para la revisión de letra seleccionada."
                    />
                  )}

                  {source.durationMs !== null ? (
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
                  ) : null}
                </article>
              </li>
            ))}
          </ol>
        </section>
      ) : null}

      <StateMessage
        state="UI-EST-11"
        title="Sincronización editable, todavía no publicada"
        description="BL-MVP-057 guarda revisiones DRAFT. BL-MVP-058 permite previsualizar la fuente YouTube sin publicar; BL-MVP-059 resolverá el seguimiento de reproducción."
      />
    </article>
  );
}
