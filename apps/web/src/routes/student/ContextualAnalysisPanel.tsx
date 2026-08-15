import { useEffect, useMemo, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import { romanizeApprovedReading } from '../editorial/ContextualReading';
import './contextual-analysis-panel.css';

const client = createHttpClient();
const territory = 'CR';
const language = 'es';

export type PublicContextualReading = {
  readingKana: string;
  furigana: string | null;
  romaji: string | null;
  readingType: string;
};

type PublicContextualVocabularySense = {
  languageTag: string;
  definition: string;
  usageNote: string | null;
  displayOrder: number;
};

type PublicContextualVocabulary = {
  lemma: string;
  reading: string | null;
  partOfSpeech: string | null;
  senseKey: string;
  inflection: string | null;
  confidenceCode: string;
  senses: PublicContextualVocabularySense[];
};

type PublicContextualKanjiReading = {
  reading: string;
  readingType: string;
  languageTag: string;
  meaning: string;
  displayOrder: number;
};

type PublicContextualKanji = {
  character: string;
  charOffset: number;
  gradeCode: string | null;
  jlptCode: string | null;
  readings: PublicContextualKanjiReading[];
};

type PublicContextualMorphology = {
  lemma: string;
  partOfSpeechCode: string;
  conjugationCode: string | null;
};

type PublicContextualGrammar = {
  grammarCode: string;
  title: string;
  levelCode: string | null;
  note: string | null;
  explanation: string | null;
  examples: string | null;
};

type PublicContextualProvenance = {
  sourceType: string;
  citation: string;
  locator: string | null;
  contributionType: string;
};

type PublicContextualLine = {
  sectionOrder: number;
  sectionLabel: string | null;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
};

export type PublicContextualAnalysis = {
  available: boolean;
  tokenKey: string;
  surface: string;
  tokenNo: number;
  targetLanguage: string;
  line: PublicContextualLine;
  readings: PublicContextualReading[];
  vocabulary: PublicContextualVocabulary[];
  kanji: PublicContextualKanji[];
  morphology: PublicContextualMorphology[];
  grammar: PublicContextualGrammar[];
  provenance: PublicContextualProvenance[];
};

type AnalysisState =
  | { phase: 'idle' }
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicContextualAnalysis }
  | { phase: 'unavailable' }
  | { phase: 'failed'; problem: ClientProblem };

export type ContextualAnalysisPanelProps = {
  slug: string;
  tokenKey: string | null;
  surfaceHint?: string | null;
  onClose?: () => void;
  showStandaloneLink?: boolean;
};

function readingRank(readingType: string) {
  const normalized = readingType.toUpperCase();
  if (normalized === 'PRIMARY') return 0;
  if (normalized === 'CONTEXTUAL') return 1;
  return 2;
}

function orderedReadings(readings: PublicContextualReading[]) {
  return [...readings].sort(
    (left, right) =>
      readingRank(left.readingType) - readingRank(right.readingType) ||
      left.readingType.localeCompare(right.readingType) ||
      left.readingKana.localeCompare(right.readingKana),
  );
}

function romaji(reading: PublicContextualReading) {
  return reading.romaji?.trim() || romanizeApprovedReading(reading.readingKana);
}

function humanCode(value: string | null) {
  return value?.replaceAll('_', ' ') ?? 'No disponible';
}

function EmptyDetail({ children }: { children: string }) {
  return <p className="contextual-analysis__empty">{children}</p>;
}

export function ContextualAnalysisPanel({
  slug,
  tokenKey,
  surfaceHint,
  onClose,
  showStandaloneLink = true,
}: ContextualAnalysisPanelProps) {
  const [state, setState] = useState<AnalysisState>({ phase: 'idle' });

  useEffect(() => {
    if (!tokenKey) {
      setState({ phase: 'idle' });
      return;
    }

    const controller = new AbortController();
    setState({ phase: 'loading' });

    const load = async () => {
      const params = new URLSearchParams({ territory, language });
      const result = await client.get<PublicContextualAnalysis>(
        `/public/catalog/songs/${encodeURIComponent(slug)}/analysis/${encodeURIComponent(tokenKey)}?${params.toString()}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState(
          result.problem.status === 404
            ? { phase: 'unavailable' }
            : { phase: 'failed', problem: result.problem },
        );
        return;
      }

      setState({ phase: 'ready', data: result.data });
    };

    void load();
    return () => controller.abort();
  }, [slug, tokenKey]);

  const readings = useMemo(
    () => (state.phase === 'ready' ? orderedReadings(state.data.readings) : []),
    [state],
  );

  return (
    <aside
      className="contextual-analysis"
      id="contextual-analysis-panel"
      aria-labelledby="contextual-analysis-title"
      data-contextual-analysis-panel
    >
      <header className="contextual-analysis__header">
        <div>
          <p className="eyebrow">BL-MVP-068 · ANÁLISIS CONTEXTUAL</p>
          <h2 id="contextual-analysis-title">Comprende esta parte</h2>
          <p>
            Lectura, significado, forma, kanji y gramática proceden del análisis publicado
            compatible con esta letra.
          </p>
        </div>
        {onClose && tokenKey ? (
          <button type="button" className="contextual-analysis__close" onClick={onClose}>
            Cerrar análisis
          </button>
        ) : null}
      </header>

      {state.phase === 'idle' ? (
        <div className="contextual-analysis__prompt">
          <strong>Selecciona una palabra de la letra.</strong>
          <span>
            El video puede seguir reproduciéndose mientras consultas el análisis. No se enviará
            texto a diccionarios ni servicios externos.
          </span>
        </div>
      ) : null}

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title={`Preparando ${surfaceHint?.trim() || 'el análisis'}`}
          description="Resolviendo el token dentro de la misma revisión publicada."
        />
      ) : null}

      {state.phase === 'unavailable' ? (
        <StateMessage
          state="UI-EST-06"
          title="Análisis no disponible"
          description="Este token ya no pertenece a la publicación activa o no tiene análisis compatible. No se sustituye por otro."
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
          <div className="contextual-analysis__selection">
            <p className="eyebrow">
              {state.data.line.sectionLabel?.trim() ||
                `Sección ${state.data.line.sectionOrder + 1}`}{' '}
              · línea {state.data.line.lineNo}
            </p>
            <h3 id="analysis-selection" lang="ja">
              {state.data.surface}
            </h3>
            <p lang="ja">{state.data.line.japaneseText}</p>

            {readings.length === 0 ? (
              <EmptyDetail>Sin lectura contextual publicada para este token.</EmptyDetail>
            ) : readings.length === 1 ? (
              <dl className="contextual-analysis__facts">
                <div>
                  <dt>Lectura contextual</dt>
                  <dd lang="ja">{readings[0]!.readingKana}</dd>
                </div>
                <div>
                  <dt>Romaji</dt>
                  <dd>{romaji(readings[0]!)}</dd>
                </div>
              </dl>
            ) : (
              <div className="contextual-analysis__alternatives">
                <strong>Lectura ambigua: se conservan las alternativas.</strong>
                <ul>
                  {readings.map((reading) => (
                    <li key={`${reading.readingType}-${reading.readingKana}`}>
                      <span lang="ja">{reading.readingKana}</span> · {romaji(reading)} ·{' '}
                      {humanCode(reading.readingType)}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>

          {!state.data.available ? (
            <StateMessage
              state="UI-EST-12"
              title="Sin detalle lingüístico adicional"
              description="El token es válido y pertenece a la publicación, pero todavía no tiene vocabulario, kanji, morfología o gramática autorizados."
            />
          ) : null}

          <section className="contextual-analysis__section" aria-labelledby="analysis-vocabulary">
            <h3 id="analysis-vocabulary">Vocabulario y significado</h3>
            {state.data.vocabulary.length === 0 ? (
              <EmptyDetail>Sin entrada de vocabulario para este token.</EmptyDetail>
            ) : (
              state.data.vocabulary.map((item, index) => {
                const firstSense = item.senses[0] ?? null;
                return (
                  <article
                    className="contextual-analysis__card"
                    key={`${item.lemma}-${item.senseKey}-${index}`}
                  >
                    <h4 lang="ja">{item.lemma}</h4>
                    {firstSense ? (
                      <>
                        <p className="contextual-analysis__context-meaning">
                          <strong>Significado en esta canción:</strong> {firstSense.definition}
                        </p>
                        {firstSense.usageNote ? <p>{firstSense.usageNote}</p> : null}
                      </>
                    ) : (
                      <EmptyDetail>Sin glosa localizada publicada.</EmptyDetail>
                    )}
                    <dl className="contextual-analysis__facts">
                      <div>
                        <dt>Lectura</dt>
                        <dd lang="ja">{item.reading ?? 'No disponible'}</dd>
                      </div>
                      <div>
                        <dt>Clase</dt>
                        <dd>{humanCode(item.partOfSpeech)}</dd>
                      </div>
                      <div>
                        <dt>Forma en contexto</dt>
                        <dd>{item.inflection ?? 'Forma base o no especificada'}</dd>
                      </div>
                    </dl>
                    {item.senses.length > 1 ? (
                      <details>
                        <summary>Ver definiciones adicionales publicadas</summary>
                        <ul>
                          {item.senses.slice(1).map((sense) => (
                            <li key={`${sense.displayOrder}-${sense.definition}`}>
                              {sense.definition}
                              {sense.usageNote ? ` — ${sense.usageNote}` : ''}
                            </li>
                          ))}
                        </ul>
                      </details>
                    ) : null}
                  </article>
                );
              })
            )}
          </section>

          <details className="contextual-analysis__details">
            <summary>Morfología y conjugación</summary>
            {state.data.morphology.length === 0 ? (
              <EmptyDetail>Sin análisis morfológico para este token.</EmptyDetail>
            ) : (
              <div className="contextual-analysis__grid">
                {state.data.morphology.map((item, index) => (
                  <dl className="contextual-analysis__facts" key={`${item.lemma}-${index}`}>
                    <div>
                      <dt>Lema</dt>
                      <dd lang="ja">{item.lemma}</dd>
                    </div>
                    <div>
                      <dt>Clase</dt>
                      <dd>{humanCode(item.partOfSpeechCode)}</dd>
                    </div>
                    <div>
                      <dt>Conjugación</dt>
                      <dd>{humanCode(item.conjugationCode)}</dd>
                    </div>
                  </dl>
                ))}
              </div>
            )}
          </details>

          <details className="contextual-analysis__details">
            <summary>Kanji</summary>
            {state.data.kanji.length === 0 ? (
              <EmptyDetail>Sin ficha de kanji asociada a este token.</EmptyDetail>
            ) : (
              <div className="contextual-analysis__kanji-grid">
                {state.data.kanji.map((item) => (
                  <article
                    className="contextual-analysis__kanji"
                    key={`${item.character}-${item.charOffset}`}
                  >
                    <h3 lang="ja">{item.character}</h3>
                    {item.readings.length > 0 ? (
                      <ul>
                        {item.readings.map((reading) => (
                          <li key={`${reading.readingType}-${reading.reading}-${reading.meaning}`}>
                            <span lang="ja">{reading.reading}</span> · {reading.meaning} ·{' '}
                            {humanCode(reading.readingType)}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <EmptyDetail>Sin lectura general localizada publicada.</EmptyDetail>
                    )}
                    <p>
                      {item.jlptCode
                        ? `JLPT ${item.jlptCode} · nivel orientativo, no certificación oficial.`
                        : 'JLPT no disponible.'}
                    </p>
                    {item.gradeCode ? <p>Grado escolar {item.gradeCode} · orientativo.</p> : null}
                  </article>
                ))}
              </div>
            )}
          </details>

          <details className="contextual-analysis__details">
            <summary>Gramática de esta línea</summary>
            {state.data.grammar.length === 0 ? (
              <EmptyDetail>Sin construcción gramatical asociada a este token.</EmptyDetail>
            ) : (
              state.data.grammar.map((item) => (
                <article className="contextual-analysis__card" key={item.grammarCode}>
                  <h4>{item.title}</h4>
                  <p>
                    <code>{item.grammarCode}</code>
                    {item.levelCode
                      ? ` · ${item.levelCode} orientativo, no certificación oficial.`
                      : ''}
                  </p>
                  {item.explanation ? <p>{item.explanation}</p> : null}
                  {item.note ? <p>{item.note}</p> : null}
                  {item.examples ? (
                    <details>
                      <summary>Ver ejemplos publicados</summary>
                      <p>{item.examples}</p>
                    </details>
                  ) : null}
                </article>
              ))
            )}
          </details>

          <details className="contextual-analysis__details">
            <summary>Procedencia</summary>
            {state.data.provenance.length === 0 ? (
              <EmptyDetail>Sin referencia pública adicional para mostrar.</EmptyDetail>
            ) : (
              <ul className="contextual-analysis__provenance">
                {state.data.provenance.map((item, index) => (
                  <li key={`${item.sourceType}-${item.citation}-${index}`}>
                    <strong>{humanCode(item.sourceType)}:</strong> {item.citation}
                    {item.locator ? ` · ${item.locator}` : ''}
                  </li>
                ))}
              </ul>
            )}
          </details>

          {showStandaloneLink ? (
            <AppLink
              href={`/aprender/${encodeURIComponent(slug)}/analisis/${encodeURIComponent(state.data.tokenKey)}`}
            >
              Abrir análisis en una vista independiente
            </AppLink>
          ) : null}
        </>
      ) : null}
    </aside>
  );
}
