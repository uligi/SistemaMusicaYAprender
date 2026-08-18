import { useEffect, useRef, useState } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import {
  FillBlankExerciseAuthoringWizard,
  type FillBlankExerciseEditSeed,
} from './FillBlankExerciseAuthoringWizard';
import './exercise-bank.css';

const client = createHttpClient();

type ExerciseCompetency = {
  code: string;
  domainCode: string;
  title: string;
};

type ExerciseSource = {
  recordingId: string;
  lineId: string | null;
  lineNo: number | null;
  japaneseText: string | null;
  lyricsRevisionId: string | null;
  lyricsRevisionNo: number | null;
  lyricsRevisionChecksumSha256: string | null;
};

type ExerciseFeedback = {
  correct: string | null;
  incorrect: string | null;
};

type ExerciseDifficulty = {
  code: string | null;
  justification: string | null;
};

type ExerciseItem = {
  exerciseItemId: string;
  itemType: string;
  itemOrder: number;
  label: string | null;
  value: string | null;
  metadataJson: string;
  isAccepted: boolean;
};

type ExerciseProvenance = {
  sourceType: string;
  citation: string;
  locator: string | null;
  contributionType: string;
  recordedAt: string;
};

type ExerciseCompleteness = {
  hasContext: boolean;
  hasOptions: boolean;
  hasSolution: boolean;
  hasExplanation: boolean;
  hasDifficulty: boolean;
  hasProvenance: boolean;
  readyForReview: boolean;
};

type ExerciseRevision = {
  exerciseRevisionId: string;
  revisionNo: number;
  statusCode: string;
  prompt: string;
  checksumSha256: string;
  version: number;
  schemaVersion: number | null;
  answerModel: string;
  explanation: string | null;
  feedback: ExerciseFeedback;
  difficulty: ExerciseDifficulty;
  items: ExerciseItem[];
  solutions: string[];
  provenance: ExerciseProvenance[];
  completeness: ExerciseCompleteness;
  warnings: string[];
};

type ExerciseBankEntry = {
  exerciseId: string;
  exerciseType: string;
  statusCode: string;
  version: number;
  competency: ExerciseCompetency;
  source: ExerciseSource;
  revisions: ExerciseRevision[];
};

type ExerciseBankSnapshot = {
  recordingId: string;
  exerciseCount: number;
  exercises: ExerciseBankEntry[];
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: ExerciseBankSnapshot }
  | { phase: 'failed'; problem: ClientProblem };

export type ExerciseBankPageProps = {
  recordingId: string;
};

function displayCode(value: string | null) {
  return value ? value.replaceAll('_', ' ') : 'Pendiente';
}

function RequirementMark({ ok, children }: { ok: boolean; children: string }) {
  return (
    <li>
      <span aria-hidden="true">{ok ? '✓' : '○'}</span>
      <span>
        {children}: <strong>{ok ? 'conservado' : 'pendiente'}</strong>
      </span>
    </li>
  );
}

function editSeedFrom(
  exercise: ExerciseBankEntry,
  revision: ExerciseRevision,
): FillBlankExerciseEditSeed | null {
  const accepted = revision.items.find((item) => item.isAccepted);
  let tokenId = '';

  if (accepted) {
    try {
      const metadata = JSON.parse(accepted.metadataJson) as { sourceTokenId?: string };
      tokenId = metadata.sourceTokenId ?? '';
    } catch {
      tokenId = '';
    }
  }

  const difficultyCode =
    revision.difficulty.code === 'BEGINNER' ||
    revision.difficulty.code === 'INTERMEDIATE' ||
    revision.difficulty.code === 'ADVANCED'
      ? revision.difficulty.code
      : null;

  const distractors = revision.items
    .filter((item) => item.itemType === 'OPTION' && !item.isAccepted)
    .map((item) => item.value ?? item.label ?? '')
    .filter(Boolean);

  if (
    !exercise.source.lineId ||
    !exercise.source.lyricsRevisionId ||
    !tokenId ||
    !difficultyCode ||
    distractors.length < 2
  ) {
    return null;
  }

  return {
    lyricsRevisionId: exercise.source.lyricsRevisionId,
    lineId: exercise.source.lineId,
    tokenId,
    competencyCode: exercise.competency.code,
    prompt: revision.prompt,
    distractors,
    explanation: revision.explanation ?? '',
    feedbackCorrect: revision.feedback.correct ?? '',
    feedbackIncorrect: revision.feedback.incorrect ?? '',
    difficultyCode,
    difficultyJustification: revision.difficulty.justification ?? '',
  };
}

export function ExerciseBankPage({ recordingId }: ExerciseBankPageProps) {
  const access = useVisibleAccess();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [authoringOpen, setAuthoringOpen] = useState(false);
  const [editSeed, setEditSeed] = useState<FillBlankExerciseEditSeed | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<ExerciseBankSnapshot>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/exercise-bank`,
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
  }, [recordingId, refreshKey]);

  const data = state.phase === 'ready' ? state.data : null;
  const canPreparePackage =
    access.capabilities.includes('EDITORIAL.SUBMIT') ||
    access.capabilities.includes('EDITORIAL.REVIEW');

  return (
    <article className="route-surface exercise-bank" data-route-id="UI-MVP-025">
      <header className="exercise-bank__header">
        <p className="eyebrow">BL-MVP-070 · UI-MVP-025</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Banco de ejercicios
        </h1>
        <p>
          Revisa el modelo versionado de cada ejercicio antes de preparar su autoría. Tipo, fuente,
          revisión, opciones, solución, explicación, dificultad y procedencia permanecen separados y
          trazables.
        </p>
      </header>

      <section
        id="exercise-authoring"
        className="exercise-bank__authoring-entry"
        aria-label="Autoría de ejercicios"
      >
        <div>
          <p className="eyebrow">BL-MVP-071 · AUTORÍA DRAFT</p>
          <h2>Crear completar espacios</h2>
          <p>
            Elige una línea, toca lo que quieres ocultar, añade distractores y pruébalo antes de
            guardar.
          </p>
        </div>
        <button
          type="button"
          className="exercise-bank__authoring-button"
          onClick={() => {
            if (authoringOpen) {
              setAuthoringOpen(false);
              setEditSeed(null);
            } else {
              setEditSeed(null);
              setAuthoringOpen(true);
            }
          }}
        >
          {authoringOpen
            ? 'Cerrar creador'
            : !data || data.exerciseCount === 0
              ? 'Crear mi primer ejercicio'
              : 'Crear otro ejercicio'}
        </button>
      </section>

      {authoringOpen ? (
        <FillBlankExerciseAuthoringWizard
          recordingId={recordingId}
          initialDraft={editSeed}
          onCancel={() => {
            setAuthoringOpen(false);
            setEditSeed(null);
          }}
          onSaved={() => {
            setAuthoringOpen(false);
            setEditSeed(null);
            setRefreshKey((current) => current + 1);
          }}
        />
      ) : null}

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando banco de ejercicios"
          description="Leyendo únicamente ejercicios y revisiones vinculados con esta canción."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-04"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {data && data.exerciseCount === 0 ? (
        <StateMessage
          state="UI-EST-12"
          title="Todavía no hay ejercicios modelados"
          description="El banco está listo para conservar revisiones. La autoría guiada de completar espacios se incorpora en el siguiente incremento."
        />
      ) : null}

      {data && data.exerciseCount > 0 ? (
        <section className="exercise-bank__list" aria-labelledby="exercise-bank-list">
          <header className="exercise-bank__section-heading">
            <div>
              <p className="eyebrow">MODELO M08</p>
              <h2 id="exercise-bank-list">
                {data.exerciseCount} {data.exerciseCount === 1 ? 'ejercicio' : 'ejercicios'}
              </h2>
            </div>
            <p>
              La vista es editorial y no publica, no crea intentos y no expone soluciones a la
              experiencia del estudiante.
            </p>
          </header>

          <ol>
            {data.exercises.map((exercise) => (
              <li key={exercise.exerciseId}>
                <article className="exercise-bank__exercise">
                  <header>
                    <div>
                      <p className="eyebrow">{displayCode(exercise.exerciseType)}</p>
                      <h3>{exercise.competency.title}</h3>
                      <p>
                        Competencia {exercise.competency.code} · dominio{' '}
                        {exercise.competency.domainCode}
                      </p>
                    </div>
                    <span>{displayCode(exercise.statusCode)}</span>
                  </header>

                  <section
                    className="exercise-bank__source"
                    aria-label={`Contexto de ${exercise.competency.title}`}
                  >
                    <div>
                      <span>Fuente exacta</span>
                      <strong>
                        {exercise.source.lyricsRevisionNo
                          ? `Letra · revisión ${exercise.source.lyricsRevisionNo}`
                          : 'Contexto de grabación'}
                      </strong>
                    </div>
                    {exercise.source.japaneseText ? (
                      <p lang="ja">{exercise.source.japaneseText}</p>
                    ) : (
                      <p>Ejercicio vinculado a la grabación sin ancla de línea.</p>
                    )}
                  </section>

                  {exercise.revisions.length === 0 ? (
                    <p className="exercise-bank__empty-revision">
                      Identidad creada; todavía no conserva una revisión editorial.
                    </p>
                  ) : (
                    <div className="exercise-bank__revisions">
                      {exercise.revisions.map((revision) => (
                        <details
                          className="exercise-bank__revision"
                          key={revision.exerciseRevisionId}
                          open={exercise.revisions.length === 1}
                        >
                          <summary>
                            <span>Revisión {revision.revisionNo}</span>
                            <span>
                              {displayCode(revision.statusCode)} ·{' '}
                              {revision.completeness.readyForReview
                                ? 'completa para revisión'
                                : 'requiere completar'}
                            </span>
                          </summary>

                          {editSeedFrom(exercise, revision) ? (
                            <div className="exercise-bank__revision-actions">
                              <button
                                type="button"
                                onClick={() => {
                                  const seed = editSeedFrom(exercise, revision);
                                  if (!seed) return;
                                  setEditSeed(seed);
                                  setAuthoringOpen(true);
                                  requestAnimationFrame(() =>
                                    document
                                      .getElementById('exercise-authoring')
                                      ?.scrollIntoView({ block: 'start', behavior: 'smooth' }),
                                  );
                                }}
                              >
                                {revision.statusCode === 'DRAFT'
                                  ? 'Editar borrador'
                                  : 'Corregir como nueva revisión'}
                              </button>
                              <span>
                                {revision.statusCode === 'DRAFT'
                                  ? 'Se actualiza únicamente el borrador editable.'
                                  : 'La revisión histórica se conserva intacta.'}
                              </span>
                            </div>
                          ) : null}

                          <div className="exercise-bank__revision-body">
                            <section>
                              <h4>Enunciado y modelo de respuesta</h4>
                              <p>{revision.prompt}</p>
                              <dl>
                                <div>
                                  <dt>Modelo</dt>
                                  <dd>{displayCode(revision.answerModel)}</dd>
                                </div>
                                <div>
                                  <dt>Esquema</dt>
                                  <dd>
                                    {revision.schemaVersion
                                      ? `v${revision.schemaVersion}`
                                      : 'No reconocido'}
                                  </dd>
                                </div>
                                <div>
                                  <dt>Checksum</dt>
                                  <dd>
                                    <code>{revision.checksumSha256.slice(0, 16)}…</code>
                                  </dd>
                                </div>
                              </dl>
                            </section>

                            <section>
                              <h4>Opciones y solución editorial</h4>
                              {revision.items.length > 0 ? (
                                <ol className="exercise-bank__options">
                                  {revision.items.map((item) => (
                                    <li key={item.exerciseItemId}>
                                      <span>
                                        {item.label ??
                                          item.value ??
                                          `${item.itemType} ${item.itemOrder}`}
                                      </span>
                                      {item.isAccepted ? <strong>Solución</strong> : null}
                                    </li>
                                  ))}
                                </ol>
                              ) : (
                                <p>Sin elementos conservados.</p>
                              )}
                              {revision.solutions.length > 0 ? (
                                <p>
                                  <strong>Respuesta válida:</strong>{' '}
                                  {revision.solutions.join(' / ')}
                                </p>
                              ) : null}
                            </section>

                            <section>
                              <h4>Explicación y retroalimentación</h4>
                              <p>{revision.explanation ?? 'Explicación pendiente.'}</p>
                              <dl>
                                <div>
                                  <dt>Correcta</dt>
                                  <dd>{revision.feedback.correct ?? 'Pendiente'}</dd>
                                </div>
                                <div>
                                  <dt>Incorrecta</dt>
                                  <dd>{revision.feedback.incorrect ?? 'Pendiente'}</dd>
                                </div>
                              </dl>
                            </section>

                            <section>
                              <h4>Dificultad editorial</h4>
                              <p>
                                <strong>{displayCode(revision.difficulty.code)}</strong>
                              </p>
                              <p>
                                {revision.difficulty.justification ??
                                  'Falta justificar la dificultad editorial.'}
                              </p>
                            </section>

                            <section>
                              <h4>Integridad de la revisión</h4>
                              <ul className="exercise-bank__requirements">
                                <RequirementMark ok={revision.completeness.hasContext}>
                                  Contexto
                                </RequirementMark>
                                <RequirementMark ok={revision.completeness.hasOptions}>
                                  Opciones
                                </RequirementMark>
                                <RequirementMark ok={revision.completeness.hasSolution}>
                                  Solución
                                </RequirementMark>
                                <RequirementMark ok={revision.completeness.hasExplanation}>
                                  Explicación
                                </RequirementMark>
                                <RequirementMark ok={revision.completeness.hasDifficulty}>
                                  Dificultad
                                </RequirementMark>
                                <RequirementMark ok={revision.completeness.hasProvenance}>
                                  Procedencia
                                </RequirementMark>
                              </ul>
                              {revision.warnings.length > 0 ? (
                                <ul
                                  className="exercise-bank__warnings"
                                  aria-label="Pendientes de revisión"
                                >
                                  {revision.warnings.map((warning) => (
                                    <li key={warning}>{warning}</li>
                                  ))}
                                </ul>
                              ) : null}
                            </section>

                            <section>
                              <h4>Procedencia</h4>
                              {revision.provenance.length > 0 ? (
                                <ul className="exercise-bank__provenance">
                                  {revision.provenance.map((item) => (
                                    <li
                                      key={`${item.sourceType}-${item.citation}-${item.recordedAt}`}
                                    >
                                      <strong>{item.citation}</strong>
                                      <span>
                                        {item.sourceType} · {displayCode(item.contributionType)}
                                      </span>
                                      {item.locator ? <span>{item.locator}</span> : null}
                                    </li>
                                  ))}
                                </ul>
                              ) : (
                                <p>Procedencia pendiente.</p>
                              )}
                            </section>
                          </div>
                        </details>
                      ))}
                    </div>
                  )}
                </article>
              </li>
            ))}
          </ol>
        </section>
      ) : null}

      {canPreparePackage ? (
        <section className="exercise-bank__authoring-entry" aria-label="Preparación del paquete">
          <div>
            <p className="eyebrow">BL-MVP-047 + BL-MVP-079 · PAQUETE</p>
            <h2>Validar ejercicios y preparar paquete</h2>
            <p>
              Revisa enlaces, fija revisiones exactas y aprueba únicamente ejercicios compatibles
              antes de congelar el paquete.
            </p>
          </div>
          <AppLink
            className="exercise-bank__authoring-button"
            href={`/editorial/paquetes/${encodeURIComponent(recordingId)}`}
          >
            Preparar paquete compatible
          </AppLink>
        </section>
      ) : null}

      <footer className="exercise-bank__footer">
        <p>
          BL-MVP-070 conserva el banco y sus revisiones. BL-MVP-071 permite crear y probar
          borradores; BL-MVP-047/079 valida su incorporación al paquete sin publicar todavía.
        </p>
      </footer>
    </article>
  );
}
