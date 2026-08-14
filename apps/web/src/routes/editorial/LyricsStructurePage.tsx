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
  const labels: Record<string, string> = {
    DRAFT: 'Borrador',
    IN_REVIEW: 'En revisión',
    APPROVED: 'Aprobada',
    PUBLISHED: 'Publicada',
    STALE: 'Necesita revisión',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

function displaySectionType(value: string) {
  const labels: Record<string, string> = {
    INTRO: 'Introducción',
    VERSE: 'Verso',
    PRE_CHORUS: 'Pre-coro',
    CHORUS: 'Coro',
    BRIDGE: 'Puente',
    INTERLUDE: 'Interludio',
    SOLO: 'Solo',
    OUTRO: 'Cierre',
    OTHER: 'Otro',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

function countLines(revision: LyricsRevision) {
  return revision.sections.reduce((total, section) => total + section.lines.length, 0);
}

function countTokens(revision: LyricsRevision) {
  return revision.sections.reduce(
    (sectionTotal, section) =>
      sectionTotal + section.lines.reduce((lineTotal, line) => lineTotal + line.tokens.length, 0),
    0,
  );
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

  const revision = state.phase === 'ready' ? state.data.revision : null;
  const lineCount = revision ? countLines(revision) : 0;
  const tokenCount = revision ? countTokens(revision) : 0;

  return (
    <article className="route-surface lyrics-structure" data-route-id="UI-MVP-021">
      <header className="lyrics-structure__header">
        <p className="eyebrow">BL-MVP-053–054 · UI-MVP-021</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Letra japonesa
        </h1>
        <p>
          Escribe y organiza la letra como la leerá una persona. Puedes pegar varias líneas de una
          vez, separar versos y coros, indicar voces y guardar nuevas revisiones sin publicar.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando letra"
          description="Buscando la revisión más reciente de esta canción."
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
          title="Todavía no hay letra"
          description="Empieza escribiendo o pegando la primera sección. Nada se publicará al guardar."
        />
      ) : null}

      {revision ? (
        <>
          <section className="lyrics-structure__summary" aria-label="Resumen de la letra">
            <div>
              <strong>r{revision.revisionNo}</strong>
              <span>revisión actual</span>
            </div>
            <div>
              <strong>{displayState(revision.statusCode)}</strong>
              <span>estado</span>
            </div>
            <div>
              <strong>{revision.sections.length}</strong>
              <span>secciones</span>
            </div>
            <div>
              <strong>{lineCount}</strong>
              <span>líneas</span>
            </div>
            <div>
              <strong>{tokenCount}</strong>
              <span>tokens definidos</span>
            </div>
          </section>
        </>
      ) : null}

      {state.phase === 'ready' ? (
        <>
          <ol className="lyrics-structure__guide" aria-label="Flujo para editar la letra">
            <li>
              <strong>1. Organiza</strong>
              <span>Separa introducción, versos, coros y otras partes.</span>
            </li>
            <li>
              <strong>2. Transcribe</strong>
              <span>Pega o escribe el japonés y marca voces o contenido desconocido.</span>
            </li>
            <li>
              <strong>3. Revisa y guarda</strong>
              <span>Previsualiza el resultado y crea una nueva revisión de borrador.</span>
            </li>
          </ol>

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
        </>
      ) : null}

      {revision ? (
        <details className="lyrics-structure__technical">
          <summary>Ver estructura técnica de la revisión</summary>
          <div className="lyrics-structure__technical-content">
            <section
              className="lyrics-structure__revision"
              aria-labelledby="lyrics-structure-revision"
            >
              <div>
                <h2 id="lyrics-structure-revision">Revisión {revision.revisionNo}</h2>
                <p>
                  {displayState(revision.statusCode)} · versión {revision.version}
                </p>
              </div>
              <dl>
                <div>
                  <dt>Secciones</dt>
                  <dd>{revision.sections.length}</dd>
                </div>
                <div>
                  <dt>Líneas</dt>
                  <dd>{lineCount}</dd>
                </div>
                <div>
                  <dt>Checksum</dt>
                  <dd>
                    <code>{revision.checksumSha256.slice(0, 16)}…</code>
                  </dd>
                </div>
              </dl>
            </section>

            <section aria-labelledby="lyrics-structure-tree">
              <header className="lyrics-structure__section-heading">
                <h2 id="lyrics-structure-tree">Árbol estructural</h2>
                <p>
                  Esta vista sirve para revisar normalización, tokens y offsets. No necesitas usarla
                  para editar la letra normalmente.
                </p>
              </header>

              <ol className="lyrics-structure__sections">
                {revision.sections.map((section) => (
                  <li key={section.sectionId}>
                    <article className="lyrics-structure__section-card">
                      <header>
                        <div>
                          <p className="eyebrow">Sección {section.displayOrder + 1}</p>
                          <h3>{section.label ?? displaySectionType(section.sectionType)}</h3>
                        </div>
                        <span>{displaySectionType(section.sectionType)}</span>
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
          </div>
        </details>
      ) : null}

      {revision ? (
        <StateMessage
          state="UI-EST-11"
          title="Guardada como borrador"
          description="Esta revisión sigue fuera de publicación. Los cambios futuros crean otra revisión o actualizan únicamente un borrador autorizado."
        />
      ) : null}
    </article>
  );
}
