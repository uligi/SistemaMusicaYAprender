type CacheEntry = {
  data: unknown;
  etag: string;
  storedAt: number;
};

export class MemoryReadCache {
  readonly #entries = new Map<string, CacheEntry>();

  readFresh<T>(key: string, maxAgeMs: number, now: number): { data: T; etag: string } | null {
    const entry = this.#entries.get(key);
    if (!entry || now - entry.storedAt > maxAgeMs) {
      return null;
    }

    return { data: entry.data as T, etag: entry.etag };
  }

  readAny<T>(key: string): { data: T; etag: string } | null {
    const entry = this.#entries.get(key);
    return entry ? { data: entry.data as T, etag: entry.etag } : null;
  }

  write<T>(key: string, data: T, etag: string, now: number): void {
    this.#entries.set(key, { data, etag, storedAt: now });
  }

  invalidate(prefix: string): void {
    const nestedPrefix = prefix.endsWith('/') ? prefix : `${prefix}/`;

    for (const key of this.#entries.keys()) {
      const isExactResource = key.startsWith(`${prefix}::`) || key.startsWith(`${prefix}?`);
      const isNestedResource = key.startsWith(nestedPrefix);

      if (isExactResource || isNestedResource) {
        this.#entries.delete(key);
      }
    }
  }

  clear(): void {
    this.#entries.clear();
  }
}
