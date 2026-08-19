import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import { normalizeUsername, usernameError } from '../../domain/identity/username';
import './username-profile.css';

const client = createHttpClient();

type UsernameSnapshot = {
  username: string | null;
  canClaim: boolean;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type UsernameState =
  | { phase: 'loading' }
  | { phase: 'ready'; snapshot: UsernameSnapshot }
  | { phase: 'saving'; snapshot: UsernameSnapshot }
  | { phase: 'failed'; snapshot?: UsernameSnapshot; message: string };

export function UsernameProfilePanel() {
  const inputRef = useRef<HTMLInputElement>(null);
  const [draft, setDraft] = useState('');
  const [fieldError, setFieldError] = useState<string>();
  const [state, setState] = useState<UsernameState>({ phase: 'loading' });

  useEffect(() => {
    const controller = new AbortController();

    void (async () => {
      const result = await client.get<UsernameSnapshot>('/profile/username', {
        cacheMode: 'no-store',
        retry: 'never',
        signal: controller.signal,
      });

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState({
          phase: 'failed',
          message: result.problem.correction,
        });
        return;
      }

      setState({ phase: 'ready', snapshot: result.data });
    })();

    return () => controller.abort();
  }, []);

  async function claim(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const error = usernameError(draft);
    if (error) {
      setFieldError(error);
      inputRef.current?.focus();
      return;
    }

    const current =
      state.phase === 'ready' || state.phase === 'failed' ? state.snapshot : undefined;
    if (!current?.canClaim) return;

    setFieldError(undefined);
    setState({ phase: 'saving', snapshot: current });

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      setState({
        phase: 'failed',
        snapshot: current,
        message: csrf.kind === 'problem' ? csrf.problem.correction : 'Vuelve a intentarlo.',
      });
      return;
    }

    const result = await client.post<{ username: string }, UsernameSnapshot>(
      '/profile/username',
      { username: normalizeUsername(draft) },
      {
        headers: {
          [csrf.data.headerName]: csrf.data.requestToken,
        },
        retry: 'never',
        invalidate: ['/profile/username'],
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setState({
        phase: 'failed',
        snapshot: current,
        message: result.problem.cause || result.problem.correction,
      });
      return;
    }

    setDraft('');
    setState({ phase: 'ready', snapshot: result.data });
  }

  if (state.phase === 'loading') {
    return (
      <section className="username-profile" aria-labelledby="username-profile-title">
        <h2 id="username-profile-title">Nombre de usuario</h2>
        <StateMessage
          description="Recuperando tu identificador visible sin exponer credenciales."
          state="UI-EST-11"
          title="Cargando nombre de usuario"
        />
      </section>
    );
  }

  const snapshot = state.snapshot;

  return (
    <section className="username-profile" aria-labelledby="username-profile-title">
      <div>
        <p className="eyebrow">Identidad visible</p>
        <h2 id="username-profile-title">Nombre de usuario</h2>
        <p>
          Sirve para que administradores y revisores puedan encontrarte sin usar tu correo ni copiar
          el UUID interno de la cuenta.
        </p>
      </div>

      {snapshot?.username ? (
        <div className="username-profile__fixed">
          <span>Tu identificador</span>
          <strong>@{snapshot.username}</strong>
          <small>
            El nombre de usuario es estable. El nombre visible y las credenciales permanecen
            separados.
          </small>
        </div>
      ) : (
        <form className="username-profile__form" onSubmit={claim}>
          <Field
            autoComplete="username"
            helpText="3–32 caracteres. Se guarda en minúsculas. Usa letras, números, punto, guion o guion bajo."
            id="profile-username"
            label="Elige tu nombre de usuario"
            maxLength={32}
            minLength={3}
            name="username"
            onChange={(event) => {
              setDraft(event.currentTarget.value);
              setFieldError(undefined);
            }}
            ref={inputRef}
            required
            spellCheck={false}
            value={draft}
            {...(fieldError ? { error: fieldError } : {})}
          />
          <Button disabled={state.phase === 'saving'} type="submit">
            {state.phase === 'saving' ? 'Guardando…' : 'Fijar nombre de usuario'}
          </Button>
        </form>
      )}

      {state.phase === 'failed' ? (
        <StateMessage
          description={state.message}
          state="UI-EST-04"
          title="No se cambió el nombre de usuario"
        />
      ) : null}
    </section>
  );
}
