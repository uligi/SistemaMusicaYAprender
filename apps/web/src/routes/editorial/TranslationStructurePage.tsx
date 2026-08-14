import { useEffect, useRef, useState } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import { TranslationEditor } from './TranslationEditor';
import './translation-structure.css';

const client = createHttpClient();

export type TranslationSourceLine = {
  lineId: string;
  lineNo: number;
  japaneseText: string;
};

export type TranslationAlignment = {
  alignmentId: string;
  tokenId: string;
  sourceLineId: string;
  sourceLineNo: number;
  surface: string;
  targetStart: number | null;
  targetEnd: number | null;
  alignmentType: string;
};

export type TranslationLine = {
  translationLineId: string;
  anchorLineId: string;
  anchorLineNo: number;
  japaneseText: string;
  variantCode: string;
  translatedText: string;
  displayOrder: number;
  alignments: TranslationAlignment[];
};

export type TranslationNote = {
  noteId: string;
  lineId: string | null;
  tokenId: string | null;
  noteType: string;
  noteText: string;
  sourceReferenceId: string | null;
  sourceType: string | null;
  citation: string | null;
  locator: string | null;
};

export type TranslationProvenance = {
  sourceReferenceId: string;
  sourceType: string;
  citation: string;
  locator: string | null;
  contributionType: string;
  recordedBy: string;
  recordedAt: string;
};

export type TranslationRevision = {
  translationRevisionId: string;
  lyricsRevisionId: string;
  lyricsRevisionNo: number;
  targetLanguage: string;
  translationType: string;
  revisionNo: number;
  parentRevisionId: string | null;
  statusCode: string;
  checksumSha256: string;
  sourceLineCount: number;
  literalCoveredLines: number;
  naturalCoveredLines: number;
  completeForReview: boolean;
  missingLiteralLineNos: number[];
  missingNaturalLineNos: number[];
  hasManyToManyAlignment: boolean;
  lines: TranslationLine[];
  notes: TranslationNote[];
  provenance: TranslationProvenance[];
};

export type TranslationContext = {
  recordingId: string;
  lyricsRevisionId: string | null;
  lyricsRevisionNo: number | null;
  targetLanguage: string;
  translationType: string;
  hasStaleRevision: boolean;
  sourceLines: TranslationSourceLine[];
  revision: TranslationRevision | null;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: TranslationContext; etag: string }
  | { phase: 'failed'; problem: ClientProblem };

export type TranslationStructurePageProps = {
  recordingId: string;
};

function displayCode(value: string) {
  return value.replaceAll('_', ' ');
}

function groupedLines(lines: TranslationLine[]) {
  const groups = new Map<
    string,
    {
      anchorLineId: string;
      anchorLineNo: number;
      japaneseText: string;
      variants: TranslationLine[];
    }
  >();

  for (const line of lines) {
    const existing = groups.get(line.anchorLineId);
    if (existing) {
      existing.variants.push(line);
      continue;
    }

    groups.set(line.anchorLineId, {
      anchorLineId: line.anchorLineId,
      anchorLineNo: line.anchorLineNo,
      japaneseText: line.japaneseText,
      variants: [line],
    });
  }

  return [...groups.values()];
}

export function TranslationStructurePage({ recordingId }: TranslationStructurePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const access = useVisibleAccess();
  const canEdit = access.capabilities.includes('EDITORIAL.DRAFT');
  const [state, setState] = useState<PageState>({ phase: 'loading' });

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const params = new URLSearchParams({
        language: 'es',
        translationType: 'HUMAN',
      });

      const result = await client.get<TranslationContext>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/translation-context?${params.toString()}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;
      setState(
        result.ok
          ? {
              phase: 'ready',
              data: result.data,
              etag: result.etag ?? '',
            }
          : { phase: 'failed', problem: result.problem },
      );
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  const revision = state.phase === 'ready' ? state.data.revision : null;
  const lineGroups = revision ? groupedLines(revision.lines) : [];

  return (
    <article className="route-surface translation-structure" data-route-id="UI-MVP-023">
      <header className="translation-structure__header">
        <p className="eyebrow">BL-MVP-061–062 · UI-MVP-023</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Traducción y alineaciones
        </h1>
        <p>
          Traduce línea por línea con la fuente japonesa siempre visible y protegida. Lo técnico
          —alineaciones, checksum y procedencia— queda disponible cuando lo necesitas, sin
          interrumpir el trabajo principal.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando el espacio de traducción"
          description="Cargando la letra japonesa vigente y el último borrador español compatible."
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
          title="Falta una letra japonesa estructurada"
          description="Primero debe existir una revisión de letra. Después podrás traducirla sin alterar el japonés."
        />
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId && !revision ? (
        <StateMessage
          state={state.data.hasStaleRevision ? 'UI-EST-09' : 'UI-EST-12'}
          title={
            state.data.hasStaleRevision
              ? 'La fuente japonesa cambió'
              : canEdit
                ? 'Nuevo borrador listo para empezar'
                : 'Sin revisión de traducción compatible'
          }
          description={
            state.data.hasStaleRevision
              ? 'Existe traducción de una revisión japonesa anterior. Sus alineaciones quedan pendientes de revisión explícita y no se reutilizan automáticamente.'
              : canEdit
                ? 'Todavía no hay traducción para esta revisión. Puedes comenzar abajo; guardar crea un borrador y no publica contenido.'
                : 'La revisión japonesa actual todavía no tiene una traducción española asociada.'
          }
        />
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId ? (
        <section
          className="translation-structure__workspace-context"
          aria-labelledby="translation-source"
        >
          <div className="translation-structure__context-copy">
            <p className="eyebrow">CONTEXTO DE TRABAJO</p>
            <h2 id="translation-source">Letra japonesa · revisión {state.data.lyricsRevisionNo}</h2>
            <p>Fuente bloqueada. Todo lo que escribas se guarda como una capa española separada.</p>
          </div>

          <dl className="translation-structure__context-facts">
            <div>
              <dt>Idioma</dt>
              <dd>Español</dd>
            </div>
            <div>
              <dt>Modo</dt>
              <dd>{canEdit ? 'Edición' : 'Lectura'}</dd>
            </div>
            <div>
              <dt>Traducción</dt>
              <dd>{revision ? `Revisión ${revision.revisionNo}` : 'Nuevo borrador'}</dd>
            </div>
          </dl>

          <details className="translation-structure__source-details" open={!canEdit}>
            <summary>
              <span>Ver letra japonesa completa</span>
              <span>{state.data.sourceLines.length} líneas</span>
            </summary>
            <ol>
              {state.data.sourceLines.map((line) => (
                <li key={line.lineId}>
                  <strong>{line.lineNo}</strong>
                  <span lang="ja">{line.japaneseText}</span>
                </li>
              ))}
            </ol>
          </details>
        </section>
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId && canEdit ? (
        <TranslationEditor
          recordingId={recordingId}
          context={state.data}
          etag={state.etag}
          onSaved={(data, etag) =>
            setState({
              phase: 'ready',
              data,
              etag,
            })
          }
        />
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId && !canEdit ? (
        <StateMessage
          state="UI-EST-08"
          title="Modo de revisión"
          description="Puedes consultar la traducción y sus evidencias. Para guardar un borrador se necesita la capacidad EDITORIAL.DRAFT."
        />
      ) : null}

      {revision ? (
        <details className="translation-structure__inspector" open={!canEdit}>
          <summary>
            <span>
              <strong>Revisión, alineaciones y procedencia</strong>
              <small>Detalles técnicos y evidencia editorial</small>
            </span>
            <span className="translation-structure__inspector-status">
              {revision.completeForReview ? 'Cobertura completa' : 'Borrador parcial'}
            </span>
          </summary>

          <div className="translation-structure__inspector-body">
            <section
              className="translation-structure__revision"
              aria-labelledby="translation-revision"
            >
              <header>
                <div>
                  <p className="eyebrow">REVISIÓN COMPATIBLE</p>
                  <h2 id="translation-revision">Traducción · revisión {revision.revisionNo}</h2>
                </div>
                <span>{displayCode(revision.statusCode)}</span>
              </header>

              <dl className="translation-structure__metrics">
                <div>
                  <dt>Literal</dt>
                  <dd>
                    {revision.literalCoveredLines}/{revision.sourceLineCount}
                  </dd>
                </div>
                <div>
                  <dt>Natural</dt>
                  <dd>
                    {revision.naturalCoveredLines}/{revision.sourceLineCount}
                  </dd>
                </div>
                <div>
                  <dt>Alineación</dt>
                  <dd>
                    {revision.hasManyToManyAlignment ? 'N:M detectada' : 'Sin N:M registrada'}
                  </dd>
                </div>
                <div>
                  <dt>Estado</dt>
                  <dd>{revision.completeForReview ? 'Lista para revisar' : 'En progreso'}</dd>
                </div>
              </dl>

              {!revision.completeForReview ? (
                <p className="translation-structure__coverage" role="status">
                  Pendientes — literal: {revision.missingLiteralLineNos.join(', ') || 'ninguna'} ·
                  natural: {revision.missingNaturalLineNos.join(', ') || 'ninguna'}.
                </p>
              ) : null}

              <p className="translation-structure__technical-id">
                Checksum: <code>{revision.checksumSha256.slice(0, 16)}…</code>
              </p>
            </section>

            <section aria-labelledby="translation-units">
              <header className="translation-structure__section-heading">
                <div>
                  <p className="eyebrow">VISTA DE REVISIÓN</p>
                  <h2 id="translation-units">Unidades traducidas</h2>
                </div>
                <p>
                  Consulta el resultado guardado y sus anclas sin mezclarlo con los campos de
                  edición.
                </p>
              </header>

              <ol className="translation-structure__units">
                {lineGroups.map((group) => (
                  <li key={group.anchorLineId}>
                    <article className="translation-structure__unit">
                      <div className="translation-structure__unit-source">
                        <strong>Línea {group.anchorLineNo}</strong>
                        <p className="translation-structure__japanese" lang="ja">
                          {group.japaneseText}
                        </p>
                      </div>

                      <div className="translation-structure__variants">
                        {group.variants.map((variant) => (
                          <div
                            key={variant.translationLineId}
                            className="translation-structure__variant"
                            role="group"
                            aria-labelledby={`translation-variant-${variant.translationLineId}`}
                          >
                            <h3 id={`translation-variant-${variant.translationLineId}`}>
                              {displayCode(variant.variantCode)}
                            </h3>
                            <p lang="es">{variant.translatedText}</p>

                            {variant.alignments.length > 0 ? (
                              <ul
                                className="translation-structure__alignments"
                                aria-label="Alineaciones"
                              >
                                {variant.alignments.map((alignment) => (
                                  <li key={alignment.alignmentId}>
                                    <span lang="ja">{alignment.surface}</span>
                                    <span>
                                      línea {alignment.sourceLineNo} ·{' '}
                                      {displayCode(alignment.alignmentType)}
                                    </span>
                                  </li>
                                ))}
                              </ul>
                            ) : null}
                          </div>
                        ))}
                      </div>
                    </article>
                  </li>
                ))}
              </ol>
            </section>

            <section className="translation-structure__support" aria-labelledby="translation-notes">
              <header className="translation-structure__section-heading">
                <div>
                  <p className="eyebrow">EVIDENCIA</p>
                  <h2 id="translation-notes">Notas y procedencia</h2>
                </div>
                <p>Información de apoyo separada del texto que verá el estudiante.</p>
              </header>

              <div className="translation-structure__support-column">
                <h3>Notas editoriales</h3>
                {revision.notes.length > 0 ? (
                  <ul>
                    {revision.notes.map((note) => (
                      <li key={note.noteId}>
                        <strong>{displayCode(note.noteType)}</strong>
                        <span>{note.noteText}</span>
                        {note.citation ? <small>Fuente: {note.citation}</small> : null}
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p>Sin notas registradas en esta revisión.</p>
                )}
              </div>

              <div className="translation-structure__support-column">
                <h3>Procedencia</h3>
                {revision.provenance.length > 0 ? (
                  <ul>
                    {revision.provenance.map((item) => (
                      <li
                        key={`${item.sourceReferenceId}-${item.contributionType}-${item.recordedAt}`}
                      >
                        <strong>{displayCode(item.contributionType)}</strong>
                        <span>{item.citation}</span>
                        {item.locator ? <small>{item.locator}</small> : null}
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p>Sin procedencia adicional registrada.</p>
                )}
              </div>
            </section>
          </div>
        </details>
      ) : null}
    </article>
  );
}
