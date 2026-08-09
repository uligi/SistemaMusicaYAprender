export type HttpMethod = 'GET' | 'HEAD' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

export type ClientProblemKind =
  | 'validation'
  | 'authentication'
  | 'authorization'
  | 'conflict'
  | 'rate-limit'
  | 'network'
  | 'server'
  | 'unexpected';

export type MutationUiState =
  'UI-EST-06' | 'UI-EST-07' | 'UI-EST-08' | 'UI-EST-09' | 'UI-EST-10' | 'UI-EST-11' | 'UI-EST-12';

export type RecoverableFieldError = {
  field: string;
  cause: string;
  correction: string;
  preserved: boolean;
};

export type ClientProblem = {
  kind: ClientProblemKind;
  status: number | null;
  code: string;
  summary: string;
  cause: string;
  correction: string;
  dataPreserved: boolean;
  retryable: boolean;
  fieldErrors: readonly RecoverableFieldError[];
  correlationId?: string;
};

export type ApiSuccess<T> = {
  ok: true;
  kind: 'success';
  status: number;
  data: T;
  fromCache: boolean;
  etag?: string;
  correlationId?: string;
};

export type ApiFailure = {
  ok: false;
  kind: 'problem';
  problem: ClientProblem;
};

export type ApiCancelled = {
  ok: false;
  kind: 'cancelled';
};

export type ApiResult<T> = ApiSuccess<T> | ApiFailure | ApiCancelled;

export type MutationState =
  | { phase: 'saving'; uiState: 'UI-EST-11' }
  | {
      phase: 'confirmed';
      uiState: 'UI-EST-12';
      etag?: string;
      correlationId?: string;
    }
  | {
      phase: 'failed';
      uiState: 'UI-EST-06' | 'UI-EST-07' | 'UI-EST-08' | 'UI-EST-09';
      problem: ClientProblem;
    }
  | { phase: 'conflict'; uiState: 'UI-EST-10'; problem: ClientProblem }
  | { phase: 'cancelled'; uiState: null };

export type CacheMode = 'default' | 'reload' | 'no-store';

export type HttpRequestOptions = {
  signal?: AbortSignal;
  headers?: Readonly<Record<string, string>>;
  locale?: string;
  retry?: 'safe' | 'never';
  cacheMode?: CacheMode;
  cacheMaxAgeMs?: number;
  ifMatch?: string;
  idempotencyKey?: string;
};

export type MutationRequestOptions = HttpRequestOptions & {
  invalidate?: readonly string[];
  onStateChange?: (state: MutationState) => void;
};

export type HttpClientConfiguration = {
  baseUrl?: string;
  locale?: string;
  readCacheMaxAgeMs?: number;
};

export type HttpClientDependencies = {
  fetcher?: typeof fetch;
  now?: () => number;
  random?: () => number;
  sleep?: (delayMs: number, signal?: AbortSignal) => Promise<void>;
};
