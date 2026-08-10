import { useEffect, useRef, useState, type FormEvent } from 'react';
import { useVisibleAccess, useVisibleAccessActions } from '../../app/access/AccessContext';
import { Button, Field, Link, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';

const httpClient = createHttpClient();

type AntiforgeryTokenResponse = {
  requestToken: string;
  headerName: string;
};

type LoginRequest = {
  email: string;
  password: string;
};

type LoginResponse = {
  status: 'AUTHENTICATED';
  role: 'STUDENT';
  message: string;
};

type LogoutResponse = {
  status: 'SIGNED_OUT';
  message: string;
};

type LoginState =
  | { phase: 'idle' }
  | { phase: 'saving' }
  | { phase: 'authenticated'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

type LogoutState =
  | { phase: 'idle' }
  | { phase: 'saving' }
  | { phase: 'signed-out'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

export function PersonalAccountLoginPage() {
  const access = useVisibleAccess();
  const { clearSession, refreshSession } = useVisibleAccessActions();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const emailRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);
  const activeRequestRef = useRef<AbortController | null>(null);
  const activeLogoutRef = useRef<AbortController | null>(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [emailError, setEmailError] = useState<string>();
  const [login, setLogin] = useState<LoginState>({ phase: 'idle' });
  const [logout, setLogout] = useState<LogoutState>({ phase: 'idle' });

  useEffect(() => {
    headingRef.current?.focus();
    return () => {
      activeRequestRef.current?.abort();
      activeLogoutRef.current?.abort();
    };
  }, []);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!emailRef.current?.validity.valid) {
      setEmailError('Escribe una dirección de correo válida.');
      emailRef.current?.focus();
      return;
    }

    activeRequestRef.current?.abort();
    const controller = new AbortController();
    activeRequestRef.current = controller;
    setEmailError(undefined);
    setLogout({ phase: 'idle' });
    setLogin({ phase: 'saving' });

    const antiforgery = await httpClient.get<AntiforgeryTokenResponse>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
      signal: controller.signal,
    });

    if (antiforgery.kind === 'cancelled') return;
    if (!antiforgery.ok) {
      setLogin({ phase: 'failed', problem: antiforgery.problem });
      return;
    }

    const result = await httpClient.post<LoginRequest, LoginResponse>(
      '/auth/login',
      { email: email.trim(), password },
      {
        headers: {
          [antiforgery.data.headerName]: antiforgery.data.requestToken,
        },
        retry: 'never',
        signal: controller.signal,
      },
    );

    if (activeRequestRef.current !== controller) return;
    activeRequestRef.current = null;
    if (result.kind === 'cancelled') return;

    setPassword('');
    if (result.ok) {
      setLogin({ phase: 'authenticated', message: result.data.message });
      void refreshSession();
      return;
    }

    setLogin({ phase: 'failed', problem: result.problem });
    requestAnimationFrame(() => passwordRef.current?.focus());
  };

  const closeSession = async () => {
    activeLogoutRef.current?.abort();
    const controller = new AbortController();
    activeLogoutRef.current = controller;
    setLogout({ phase: 'saving' });

    const antiforgery = await httpClient.get<AntiforgeryTokenResponse>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
      signal: controller.signal,
    });

    if (antiforgery.kind === 'cancelled') return;
    if (!antiforgery.ok) {
      setLogout({ phase: 'failed', problem: antiforgery.problem });
      return;
    }

    const result = await httpClient.post<Record<string, never>, LogoutResponse>(
      '/auth/logout',
      {},
      {
        headers: {
          [antiforgery.data.headerName]: antiforgery.data.requestToken,
        },
        retry: 'never',
        signal: controller.signal,
        invalidate: ['/auth/session'],
      },
    );

    if (activeLogoutRef.current !== controller) return;
    activeLogoutRef.current = null;
    if (result.kind === 'cancelled') return;

    if (result.ok) {
      clearSession();
      setLogin({ phase: 'idle' });
      setLogout({ phase: 'signed-out', message: result.data.message });
      requestAnimationFrame(() => headingRef.current?.focus());
      return;
    }

    setLogout({ phase: 'failed', problem: result.problem });
  };

  const canCloseSession = access.isAuthenticated || login.phase === 'authenticated';

  return (
    <article className="route-surface login" data-route-id="UI-MVP-007">
      <div className="login__intro">
        <p className="eyebrow">UI-MVP-007 · Área pública</p>
        <h1 id="route-title" ref={headingRef} tabIndex={-1}>
          Inicia sesión
        </h1>
        <p>
          Accede con una cuenta activa. La respuesta de error no confirma si el correo existe y la
          sesión permanece protegida por el servidor.
        </p>
      </div>

      {!access.isAuthenticated ? (
        <form
          aria-busy={login.phase === 'saving'}
          className="login__form"
          noValidate
          onSubmit={submit}
        >
          <Field
            autoComplete="username"
            id="login-email"
            label="Correo electrónico"
            maxLength={254}
            name="email"
            onChange={(event) => {
              setEmail(event.currentTarget.value);
              setEmailError(undefined);
            }}
            ref={emailRef}
            required
            type="email"
            value={email}
            {...(emailError ? { error: emailError } : {})}
          />

          <Field
            autoComplete="current-password"
            helpText="Puedes pegar la contraseña o usar tu gestor de credenciales."
            id="login-password"
            label="Contraseña"
            name="password"
            onChange={(event) => setPassword(event.currentTarget.value)}
            ref={passwordRef}
            required
            type="password"
            value={password}
          />

          <Button disabled={login.phase === 'saving'} type="submit">
            {login.phase === 'saving' ? 'Comprobando acceso…' : 'Iniciar sesión'}
          </Button>
        </form>
      ) : null}

      {login.phase === 'saving' ? (
        <StateMessage
          description="La credencial se comprueba sin exponerla en la URL ni en el almacenamiento del navegador."
          state="UI-EST-11"
          title="Comprobando acceso"
        />
      ) : null}

      {login.phase === 'authenticated' ? (
        <StateMessage
          action={<Link href="/preferencias">Continuar a tu espacio</Link>}
          description={login.message}
          state="UI-EST-12"
          title="Sesión confirmada"
        />
      ) : null}

      {login.phase === 'failed' ? (
        <StateMessage
          description={
            login.problem.code === 'identity.login.failed'
              ? 'Revisa el correo y la contraseña e inténtalo nuevamente.'
              : login.problem.correction
          }
          state={login.problem.kind === 'authentication' ? 'UI-EST-09' : 'UI-EST-06'}
          title={
            login.problem.code === 'identity.login.failed'
              ? 'No se pudo iniciar sesión'
              : login.problem.summary
          }
        />
      ) : null}

      {canCloseSession ? (
        <section
          aria-busy={logout.phase === 'saving'}
          aria-labelledby="logout-title"
          className="login__logout"
        >
          <div>
            <h2 id="logout-title">Sesión activa</h2>
            <p>
              Cerrar sesión revoca únicamente esta sesión en el servidor. Otras sesiones y cuentas
              permanecen independientes.
            </p>
          </div>
          <Button
            disabled={logout.phase === 'saving'}
            onClick={() => void closeSession()}
            type="button"
          >
            {logout.phase === 'saving' ? 'Cerrando sesión…' : 'Cerrar sesión'}
          </Button>
        </section>
      ) : null}

      {logout.phase === 'saving' ? (
        <StateMessage
          description="El servidor está revocando la sesión actual antes de retirar la cookie."
          state="UI-EST-11"
          title="Cerrando sesión"
        />
      ) : null}

      {logout.phase === 'signed-out' ? (
        <StateMessage description={logout.message} state="UI-EST-12" title="Sesión cerrada" />
      ) : null}

      {logout.phase === 'failed' ? (
        <StateMessage
          description={logout.problem.correction}
          state="UI-EST-06"
          title={logout.problem.summary}
        />
      ) : null}

      <p className="login__privacy">
        La cookie de sesión es HttpOnly, Secure y de mismo origen. No guardamos tokens de sesión en
        localStorage ni en la URL.
      </p>
    </article>
  );
}
