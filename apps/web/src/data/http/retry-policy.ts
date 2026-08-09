import type { HttpMethod } from './types.js';

export const MAX_HTTP_ATTEMPTS = 3;

const transientStatuses = new Set([408, 425, 429, 502, 503, 504]);

export function isTransientHttpStatus(status: number): boolean {
  return transientStatuses.has(status);
}

export function canRetrySafely(method: HttpMethod, idempotencyKey?: string): boolean {
  if (method === 'GET' || method === 'HEAD') {
    return true;
  }

  return Boolean(idempotencyKey && idempotencyKey.trim().length > 0);
}

export function retryDelayMs(failedAttempt: number, random: () => number): number {
  const boundedAttempt = Math.max(1, Math.min(failedAttempt, MAX_HTTP_ATTEMPTS - 1));
  const exponential = 150 * 2 ** (boundedAttempt - 1);
  const jitter = Math.floor(Math.max(0, Math.min(0.999_999, random())) * 100);
  return exponential + jitter;
}

export async function abortableDelay(delayMs: number, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) {
    throw new DOMException('Request cancelled.', 'AbortError');
  }

  await new Promise<void>((resolve, reject) => {
    const onComplete = () => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    };

    const timeout = globalThis.setTimeout(onComplete, delayMs);

    const onAbort = () => {
      globalThis.clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
      reject(new DOMException('Request cancelled.', 'AbortError'));
    };

    signal?.addEventListener('abort', onAbort, { once: true });
  });
}
