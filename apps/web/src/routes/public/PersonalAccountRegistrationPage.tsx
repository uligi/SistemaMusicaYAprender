import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';

const httpClient = createHttpClient();

type RegistrationResponse = {
  status: 'RECEIVED';
  message: string;
};

type SubmissionState =
  | { phase: 'idle' }
  | { phase: 'saving' }
  | { phase: 'accepted'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

type PendingOperation = {
  email: string;
  idempotencyKey: string;
};

export function PersonalAccountRegistrationPage() {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const emailInputRef = useRef<HTMLInputElement>(null);
  const pendingOperationRef = useRef<PendingOperation | null>(null);
  const activeRequestRef = useRef<AbortController | null>(null);
  const [email, setEmail] = useState('');
  const [emailError, setEmailError] = useState<string>();
  const [submission, setSubmission] = useState<SubmissionState>({ phase: 'idle' });

  useEffect(() => {
    headingRef.current?.focus();
    return () => activeRequestRef.current?.abort();
  }, []);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    const input = emailInputRef.current;
    if (!input?.validity.valid) {
      setEmailError('Escribe una dirección de correo válida de hasta 254 caracteres.');
      setSubmission({ phase: 'idle' });
      input?.focus();
      return;
    }

    const submittedEmail = email.trim();
    const pendingOperation = pendingOperationRef.current;
    const operation =
      pendingOperation?.email === submittedEmail
        ? pendingOperation
        : {
            email: submittedEmail,
            idempotencyKey: crypto.randomUUID(),
          };

    pendingOperationRef.current = operation;
    activeRequestRef.current?.abort();

    const controller = new AbortController();
    activeRequestRef.current = controller;
    setEmailError(undefined);
    setSubmission({ phase: 'saving' });

    const result = await httpClient.post<{ email: string }, RegistrationResponse>(
      '/auth/register',
      { email: submittedEmail },
      {
        idempotencyKey: operation.idempotencyKey,
        signal: controller.signal,
      },
    );

    if (activeRequestRef.current !== controller) return;
    activeRequestRef.current = null;

    if (result.kind === 'cancelled') return;

    if (result.ok) {
      pendingOperationRef.current = null;
      setEmail('');
      setSubmission({ phase: 'accepted', message: result.data.message });
      return;
    }

    if (result.problem.fieldErrors.some((fieldError) => fieldError.field === 'email')) {
      setEmailError('Escribe una dirección de correo válida de hasta 254 caracteres.');
      requestAnimationFrame(() => emailInputRef.current?.focus());
    }

    if (result.problem.code === 'identity.registration.idempotency-conflict') {
      pendingOperationRef.current = null;
    }

    setSubmission({ phase: 'failed', problem: result.problem });
  };

  return (
    <article className="route-surface registration" data-route-id="UI-MVP-005">
      <div className="registration__intro">
        <p className="eyebrow">UI-MVP-005 · Área pública</p>
        <h1 id="route-title" ref={headingRef} tabIndex={-1}>
          Crea tu cuenta personal
        </h1>
        <p>
          Comienza con tu correo. La respuesta será la misma aunque ya exista una solicitud, para
          proteger la privacidad de cada cuenta.
        </p>
      </div>

      <form className="registration__form" noValidate onSubmit={submit}>
        <Field
          autoComplete="email"
          helpText="Usaremos este correo solo para el acceso y la verificación de la cuenta."
          id="registration-email"
          label="Correo electrónico"
          maxLength={254}
          name="email"
          onChange={(event) => {
            const nextEmail = event.currentTarget.value;
            if (pendingOperationRef.current?.email !== nextEmail.trim()) {
              pendingOperationRef.current = null;
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

        <Button disabled={submission.phase === 'saving'} type="submit">
          {submission.phase === 'saving' ? 'Enviando solicitud…' : 'Continuar registro'}
        </Button>
      </form>

      {submission.phase === 'saving' ? (
        <StateMessage
          description="Conservamos la misma operación mientras se confirma la respuesta."
          state="UI-EST-11"
          title="Enviando solicitud"
        />
      ) : null}

      {submission.phase === 'accepted' ? (
        <StateMessage
          description={submission.message}
          state="UI-EST-12"
          title="Solicitud recibida"
        />
      ) : null}

      {submission.phase === 'failed' ? (
        <StateMessage
          description={
            submission.problem.code === 'identity.registration.idempotency-conflict'
              ? 'Vuelve a enviar los datos para iniciar una operación nueva.'
              : submission.problem.correction
          }
          state={
            submission.problem.kind === 'validation'
              ? 'UI-EST-09'
              : submission.problem.kind === 'conflict'
                ? 'UI-EST-10'
                : 'UI-EST-06'
          }
          title={
            submission.problem.code === 'identity.registration.idempotency-conflict'
              ? 'La solicitud necesita una clave nueva'
              : submission.problem.summary
          }
        />
      ) : null}

      <p className="registration__privacy">
        Una cuenta nueva permanece pendiente. Los consentimientos, la verificación y la credencial
        se completarán antes de activar el acceso.
      </p>
    </article>
  );
}
