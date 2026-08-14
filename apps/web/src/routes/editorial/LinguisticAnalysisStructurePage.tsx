import { useEffect, useMemo, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import { ContextualReading, ContextualReadingStatus } from './ContextualReading';
import './linguistic-analysis-structure.css';

const client = createHttpClient();

type SourceToken = {
  tokenId: string;
  lineId: string;
  lineNo: number;
  tokenNo: number;
  surface: string;
  normalizedSurface: string;
};

type SourceLine = {
  lineId: string;
  lineNo: number;
  sectionDisplayOrder: number;
  sectionLabel: string | null;
  japaneseText: string;
  tokens: SourceToken[];
};

type TokenReading = {
  tokenReadingId: string;
  tokenId: string;
  lineId: string;
  lineNo: number;
  surface: string;
  readingKana: string;
  furigana: string | null;
  romaji: string | null;
  readingType: string;
};

type VocabularySense = {
  senseId: string;
  languageTag: string;
  definition: string;
  usageNote: string | null;
  displayOrder: number;
};

type VocabularyOccurrence = {
  occurrenceId: string;
  tokenId: string;
  lineId: string;
  lineNo: number;
  surface: string;
  vocabularyId: string;
  lemma: string;
  reading: string | null;
  partOfSpeech: string | null;
  senseKey: string;
  inflection: string | null;
  confidenceCode: string;
  senses: VocabularySense[];
};

type Morphology = {
  annotationId: string;
  tokenId: string;
  lineId: string;
  lineNo: number;
  surface: string;
  lemma: string;
  partOfSpeechCode: string;
  conjugationCode: string | null;
  featuresJson: string;
};

type GrammarOccurrence = {
  occurrenceId: string;
  lineId: string;
  lineNo: number;
  japaneseText: string;
  grammarPointId: string;
  grammarCode: string;
  title: string;
  levelCode: string | null;
  startTokenId: string | null;
  endTokenId: string | null;
  note: string | null;
  explanation: string | null;
  examples: string | null;
};

type Provenance = {
  sourceReferenceId: string;
  sourceType: string;
  citation: string;
  locator: string | null;
  contributionType: string;
  recordedBy: string;
  recordedAt: string;
};

type AnalysisRevision = {
  analysisRevisionId: string;
  lyricsRevisionId: string;
  lyricsRevisionNo: number;
  revisionNo: number;
  parentRevisionId: string | null;
  statusCode: string;
  checksumSha256: string;
  sourceLineCount: number;
  sourceTokenCount: number;
  readingCoveredTokens: number;
  vocabularyCoveredTokens: number;
  morphologyCoveredTokens: number;
  grammarCoveredLines: number;
  readings: TokenReading[];
  vocabulary: VocabularyOccurrence[];
  morphology: Morphology[];
  grammar: GrammarOccurrence[];
  provenance: Provenance[];
};

type AnalysisContext = {
  recordingId: string;
  lyricsRevisionId: string | null;
  lyricsRevisionNo: number | null;
  explanationLanguage: string;
  hasStaleRevision: boolean;
  sourceLines: SourceLine[];
  revision: AnalysisRevision | null;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: AnalysisContext }
  | { phase: 'failed'; problem: ClientProblem };

export type LinguisticAnalysisStructurePageProps = {
  recordingId: string;
};

function displayCode(value: string | null) {
  return value ? value.replaceAll('_', ' ') : '—';
}

export function LinguisticAnalysisStructurePage({
  recordingId,
}: LinguisticAnalysisStructurePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const params = new URLSearchParams({ language: 'es' });
      const result = await client.get<AnalysisContext>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/analysis-context?${params.toString()}`,
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

  const data = state.phase === 'ready' ? state.data : null;
  const revision = data?.revision ?? null;
  const readingsByToken = useMemo(() => {
    const map = new Map<string, TokenReading[]>();
    for (const item of revision?.readings ?? []) {
      const current = map.get(item.tokenId) ?? [];
      current.push(item);
      map.set(item.tokenId, current);
    }
    return map;
  }, [revision]);

  const vocabularyByToken = useMemo(() => {
    const map = new Map<string, VocabularyOccurrence[]>();
    for (const item of revision?.vocabulary ?? []) {
      const current = map.get(item.tokenId) ?? [];
      current.push(item);
      map.set(item.tokenId, current);
    }
    return map;
  }, [revision]);

  const morphologyByToken = useMemo(() => {
    const map = new Map<string, Morphology[]>();
    for (const item of revision?.morphology ?? []) {
      const current = map.get(item.tokenId) ?? [];
      current.push(item);
      map.set(item.tokenId, current);
    }
    return map;
  }, [revision]);

  const grammarByLine = useMemo(() => {
    const map = new Map<string, GrammarOccurrence[]>();
    for (const item of revision?.grammar ?? []) {
      const current = map.get(item.lineId) ?? [];
      current.push(item);
      map.set(item.lineId, current);
    }
    return map;
  }, [revision]);

  return (
    <article className="route-surface linguistic-analysis" data-route-id="UI-MVP-024">
      <header className="linguistic-analysis__header">
        <p className="eyebrow">BL-MVP-064–065 · UI-MVP-024</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Análisis lingüístico
        </h1>
        <p>
          Consulta la revisión de análisis compatible con la letra japonesa vigente. Lecturas,
          sentidos, morfología y gramática permanecen anclados a tokens y líneas canónicos.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando análisis lingüístico"
          description="Resolviendo la revisión japonesa vigente y el último análisis compatible."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-04"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {data && !data.lyricsRevisionId ? (
        <StateMessage
          state="UI-EST-12"
          title="Falta una letra japonesa tokenizada"
          description="El análisis necesita una revisión estructurada de letra antes de poder asociar lecturas y anotaciones."
        />
      ) : null}

      {data?.lyricsRevisionId && !revision ? (
        <StateMessage
          state={data.hasStaleRevision ? 'UI-EST-09' : 'UI-EST-12'}
          title={
            data.hasStaleRevision
              ? 'La fuente japonesa cambió'
              : 'Sin revisión de análisis compatible'
          }
          description={
            data.hasStaleRevision
              ? 'Existe análisis para una revisión japonesa anterior. No se mezclan ni migran automáticamente sus tokens, lecturas o explicaciones.'
              : 'La revisión japonesa vigente todavía no tiene un análisis lingüístico asociado.'
          }
        />
      ) : null}

      {data?.lyricsRevisionId ? (
        <section className="linguistic-analysis__context" aria-labelledby="analysis-source">
          <div>
            <p className="eyebrow">FUENTE EXACTA</p>
            <h2 id="analysis-source">Letra japonesa · revisión {data.lyricsRevisionNo}</h2>
            <p>
              El texto japonés proviene de M03 y permanece de solo lectura; M05 conserva
              referencias, no una copia editable.
            </p>
          </div>
          <dl>
            <div>
              <dt>Líneas</dt>
              <dd>{data.sourceLines.length}</dd>
            </div>
            <div>
              <dt>Idioma de explicación</dt>
              <dd>{data.explanationLanguage}</dd>
            </div>
            <div>
              <dt>Análisis</dt>
              <dd>{revision ? `Revisión ${revision.revisionNo}` : 'Pendiente'}</dd>
            </div>
          </dl>
        </section>
      ) : null}

      {data?.lyricsRevisionId ? (
        <ContextualReadingStatus
          sourceTokenCount={data.sourceLines.reduce((total, line) => total + line.tokens.length, 0)}
          readingCoveredTokens={revision?.readingCoveredTokens ?? 0}
          revisionNo={revision?.revisionNo ?? null}
        />
      ) : null}

      {revision ? (
        <>
          <section className="linguistic-analysis__summary" aria-labelledby="analysis-summary">
            <header>
              <div>
                <p className="eyebrow">COBERTURA DIFERENCIADA</p>
                <h2 id="analysis-summary">Análisis · revisión {revision.revisionNo}</h2>
              </div>
              <span>{displayCode(revision.statusCode)}</span>
            </header>
            <dl>
              <div>
                <dt>Lecturas</dt>
                <dd>
                  {revision.readingCoveredTokens}/{revision.sourceTokenCount} tokens
                </dd>
              </div>
              <div>
                <dt>Vocabulario</dt>
                <dd>
                  {revision.vocabularyCoveredTokens}/{revision.sourceTokenCount} tokens
                </dd>
              </div>
              <div>
                <dt>Morfología</dt>
                <dd>
                  {revision.morphologyCoveredTokens}/{revision.sourceTokenCount} tokens
                </dd>
              </div>
              <div>
                <dt>Gramática</dt>
                <dd>
                  {revision.grammarCoveredLines}/{revision.sourceLineCount} líneas
                </dd>
              </div>
            </dl>
          </section>

          <section className="linguistic-analysis__lines" aria-labelledby="analysis-lines">
            <header className="linguistic-analysis__section-heading">
              <div>
                <p className="eyebrow">ANCLAJE CANÓNICO</p>
                <h2 id="analysis-lines">Líneas y tokens</h2>
              </div>
              <p>
                Cada ayuda aparece junto al token o línea exactos que la originan. Una categoría
                ausente queda pendiente sin inferirse de otra.
              </p>
            </header>

            <ol>
              {data
                ? data.sourceLines.map((line) => {
                    const lineGrammar = grammarByLine.get(line.lineId) ?? [];
                    return (
                      <li key={line.lineId}>
                        <article className="linguistic-analysis__line">
                          <header>
                            <div>
                              <strong>
                                {line.sectionLabel
                                  ? `${line.sectionLabel} · línea ${line.lineNo}`
                                  : `Línea ${line.lineNo}`}
                              </strong>
                              <p lang="ja">{line.japaneseText}</p>
                            </div>
                            <span>{line.tokens.length} tokens</span>
                          </header>

                          <div className="linguistic-analysis__tokens">
                            {line.tokens.map((token) => {
                              const readings = readingsByToken.get(token.tokenId) ?? [];
                              const vocabulary = vocabularyByToken.get(token.tokenId) ?? [];
                              const morphology = morphologyByToken.get(token.tokenId) ?? [];
                              return (
                                <details key={token.tokenId} className="linguistic-analysis__token">
                                  <summary>
                                    <span lang="ja">{token.surface}</span>
                                    <span>
                                      {readings.length + vocabulary.length + morphology.length > 0
                                        ? 'Ver análisis'
                                        : 'Pendiente'}
                                    </span>
                                  </summary>
                                  <div className="linguistic-analysis__token-body">
                                    <section aria-label={`Lecturas de ${token.surface}`}>
                                      <h3>Lectura contextual</h3>
                                      <ContextualReading
                                        surface={token.surface}
                                        readings={readings}
                                        analysisRevisionId={revision.analysisRevisionId}
                                        revisionNo={revision.revisionNo}
                                      />
                                    </section>

                                    <section aria-label={`Vocabulario de ${token.surface}`}>
                                      <h3>Sentido</h3>
                                      {vocabulary.length > 0 ? (
                                        <ul>
                                          {vocabulary.map((item) => (
                                            <li key={item.occurrenceId}>
                                              <strong lang="ja">{item.lemma}</strong>
                                              {item.reading ? (
                                                <span lang="ja">{item.reading}</span>
                                              ) : null}
                                              <span>{displayCode(item.partOfSpeech)}</span>
                                              {item.senses.map((sense) => (
                                                <p key={sense.senseId} lang={sense.languageTag}>
                                                  {sense.definition}
                                                </p>
                                              ))}
                                              <small>{displayCode(item.confidenceCode)}</small>
                                            </li>
                                          ))}
                                        </ul>
                                      ) : (
                                        <p>Sin sentido contextual registrado.</p>
                                      )}
                                    </section>

                                    <section aria-label={`Morfología de ${token.surface}`}>
                                      <h3>Morfología</h3>
                                      {morphology.length > 0 ? (
                                        <ul>
                                          {morphology.map((item) => (
                                            <li key={item.annotationId}>
                                              <strong lang="ja">{item.lemma}</strong>
                                              <span>{displayCode(item.partOfSpeechCode)}</span>
                                              {item.conjugationCode ? (
                                                <span>{displayCode(item.conjugationCode)}</span>
                                              ) : null}
                                            </li>
                                          ))}
                                        </ul>
                                      ) : (
                                        <p>Sin morfología registrada.</p>
                                      )}
                                    </section>
                                  </div>
                                </details>
                              );
                            })}
                          </div>

                          {lineGrammar.length > 0 ? (
                            <section
                              className="linguistic-analysis__grammar"
                              aria-label="Gramática de la línea"
                            >
                              <h3>Gramática y explicación contextual</h3>
                              <ul>
                                {lineGrammar.map((item) => (
                                  <li key={item.occurrenceId}>
                                    <strong>{item.title}</strong>
                                    <span>{displayCode(item.grammarCode)}</span>
                                    {item.levelCode ? <span>Nivel: {item.levelCode}</span> : null}
                                    {item.explanation ? (
                                      <p lang={data.explanationLanguage}>{item.explanation}</p>
                                    ) : null}
                                    {item.note ? <small>{item.note}</small> : null}
                                  </li>
                                ))}
                              </ul>
                            </section>
                          ) : null}
                        </article>
                      </li>
                    );
                  })
                : null}
            </ol>
          </section>

          <details className="linguistic-analysis__provenance">
            <summary>
              <span>Procedencia y revisión</span>
              <span>{revision.provenance.length} referencias</span>
            </summary>
            <div>
              <p>
                Checksum: <code>{revision.checksumSha256.slice(0, 16)}…</code>
              </p>
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
                <p>Sin referencias adicionales registradas.</p>
              )}
            </div>
          </details>

          <footer className="linguistic-analysis__footer">
            <p>
              BL-MVP-064 modela y consulta revisiones. La edición pertenece a BL-MVP-067; esta
              pantalla no publica, no modifica tokens y no usa servicios lingüísticos externos.
            </p>
          </footer>
        </>
      ) : null}
    </article>
  );
}
