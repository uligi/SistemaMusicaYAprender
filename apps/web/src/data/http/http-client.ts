import { MemoryReadCache } from './read-cache.js';
import {
  abortableDelay,
  canRetrySafely,
  isTransientHttpStatus,
  MAX_HTTP_ATTEMPTS,
  retryDelayMs,
} from './retry-policy.js';
import {
  createNetworkProblem,
  createUnexpectedProblem,
  parseProblemDetails,
} from './problem-details.js';
import { mutationStateFromResult, savingMutationState } from './request-state.js';
import type {
  ApiResult,
  HttpClientConfiguration,
  HttpClientDependencies,
  HttpMethod,
  HttpRequestOptions,
  MutationRequestOptions,
} from './types.js';

const DEFAULT_BASE_URL = '/api/v1';
const DEFAULT_LOCALE = 'es-CR';
const DEFAULT_READ_CACHE_MAX_AGE_MS = 5_000;

function normalizeBaseUrl(baseUrl: string): string {
  const normalized = baseUrl.trim().replace(/\/+$/, '');
  if (
    !normalized.startsWith('/') ||
    normalized.startsWith('//') ||
    normalized.includes('://') ||
    normalized.includes('?') ||
    normalized.includes('#')
  ) {
    throw new Error(
      'El cliente HTTP solo admite una base same-origin relativa sin query ni fragmento.',
    );
  }

  return normalized;
}

function normalizePath(path: string): string {
  const normalized = path.trim();
  const pathOnly = normalized.split(/[?#]/, 1)[0] ?? '';

  if (
    !pathOnly.startsWith('/') ||
    pathOnly.startsWith('//') ||
    pathOnly.includes('://') ||
    normalized.includes('#')
  ) {
    throw new Error(
      'La ruta HTTP debe ser relativa al mismo origen, comenzar con / y no usar fragmentos.',
    );
  }

  return normalized;
}

function resolveApiUrl(baseUrl: string, path: string): string {
  const normalizedPath = normalizePath(path);
  const placeholderOrigin = 'http://musica-aprender.invalid';
  const resolved = new URL(`${baseUrl}${normalizedPath}`, placeholderOrigin);
  const basePathPrefix = `${baseUrl}/`;

  if (!resolved.pathname.startsWith(basePathPrefix)) {
    throw new Error('La ruta HTTP debe permanecer dentro de la base API configurada.');
  }

  return `${resolved.pathname}${resolved.search}`;
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError';
}

function isNetworkError(error: unknown): boolean {
  return error instanceof TypeError;
}

function correlationIdFrom(response: Response): string | undefined {
  return response.headers.get('x-correlation-id') ?? undefined;
}

async function parseSuccessBody<T>(response: Response): Promise<T> {
  if (response.status === 204 || response.status === 205) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export class TypedHttpClient {
  readonly #baseUrl: string;
  readonly #locale: string;
  readonly #readCacheMaxAgeMs: number;
  readonly #fetcher: typeof fetch;
  readonly #now: () => number;
  readonly #random: () => number;
  readonly #sleep: (delayMs: number, signal?: AbortSignal) => Promise<void>;
  readonly #cache = new MemoryReadCache();

  constructor(
    configuration: HttpClientConfiguration = {},
    dependencies: HttpClientDependencies = {},
  ) {
    this.#baseUrl = normalizeBaseUrl(configuration.baseUrl ?? DEFAULT_BASE_URL);
    this.#locale = configuration.locale ?? DEFAULT_LOCALE;
    this.#readCacheMaxAgeMs = configuration.readCacheMaxAgeMs ?? DEFAULT_READ_CACHE_MAX_AGE_MS;
    this.#fetcher = dependencies.fetcher ?? globalThis.fetch.bind(globalThis);
    this.#now = dependencies.now ?? Date.now;
    this.#random = dependencies.random ?? Math.random;
    this.#sleep = dependencies.sleep ?? abortableDelay;
  }

  get<T>(path: string, options: HttpRequestOptions = {}): Promise<ApiResult<T>> {
    return this.#request<T>('GET', path, undefined, options);
  }

  post<TRequest, TResponse>(
    path: string,
    body: TRequest,
    options: MutationRequestOptions = {},
  ): Promise<ApiResult<TResponse>> {
    return this.#mutation<TResponse>('POST', path, body, options);
  }

  put<TRequest, TResponse>(
    path: string,
    body: TRequest,
    options: MutationRequestOptions = {},
  ): Promise<ApiResult<TResponse>> {
    return this.#mutation<TResponse>('PUT', path, body, options);
  }

  patch<TRequest, TResponse>(
    path: string,
    body: TRequest,
    options: MutationRequestOptions = {},
  ): Promise<ApiResult<TResponse>> {
    return this.#mutation<TResponse>('PATCH', path, body, options);
  }

  delete<TResponse>(
    path: string,
    options: MutationRequestOptions = {},
  ): Promise<ApiResult<TResponse>> {
    return this.#mutation<TResponse>('DELETE', path, undefined, options);
  }

  invalidate(pathPrefix = '/'): void {
    this.#cache.invalidate(resolveApiUrl(this.#baseUrl, pathPrefix));
  }

  clearReadCache(): void {
    this.#cache.clear();
  }

  async #mutation<TResponse>(
    method: Exclude<HttpMethod, 'GET' | 'HEAD'>,
    path: string,
    body: unknown,
    options: MutationRequestOptions,
  ): Promise<ApiResult<TResponse>> {
    options.onStateChange?.(savingMutationState);
    const result = await this.#request<TResponse>(method, path, body, options);

    if (result.ok) {
      for (const prefix of options.invalidate ?? [path]) {
        this.invalidate(prefix);
      }
    }

    options.onStateChange?.(mutationStateFromResult(result));
    return result;
  }

  async #request<T>(
    method: HttpMethod,
    path: string,
    body: unknown,
    options: HttpRequestOptions,
  ): Promise<ApiResult<T>> {
    const url = resolveApiUrl(this.#baseUrl, path);
    const locale = options.locale ?? this.#locale;
    const cacheKey = this.#cacheKey(url, locale);
    const cacheMode = options.cacheMode ?? 'default';
    const cacheMaxAgeMs = options.cacheMaxAgeMs ?? this.#readCacheMaxAgeMs;
    const existingCache = method === 'GET' ? this.#cache.readAny<T>(cacheKey) : null;

    if (method === 'GET' && cacheMode === 'default') {
      const fresh = this.#cache.readFresh<T>(cacheKey, cacheMaxAgeMs, this.#now());
      if (fresh) {
        return {
          ok: true,
          kind: 'success',
          status: 200,
          data: fresh.data,
          fromCache: true,
          etag: fresh.etag,
        };
      }
    }

    const retryAllowed =
      options.retry !== 'never' && canRetrySafely(method, options.idempotencyKey);
    const maxAttempts = retryAllowed ? MAX_HTTP_ATTEMPTS : 1;
    const serializedBody = body === undefined ? undefined : JSON.stringify(body);

    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      if (options.signal?.aborted) {
        return { ok: false, kind: 'cancelled' };
      }

      const headers = new Headers(options.headers);
      headers.set('Accept', 'application/json, application/problem+json');
      headers.set('Accept-Language', locale);

      if (serializedBody !== undefined) {
        headers.set('Content-Type', 'application/json; charset=utf-8');
      }

      if (options.ifMatch) {
        headers.set('If-Match', options.ifMatch);
      }

      if (options.idempotencyKey) {
        headers.set('Idempotency-Key', options.idempotencyKey);
      }

      if (method === 'GET' && cacheMode !== 'no-store' && existingCache?.etag) {
        headers.set('If-None-Match', existingCache.etag);
      }

      let response: Response;
      try {
        response = await this.#fetcher(url, {
          method,
          headers,
          credentials: 'same-origin',
          ...(serializedBody !== undefined ? { body: serializedBody } : {}),
          ...(options.signal ? { signal: options.signal } : {}),
        });
      } catch (error) {
        if (isAbortError(error) || options.signal?.aborted) {
          return { ok: false, kind: 'cancelled' };
        }

        if (isNetworkError(error) && attempt < maxAttempts) {
          const delayMs = retryDelayMs(attempt, this.#random);
          try {
            await this.#sleep(delayMs, options.signal);
          } catch (delayError) {
            if (isAbortError(delayError) || options.signal?.aborted) {
              return { ok: false, kind: 'cancelled' };
            }
            throw delayError;
          }
          continue;
        }

        return { ok: false, kind: 'problem', problem: createNetworkProblem() };
      }

      if (isTransientHttpStatus(response.status) && attempt < maxAttempts) {
        const delayMs = retryDelayMs(attempt, this.#random);
        try {
          await this.#sleep(delayMs, options.signal);
        } catch (delayError) {
          if (isAbortError(delayError) || options.signal?.aborted) {
            return { ok: false, kind: 'cancelled' };
          }
          throw delayError;
        }
        continue;
      }

      if (response.status === 304 && method === 'GET' && existingCache) {
        return {
          ok: true,
          kind: 'success',
          status: 304,
          data: existingCache.data,
          fromCache: true,
          etag: existingCache.etag,
          ...(correlationIdFrom(response)
            ? { correlationId: correlationIdFrom(response) as string }
            : {}),
        };
      }

      if (!response.ok) {
        const problem = await parseProblemDetails(response);
        if (options.signal?.aborted) {
          return { ok: false, kind: 'cancelled' };
        }
        return { ok: false, kind: 'problem', problem };
      }

      let data: T;
      try {
        data = await parseSuccessBody<T>(response);
      } catch (error) {
        if (isAbortError(error) || options.signal?.aborted) {
          return { ok: false, kind: 'cancelled' };
        }

        const correlationId = correlationIdFrom(response);
        return {
          ok: false,
          kind: 'problem',
          problem: createUnexpectedProblem(response.status, correlationId),
        };
      }

      const etag = response.headers.get('etag') ?? undefined;
      const correlationId = correlationIdFrom(response);

      if (method === 'GET' && cacheMode !== 'no-store' && etag) {
        this.#cache.write(cacheKey, data, etag, this.#now());
      }

      return {
        ok: true,
        kind: 'success',
        status: response.status,
        data,
        fromCache: false,
        ...(etag ? { etag } : {}),
        ...(correlationId ? { correlationId } : {}),
      };
    }

    return { ok: false, kind: 'problem', problem: createNetworkProblem() };
  }

  #cacheKey(url: string, locale: string): string {
    return `${url}::${locale}`;
  }
}

export function createHttpClient(
  configuration: HttpClientConfiguration = {},
  dependencies: HttpClientDependencies = {},
): TypedHttpClient {
  return new TypedHttpClient(configuration, dependencies);
}
