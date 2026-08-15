import { useEffect, useMemo, useState } from 'react';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './fill-blank-exercise-authoring.css';

const client = createHttpClient();

type SourceToken = {
  tokenId: string;
  tokenNo: number;
  surface: string;
};

type SourceLine = {
  lineId: string;
  lineNo: number;
  japaneseText: string;
  tokens: SourceToken[];
};

type Competency = {
  code: string;
  domainCode: string;
  title: string;
  description: string;
};

type AuthoringContext = {
  recordingId: string;
  lyricsRevisionId: string | null;
  lyricsRevisionNo: number | null;
  lyricsRevisionChecksumSha256: string | null;
  lines: SourceLine[];
  competencies: Competency[];
  canAuthor: boolean;
  blockingReason: string | null;
};

type SavedDraft = {
  exerciseId: string;
  exerciseRevisionId: string;
  revisionNo: number;
  version: number;
  statusCode: string;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type Draft = {
  lineId: string;
  tokenId: string;
  competencyCode: string;
  prompt: string;
  distractors: string[];
  explanation: string;
  feedbackCorrect: string;
  feedbackIncorrect: string;
  difficultyCode: 'BEGINNER' | 'INTERMEDIATE' | 'ADVANCED';
  difficultyJustification: string;
};

type Props = {
  recordingId: string;
  onSaved: () => void;
  onCancel: () => void;
};

const emptyDraft: Draft = {
  lineId: '',
  tokenId: '',
  competencyCode: 'VOCAB.CONTEXT',
  prompt: 'Completa el espacio con la opción correcta.',
  distractors: ['', ''],
  explanation: '',
  feedbackCorrect: '¡Correcto! Identificaste la expresión en su contexto.',
  feedbackIncorrect: 'Casi. Vuelve a leer la línea y compara las opciones.',
  difficultyCode: 'BEGINNER',
  difficultyJustification: 'Una línea breve con una única respuesta contextual.',
};

function normalizeOption(value: string) {
  return value.normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('ja-JP');
}

function previewLine(line: SourceLine | undefined, token: SourceToken | undefined) {
  if (!line || !token) return 'Selecciona una línea y luego el espacio.';
  const index = line.japaneseText.indexOf(token.surface);
  if (index < 0) return line.japaneseText;
  return `${line.japaneseText.slice(0, index)}＿＿＿${line.japaneseText.slice(
    index + token.surface.length,
  )}`;
}

export function FillBlankExerciseAuthoringWizard({ recordingId, onSaved, onCancel }: Props) {
  const [context, setContext] = useState<AuthoringContext | null>(null);
  const [etag, setEtag] = useState('');
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [step, setStep] = useState(1);
  const [previewAnswer, setPreviewAnswer] = useState('');
  const [previewChecked, setPreviewChecked] = useState(false);
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);

  useEffect(() => {
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<AuthoringContext>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/exercise-authoring-context`,
        { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
      );

      if (result.kind === 'cancelled') return;
      if (!result.ok) {
        setProblem(result.problem);
        return;
      }

      setContext(result.data);
      setEtag(result.etag ?? '');
      const firstCompetency = result.data.competencies[0];
      if (firstCompetency) {
        setDraft((current) => ({ ...current, competencyCode: firstCompetency.code }));
      }
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  const selectedLine = useMemo(
    () => context?.lines.find((line) => line.lineId === draft.lineId),
    [context, draft.lineId],
  );
  const selectedToken = useMemo(
    () => selectedLine?.tokens.find((token) => token.tokenId === draft.tokenId),
    [selectedLine, draft.tokenId],
  );
  const correctKey = normalizeOption(selectedToken?.surface ?? '');
  const distractorKeys = draft.distractors.map(normalizeOption);

  const optionErrors = useMemo(() => {
    const messages: string[] = [];
    if (draft.distractors.some((value) => !value.trim())) {
      messages.push('Completa todos los distractores.');
    }
    if (correctKey && distractorKeys.includes(correctKey)) {
      messages.push('Un distractor coincide con la respuesta correcta.');
    }
    const nonEmpty = distractorKeys.filter(Boolean);
    if (new Set(nonEmpty).size !== nonEmpty.length) {
      messages.push('Hay distractores repetidos o indistinguibles.');
    }
    return messages;
  }, [correctKey, distractorKeys, draft.distractors]);

  const explanationReady =
    Boolean(draft.explanation.trim()) &&
    Boolean(draft.feedbackCorrect.trim()) &&
    Boolean(draft.feedbackIncorrect.trim()) &&
    Boolean(draft.difficultyJustification.trim());

  const canPreview =
    Boolean(context?.lyricsRevisionId) &&
    Boolean(selectedLine) &&
    Boolean(selectedToken) &&
    optionErrors.length === 0 &&
    explanationReady;

  const previewOptions = useMemo(
    () => (selectedToken ? [selectedToken.surface, ...draft.distractors] : []),
    [draft.distractors, selectedToken],
  );

  function selectLine(line: SourceLine) {
    setDraft((current) => ({ ...current, lineId: line.lineId, tokenId: '' }));
    setPreviewAnswer('');
    setPreviewChecked(false);
  }

  function selectToken(token: SourceToken) {
    setDraft((current) => ({ ...current, tokenId: token.tokenId }));
    setPreviewAnswer('');
    setPreviewChecked(false);
  }

  function updateDraftField<K extends keyof Draft>(field: K, value: Draft[K]) {
    setDraft((current) => ({ ...current, [field]: value }));
    setPreviewChecked(false);
  }

  function updateDistractor(index: number, value: string) {
    setDraft((current) => ({
      ...current,
      distractors: current.distractors.map((item, position) => (position === index ? value : item)),
    }));
    setPreviewChecked(false);
  }

  function addDistractor() {
    setDraft((current) =>
      current.distractors.length >= 4
        ? current
        : { ...current, distractors: [...current.distractors, ''] },
    );
  }

  function removeDistractor(index: number) {
    setDraft((current) =>
      current.distractors.length <= 2
        ? current
        : {
            ...current,
            distractors: current.distractors.filter((_, position) => position !== index),
          },
    );
  }

  async function save() {
    if (!context?.lyricsRevisionId || !selectedLine || !selectedToken || !canPreview || !etag) {
      return;
    }

    setProblem(null);

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, SavedDraft>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/fill-blank-exercise-drafts`,
      {
        lyricsRevisionId: context.lyricsRevisionId,
        lineId: selectedLine.lineId,
        tokenId: selectedToken.tokenId,
        competencyCode: draft.competencyCode,
        prompt: draft.prompt.trim(),
        distractors: draft.distractors.map((value) => value.trim()),
        explanation: draft.explanation.trim(),
        feedbackCorrect: draft.feedbackCorrect.trim(),
        feedbackIncorrect: draft.feedbackIncorrect.trim(),
        difficultyCode: draft.difficultyCode,
        difficultyJustification: draft.difficultyJustification.trim(),
      },
      {
        headers: { [csrf.data.headerName]: csrf.data.requestToken },
        ifMatch: etag,
        retry: 'never',
        invalidate: [
          `/editorial/song-drafts/${encodeURIComponent(recordingId)}/exercise-bank`,
          `/editorial/song-drafts/${encodeURIComponent(recordingId)}/exercise-authoring-context`,
        ],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;
    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    onSaved();
  }

  if (!context && !problem) {
    return (
      <section className="fill-author" aria-labelledby="fill-author-title">
        <StateMessage
          state="UI-EST-01"
          title="Preparando el creador de ejercicios"
          description="Cargando la revisión DRAFT exacta de la letra."
        />
      </section>
    );
  }

  if (problem && !context) {
    return (
      <section className="fill-author" aria-labelledby="fill-author-title">
        <StateMessage state="UI-EST-04" title={problem.summary} description={problem.correction} />
        <Button type="button" onClick={onCancel}>
          Volver al banco
        </Button>
      </section>
    );
  }

  if (!context?.canAuthor) {
    return (
      <section className="fill-author" aria-labelledby="fill-author-title">
        <header className="fill-author__header">
          <div>
            <p className="eyebrow">BL-MVP-071 · DRAFT</p>
            <h2 id="fill-author-title">Crear ejercicio de completar espacios</h2>
          </div>
          <Button type="button" onClick={onCancel}>
            Volver al banco
          </Button>
        </header>
        <StateMessage
          state="UI-EST-10"
          title="Falta preparar la fuente"
          description={context?.blockingReason ?? 'La fuente DRAFT todavía no está lista.'}
        />
      </section>
    );
  }

  return (
    <section className="fill-author" aria-labelledby="fill-author-title">
      <header className="fill-author__header">
        <div>
          <p className="eyebrow">BL-MVP-071 · BORRADOR</p>
          <h2 id="fill-author-title">Crear ejercicio de completar espacios</h2>
          <p>
            Cuatro pasos cortos. Nada de esta pantalla publica contenido ni crea intentos de
            estudiante.
          </p>
        </div>
        <div className="fill-author__draft-badge">
          <strong>DRAFT</strong>
          <span>Letra · revisión {context.lyricsRevisionNo}</span>
        </div>
      </header>

      <nav className="fill-author__steps" aria-label="Pasos de autoría">
        {[
          [1, 'Dónde preguntar'],
          [2, 'Opciones'],
          [3, 'Explicación'],
          [4, 'Probar borrador'],
        ].map(([number, label]) => (
          <button
            key={number}
            type="button"
            className={step === number ? 'is-active' : ''}
            aria-current={step === number ? 'step' : undefined}
            onClick={() => setStep(Number(number))}
          >
            <span>{number}</span>
            {label}
          </button>
        ))}
      </nav>

      {step === 1 ? (
        <div className="fill-author__panel">
          <header>
            <p className="eyebrow">PASO 1 DE 4</p>
            <h3>Elige la línea y después toca lo que quieres ocultar</h3>
            <p>
              Usamos la línea y el token exactos de la revisión DRAFT; no se copia ni reescribe la
              letra.
            </p>
          </header>

          <div className="fill-author__lines" role="group" aria-label="Líneas disponibles">
            {context.lines.map((line) => (
              <button
                type="button"
                key={line.lineId}
                className={draft.lineId === line.lineId ? 'is-selected' : ''}
                onClick={() => selectLine(line)}
              >
                <span>Línea {line.lineNo}</span>
                <strong lang="ja">{line.japaneseText}</strong>
              </button>
            ))}
          </div>

          {selectedLine ? (
            <div className="fill-author__tokens">
              <h4>Ahora elige el espacio</h4>
              <p>La respuesta correcta se toma automáticamente del token seleccionado.</p>
              <div>
                {selectedLine.tokens.map((token) => (
                  <button
                    type="button"
                    key={token.tokenId}
                    className={draft.tokenId === token.tokenId ? 'is-selected' : ''}
                    onClick={() => selectToken(token)}
                  >
                    <span lang="ja">{token.surface}</span>
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {selectedToken ? (
            <div className="fill-author__selection-summary" role="status">
              <span>Así quedará el espacio</span>
              <strong lang="ja">{previewLine(selectedLine, selectedToken)}</strong>
              <small>
                Respuesta editorial: <span lang="ja">{selectedToken.surface}</span>
              </small>
            </div>
          ) : null}

          <div className="fill-author__actions">
            <Button type="button" onClick={onCancel}>
              Cancelar
            </Button>
            <Button type="button" disabled={!selectedToken} onClick={() => setStep(2)}>
              Siguiente: opciones
            </Button>
          </div>
        </div>
      ) : null}

      {step === 2 ? (
        <div className="fill-author__panel">
          <header>
            <p className="eyebrow">PASO 2 DE 4</p>
            <h3>Crea opciones que sean distintas de verdad</h3>
            <p>
              La respuesta correcta queda protegida. Escribe entre 2 y 4 distractores plausibles,
              pero no equivalentes.
            </p>
          </header>

          <div className="fill-author__correct-answer">
            <span>Respuesta correcta</span>
            <strong lang="ja">{selectedToken?.surface ?? '—'}</strong>
          </div>

          <div className="fill-author__distractors">
            {draft.distractors.map((value, index) => (
              <div key={`distractor-${index}`}>
                <label htmlFor={`fill-distractor-${index}`}>Distractor {index + 1}</label>
                <input
                  id={`fill-distractor-${index}`}
                  value={value}
                  maxLength={120}
                  placeholder="Escribe una opción diferente…"
                  onChange={(event) => updateDistractor(index, event.currentTarget.value)}
                />
                {draft.distractors.length > 2 ? (
                  <button type="button" onClick={() => removeDistractor(index)}>
                    Quitar
                  </button>
                ) : null}
              </div>
            ))}
          </div>

          {draft.distractors.length < 4 ? (
            <button type="button" className="fill-author__add" onClick={addDistractor}>
              + Añadir otro distractor
            </button>
          ) : null}

          {optionErrors.length > 0 ? (
            <div className="fill-author__validation" role="alert">
              <strong>Antes de continuar</strong>
              <ul>
                {optionErrors.map((message) => (
                  <li key={message}>{message}</li>
                ))}
              </ul>
            </div>
          ) : (
            <p className="fill-author__ok" role="status">
              ✓ Las opciones son distinguibles.
            </p>
          )}

          <div className="fill-author__actions">
            <Button type="button" onClick={() => setStep(1)}>
              Atrás
            </Button>
            <Button type="button" disabled={optionErrors.length > 0} onClick={() => setStep(3)}>
              Siguiente: explicación
            </Button>
          </div>
        </div>
      ) : null}

      {step === 3 ? (
        <div className="fill-author__panel">
          <header>
            <p className="eyebrow">PASO 3 DE 4</p>
            <h3>Explica qué aprende el estudiante</h3>
            <p>Los textos son educativos y se guardan dentro de la misma revisión DRAFT.</p>
          </header>

          <label>
            Competencia
            <select
              value={draft.competencyCode}
              onChange={(event) => updateDraftField('competencyCode', event.currentTarget.value)}
            >
              {context.competencies.map((competency) => (
                <option key={competency.code} value={competency.code}>
                  {competency.title}
                </option>
              ))}
            </select>
          </label>

          <label>
            Instrucción para el estudiante
            <input
              value={draft.prompt}
              maxLength={240}
              onChange={(event) => updateDraftField('prompt', event.currentTarget.value)}
            />
          </label>

          <label>
            Explicación educativa
            <textarea
              rows={3}
              value={draft.explanation}
              maxLength={1200}
              placeholder="Ej.: 何度でも expresa repetición: «una y otra vez»."
              onChange={(event) => updateDraftField('explanation', event.currentTarget.value)}
            />
          </label>

          <div className="fill-author__feedback-grid">
            <label>
              Si acierta
              <textarea
                rows={2}
                value={draft.feedbackCorrect}
                maxLength={500}
                onChange={(event) => updateDraftField('feedbackCorrect', event.currentTarget.value)}
              />
            </label>
            <label>
              Si falla
              <textarea
                rows={2}
                value={draft.feedbackIncorrect}
                maxLength={500}
                onChange={(event) =>
                  updateDraftField('feedbackIncorrect', event.currentTarget.value)
                }
              />
            </label>
          </div>

          <div className="fill-author__difficulty">
            <label>
              Dificultad
              <select
                value={draft.difficultyCode}
                onChange={(event) =>
                  updateDraftField(
                    'difficultyCode',
                    event.currentTarget.value as Draft['difficultyCode'],
                  )
                }
              >
                <option value="BEGINNER">Básico</option>
                <option value="INTERMEDIATE">Intermedio</option>
                <option value="ADVANCED">Avanzado</option>
              </select>
            </label>
            <label>
              ¿Por qué?
              <input
                value={draft.difficultyJustification}
                maxLength={500}
                onChange={(event) =>
                  updateDraftField('difficultyJustification', event.currentTarget.value)
                }
              />
            </label>
          </div>

          {!explanationReady ? (
            <p className="fill-author__hint">
              Completa explicación, ambos mensajes y la justificación de dificultad.
            </p>
          ) : null}

          <div className="fill-author__actions">
            <Button type="button" onClick={() => setStep(2)}>
              Atrás
            </Button>
            <Button type="button" disabled={!explanationReady} onClick={() => setStep(4)}>
              Probar borrador
            </Button>
          </div>
        </div>
      ) : null}

      {step === 4 ? (
        <div className="fill-author__panel">
          <header>
            <p className="eyebrow">PASO 4 DE 4 · VISTA PREVIA DRAFT</p>
            <h3>Prueba exactamente lo que acabas de crear</h3>
            <p>
              Puedes responder aquí. Esta prueba es local: no crea sesión, intento, evidencia ni
              progreso.
            </p>
          </header>

          <article className="fill-author__preview" aria-label="Vista previa del ejercicio DRAFT">
            <span className="fill-author__preview-badge">BORRADOR · NO PUBLICADO</span>
            <p>{draft.prompt}</p>
            <blockquote lang="ja">{previewLine(selectedLine, selectedToken)}</blockquote>
            <div className="fill-author__preview-options">
              {previewOptions.map((option, index) => (
                <button
                  type="button"
                  key={`${option}-${index}`}
                  aria-pressed={previewAnswer === option}
                  onClick={() => {
                    setPreviewAnswer(option);
                    setPreviewChecked(false);
                  }}
                >
                  <span lang="ja">{option}</span>
                </button>
              ))}
            </div>
            <Button type="button" disabled={!previewAnswer} onClick={() => setPreviewChecked(true)}>
              Comprobar en vista previa
            </Button>

            {previewChecked ? (
              <div className="fill-author__preview-feedback" role="status">
                <strong>
                  {normalizeOption(previewAnswer) === correctKey ? '✓ Correcto' : 'Todavía no'}
                </strong>
                <p>
                  {normalizeOption(previewAnswer) === correctKey
                    ? draft.feedbackCorrect
                    : draft.feedbackIncorrect}
                </p>
                <p>{draft.explanation}</p>
              </div>
            ) : null}
          </article>

          {mutation?.phase === 'saving' ? (
            <StateMessage
              state="UI-EST-11"
              title="Guardando borrador"
              description="Conservando la fuente exacta, opciones y retroalimentación sin publicar."
            />
          ) : null}

          {mutation?.phase === 'conflict' &&
          problem?.code === 'learning.fill-blank.source-changed' ? (
            <StateMessage
              state="UI-EST-10"
              title="La fuente DRAFT cambió"
              description="Tu borrador sigue intacto. Vuelve al paso de fuente para confirmar la revisión vigente antes de guardar."
            />
          ) : problem ? (
            <StateMessage
              state="UI-EST-04"
              title={problem.summary}
              description={problem.correction}
            />
          ) : null}

          <div className="fill-author__actions">
            <Button type="button" onClick={() => setStep(3)}>
              Volver a editar
            </Button>
            <Button
              type="button"
              disabled={!canPreview || mutation?.phase === 'saving'}
              onClick={() => void save()}
            >
              Guardar borrador
            </Button>
          </div>
        </div>
      ) : null}
    </section>
  );
}
