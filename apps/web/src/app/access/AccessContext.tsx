import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { createHttpClient } from '../../data/http';

export type VisibleAccessSnapshot = {
  isAuthenticated: boolean;
  capabilities: readonly string[];
  source: 'anonymous-bootstrap' | 'server-session';
};

const anonymousAccess: VisibleAccessSnapshot = Object.freeze({
  isAuthenticated: false,
  capabilities: Object.freeze([]),
  source: 'anonymous-bootstrap',
});

const AccessContext = createContext<VisibleAccessSnapshot>(anonymousAccess);

const httpClient = createHttpClient();

type SessionResponse = {
  status: 'AUTHENTICATED';
  role: string;
};

export type AccessProviderProps = {
  children: ReactNode;
  value?: VisibleAccessSnapshot;
};

export function AccessProvider({ children, value = anonymousAccess }: AccessProviderProps) {
  const [sessionAccess, setSessionAccess] = useState<VisibleAccessSnapshot>(value);

  useEffect(() => {
    if (value !== anonymousAccess) return;

    const controller = new AbortController();

    const loadSession = async () => {
      const result = await httpClient.get<SessionResponse>('/auth/session', {
        cacheMode: 'no-store',
        retry: 'never',
        signal: controller.signal,
      });

      if (result.kind === 'cancelled') return;

      setSessionAccess({
        isAuthenticated: result.ok && result.data.status === 'AUTHENTICATED',
        capabilities: [],
        source: 'server-session',
      });
    };

    void loadSession();
    return () => controller.abort();
  }, [value]);

  return <AccessContext.Provider value={sessionAccess}>{children}</AccessContext.Provider>;
}

export function useVisibleAccess() {
  return useContext(AccessContext);
}
