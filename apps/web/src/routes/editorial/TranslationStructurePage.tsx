import { useEffect, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import './translation-structure.css';

const client = createHttpClient();

type TranslationSourceLine = {
  lineId: string;
  lineNo: number;
  japaneseText: string;
};

type TranslationAlignment = {
  alignmentId: string;
  tokenId: string;
  sourceLineId: string;
  sourceLineNo: number;
  surface: string;
  targetStart: number | null;
  targetEnd: number | null;
  alignmentType: string;
};

type TranslationLine = {
  translationLineId: string;
  anchorLineId: string;
  anchorLineNo: number;
  japaneseText: string;
  variantCode: string;
  translatedText: string;
  displayOrder: number;
  alignments: TranslationAlignment[];
};

type TranslationNote = {
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

type TranslationProvenance = {
  sourceReferenceId: string;
  sourceType: string;
  citation: string;
  locator: string | null;
  contributionType: string;
  recordedBy: string;
  recordedAt: string;
};

type TranslationRevision = {
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

type TranslationContext = {
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
  | { phase: 'ready'; data: TranslationContext }
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
          ? { phase: 'ready', data: result.data }
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
        <p className="eyebrow">BL-MVP-061 · UI-MVP-023</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Traducción y alineaciones
        </h1>
        <p>
          Modelo versionado de traducción al español asociado a una revisión japonesa exacta. Las
          variantes literal y natural permanecen separadas y la alineación N:M conserva procedencia
          sin modificar la letra original.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando modelo de traducción"
          description="Resolviendo la revisión japonesa vigente y una traducción española compatible."
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
          title="Sin letra japonesa estructurada"
          description="La traducción necesita una revisión exacta de letra antes de poder modelarse."
        />
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId && !revision ? (
        <StateMessage
          state={state.data.hasStaleRevision ? 'UI-EST-09' : 'UI-EST-12'}
          title={
            state.data.hasStaleRevision
              ? 'La fuente japonesa cambió'
              : 'Sin revisión de traducción compatible'
          }
          description={
            state.data.hasStaleRevision
              ? 'Existe traducción de una revisión japonesa anterior. Sus alineaciones quedan pendientes de revisión explícita y no se reutilizan automáticamente.'
              : 'La revisión japonesa actual todavía no tiene una traducción española asociada. BL-MVP-062 incorporará el editor; esta pantalla no publica contenido.'
          }
        />
      ) : null}

      {state.phase === 'ready' && state.data.lyricsRevisionId ? (
        <section className="translation-structure__source" aria-labelledby="translation-source">
          <header>
            <div>
              <p className="eyebrow">FUENTE EXACTA</p>
              <h2 id="translation-source">
                Letra japonesa · revisión {state.data.lyricsRevisionNo}
              </h2>
            </div>
            <span lang="es">{state.data.targetLanguage}</span>
          </header>
          <p>
            La compatibilidad se resuelve por identificador de revisión, nunca por similitud del
            texto.
          </p>
          <ol>
            {state.data.sourceLines.map((line) => (
              <li key={line.lineId}>
                <strong>Línea {line.lineNo}</strong>
                <span lang="ja">{line.japaneseText}</span>
              </li>
            ))}
          </ol>
        </section>
      ) : null}

      {revision ? (
        <>
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
                <dt>Idioma</dt>
                <dd>{revision.targetLanguage}</dd>
              </div>
              <div>
                <dt>Tipo</dt>
                <dd>{displayCode(revision.translationType)}</dd>
              </div>
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
                <dd>{revision.hasManyToManyAlignment ? 'N:M detectada' : 'Sin N:M registrada'}</dd>
              </div>
              <div>
                <dt>Revisión</dt>
                <dd>{revision.completeForReview ? 'Cobertura completa' : 'Borrador parcial'}</dd>
              </div>
            </dl>

            {!revision.completeForReview ? (
              <p className="translation-structure__coverage" role="status">
                Pendientes — literal: {revision.missingLiteralLineNos.join(', ') || 'ninguna'} ·
                natural: {revision.missingNaturalLineNos.join(', ') || 'ninguna'}.
              </p>
            ) : null}

            <p>
              Checksum: <code>{revision.checksumSha256.slice(0, 16)}…</code>
            </p>
          </section>

          <section aria-labelledby="translation-units">
            <header className="translation-structure__section-heading">
              <h2 id="translation-units">Unidades y variantes</h2>
              <p>
                Japonés y español se presentan como capas distintas. Las relaciones con tokens son
                explícitas y admiten correspondencias N:M sin duplicar la letra.
              </p>
            </header>

            <ol className="translation-structure__units">
              {lineGroups.map((group) => (
                <li key={group.anchorLineId}>
                  <article className="translation-structure__unit">
                    <header>
                      <strong>Línea ancla {group.anchorLineNo}</strong>
                    </header>
                    <p className="translation-structure__japanese" lang="ja">
                      {group.japaneseText}
                    </p>

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
              <h2 id="translation-notes">Notas y procedencia</h2>
              <p>
                Las notas editoriales permanecen separadas del texto traducido. Nada de esta vista
                publica una revisión.
              </p>
            </header>

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

            {revision.provenance.length > 0 ? (
              <ul>
                {revision.provenance.map((item) => (
                  <li key={`${item.sourceReferenceId}-${item.contributionType}-${item.recordedAt}`}>
                    <strong>{displayCode(item.contributionType)}</strong>
                    <span>{item.citation}</span>
                    {item.locator ? <small>{item.locator}</small> : null}
                  </li>
                ))}
              </ul>
            ) : (
              <p>Sin procedencia adicional registrada.</p>
            )}
          </section>
        </>
      ) : null}
    </article>
  );
}
