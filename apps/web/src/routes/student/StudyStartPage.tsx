import { useEffect, useRef, useState } from 'react';
import { AppLink, navigate } from '../../app/router/navigation';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './study-start.css';

const client = createHttpClient();
const territory = 'CR';
const language = 'es';

type PublicSong = {
  slug: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  artistName: string;
  availableComponents: string[];
};

type SessionSummary = {
  studySessionId: string;
  statusCode: string;
  startedAt: string;
  version: number;
};

type StartContext = {
  eligible: boolean;
  blockingReason: string | null;
  eligibleExerciseCount: number;
  publicationNo: number | null;
  activeSession: SessionSummary | null;
};

type StartResponse = SessionSummary & {
  publicationNo: number;
  reusedExisting: boolean;
  message: string;
};

type PreparedExercise = {
  instanceId: string;
  reusedExisting: boolean;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; song: PublicSong; context: StartContext }
  | { phase: 'unavailable' }
  | { phase: 'failed'; problem: ClientProblem };

export type StudyStartPageProps = {
  slug: string;
};

export function StudyStartPage({ slug }: StudyStartPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const idempotencyKeyRef = useRef<string | null>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [started, setStarted] = useState<StartResponse | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    setState({ phase: 'loading' });
    setProblem(null);
    setStarted(null);
    idempotencyKeyRef.current = null;

    const load = async () => {
      const params = new URLSearchParams({ territory, language });
      const [song, context] = await Promise.all([
        client.get<PublicSong>(
          `/public/catalog/songs/${encodeURIComponent(slug)}?${params.toString()}`,
          { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
        ),
        client.get<StartContext>(
          `/study/songs/${encodeURIComponent(slug)}/session-start?${params.toString()}`,
          { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
        ),
      ]);

      if (song.kind === 'cancelled' || context.kind === 'cancelled') return;

      if (!song.ok) {
        if (song.problem.status === 404) {
          setState({ phase: 'unavailable' });
        } else {
          setState({ phase: 'failed', problem: song.problem });
        }
        return;
      }

      if (!context.ok) {
        setState({ phase: 'failed', problem: context.problem });
        return;
      }

      setState({ phase: 'ready', song: song.data, context: context.data });
    };

    void load();
    return () => controller.abort();
  }, [slug]);

  useEffect(() => {
    headingRef.current?.focus();
  }, [state.phase]);

  async function readCsrf(): Promise<Csrf | null> {
    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return null;
    }

    return csrf.data;
  }

  async function startSession() {
    if (state.phase !== 'ready' || !state.context.eligible || state.context.activeSession) {
      return;
    }

    setProblem(null);

    const csrf = await readCsrf();
    if (!csrf) return;

    idempotencyKeyRef.current ??= crypto.randomUUID();

    const params = new URLSearchParams({ territory, language });
    const result = await client.post<Record<string, never>, StartResponse>(
      `/study/songs/${encodeURIComponent(slug)}/sessions?${params.toString()}`,
      {},
      {
        headers: {
          [csrf.headerName]: csrf.requestToken,
          'Idempotency-Key': idempotencyKeyRef.current,
        },
        retry: 'never',
        invalidate: [`/study/songs/${encodeURIComponent(slug)}/session-start`],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setStarted(result.data);
    setState((current) =>
      current.phase === 'ready'
        ? {
            ...current,
            context: {
              ...current.context,
              activeSession: {
                studySessionId: result.data.studySessionId,
                statusCode: result.data.statusCode,
                startedAt: result.data.startedAt,
                version: result.data.version,
              },
            },
          }
        : current,
    );
  }

  async function openExercise(studySessionId: string) {
    setProblem(null);

    const csrf = await readCsrf();
    if (!csrf) return;

    const result = await client.post<Record<string, never>, PreparedExercise>(
      `/study/sessions/${encodeURIComponent(studySessionId)}/instances`,
      {},
      {
        headers: {
          [csrf.headerName]: csrf.requestToken,
        },
        retry: 'never',
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    navigate(
      `/estudiar/${encodeURIComponent(slug)}/ejercicio/${encodeURIComponent(result.data.instanceId)}`,
    );
  }

  return (
    <article className="route-surface study-start" data-route-id="UI-MVP-011">
      <header className="study-start__header">
        <p className="eyebrow">PRÁCTICA PRIVADA</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Practicar esta canción
        </h1>
        <p>
          Preparamos una sesión solo cuando existe una actividad publicada. Tus respuestas, notas y
          progreso siguen siendo privados.
        </p>
      </header>

      <nav className="study-start__links" aria-label="Navegación de práctica">
        <AppLink href={`/aprender/${encodeURIComponent(slug)}`}>Volver al reproductor</AppLink>
        <AppLink href={`/canciones/${encodeURIComponent(slug)}`}>Ver ficha pública</AppLink>
      </nav>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Comprobando la práctica disponible"
          description="Validando la publicación vigente y las actividades que puedes estudiar."
        />
      ) : null}

      {state.phase === 'unavailable' ? (
        <StateMessage
          state="UI-EST-04"
          title="Esta canción no está disponible para estudiar"
          description="Vuelve al catálogo y elige una publicación vigente."
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
          <section className="study-start__song" aria-labelledby="study-song-title">
            <div>
              <p className="eyebrow">CONTENIDO PUBLICADO</p>
              <h2 id="study-song-title" lang="ja">
                {state.song.canonicalTitle}
              </h2>
              <p>
                {state.song.artistName} · {state.song.recordingTitle ?? 'Grabación publicada'}
              </p>
            </div>
            <span className="study-start__publication">
              {state.context.publicationNo
                ? `Publicación ${state.context.publicationNo}`
                : 'Publicación vigente'}
            </span>
          </section>

          <section className="study-start__privacy" aria-labelledby="study-privacy-title">
            <p className="eyebrow">TU ESPACIO</p>
            <h2 id="study-privacy-title">Tu sesión es privada</h2>
            <ul>
              <li>Solo se guarda el estado de tu sesión.</li>
              <li>No se registra una respuesta hasta que la confirmes en un ejercicio.</li>
              <li>No se crea evidencia ni progreso por abrir o interrumpir esta pantalla.</li>
              <li>No hay un temporizador obligatorio.</li>
            </ul>
          </section>

          {!state.context.eligible ? (
            <StateMessage
              state="UI-EST-04"
              title="Todavía no hay una práctica publicada"
              description={
                state.context.blockingReason ??
                'No se creó una sesión vacía ni se registró progreso.'
              }
            />
          ) : null}

          {state.context.eligible && state.context.activeSession ? (
            <StateMessage
              state="UI-EST-12"
              title="Ya tienes una sesión en curso"
              description="Conservamos la misma sesión privada para evitar duplicados. No se creó una segunda sesión."
            />
          ) : null}

          {started ? (
            <section className="study-start__success" aria-live="polite">
              <p className="eyebrow">SESIÓN LISTA</p>
              <h2>Tu sesión está preparada</h2>
              <p>{started.message}</p>
              <p>
                Todavía no se ha registrado ninguna respuesta, nota, evidencia ni cambio de
                progreso.
              </p>
            </section>
          ) : null}

          {problem ? (
            <StateMessage
              state={mutation?.phase === 'conflict' ? 'UI-EST-10' : 'UI-EST-06'}
              title={problem.summary}
              description={problem.correction}
            />
          ) : null}

          {state.context.eligible && !state.context.activeSession ? (
            <div className="study-start__action">
              <div>
                <strong>¿Listo para practicar?</strong>
                <span>
                  {state.context.eligibleExerciseCount === 1
                    ? 'Hay 1 actividad publicada disponible.'
                    : `Hay ${state.context.eligibleExerciseCount} actividades publicadas disponibles.`}
                </span>
              </div>
              <Button
                type="button"
                disabled={mutation?.phase === 'saving'}
                onClick={() => void startSession()}
              >
                {mutation?.phase === 'saving' ? 'Preparando sesión…' : 'Empezar a practicar'}
              </Button>
            </div>
          ) : null}

          {state.context.activeSession ? (
            <div className="study-start__action">
              <div>
                <strong>Sesión conservada</strong>
                <span>
                  El primer ejercicio se congela una sola vez y conserva su orden al volver.
                </span>
              </div>
              <Button
                type="button"
                disabled={mutation?.phase === 'saving'}
                onClick={() => void openExercise(state.context.activeSession!.studySessionId)}
              >
                {mutation?.phase === 'saving'
                  ? 'Preparando ejercicio…'
                  : 'Continuar con el ejercicio'}
              </Button>
            </div>
          ) : null}
        </>
      ) : null}
    </article>
  );
}
