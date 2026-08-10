import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';

const httpClient = createHttpClient();

type VerificationResponse = {
  status: 'VERIFIED' | 'RECEIVED';
  message: string;
};

type VerificationSubmission =
  | { phase: 'idle' }
  | { phase: 'saving' }
  | { phase: 'accepted'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

type ResendSubmission =
  | { phase: 'idle' }
  | { phase: 'saving' }
  | { phase: 'accepted'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

type PendingResend = {
  email: string;
  idempotencyKey: string;
};

export function PersonalAccountVerificationPage() {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const tokenInputRef = useRef<HTMLInputElement>(null);
  const emailInputRef = useRef<HTMLInputElement>(null);
  const verificationRequestRef = useRef<AbortController | null>(null);
  const resendRequestRef = useRef<AbortController | null>(null);
  const pendingResendRef = useRef<PendingResend | null>(null);
  const [token, setToken] = useState('');
  const [email, setEmail] = useState('');
  const [tokenError, setTokenError] = useState<string>();
  const [emailError, setEmailError] = useState<string>();
  const [verification, setVerification] = useState<VerificationSubmission>({ phase: 'idle' });
  const [resend, setResend] = useState<ResendSubmission>({ phase: 'idle' });

  useEffect(() => {
    headingRef.current?.focus();

    return () => {
      verificationRequestRef.current?.abort();
      resendRequestRef.current?.abort();
    };
  }, []);

  const verifyAccount = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    const submittedToken = token.trim();
    if (submittedToken.length === 0 || submittedToken.length > 128) {
      setTokenError('Escribe el código completo recibido por correo.');
      setVerification({ phase: 'idle' });
      tokenInputRef.current?.focus();
      return;
    }

    verificationRequestRef.current?.abort();
    const controller = new AbortController();
    verificationRequestRef.current = controller;
    setTokenError(undefined);
    setVerification({ phase: 'saving' });

    const result = await httpClient.post<{ token: string }, VerificationResponse>(
      '/auth/verify-account',
      { token: submittedToken },
      { signal: controller.signal, retry: 'never' },
    );

    if (verificationRequestRef.current !== controller) return;
    verificationRequestRef.current = null;
    if (result.kind === 'cancelled') return;

    if (result.ok) {
      setToken('');
      setVerification({ phase: 'accepted', message: result.data.message });
      return;
    }

    if (result.problem.fieldErrors.some((fieldError) => fieldError.field === 'token')) {
      setTokenError('El código no es válido, ya fue consumido o venció. Solicita uno nuevo.');
      requestAnimationFrame(() => tokenInputRef.current?.focus());
    }

    setVerification({ phase: 'failed', problem: result.problem });
  };

  const resendCode = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!emailInputRef.current?.validity.valid) {
      setEmailError('Escribe una dirección de correo válida de hasta 254 caracteres.');
      setResend({ phase: 'idle' });
      emailInputRef.current?.focus();
      return;
    }

    const submittedEmail = email.trim();
    const pending = pendingResendRef.current;
    const operation =
      pending?.email === submittedEmail
        ? pending
        : { email: submittedEmail, idempotencyKey: crypto.randomUUID() };
    pendingResendRef.current = operation;

    resendRequestRef.current?.abort();
    const controller = new AbortController();
    resendRequestRef.current = controller;
    setEmailError(undefined);
    setResend({ phase: 'saving' });

    const result = await httpClient.post<{ email: string }, VerificationResponse>(
      '/auth/verification/resend',
      { email: submittedEmail },
      { idempotencyKey: operation.idempotencyKey, signal: controller.signal },
    );

    if (resendRequestRef.current !== controller) return;
    resendRequestRef.current = null;
    if (result.kind === 'cancelled') return;

    if (result.ok) {
      pendingResendRef.current = null;
      setEmail('');
      setResend({ phase: 'accepted', message: result.data.message });
      return;
    }

    if (result.problem.fieldErrors.some((fieldError) => fieldError.field === 'email')) {
      setEmailError('Escribe una dirección de correo válida de hasta 254 caracteres.');
      requestAnimationFrame(() => emailInputRef.current?.focus());
    }

    if (result.problem.code === 'identity.verification-resend.idempotency-conflict') {
      pendingResendRef.current = null;
    }

    setResend({ phase: 'failed', problem: result.problem });
  };

  return (
    <article className="route-surface verification" data-route-id="UI-MVP-006">
      <div className="verification__intro">
        <p className="eyebrow">UI-MVP-006 · Área pública</p>
        <h1 id="route-title" ref={headingRef} tabIndex={-1}>
          Verifica tu cuenta
        </h1>
        <p>
          Escribe el código de un solo uso que recibiste por correo. Por seguridad, el código no se
          lee desde la dirección de esta página ni se guarda en el navegador.
        </p>
      </div>

      <section aria-labelledby="verification-code-title" className="verification__panel">
        <h2 id="verification-code-title">Código de verificación</h2>
        <form
          aria-busy={verification.phase === 'saving'}
          className="verification__form"
          noValidate
          onSubmit={verifyAccount}
        >
          <Field
            autoCapitalize="none"
            autoComplete="one-time-code"
            helpText="El código distingue mayúsculas y minúsculas y vence 30 minutos después de emitirse."
            id="account-verification-token"
            label="Código recibido"
            maxLength={128}
            name="token"
            onChange={(event) => {
              setToken(event.currentTarget.value);
              setTokenError(undefined);
            }}
            ref={tokenInputRef}
            required
            spellCheck={false}
            type="text"
            value={token}
            {...(tokenError ? { error: tokenError } : {})}
          />
          <Button disabled={verification.phase === 'saving'} type="submit">
            {verification.phase === 'saving' ? 'Verificando…' : 'Verificar cuenta'}
          </Button>
        </form>

        {verification.phase === 'saving' ? (
          <StateMessage
            description="Validamos el código y las condiciones vigentes en una sola operación."
            state="UI-EST-11"
            title="Verificando cuenta"
          />
        ) : null}
        {verification.phase === 'accepted' ? (
          <StateMessage
            description={verification.message}
            state="UI-EST-12"
            title="Cuenta verificada"
          />
        ) : null}
        {verification.phase === 'failed' ? (
          <StateMessage
            description={verification.problem.correction}
            state={verification.problem.kind === 'conflict' ? 'UI-EST-10' : 'UI-EST-09'}
            title={verification.problem.summary}
          />
        ) : null}
      </section>

      <section aria-labelledby="verification-resend-title" className="verification__panel">
        <h2 id="verification-resend-title">¿Necesitas otro código?</h2>
        <p className="verification__help">
          La respuesta no revelará si el correo corresponde a una cuenta pendiente.
        </p>
        <form
          aria-busy={resend.phase === 'saving'}
          className="verification__form"
          noValidate
          onSubmit={resendCode}
        >
          <Field
            autoComplete="email"
            id="verification-resend-email"
            label="Correo electrónico"
            maxLength={254}
            name="email"
            onChange={(event) => {
              const nextEmail = event.currentTarget.value;
              if (pendingResendRef.current?.email !== nextEmail.trim()) {
                pendingResendRef.current = null;
              }
              setEmail(nextEmail);
              setEmailError(undefined);
            }}
            ref={emailInputRef}
            required
            type="email"
            value={email}
            {...(emailError ? { error: emailError } : {})}
          />
          <Button disabled={resend.phase === 'saving'} type="submit" variant="secondary">
            {resend.phase === 'saving' ? 'Solicitando…' : 'Solicitar otro código'}
          </Button>
        </form>

        {resend.phase === 'accepted' ? (
          <StateMessage description={resend.message} state="UI-EST-12" title="Solicitud recibida" />
        ) : null}
        {resend.phase === 'failed' ? (
          <StateMessage
            description={resend.problem.correction}
            state={resend.problem.kind === 'conflict' ? 'UI-EST-10' : 'UI-EST-06'}
            title={resend.problem.summary}
          />
        ) : null}
      </section>
    </article>
  );
}
