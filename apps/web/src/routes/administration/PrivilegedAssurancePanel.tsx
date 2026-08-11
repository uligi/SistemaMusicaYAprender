import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';

type MfaStatus = {
  enrolled: boolean;
  recentAssurance: boolean;
  methodType?: string | null;
  assuranceExpiresAt?: string | null;
};

type EnrollmentStarted = {
  challengeId: string;
  secret: string;
  otpAuthUri: string;
  expiresAt: string;
};

type ChallengeStarted = {
  challengeId: string;
  expiresAt: string;
  maximumAttempts: number;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

export type PrivilegedAssurancePanelProps = {
  onReadyChange: (ready: boolean) => void;
};

const client = createHttpClient();

function problemMessage(result: unknown): string {
  if (
    typeof result === 'object' &&
    result !== null &&
    'kind' in result &&
    (result as { kind?: string }).kind === 'problem' &&
    'problem' in result
  ) {
    const problem = (
      result as {
        problem?: { detail?: string; title?: string };
      }
    ).problem;
    return problem?.detail ?? problem?.title ?? 'No fue posible completar la verificación.';
  }

  return 'No fue posible completar la verificación.';
}

async function csrfHeaders(): Promise<Readonly<Record<string, string>> | null> {
  const result = await client.get<Csrf>('/auth/csrf', {
    cacheMode: 'no-store',
    retry: 'never',
  });

  if (!result.ok) return null;

  return {
    [result.data.headerName]: result.data.requestToken,
  };
}

export function PrivilegedAssurancePanel({ onReadyChange }: PrivilegedAssurancePanelProps) {
  const [status, setStatus] = useState<MfaStatus | null>(null);
  const [password, setPassword] = useState('');
  const [enrollment, setEnrollment] = useState<EnrollmentStarted | null>(null);
  const [stepUp, setStepUp] = useState<ChallengeStarted | null>(null);
  const [code, setCode] = useState('');
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const loadStatus = useCallback(async () => {
    const result = await client.get<MfaStatus>('/security/mfa/status', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!result.ok) {
      setStatus(null);
      onReadyChange(false);
      setError(problemMessage(result));
      return;
    }

    setStatus(result.data);
    onReadyChange(result.data.recentAssurance);
  }, [onReadyChange]);

  useEffect(() => {
    void loadStatus();
  }, [loadStatus]);

  useEffect(() => {
    if (!status?.recentAssurance || !status.assuranceExpiresAt) return;

    const remaining = new Date(status.assuranceExpiresAt).getTime() - Date.now();
    if (remaining <= 0) {
      onReadyChange(false);
      return;
    }

    const timeout = window.setTimeout(
      () => {
        setStatus((current) =>
          current
            ? {
                ...current,
                recentAssurance: false,
                assuranceExpiresAt: null,
              }
            : current,
        );
        onReadyChange(false);
      },
      Math.min(remaining + 250, 2_147_000_000),
    );

    return () => window.clearTimeout(timeout);
  }, [onReadyChange, status?.assuranceExpiresAt, status?.recentAssurance]);

  async function beginEnrollment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');
    setError('');

    if (!password) {
      setError('Escribe tu contraseña actual para confirmar la inscripción.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<{ currentPassword: string }, EnrollmentStarted>(
      '/security/mfa/enrollment/start',
      { currentPassword: password },
      {
        headers,
        retry: 'never',
      },
    );
    setBusy(false);
    setPassword('');

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setEnrollment(result.data);
    setCode('');
    setMessage(
      'Añade la clave en tu aplicación autenticadora y confirma un código antes de que expire el reto.',
    );
  }

  async function confirmEnrollment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');
    setError('');

    if (!enrollment || !/^\d{6}$/.test(code)) {
      setError('Escribe el código de seis dígitos de tu aplicación autenticadora.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<
      { challengeId: string; secret: string; code: string },
      MfaStatus
    >(
      '/security/mfa/enrollment/confirm',
      {
        challengeId: enrollment.challengeId,
        secret: enrollment.secret,
        code,
      },
      {
        headers,
        retry: 'never',
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setEnrollment(null);
    setCode('');
    setStatus(result.data);
    setMessage('Segundo factor TOTP confirmado. Ahora realiza la verificación reforzada.');
    onReadyChange(false);
  }

  async function beginStepUp() {
    setMessage('');
    setError('');

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<Record<string, never>, ChallengeStarted>(
      '/security/mfa/step-up/start',
      {},
      {
        headers,
        retry: 'never',
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setStepUp(result.data);
    setCode('');
    setMessage(
      `Reto iniciado. Tienes hasta ${result.data.maximumAttempts} intentos antes de iniciar uno nuevo.`,
    );
  }

  async function confirmStepUp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');
    setError('');

    if (!stepUp || !/^\d{6}$/.test(code)) {
      setError('Escribe el código de seis dígitos de tu aplicación autenticadora.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<{ challengeId: string; code: string }, MfaStatus>(
      '/security/mfa/step-up/confirm',
      {
        challengeId: stepUp.challengeId,
        code,
      },
      {
        headers,
        retry: 'never',
        invalidate: ['/security/role-assignments'],
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setStepUp(null);
    setCode('');
    setStatus(result.data);
    onReadyChange(result.data.recentAssurance);
    setMessage('Verificación reforzada confirmada para esta sesión.');
  }

  return (
    <section className="role-management__assurance" aria-labelledby="privileged-assurance-title">
      <div>
        <p className="role-management__eyebrow">Acceso privilegiado · BL-MVP-032</p>
        <h2 id="privileged-assurance-title">Verificación reforzada</h2>
        <p>
          Las operaciones administrativas requieren un segundo factor confirmado recientemente. La
          clave TOTP no se persiste en el navegador ni se guarda en claro en PostgreSQL.
        </p>
      </div>

      {error ? (
        <StateMessage state="UI-EST-04" title="No se amplió el acceso" description={error} />
      ) : null}

      {message ? (
        <p className="role-management__success" role="status">
          {message}
        </p>
      ) : null}

      {status?.recentAssurance ? (
        <p className="role-management__assurance-ok" role="status">
          Verificación vigente
          {status.assuranceExpiresAt
            ? ` hasta ${new Date(status.assuranceExpiresAt).toLocaleTimeString('es-CR')}`
            : ''}
          .
        </p>
      ) : null}

      {status && !status.enrolled ? (
        <form className="role-management__assurance-form" onSubmit={beginEnrollment}>
          <Field
            id="mfa-current-password"
            label="Contraseña actual"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
          <Button type="submit" disabled={busy}>
            Preparar segundo factor
          </Button>
        </form>
      ) : null}

      {enrollment ? (
        <form className="role-management__assurance-form" onSubmit={confirmEnrollment}>
          <p>
            Clave manual del autenticador:{' '}
            <code className="role-management__totp-secret">{enrollment.secret}</code>
          </p>
          <p>El reto vence a las {new Date(enrollment.expiresAt).toLocaleTimeString('es-CR')}.</p>
          <Field
            id="mfa-enrollment-code"
            label="Código de confirmación"
            inputMode="numeric"
            autoComplete="one-time-code"
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
            minLength={6}
            maxLength={6}
            required
          />
          <Button type="submit" disabled={busy}>
            Confirmar segundo factor
          </Button>
        </form>
      ) : null}

      {status?.enrolled && !status.recentAssurance && !stepUp ? (
        <Button type="button" disabled={busy} onClick={() => void beginStepUp()}>
          Verificar con autenticador
        </Button>
      ) : null}

      {stepUp ? (
        <form className="role-management__assurance-form" onSubmit={confirmStepUp}>
          <Field
            id="mfa-step-up-code"
            label="Código del autenticador"
            inputMode="numeric"
            autoComplete="one-time-code"
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
            minLength={6}
            maxLength={6}
            required
          />
          <Button type="submit" disabled={busy}>
            Confirmar verificación reforzada
          </Button>
        </form>
      ) : null}
    </section>
  );
}
