import { useEffect, useMemo, useState } from 'react';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import type { AnalysisContext } from './LinguisticAnalysisStructurePage';
import './linguistic-analysis-editor.css';

const client = createHttpClient();

type Csrf = { requestToken: string; headerName: string };
type ReadingDraft = {
  tokenId: string;
  readingKana: string;
  furigana: string;
  romaji: string;
  readingType: string;
};
type VocabularyDraft = {
  tokenId: string;
  lemma: string;
  reading: string;
  partOfSpeech: string;
  senseKey: string;
  definition: string;
  usageNote: string;
  inflection: string;
  confidenceCode: string;
};
type KanjiDraft = {
  tokenId: string;
  charOffset: number;
  character: string;
  reading: string;
  readingType: string;
  meaning: string;
  gradeCode: string;
  jlptCode: string;
};
type MorphologyDraft = {
  tokenId: string;
  lemma: string;
  partOfSpeechCode: string;
  conjugationCode: string;
  featuresJson: string;
};
type GrammarDraft = {
  lineId: string;
  startTokenId: string;
  endTokenId: string;
  grammarCode: string;
  title: string;
  levelCode: string;
  note: string;
  explanation: string;
  examples: string;
};

type AnalysisDraft = {
  lyricsRevisionId: string;
  explanationLanguage: string;
  provenanceCitation: string;
  readings: ReadingDraft[];
  vocabulary: VocabularyDraft[];
  kanji: KanjiDraft[];
  morphology: MorphologyDraft[];
  grammar: GrammarDraft[];
};

type ValidationIssue = {
  severity: 'ERROR' | 'WARNING';
  code: string;
  message: string;
  location: string | null;
};
type ValidationReport = {
  canSave: boolean;
  errorCount: number;
  warningCount: number;
  orphanCount: number;
  checksumSha256: string;
  coverage: {
    totalTokens: number;
    readingTokens: number;
    vocabularyTokens: number;
    kanjiTokens: number;
    morphologyTokens: number;
    totalLines: number;
    grammarLines: number;
  };
  provenanceCitation: string;
  issues: ValidationIssue[];
};

type EditorPhase = 'idle' | 'validating' | 'saving' | 'saved';

function fromContext(context: AnalysisContext): AnalysisDraft {
  const revision = context.revision;

  return {
    lyricsRevisionId: context.lyricsRevisionId ?? '',
    explanationLanguage: context.explanationLanguage,
    provenanceCitation: revision?.provenance[0]?.citation ?? 'Curaduría editorial interna',
    readings:
      revision?.readings.map((item) => ({
        tokenId: item.tokenId,
        readingKana: item.readingKana,
        furigana: item.furigana ?? '',
        romaji: item.romaji ?? '',
        readingType: item.readingType,
      })) ?? [],
    vocabulary:
      revision?.vocabulary.map((item) => ({
        tokenId: item.tokenId,
        lemma: item.lemma,
        reading: item.reading ?? '',
        partOfSpeech: item.partOfSpeech ?? 'OTHER',
        senseKey: item.senseKey,
        definition: item.senses.at(-1)?.definition ?? '',
        usageNote: item.senses.at(-1)?.usageNote ?? '',
        inflection: item.inflection ?? '',
        confidenceCode: item.confidenceCode,
      })) ?? [],
    kanji:
      revision?.kanji?.map((item) => ({
        tokenId: item.tokenId,
        charOffset: item.charOffset,
        character: item.character,
        reading: item.readings.at(-1)?.reading ?? '',
        readingType: item.readings.at(-1)?.readingType ?? 'GENERAL',
        meaning: item.readings.at(-1)?.meaning ?? '',
        gradeCode: item.gradeCode ?? '',
        jlptCode: item.jlptCode ?? '',
      })) ?? [],
    morphology:
      revision?.morphology.map((item) => ({
        tokenId: item.tokenId,
        lemma: item.lemma,
        partOfSpeechCode: item.partOfSpeechCode,
        conjugationCode: item.conjugationCode ?? '',
        featuresJson: item.featuresJson || '{}',
      })) ?? [],
    grammar:
      revision?.grammar.map((item) => ({
        lineId: item.lineId,
        startTokenId: item.startTokenId ?? '',
        endTokenId: item.endTokenId ?? '',
        grammarCode: item.grammarCode,
        title: item.title,
        levelCode: item.levelCode ?? '',
        note: item.note ?? '',
        explanation: item.explanation ?? '',
        examples: item.examples ?? '',
      })) ?? [],
  };
}

function bodyFromDraft(draft: AnalysisDraft) {
  const clean = (value: string) => value.trim() || null;
  return {
    lyricsRevisionId: draft.lyricsRevisionId,
    explanationLanguage: draft.explanationLanguage,
    provenanceCitation: draft.provenanceCitation.trim(),
    readings: draft.readings.map((item) => ({
      ...item,
      readingKana: item.readingKana.trim(),
      furigana: clean(item.furigana),
      romaji: clean(item.romaji),
    })),
    vocabulary: draft.vocabulary.map((item) => ({
      ...item,
      lemma: item.lemma.trim(),
      reading: item.reading.trim(),
      senseKey: item.senseKey.trim(),
      definition: item.definition.trim(),
      usageNote: clean(item.usageNote),
      inflection: clean(item.inflection),
    })),
    kanji: draft.kanji.map((item) => ({
      ...item,
      reading: clean(item.reading),
      meaning: clean(item.meaning),
      gradeCode: clean(item.gradeCode),
      jlptCode: clean(item.jlptCode),
    })),
    morphology: draft.morphology.map((item) => ({
      ...item,
      lemma: item.lemma.trim(),
      conjugationCode: clean(item.conjugationCode),
      featuresJson: item.featuresJson.trim() || '{}',
    })),
    grammar: draft.grammar.map((item) => ({
      ...item,
      startTokenId: clean(item.startTokenId),
      endTokenId: clean(item.endTokenId),
      grammarCode: item.grammarCode.trim(),
      title: item.title.trim(),
      levelCode: clean(item.levelCode),
      note: clean(item.note),
      explanation: clean(item.explanation),
      examples: clean(item.examples),
    })),
  };
}

function hanCharacters(surface: string) {
  return Array.from(surface)
    .map((character, charOffset) => ({ character, charOffset }))
    .filter(({ character }) => /\p{Script=Han}/u.test(character));
}

export type LinguisticAnalysisEditorProps = {
  recordingId: string;
  context: AnalysisContext;
  etag: string;
  onSaved: (context: AnalysisContext, etag: string) => void;
};

export function LinguisticAnalysisEditor({
  recordingId,
  context,
  etag,
  onSaved,
}: LinguisticAnalysisEditorProps) {
  const [draft, setDraft] = useState<AnalysisDraft>(() => fromContext(context));
  const [baseEtag, setBaseEtag] = useState(etag);
  const [selectedLineId, setSelectedLineId] = useState(context.sourceLines[0]?.lineId ?? '');
  const [selectedTokenId, setSelectedTokenId] = useState(
    context.sourceLines[0]?.tokens[0]?.tokenId ?? '',
  );
  const [validation, setValidation] = useState<ValidationReport | null>(null);
  const [phase, setPhase] = useState<EditorPhase>('idle');
  const [problem, setProblem] = useState<ClientProblem | null>(null);

  useEffect(() => {
    setDraft(fromContext(context));
    setBaseEtag(etag);
    setSelectedLineId(context.sourceLines[0]?.lineId ?? '');
    setSelectedTokenId(context.sourceLines[0]?.tokens[0]?.tokenId ?? '');
    setValidation(null);
    setPhase((current) => (current === 'saved' ? current : 'idle'));
    setProblem(null);
  }, [context, etag]);

  const selectedLine =
    context.sourceLines.find((line) => line.lineId === selectedLineId) ??
    context.sourceLines[0] ??
    null;
  const selectedToken =
    selectedLine?.tokens.find((token) => token.tokenId === selectedTokenId) ??
    selectedLine?.tokens[0] ??
    null;

  const lineProgress = useMemo(
    () =>
      new Map(
        context.sourceLines.map((line) => {
          const tokenIds = new Set(line.tokens.map((token) => token.tokenId));
          const annotations =
            draft.readings.filter((item) => tokenIds.has(item.tokenId)).length +
            draft.vocabulary.filter((item) => tokenIds.has(item.tokenId)).length +
            draft.kanji.filter((item) => tokenIds.has(item.tokenId)).length +
            draft.morphology.filter((item) => tokenIds.has(item.tokenId)).length +
            draft.grammar.filter((item) => item.lineId === line.lineId).length;
          return [line.lineId, annotations] as const;
        }),
      ),
    [context.sourceLines, draft],
  );

  const tokenReadings = selectedToken
    ? draft.readings.filter((item) => item.tokenId === selectedToken.tokenId)
    : [];
  const tokenVocabulary = selectedToken
    ? draft.vocabulary.filter((item) => item.tokenId === selectedToken.tokenId)
    : [];
  const tokenKanji = selectedToken
    ? draft.kanji.filter((item) => item.tokenId === selectedToken.tokenId)
    : [];
  const tokenMorphology = selectedToken
    ? (draft.morphology.find((item) => item.tokenId === selectedToken.tokenId) ?? null)
    : null;
  const lineGrammar = selectedLine
    ? draft.grammar.filter((item) => item.lineId === selectedLine.lineId)
    : [];

  function changed(next: AnalysisDraft) {
    setDraft(next);
    setValidation(null);
    setPhase('idle');
    setProblem(null);
  }

  function chooseLine(lineId: string) {
    const line = context.sourceLines.find((item) => item.lineId === lineId);
    setSelectedLineId(lineId);
    setSelectedTokenId(line?.tokens[0]?.tokenId ?? '');
  }

  function addReading() {
    if (!selectedToken) return;
    const count = tokenReadings.length;
    changed({
      ...draft,
      readings: [
        ...draft.readings,
        {
          tokenId: selectedToken.tokenId,
          readingKana: '',
          furigana: '',
          romaji: '',
          readingType: count === 0 ? 'CONTEXTUAL' : `ALTERNATIVE.${String(count).padStart(2, '0')}`,
        },
      ],
    });
  }

  function updateReading(
    readingType: string,
    field: 'readingKana' | 'furigana' | 'romaji',
    value: string,
  ) {
    if (!selectedToken) return;
    changed({
      ...draft,
      readings: draft.readings.map((item) =>
        item.tokenId === selectedToken.tokenId && item.readingType === readingType
          ? { ...item, [field]: value }
          : item,
      ),
    });
  }

  function removeReading(readingType: string) {
    if (!selectedToken) return;
    changed({
      ...draft,
      readings: draft.readings.filter(
        (item) => !(item.tokenId === selectedToken.tokenId && item.readingType === readingType),
      ),
    });
  }

  function addVocabulary() {
    if (!selectedToken) return;
    changed({
      ...draft,
      vocabulary: [
        ...draft.vocabulary,
        {
          tokenId: selectedToken.tokenId,
          lemma: selectedToken.surface,
          reading: tokenReadings[0]?.readingKana ?? '',
          partOfSpeech: 'OTHER',
          senseKey: '',
          definition: '',
          usageNote: '',
          inflection: '',
          confidenceCode: 'EDITORIAL',
        },
      ],
    });
  }

  function updateVocabulary(
    index: number,
    field: 'lemma' | 'reading' | 'partOfSpeech' | 'definition' | 'usageNote' | 'inflection',
    value: string,
  ) {
    const current = tokenVocabulary[index];
    if (!current) return;
    changed({
      ...draft,
      vocabulary: draft.vocabulary.map((item) =>
        item === current ? { ...item, [field]: value } : item,
      ),
    });
  }

  function removeVocabulary(index: number) {
    const current = tokenVocabulary[index];
    if (!current) return;
    changed({ ...draft, vocabulary: draft.vocabulary.filter((item) => item !== current) });
  }

  function prepareKanji() {
    if (!selectedToken) return;
    const existing = new Set(tokenKanji.map((item) => `${item.charOffset}:${item.character}`));
    const additions = hanCharacters(selectedToken.surface)
      .filter((item) => !existing.has(`${item.charOffset}:${item.character}`))
      .map((item) => ({
        tokenId: selectedToken.tokenId,
        charOffset: item.charOffset,
        character: item.character,
        reading: '',
        readingType: 'GENERAL',
        meaning: '',
        gradeCode: '',
        jlptCode: '',
      }));
    if (additions.length > 0) changed({ ...draft, kanji: [...draft.kanji, ...additions] });
  }

  function updateKanji(
    index: number,
    field: 'reading' | 'meaning' | 'gradeCode' | 'jlptCode',
    value: string,
  ) {
    const current = tokenKanji[index];
    if (!current) return;
    changed({
      ...draft,
      kanji: draft.kanji.map((item) => (item === current ? { ...item, [field]: value } : item)),
    });
  }

  function removeKanji(index: number) {
    const current = tokenKanji[index];
    if (!current) return;
    changed({ ...draft, kanji: draft.kanji.filter((item) => item !== current) });
  }

  function ensureMorphology() {
    if (!selectedToken || tokenMorphology) return;
    changed({
      ...draft,
      morphology: [
        ...draft.morphology,
        {
          tokenId: selectedToken.tokenId,
          lemma: selectedToken.surface,
          partOfSpeechCode: 'OTHER',
          conjugationCode: '',
          featuresJson: '{}',
        },
      ],
    });
  }

  function updateMorphology(
    field: 'lemma' | 'partOfSpeechCode' | 'conjugationCode' | 'featuresJson',
    value: string,
  ) {
    if (!selectedToken) return;
    changed({
      ...draft,
      morphology: draft.morphology.map((item) =>
        item.tokenId === selectedToken.tokenId ? { ...item, [field]: value } : item,
      ),
    });
  }

  function removeMorphology() {
    if (!selectedToken) return;
    changed({
      ...draft,
      morphology: draft.morphology.filter((item) => item.tokenId !== selectedToken.tokenId),
    });
  }

  function addGrammar() {
    if (!selectedLine) return;
    changed({
      ...draft,
      grammar: [
        ...draft.grammar,
        {
          lineId: selectedLine.lineId,
          startTokenId: '',
          endTokenId: '',
          grammarCode: '',
          title: '',
          levelCode: '',
          note: '',
          explanation: '',
          examples: '',
        },
      ],
    });
  }

  function updateGrammar(
    index: number,
    field:
      'startTokenId' | 'endTokenId' | 'title' | 'levelCode' | 'note' | 'explanation' | 'examples',
    value: string,
  ) {
    const current = lineGrammar[index];
    if (!current) return;
    changed({
      ...draft,
      grammar: draft.grammar.map((item) => (item === current ? { ...item, [field]: value } : item)),
    });
  }

  function removeGrammar(index: number) {
    const current = lineGrammar[index];
    if (!current) return;
    changed({ ...draft, grammar: draft.grammar.filter((item) => item !== current) });
  }

  async function getCsrf() {
    const result = await client.get<Csrf>('/auth/csrf', { cacheMode: 'no-store', retry: 'never' });
    return result.ok ? result.data : null;
  }

  async function validateDraft() {
    if (!baseEtag || !draft.lyricsRevisionId) return;
    setProblem(null);
    setPhase('validating');

    const token = await getCsrf();
    if (!token) {
      setPhase('idle');
      return;
    }

    const result = await client.post<ReturnType<typeof bodyFromDraft>, ValidationReport>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/analysis-revisions/validate`,
      bodyFromDraft(draft),
      {
        headers: { [token.headerName]: token.requestToken },
        ifMatch: baseEtag,
        retry: 'never',
      },
    );

    if (result.kind === 'cancelled') return;
    setPhase('idle');
    if (!result.ok) {
      setProblem(result.problem);
      return;
    }
    setValidation(result.data);
  }

  async function saveDraft() {
    if (!baseEtag || !validation?.canSave) return;
    setProblem(null);
    setPhase('saving');

    const token = await getCsrf();
    if (!token) {
      setPhase('idle');
      return;
    }

    const result = await client.post<ReturnType<typeof bodyFromDraft>, AnalysisContext>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/analysis-revisions`,
      bodyFromDraft(draft),
      {
        headers: { [token.headerName]: token.requestToken },
        ifMatch: baseEtag,
        retry: 'never',
        invalidate: [`/editorial/song-drafts/${encodeURIComponent(recordingId)}/analysis-context`],
      },
    );

    if (result.kind === 'cancelled') return;
    if (!result.ok) {
      setPhase('idle');
      setProblem(result.problem);
      return;
    }

    const nextEtag = result.etag ?? baseEtag;
    setBaseEtag(nextEtag);
    setPhase('saved');
    onSaved(result.data, nextEtag);
  }

  if (!context.lyricsRevisionId || context.sourceLines.length === 0) return null;

  return (
    <section
      className="analysis-editor"
      aria-labelledby="analysis-editor-title"
      data-bl="BL-MVP-067"
    >
      <header className="analysis-editor__hero">
        <div>
          <p className="eyebrow">BL-MVP-067 · espacio editorial</p>
          <h2 id="analysis-editor-title">Preparar análisis de japonés</h2>
          <p>
            Trabaja por línea y palabra. <strong>No necesitas completar todo de una vez.</strong> La
            letra japonesa está bloqueada y cada guardado crea una nueva revisión DRAFT.
          </p>
        </div>
        <div className="analysis-editor__revision">
          <strong>Letra japonesa · revisión {context.lyricsRevisionNo}</strong>
          <span>
            {context.revision ? `Análisis r${context.revision.revisionNo}` : 'Primer análisis'}
          </span>
        </div>
      </header>

      <nav className="analysis-editor__steps" aria-label="Pasos del análisis">
        <a href="#analysis-step-1">
          <span>1</span> Elige una línea y una palabra
        </a>
        <a href="#analysis-step-2">
          <span>2</span> Completa solo lo que conozcas
        </a>
        <a href="#analysis-step-3">
          <span>3</span> Revisa y guarda
        </a>
      </nav>

      <div className="analysis-editor__workspace">
        <div className="analysis-editor__lines" aria-labelledby="analysis-step-1">
          <header>
            <p className="eyebrow">PASO 1</p>
            <h3 id="analysis-step-1">Elige una línea y una palabra</h3>
            <p>Empieza donde tengas información. Puedes volver a cualquier línea.</p>
          </header>
          <div className="analysis-editor__line-list">
            {context.sourceLines.map((line) => {
              const active = line.lineId === selectedLine?.lineId;
              const count = lineProgress.get(line.lineId) ?? 0;
              return (
                <button
                  key={line.lineId}
                  type="button"
                  className={active ? 'is-active' : undefined}
                  aria-pressed={active}
                  onClick={() => chooseLine(line.lineId)}
                >
                  <span>Línea {line.lineNo}</span>
                  <strong lang="ja">{line.japaneseText}</strong>
                  <small>{count > 0 ? `${count} anotaciones` : 'Sin analizar'}</small>
                </button>
              );
            })}
          </div>
        </div>

        <div className="analysis-editor__main">
          {selectedLine ? (
            <section className="analysis-editor__source" aria-label="Fuente japonesa seleccionada">
              <p className="eyebrow">FUENTE BLOQUEADA · NO SE MODIFICA AQUÍ</p>
              <p className="analysis-editor__japanese-line" lang="ja">
                {selectedLine.japaneseText}
              </p>
              <div className="analysis-editor__tokens" aria-label="Palabras de la línea">
                {selectedLine.tokens.map((token) => (
                  <button
                    key={token.tokenId}
                    type="button"
                    aria-pressed={token.tokenId === selectedToken?.tokenId}
                    className={token.tokenId === selectedToken?.tokenId ? 'is-active' : undefined}
                    onClick={() => setSelectedTokenId(token.tokenId)}
                    lang="ja"
                  >
                    {token.surface}
                  </button>
                ))}
              </div>
            </section>
          ) : null}

          <section className="analysis-editor__fields" aria-labelledby="analysis-step-2">
            <header>
              <p className="eyebrow">PASO 2</p>
              <h3 id="analysis-step-2">Completa solo lo que conozcas</h3>
              <p>
                Las categorías son independientes. Dejar una pendiente es válido y quedará reflejado
                en la cobertura.
              </p>
            </header>

            {selectedToken ? (
              <>
                <div className="analysis-editor__selected">
                  <span>Palabra seleccionada</span>
                  <strong lang="ja">{selectedToken.surface}</strong>
                </div>

                <details open>
                  <summary>
                    Pronunciación y furigana <span>{tokenReadings.length || 'Pendiente'}</span>
                  </summary>
                  <div className="analysis-editor__detail-body">
                    <p className="analysis-editor__help">
                      Escribe la lectura que corresponde <strong>en esta canción</strong>. El
                      sistema no la adivina desde el kanji.
                    </p>
                    {tokenReadings.map((item) => (
                      <fieldset key={item.readingType}>
                        <legend>
                          {item.readingType === 'CONTEXTUAL'
                            ? 'Lectura contextual'
                            : 'Lectura alternativa'}
                        </legend>
                        <label>
                          Lectura en kana
                          <input
                            value={item.readingKana}
                            onChange={(event) =>
                              updateReading(item.readingType, 'readingKana', event.target.value)
                            }
                            lang="ja"
                            placeholder="例: がくせい"
                          />
                        </label>
                        <label>
                          Furigana editorial <span>opcional</span>
                          <input
                            value={item.furigana}
                            onChange={(event) =>
                              updateReading(item.readingType, 'furigana', event.target.value)
                            }
                            lang="ja"
                            placeholder="例: 学生[がくせい]"
                          />
                        </label>
                        <label>
                          Romaji <span>opcional; si queda vacío se resuelve localmente</span>
                          <input
                            value={item.romaji}
                            onChange={(event) =>
                              updateReading(item.readingType, 'romaji', event.target.value)
                            }
                            placeholder="gakusei"
                          />
                        </label>
                        <Button
                          type="button"
                          variant="secondary"
                          onClick={() => removeReading(item.readingType)}
                        >
                          Quitar esta lectura
                        </Button>
                      </fieldset>
                    ))}
                    <Button type="button" variant="secondary" onClick={addReading}>
                      {tokenReadings.length === 0
                        ? 'Añadir pronunciación'
                        : 'Añadir lectura alternativa'}
                    </Button>
                  </div>
                </details>

                <details>
                  <summary>
                    Vocabulario y significado <span>{tokenVocabulary.length || 'Pendiente'}</span>
                  </summary>
                  <div className="analysis-editor__detail-body">
                    <p className="analysis-editor__help">
                      Registra el significado que tiene aquí. No reemplaza la traducción de la
                      canción. Si corriges una definición o nota ya existente, se conserva el
                      historial editorial y esta revisión volverá a abrir la versión más reciente.
                    </p>
                    {tokenVocabulary.map((item, index) => (
                      <fieldset key={`${item.tokenId}-${index}`}>
                        <legend>Sentido {index + 1}</legend>
                        <div className="analysis-editor__two-cols">
                          <label>
                            Lema
                            <input
                              value={item.lemma}
                              onChange={(event) =>
                                updateVocabulary(index, 'lemma', event.target.value)
                              }
                              lang="ja"
                            />
                          </label>
                          <label>
                            Lectura
                            <input
                              value={item.reading}
                              onChange={(event) =>
                                updateVocabulary(index, 'reading', event.target.value)
                              }
                              lang="ja"
                            />
                          </label>
                        </div>
                        <label>
                          Significado contextual en español
                          <textarea
                            value={item.definition}
                            onChange={(event) =>
                              updateVocabulary(index, 'definition', event.target.value)
                            }
                            placeholder="Escribe una explicación breve y útil."
                          />
                        </label>
                        <div className="analysis-editor__two-cols">
                          <label>
                            Categoría
                            <select
                              value={item.partOfSpeech}
                              onChange={(event) =>
                                updateVocabulary(index, 'partOfSpeech', event.target.value)
                              }
                            >
                              <option value="OTHER">Otra / no definida</option>
                              <option value="NOUN">Sustantivo</option>
                              <option value="VERB">Verbo</option>
                              <option value="ADJECTIVE">Adjetivo</option>
                              <option value="ADVERB">Adverbio</option>
                              <option value="PARTICLE">Partícula</option>
                              <option value="EXPRESSION">Expresión</option>
                            </select>
                          </label>
                          <label>
                            Forma encontrada <span>opcional</span>
                            <input
                              value={item.inflection}
                              onChange={(event) =>
                                updateVocabulary(index, 'inflection', event.target.value)
                              }
                              lang="ja"
                            />
                          </label>
                        </div>
                        <label>
                          Nota de uso <span>opcional</span>
                          <textarea
                            value={item.usageNote}
                            onChange={(event) =>
                              updateVocabulary(index, 'usageNote', event.target.value)
                            }
                          />
                        </label>
                        <Button
                          type="button"
                          variant="secondary"
                          onClick={() => removeVocabulary(index)}
                        >
                          Quitar este sentido
                        </Button>
                      </fieldset>
                    ))}
                    <Button type="button" variant="secondary" onClick={addVocabulary}>
                      Añadir significado
                    </Button>
                  </div>
                </details>

                <details>
                  <summary>
                    Morfología <span>{tokenMorphology ? '1' : 'Pendiente'}</span>
                  </summary>
                  <div className="analysis-editor__detail-body">
                    {tokenMorphology ? (
                      <fieldset>
                        <legend>Forma de esta palabra</legend>
                        <div className="analysis-editor__two-cols">
                          <label>
                            Lema
                            <input
                              value={tokenMorphology.lemma}
                              onChange={(event) => updateMorphology('lemma', event.target.value)}
                              lang="ja"
                            />
                          </label>
                          <label>
                            Categoría
                            <select
                              value={tokenMorphology.partOfSpeechCode}
                              onChange={(event) =>
                                updateMorphology('partOfSpeechCode', event.target.value)
                              }
                            >
                              <option value="OTHER">Otra / no definida</option>
                              <option value="NOUN">Sustantivo</option>
                              <option value="VERB">Verbo</option>
                              <option value="ADJECTIVE">Adjetivo</option>
                              <option value="AUXILIARY">Auxiliar</option>
                            </select>
                          </label>
                        </div>
                        <label>
                          Conjugación <span>opcional</span>
                          <input
                            value={tokenMorphology.conjugationCode}
                            onChange={(event) =>
                              updateMorphology('conjugationCode', event.target.value)
                            }
                            placeholder="Ej.: PAST, TE_FORM"
                          />
                        </label>
                        <details className="analysis-editor__advanced">
                          <summary>Detalles avanzados</summary>
                          <label>
                            Rasgos estructurados (JSON)
                            <textarea
                              value={tokenMorphology.featuresJson}
                              onChange={(event) =>
                                updateMorphology('featuresJson', event.target.value)
                              }
                              spellCheck={false}
                            />
                          </label>
                        </details>
                        <Button type="button" variant="secondary" onClick={removeMorphology}>
                          Quitar morfología
                        </Button>
                      </fieldset>
                    ) : (
                      <Button type="button" variant="secondary" onClick={ensureMorphology}>
                        Añadir morfología
                      </Button>
                    )}
                  </div>
                </details>

                <details>
                  <summary>
                    Kanji de esta palabra <span>{tokenKanji.length || 'Pendiente'}</span>
                  </summary>
                  <div className="analysis-editor__detail-body">
                    <p className="analysis-editor__help">
                      Podemos detectar qué caracteres kanji ya están escritos en la palabra, pero no
                      inventamos su lectura ni significado. Lectura general y significado educativo
                      son opcionales como pareja: si completas uno, completa también el otro. Dejar
                      ambos vacíos no borra datos estables previos.
                    </p>
                    {tokenKanji.map((item, index) => (
                      <fieldset key={`${item.charOffset}-${item.character}`}>
                        <legend lang="ja">{item.character}</legend>
                        <div className="analysis-editor__two-cols">
                          <label>
                            Lectura general <span>opcional; junto con significado</span>
                            <input
                              value={item.reading}
                              onChange={(event) =>
                                updateKanji(index, 'reading', event.target.value)
                              }
                              lang="ja"
                            />
                          </label>
                          <label>
                            Significado educativo <span>opcional; junto con lectura</span>
                            <input
                              value={item.meaning}
                              onChange={(event) =>
                                updateKanji(index, 'meaning', event.target.value)
                              }
                            />
                          </label>
                          <label>
                            JLPT <span>orientativo</span>
                            <select
                              aria-label="JLPT orientativo"
                              value={item.jlptCode}
                              onChange={(event) =>
                                updateKanji(index, 'jlptCode', event.target.value)
                              }
                            >
                              <option value="">Sin clasificar</option>
                              <option value="N5">N5</option>
                              <option value="N4">N4</option>
                              <option value="N3">N3</option>
                              <option value="N2">N2</option>
                              <option value="N1">N1</option>
                            </select>
                          </label>
                          <label>
                            Nivel escolar <span>opcional</span>
                            <input
                              value={item.gradeCode}
                              onChange={(event) =>
                                updateKanji(index, 'gradeCode', event.target.value)
                              }
                            />
                          </label>
                        </div>
                        <small>
                          La lectura general no sustituye la pronunciación contextual de arriba.
                        </small>
                        <Button
                          type="button"
                          variant="secondary"
                          onClick={() => removeKanji(index)}
                        >
                          Quitar este kanji
                        </Button>
                      </fieldset>
                    ))}
                    <Button type="button" variant="secondary" onClick={prepareKanji}>
                      Preparar kanji escritos en la palabra
                    </Button>
                  </div>
                </details>
              </>
            ) : (
              <StateMessage
                state="UI-EST-12"
                title="Esta línea no tiene palabras tokenizadas"
                description="Vuelve a la edición de letra para estructurarla antes de analizarla."
              />
            )}

            {selectedLine ? (
              <details>
                <summary>
                  Gramática de la línea <span>{lineGrammar.length || 'Pendiente'}</span>
                </summary>
                <div className="analysis-editor__detail-body">
                  <p className="analysis-editor__help">
                    La gramática se ancla a la línea. El rango de palabras es opcional. Cambiar
                    nombre o nivel actualiza la versión estable del punto; una explicación nueva se
                    conserva como una revisión adicional y no borra el historial anterior.
                  </p>
                  {lineGrammar.map((item, index) => (
                    <fieldset key={`${item.lineId}-${index}`}>
                      <legend>Punto gramatical {index + 1}</legend>
                      <label>
                        Nombre claro
                        <input
                          value={item.title}
                          onChange={(event) => updateGrammar(index, 'title', event.target.value)}
                          placeholder="Ej.: Cópula です"
                        />
                      </label>
                      <label>
                        Explicación en español <span>opcional</span>
                        <textarea
                          value={item.explanation}
                          onChange={(event) =>
                            updateGrammar(index, 'explanation', event.target.value)
                          }
                        />
                      </label>
                      <div className="analysis-editor__two-cols">
                        <label>
                          Desde la palabra <span>opcional</span>
                          <select
                            value={item.startTokenId}
                            onChange={(event) =>
                              updateGrammar(index, 'startTokenId', event.target.value)
                            }
                          >
                            <option value="">Toda la línea / sin rango</option>
                            {selectedLine.tokens.map((token) => (
                              <option key={token.tokenId} value={token.tokenId}>
                                {token.surface}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label>
                          Hasta la palabra <span>opcional</span>
                          <select
                            value={item.endTokenId}
                            onChange={(event) =>
                              updateGrammar(index, 'endTokenId', event.target.value)
                            }
                          >
                            <option value="">Toda la línea / sin rango</option>
                            {selectedLine.tokens.map((token) => (
                              <option key={token.tokenId} value={token.tokenId}>
                                {token.surface}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                      <label>
                        Nivel JLPT <span>orientativo</span>
                        <select
                          aria-label="Nivel JLPT orientativo"
                          value={item.levelCode}
                          onChange={(event) =>
                            updateGrammar(index, 'levelCode', event.target.value)
                          }
                        >
                          <option value="">Sin clasificar</option>
                          <option value="N5">N5</option>
                          <option value="N4">N4</option>
                          <option value="N3">N3</option>
                          <option value="N2">N2</option>
                          <option value="N1">N1</option>
                        </select>
                      </label>
                      <label>
                        Nota interna <span>opcional</span>
                        <textarea
                          value={item.note}
                          onChange={(event) => updateGrammar(index, 'note', event.target.value)}
                        />
                      </label>
                      <Button
                        type="button"
                        variant="secondary"
                        onClick={() => removeGrammar(index)}
                      >
                        Quitar punto gramatical
                      </Button>
                    </fieldset>
                  ))}
                  <Button type="button" variant="secondary" onClick={addGrammar}>
                    Añadir punto gramatical
                  </Button>
                </div>
              </details>
            ) : null}
          </section>
        </div>
      </div>

      <section className="analysis-editor__review" aria-labelledby="analysis-step-3">
        <div className="analysis-editor__review-copy">
          <p className="eyebrow">PASO 3</p>
          <h3 id="analysis-step-3">Revisa y guarda</h3>
          <p>
            Primero valida. Verás cobertura, anclas y procedencia exactamente como el servidor las
            guardará.
          </p>
        </div>

        <label className="analysis-editor__provenance">
          Procedencia de esta revisión
          <input
            value={draft.provenanceCitation}
            onChange={(event) => changed({ ...draft, provenanceCitation: event.target.value })}
            placeholder="Ej.: Curaduría editorial interna"
          />
          <small>
            Describe quién o qué fuente respalda el análisis. No se envía fuera del sistema.
          </small>
        </label>

        <div className="analysis-editor__review-actions" aria-label="Validación y guardado">
          <div>
            <span>Estado</span>
            <strong>
              {validation
                ? validation.canSave
                  ? 'Listo para guardar'
                  : `${validation.errorCount} errores`
                : 'Aún no validado'}
            </strong>
          </div>
          <Button
            type="button"
            variant="secondary"
            onClick={() => void validateDraft()}
            disabled={!baseEtag || phase === 'validating' || phase === 'saving'}
          >
            {phase === 'validating' ? 'Validando…' : 'Validar borrador'}
          </Button>
          <Button
            type="button"
            onClick={() => void saveDraft()}
            disabled={!validation?.canSave || phase === 'saving'}
          >
            {phase === 'saving' ? 'Guardando…' : 'Guardar nueva revisión'}
          </Button>
        </div>

        {validation ? (
          <section className="analysis-editor__preview" aria-labelledby="analysis-preview-title">
            <header>
              <div>
                <p className="eyebrow">PREVISUALIZACIÓN DEL PAQUETE</p>
                <h4 id="analysis-preview-title">
                  {validation.canSave ? 'Todo listo para guardar' : 'Hay puntos por corregir'}
                </h4>
              </div>
              <span>{validation.orphanCount} huérfanos</span>
            </header>
            <dl>
              <div>
                <dt>Lecturas</dt>
                <dd>
                  {validation.coverage.readingTokens}/{validation.coverage.totalTokens}
                </dd>
              </div>
              <div>
                <dt>Vocabulario</dt>
                <dd>
                  {validation.coverage.vocabularyTokens}/{validation.coverage.totalTokens}
                </dd>
              </div>
              <div>
                <dt>Kanji</dt>
                <dd>
                  {validation.coverage.kanjiTokens}/{validation.coverage.totalTokens}
                </dd>
              </div>
              <div>
                <dt>Morfología</dt>
                <dd>
                  {validation.coverage.morphologyTokens}/{validation.coverage.totalTokens}
                </dd>
              </div>
              <div>
                <dt>Gramática</dt>
                <dd>
                  {validation.coverage.grammarLines}/{validation.coverage.totalLines}
                </dd>
              </div>
            </dl>
            {validation.issues.length > 0 ? (
              <ul className="analysis-editor__issues">
                {validation.issues.map((issue, index) => (
                  <li key={`${issue.code}-${index}`} data-severity={issue.severity}>
                    <strong>{issue.severity === 'ERROR' ? 'Corrige:' : 'Ten en cuenta:'}</strong>{' '}
                    {issue.message}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="analysis-editor__no-issues">Sin errores ni advertencias.</p>
            )}
            <details className="analysis-editor__advanced">
              <summary>Detalles técnicos de la previsualización</summary>
              <dl>
                <div>
                  <dt>Checksum</dt>
                  <dd>
                    <code>{validation.checksumSha256}</code>
                  </dd>
                </div>
                <div>
                  <dt>Procedencia</dt>
                  <dd>{validation.provenanceCitation}</dd>
                </div>
              </dl>
            </details>
          </section>
        ) : null}

        {problem ? (
          <StateMessage
            state={problem.status === 412 ? 'UI-EST-10' : 'UI-EST-04'}
            title={problem.summary}
            description={
              problem.status === 412
                ? `${problem.correction} Lo que escribiste sigue en pantalla; recarga solo cuando estés listo para reanclarlo.`
                : problem.correction
            }
          />
        ) : null}
        {phase === 'saved' ? (
          <StateMessage
            state="UI-EST-12"
            title="Revisión de análisis guardada"
            description="Quedó como DRAFT. No se publicó y la letra japonesa permaneció intacta."
          />
        ) : null}
      </section>
    </section>
  );
}
