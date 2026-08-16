import { useEffect, useRef, useState } from 'react';
import { AppLink, navigate } from '../../app/router/navigation';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './study-exercise.css';

const client = createHttpClient();

type FrozenOption = {
  instanceItemId: string;
  displayOrder: number;
  value: string;
};

type FrozenSubmission = {
  submissionId: string;
  statusCode: string;
  submittedAt: string;
  selectedInstanceItemId: string;
};

type FrozenExercise = {
  instanceId: string;
  studySessionId: string;
  stateCode: string;
  instanceNo: number;
  deliveredAt: string;
  version: number;
  exerciseRevisionNo: number;
  prompt: string;
  lineNo: number;
  maskedJapaneseText: string;
  options: FrozenOption[];
  submission: FrozenSubmission | null;
};

type SubmitResponse = {
  submissionId: string;
  instanceId: string;
  statusCode: string;
  submittedAt: string;
  selectedInstanceItemId: string;
  reusedExisting: boolean;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; exercise: FrozenExercise }
  | { phase: 'failed'; problem: ClientProblem };

export type StudyExercisePageProps = {
  slug: string;
  instanceId: string;
  mode: 'exercise' | 'result';
};

export function StudyExercisePage({ slug, instanceId, mode }: StudyExercisePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const idempotencyKeyRef = useRef<string | null>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [selected, setSelected] = useState<string | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [problem, setProblem] = useState<ClientProblem | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    setState({ phase: 'loading' });
    setSelected(null);
    setMutation(null);
    setProblem(null);
    idempotencyKeyRef.current = null;

    const load = async () => {
      const result = await client.get<FrozenExercise>(
        `/study/exercise-instances/${encodeURIComponent(instanceId)}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      setSelected(result.data.submission?.selectedInstanceItemId ?? null);
      setState({ phase: 'ready', exercise: result.data });
    };

    void load();
    return () => controller.abort();
  }, [instanceId, mode]);

  useEffect(() => {
    headingRef.current?.focus();
  }, [state.phase, mode]);

  async function submitAnswer() {
    if (state.phase !== 'ready' || !selected || state.exercise.submission) {
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

    idempotencyKeyRef.current ??= crypto.randomUUID();

    const result = await client.post<{ selectedInstanceItemId: string }, SubmitResponse>(
      `/study/exercise-instances/${encodeURIComponent(instanceId)}/submissions`,
      { selectedInstanceItemId: selected },
      {
        headers: {
          [csrf.data.headerName]: csrf.data.requestToken,
          'Idempotency-Key': idempotencyKeyRef.current,
        },
        retry: 'never',
        invalidate: [`/study/exercise-instances/${encodeURIComponent(instanceId)}`],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    navigate(`/estudiar/${encodeURIComponent(slug)}/resultado/${encodeURIComponent(instanceId)}`);
  }

  const routeId = mode === 'exercise' ? 'UI-MVP-012' : 'UI-MVP-013';

  return (
    <article className="route-surface study-exercise" data-route-id={routeId}>
      <header className="study-exercise__header">
        <p className="eyebrow">PRÁCTICA PRIVADA</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          {mode === 'exercise' ? 'Completa el espacio' : 'Respuesta confirmada'}
        </h1>
        <p>
          El ejercicio conserva la revisión y el orden que recibiste. Recargar la página no cambia
          lo ya presentado.
        </p>
      </header>

      <nav className="study-exercise__links" aria-label="Navegación de práctica">
        <AppLink href={`/estudiar/${encodeURIComponent(slug)}`}>
          Volver al inicio de estudio
        </AppLink>
        <AppLink href={`/aprender/${encodeURIComponent(slug)}`}>Volver a la canción</AppLink>
      </nav>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Recuperando tu ejercicio"
          description="Estamos recuperando exactamente la instancia privada que ya corresponde a tu sesión."
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
          <section className="study-exercise__frozen" aria-labelledby="frozen-exercise-title">
            <div>
              <p className="eyebrow">ACTIVIDAD CONGELADA</p>
              <h2 id="frozen-exercise-title">Ejercicio {state.exercise.instanceNo}</h2>
            </div>
            <span>Revisión {state.exercise.exerciseRevisionNo}</span>
          </section>

          <section className="study-exercise__question" aria-labelledby="exercise-prompt">
            <p className="eyebrow">CONTEXTO PUBLICADO</p>
            <h2 id="exercise-prompt">{state.exercise.prompt}</h2>
            <p className="study-exercise__line" lang="ja">
              {state.exercise.maskedJapaneseText}
            </p>
            <p className="study-exercise__hint">Línea {state.exercise.lineNo}</p>
          </section>

          <fieldset
            className="study-exercise__options"
            disabled={Boolean(state.exercise.submission) || mutation?.phase === 'saving'}
          >
            <legend>Elige una opción</legend>
            {state.exercise.options.map((option) => (
              <label
                className={selected === option.instanceItemId ? 'is-selected' : undefined}
                key={option.instanceItemId}
              >
                <input
                  type="radio"
                  name="study-answer"
                  value={option.instanceItemId}
                  checked={selected === option.instanceItemId}
                  onChange={() => setSelected(option.instanceItemId)}
                />
                <span lang="ja">{option.value}</span>
              </label>
            ))}
          </fieldset>

          {problem ? (
            <StateMessage
              state={mutation?.phase === 'conflict' ? 'UI-EST-10' : 'UI-EST-06'}
              title={problem.summary}
              description={problem.correction}
            />
          ) : null}

          {mode === 'exercise' && !state.exercise.submission ? (
            <div className="study-exercise__action">
              <div>
                <strong>Revisa tu elección antes de confirmar</strong>
                <span>Solo al confirmar se guarda una respuesta lógica para esta instancia.</span>
              </div>
              <Button
                type="button"
                disabled={!selected || mutation?.phase === 'saving'}
                onClick={() => void submitAnswer()}
              >
                {mutation?.phase === 'saving' ? 'Confirmando…' : 'Confirmar respuesta'}
              </Button>
            </div>
          ) : null}

          {mode === 'exercise' && state.exercise.submission ? (
            <StateMessage
              state="UI-EST-12"
              title="Esta respuesta ya está confirmada"
              description="No se creará una segunda entrega. Puedes abrir el estado confirmado."
            />
          ) : null}

          {mode === 'exercise' && state.exercise.submission ? (
            <AppLink
              href={`/estudiar/${encodeURIComponent(slug)}/resultado/${encodeURIComponent(instanceId)}`}
            >
              Ver respuesta confirmada
            </AppLink>
          ) : null}

          {mode === 'result' && !state.exercise.submission ? (
            <StateMessage
              state="UI-EST-04"
              title="Todavía no hay una respuesta confirmada"
              description="Vuelve al ejercicio, elige una opción y confírmala. Salir sin confirmar no crea evaluación, evidencia ni progreso."
            />
          ) : null}

          {mode === 'result' && state.exercise.submission ? (
            <section className="study-exercise__confirmed" aria-live="polite">
              <p className="eyebrow">GUARDADO</p>
              <h2>Tu respuesta quedó confirmada</h2>
              <p>
                Elegiste:{' '}
                <strong lang="ja">
                  {state.exercise.options.find(
                    (option) =>
                      option.instanceItemId === state.exercise.submission?.selectedInstanceItemId,
                  )?.value ?? 'Opción confirmada'}
                </strong>
              </p>
              <p>
                La corrección todavía no se muestra. Se calculará de forma reproducible en el
                siguiente paso de la práctica.
              </p>
              <p>
                Recargar esta página conserva la misma entrega; no crea otra respuesta, evidencia ni
                progreso.
              </p>
            </section>
          ) : null}
        </>
      ) : null}
    </article>
  );
}
