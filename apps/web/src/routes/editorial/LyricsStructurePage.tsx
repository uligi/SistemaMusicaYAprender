import { useEffect, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { LyricsStructuredEditor } from './LyricsStructuredEditor';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import './lyrics-structure.css';

const client = createHttpClient();

export type LyricsToken = {
  tokenId: string;
  tokenNo: number;
  surface: string;
  normalizedSurface: string;
  startOffset: number;
  endOffset: number;
};

export type LyricsLine = {
  lineId: string;
  lineNo: number;
  japaneseText: string;
  normalizedText: string;
  speakerLabel: string | null;
  tokens: LyricsToken[];
};

export type LyricsSection = {
  sectionId: string;
  sectionType: string;
  label: string | null;
  displayOrder: number;
  lines: LyricsLine[];
};

export type LyricsRevision = {
  lyricsRevisionId: string;
  recordingId: string;
  revisionNo: number;
  parentRevisionId: string | null;
  statusCode: string;
  createdBy: string;
  createdAt: string;
  checksumSha256: string;
  version: number;
  sections: LyricsSection[];
};

export type LyricsStructureResponse = {
  exists: boolean;
  revision: LyricsRevision | null;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: LyricsStructureResponse; etag: string }
  | { phase: 'failed'; problem: ClientProblem };

export type LyricsStructurePageProps = {
  recordingId: string;
};

function displayState(value: string) {
  return value.replaceAll('_', ' ');
}

export function LyricsStructurePage({ recordingId }: LyricsStructurePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<LyricsStructureResponse>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/lyrics-revisions/latest`,
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
          ? {
              phase: 'ready',
              data: result.data,
              etag: result.etag ?? '"lyrics-none"',
            }
          : { phase: 'failed', problem: result.problem },
      );
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  return (
    <article className="route-surface lyrics-structure" data-route-id="UI-MVP-021">
      <header className="lyrics-structure__header">
        <p className="eyebrow">BL-MVP-053–054 · UI-MVP-021</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Estructura de letra japonesa
        </h1>
        <p>
          Modelo y editor de revisiones, secciones, líneas y voces. La superficie japonesa se
          conserva separada de cualquier normalización; el borrador puede previsualizarse y
          guardarse sin publicar.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando estructura de letra"
          description="Resolviendo la revisión más reciente para esta grabación."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-04"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {state.phase === 'ready' && !state.data.exists ? (
        <StateMessage
          state="UI-EST-12"
          title="Sin revisión de letra"
          description="La grabación todavía no tiene una revisión estructurada. Puedes comenzar un borrador en el editor de esta pantalla."
        />
      ) : null}

      {state.phase === 'ready' ? (
        <LyricsStructuredEditor
          recordingId={recordingId}
          revision={state.data.revision}
          etag={state.etag}
          onSaved={(response, nextEtag) =>
            setState({
              phase: 'ready',
              data: response,
              etag: nextEtag,
            })
          }
        />
      ) : null}

      {state.phase === 'ready' && state.data.revision ? (
        <>
          <section
            className="lyrics-structure__revision"
            aria-labelledby="lyrics-structure-revision"
          >
            <div>
              <h2 id="lyrics-structure-revision">Revisión {state.data.revision.revisionNo}</h2>
              <p>
                {displayState(state.data.revision.statusCode)} · versión{' '}
                {state.data.revision.version}
              </p>
            </div>
            <dl>
              <div>
                <dt>Secciones</dt>
                <dd>{state.data.revision.sections.length}</dd>
              </div>
              <div>
                <dt>Checksum</dt>
                <dd>
                  <code>{state.data.revision.checksumSha256.slice(0, 16)}…</code>
                </dd>
              </div>
            </dl>
          </section>

          <section aria-labelledby="lyrics-structure-tree">
            <header className="lyrics-structure__section-heading">
              <h2 id="lyrics-structure-tree">Árbol estructural</h2>
              <p>
                Los identificadores son internos y estables; el texto visible nunca funciona como
                clave.
              </p>
            </header>

            <ol className="lyrics-structure__sections">
              {state.data.revision.sections.map((section) => (
                <li key={section.sectionId}>
                  <article className="lyrics-structure__section-card">
                    <header>
                      <div>
                        <p className="eyebrow">Sección {section.displayOrder + 1}</p>
                        <h3>{section.label ?? displayState(section.sectionType)}</h3>
                      </div>
                      <span>{displayState(section.sectionType)}</span>
                    </header>

                    <ol className="lyrics-structure__lines">
                      {section.lines.map((line) => (
                        <li key={line.lineId}>
                          <article className="lyrics-structure__line">
                            <header>
                              <strong>Línea {line.lineNo}</strong>
                              {line.speakerLabel ? <span>{line.speakerLabel}</span> : null}
                            </header>

                            <p className="lyrics-structure__surface" lang="ja">
                              {line.japaneseText}
                            </p>

                            {line.normalizedText !== line.japaneseText ? (
                              <p className="lyrics-structure__normalized">
                                <strong>Normalizada:</strong>{' '}
                                <span lang="ja">{line.normalizedText}</span>
                              </p>
                            ) : null}

                            {line.tokens.length > 0 ? (
                              <ul
                                className="lyrics-structure__tokens"
                                aria-label={`Tokens de la línea ${line.lineNo}`}
                              >
                                {line.tokens.map((token) => (
                                  <li key={token.tokenId}>
                                    <span lang="ja">{token.surface}</span>
                                    <small>
                                      {token.startOffset}–{token.endOffset}
                                    </small>
                                  </li>
                                ))}
                              </ul>
                            ) : (
                              <p className="lyrics-structure__no-tokens">
                                Sin tokens manuales en esta revisión.
                              </p>
                            )}
                          </article>
                        </li>
                      ))}
                    </ol>
                  </article>
                </li>
              ))}
            </ol>
          </section>

          <StateMessage
            state="UI-EST-11"
            title="Revisión modelada, no publicada"
            description="Corregir una revisión futura crea una nueva versión o edita únicamente un borrador autorizado; una revisión aprobada no se sobrescribe físicamente."
          />
        </>
      ) : null}
    </article>
  );
}
