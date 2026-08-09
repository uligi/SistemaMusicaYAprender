import type { ClientProblem, ClientProblemKind, RecoverableFieldError } from './types.js';
import { isTransientHttpStatus } from './retry-policy.js';

const stableCodePattern = /^[a-z0-9][a-z0-9._-]{0,127}$/i;

function classifyStatus(status: number): ClientProblemKind {
  if (status === 400 || status === 422) return 'validation';
  if (status === 401) return 'authentication';
  if (status === 403) return 'authorization';
  if (status === 409 || status === 412) return 'conflict';
  if (status === 429) return 'rate-limit';
  if (status >= 500) return 'server';
  return 'unexpected';
}

function localizedContract(
  kind: ClientProblemKind,
): Pick<ClientProblem, 'summary' | 'cause' | 'correction' | 'dataPreserved'> {
  switch (kind) {
    case 'validation':
      return {
        summary: 'Revisa los datos',
        cause: 'El servidor rechazó uno o más valores.',
        correction: 'Corrige los campos indicados y vuelve a intentarlo.',
        dataPreserved: true,
      };
    case 'authentication':
      return {
        summary: 'Necesitas iniciar sesión',
        cause: 'La sesión no está disponible o ya venció.',
        correction: 'Inicia sesión y vuelve a la operación pendiente.',
        dataPreserved: true,
      };
    case 'authorization':
      return {
        summary: 'Acceso denegado',
        cause: 'La operación no está permitida para la sesión actual.',
        correction:
          'Vuelve a una ruta permitida o solicita el acceso por el canal correspondiente.',
        dataPreserved: true,
      };
    case 'conflict':
      return {
        summary: 'Hay una versión más reciente',
        cause: 'La versión confirmada cambió desde que se leyó el recurso.',
        correction: 'Recarga la versión vigente antes de decidir cómo continuar.',
        dataPreserved: true,
      };
    case 'rate-limit':
      return {
        summary: 'La solicitud debe esperar',
        cause: 'El servicio limitó temporalmente nuevas solicitudes.',
        correction: 'Espera un momento antes de volver a intentarlo.',
        dataPreserved: true,
      };
    case 'network':
      return {
        summary: 'Red interrumpida',
        cause: 'No fue posible confirmar una respuesta del servidor.',
        correction: 'Comprueba la conexión y reintenta de forma segura.',
        dataPreserved: true,
      };
    case 'server':
      return {
        summary: 'El servicio no pudo completar la operación',
        cause: 'El servidor informó una falla temporal o interna.',
        correction: 'Conserva los datos y reintenta solo cuando la operación sea segura.',
        dataPreserved: true,
      };
    case 'unexpected':
      return {
        summary: 'No se pudo completar la solicitud',
        cause: 'La respuesta no coincide con el contrato esperado.',
        correction: 'Conserva los datos y vuelve a intentarlo desde una ruta segura.',
        dataPreserved: true,
      };
  }
}

function safeCode(value: unknown, status: number): string {
  return typeof value === 'string' && stableCodePattern.test(value) ? value : `http.${status}`;
}

function safeCorrelationId(value: unknown): string | undefined {
  if (typeof value !== 'string' || value.length < 8 || value.length > 128) {
    return undefined;
  }

  return value;
}

function extractFieldErrors(payload: unknown): readonly RecoverableFieldError[] {
  if (!payload || typeof payload !== 'object') {
    return [];
  }

  const errors = (payload as Record<string, unknown>).errors;
  if (!errors || typeof errors !== 'object' || Array.isArray(errors)) {
    return [];
  }

  return Object.keys(errors).map((field) => ({
    field,
    cause: 'El servidor no aceptó este campo.',
    correction: 'Revisa el valor y la ayuda asociada antes de reenviar.',
    preserved: true,
  }));
}

function isProblemJson(response: Response): boolean {
  const contentType = response.headers.get('content-type')?.toLowerCase() ?? '';
  return contentType.includes('application/problem+json');
}

export function createNetworkProblem(): ClientProblem {
  const contract = localizedContract('network');
  return {
    kind: 'network',
    status: null,
    code: 'client.network',
    ...contract,
    retryable: true,
    fieldErrors: [],
  };
}

export function createUnexpectedProblem(status: number, correlationId?: string): ClientProblem {
  const contract = localizedContract('unexpected');
  return {
    kind: 'unexpected',
    status,
    code: `http.${status}`,
    ...contract,
    retryable: false,
    fieldErrors: [],
    ...(correlationId ? { correlationId } : {}),
  };
}

export async function parseProblemDetails(response: Response): Promise<ClientProblem> {
  let payload: unknown = null;

  if (isProblemJson(response)) {
    try {
      payload = await response.clone().json();
    } catch {
      payload = null;
    }
  }

  const payloadRecord =
    payload && typeof payload === 'object' ? (payload as Record<string, unknown>) : null;
  const kind = classifyStatus(response.status);
  const contract = localizedContract(kind);
  const headerCorrelationId = safeCorrelationId(response.headers.get('x-correlation-id'));
  const payloadCorrelationId = safeCorrelationId(payloadRecord?.correlation_id);
  const correlationId = headerCorrelationId || payloadCorrelationId;

  return {
    kind,
    status: response.status,
    code: safeCode(payloadRecord?.code, response.status),
    ...contract,
    retryable: isTransientHttpStatus(response.status),
    fieldErrors: extractFieldErrors(payload),
    ...(correlationId ? { correlationId } : {}),
  };
}
