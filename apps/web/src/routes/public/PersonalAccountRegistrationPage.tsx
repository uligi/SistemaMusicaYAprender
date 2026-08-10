import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';

const httpClient = createHttpClient();

type RegistrationConsentNotice = {
  purposeCode: string;
  title: string;
  noticeVersion: string;
  effectiveFromUtc: string;
  required: true;
};

type RegistrationConsentCatalogResponse = {
  notices: RegistrationConsentNotice[];
};

type RegistrationConsentRequest = {
  purposeCode: string;
  noticeVersion: string;
  decision: boolean;
};

type RegistrationRequest = {
  email: string;
  consents: RegistrationConsentRequest[];
};

type RegistrationResponse = {
  status: 'RECEIVED';
  message: string;
};

type ConsentCatalogState =
  | { phase: 'loading' }
  | { phase: 'ready'; notices: RegistrationConsentNotice[] }
  | { phase: 'failed'; correction: string };

type SubmissionState =
  | { phase: 'idle' }
  | { phase: 'saving' }
  | { phase: 'accepted'; message: string }
  | { phase: 'failed'; problem: ClientProblem };

type PendingOperation = {
  email: string;
  consentFingerprint: string;
  idempotencyKey: string;
};

function emptyConsentSelections(notices: readonly RegistrationConsentNotice[]) {
  return Object.fromEntries(notices.map((notice) => [notice.purposeCode, false]));
}

function consentFingerprint(notices: readonly RegistrationConsentNotice[]) {
  return notices
    .map((notice) => `${notice.purposeCode}:${notice.noticeVersion}:true`)
    .sort()
    .join('|');
}

function isUsableCatalog(
  response: RegistrationConsentCatalogResponse,
): response is RegistrationConsentCatalogResponse {
  const purposes = new Set(response.notices.map((notice) => notice.purposeCode));
  return (
    response.notices.length === 2 &&
    purposes.size === response.notices.length &&
    response.notices.every(
      (notice) =>
        notice.required === true &&
        notice.purposeCode.length > 0 &&
        notice.noticeVersion.length > 0,
    )
  );
}

export function PersonalAccountRegistrationPage() {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const emailInputRef = useRef<HTMLInputElement>(null);
  const consentInputRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const pendingOperationRef = useRef<PendingOperation | null>(null);
  const activeRequestRef = useRef<AbortController | null>(null);
  const [email, setEmail] = useState('');
  const [emailError, setEmailError] = useState<string>();
  const [consentError, setConsentError] = useState<string>();
  const [consentCatalog, setConsentCatalog] = useState<ConsentCatalogState>({
    phase: 'loading',
  });
  const [consentSelections, setConsentSelections] = useState<Record<string, boolean>>({});
  const [submission, setSubmission] = useState<SubmissionState>({ phase: 'idle' });

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const loadConsents = async () => {
      const result = await httpClient.get<RegistrationConsentCatalogResponse>(
        '/auth/registration-consents',
        { cacheMode: 'no-store', signal: controller.signal },
      );

      if (result.kind === 'cancelled') return;

      if (!result.ok || !isUsableCatalog(result.data)) {
        setConsentCatalog({
          phase: 'failed',
          correction: result.ok
            ? 'Vuelve a cargar la página antes de iniciar el registro.'
            : result.problem.correction,
        });
        return;
      }

      setConsentSelections(emptyConsentSelections(result.data.notices));
      setConsentCatalog({ phase: 'ready', notices: result.data.notices });
    };

    void loadConsents();

    return () => {
      controller.abort();
      activeRequestRef.current?.abort();
    };
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

    if (consentCatalog.phase !== 'ready') {
      setSubmission({ phase: 'idle' });
      return;
    }

    const firstUnaccepted = consentCatalog.notices.find(
      (notice) => !consentSelections[notice.purposeCode],
    );
    if (firstUnaccepted) {
      setConsentError(
        'Acepta las versiones vigentes de los términos de uso y la política de privacidad.',
      );
      setSubmission({ phase: 'idle' });
      consentInputRefs.current[firstUnaccepted.purposeCode]?.focus();
      return;
    }

    const submittedEmail = email.trim();
    const fingerprint = consentFingerprint(consentCatalog.notices);
    const pendingOperation = pendingOperationRef.current;
    const operation =
      pendingOperation?.email === submittedEmail &&
      pendingOperation.consentFingerprint === fingerprint
        ? pendingOperation
        : {
            email: submittedEmail,
            consentFingerprint: fingerprint,
            idempotencyKey: crypto.randomUUID(),
          };

    pendingOperationRef.current = operation;
    activeRequestRef.current?.abort();

    const controller = new AbortController();
    activeRequestRef.current = controller;
    setEmailError(undefined);
    setConsentError(undefined);
    setSubmission({ phase: 'saving' });

    const result = await httpClient.post<RegistrationRequest, RegistrationResponse>(
      '/auth/register',
      {
        email: submittedEmail,
        consents: consentCatalog.notices.map((notice) => ({
          purposeCode: notice.purposeCode,
          noticeVersion: notice.noticeVersion,
          decision: true,
        })),
      },
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
      setConsentSelections(emptyConsentSelections(consentCatalog.notices));
      setSubmission({ phase: 'accepted', message: result.data.message });
      return;
    }

    if (result.problem.fieldErrors.some((fieldError) => fieldError.field === 'email')) {
      setEmailError('Escribe una dirección de correo válida de hasta 254 caracteres.');
      requestAnimationFrame(() => emailInputRef.current?.focus());
    }

    if (result.problem.fieldErrors.some((fieldError) => fieldError.field === 'consents')) {
      setConsentError(
        'Las condiciones cambiaron o falta una aceptación. Revisa las versiones vigentes.',
      );
      requestAnimationFrame(() =>
        consentInputRefs.current[consentCatalog.notices[0]?.purposeCode ?? '']?.focus(),
      );
    }

    if (result.problem.code === 'identity.registration.idempotency-conflict') {
      pendingOperationRef.current = null;
    }

    setSubmission({ phase: 'failed', problem: result.problem });
  };

  const notices = consentCatalog.phase === 'ready' ? consentCatalog.notices : [];

  return (
    <article className="route-surface registration" data-route-id="UI-MVP-005">
      <div className="registration__intro">
        <p className="eyebrow">UI-MVP-005 · Área pública</p>
        <h1 id="route-title" ref={headingRef} tabIndex={-1}>
          Crea tu cuenta personal
        </h1>
        <p>
          Comienza con tu correo y acepta las condiciones vigentes. La respuesta será la misma
          aunque ya exista una solicitud, para proteger la privacidad de cada cuenta.
        </p>
      </div>

      <form
        aria-busy={submission.phase === 'saving' || consentCatalog.phase === 'loading'}
        className="registration__form"
        noValidate
        onSubmit={submit}
      >
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

        {consentCatalog.phase === 'loading' ? (
          <StateMessage
            description="Comprobamos qué versiones deben quedar asociadas con el registro."
            state="UI-EST-01"
            title="Cargando condiciones vigentes"
          />
        ) : null}

        {consentCatalog.phase === 'failed' ? (
          <StateMessage
            description={consentCatalog.correction}
            state="UI-EST-06"
            title="No pudimos cargar las condiciones vigentes"
          />
        ) : null}

        {notices.length > 0 ? (
          <fieldset
            aria-describedby={consentError ? 'registration-consents-error' : undefined}
            className="registration__consents"
          >
            <legend>Condiciones obligatorias</legend>
            <p className="registration__consents-help">
              Cada aceptación se registra por separado con su versión y fecha.
            </p>
            {notices.map((notice) => {
              const inputId = `registration-consent-${notice.purposeCode.toLowerCase()}`;
              return (
                <label className="registration__consent" htmlFor={inputId} key={notice.purposeCode}>
                  <input
                    checked={consentSelections[notice.purposeCode] ?? false}
                    id={inputId}
                    name={notice.purposeCode}
                    onChange={(event) => {
                      const checked = event.currentTarget.checked;
                      setConsentSelections((current) => ({
                        ...current,
                        [notice.purposeCode]: checked,
                      }));
                      setConsentError(undefined);
                    }}
                    ref={(element) => {
                      consentInputRefs.current[notice.purposeCode] = element;
                    }}
                    required
                    type="checkbox"
                  />
                  <span>
                    Acepto {notice.title.toLocaleLowerCase('es-CR')}{' '}
                    <small>(versión {notice.noticeVersion})</small>
                  </span>
                </label>
              );
            })}
            {consentError ? (
              <p className="ma-field__error" id="registration-consents-error" role="alert">
                {consentError}
              </p>
            ) : null}
          </fieldset>
        ) : null}

        <Button
          disabled={submission.phase === 'saving' || consentCatalog.phase !== 'ready'}
          type="submit"
        >
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
        Una cuenta nueva permanece pendiente. La verificación de un solo uso y la credencial se
        completarán antes de activar el acceso.
      </p>
    </article>
  );
}
