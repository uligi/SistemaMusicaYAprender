import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { createHttpClient } from '../../data/http';

export type VisibleAccessSnapshot = {
  isAuthenticated: boolean;
  capabilities: readonly string[];
  source: 'anonymous-bootstrap' | 'server-session';
};

export type VisibleAccessActions = {
  refreshSession: () => Promise<boolean>;
  clearSession: () => void;
};

const anonymousAccess: VisibleAccessSnapshot = Object.freeze({
  isAuthenticated: false,
  capabilities: Object.freeze([]),
  source: 'anonymous-bootstrap',
});

const signedOutAccess: VisibleAccessSnapshot = Object.freeze({
  isAuthenticated: false,
  capabilities: Object.freeze([]),
  source: 'server-session',
});

const AccessContext = createContext<VisibleAccessSnapshot>(anonymousAccess);
const AccessActionsContext = createContext<VisibleAccessActions | null>(null);

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

  const refreshSession = useCallback(async () => {
    const result = await httpClient.get<SessionResponse>('/auth/session', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    const authenticated = result.ok && result.data.status === 'AUTHENTICATED';
    setSessionAccess({
      isAuthenticated: authenticated,
      capabilities: [],
      source: 'server-session',
    });

    return authenticated;
  }, []);

  const clearSession = useCallback(() => {
    httpClient.clearReadCache();
    setSessionAccess(signedOutAccess);
  }, []);

  const actions = useMemo<VisibleAccessActions>(
    () => ({ refreshSession, clearSession }),
    [clearSession, refreshSession],
  );

  useEffect(() => {
    if (value !== anonymousAccess) return;

    let active = true;

    const loadSession = async () => {
      const result = await httpClient.get<SessionResponse>('/auth/session', {
        cacheMode: 'no-store',
        retry: 'never',
      });

      if (!active || result.kind === 'cancelled') return;

      setSessionAccess({
        isAuthenticated: result.ok && result.data.status === 'AUTHENTICATED',
        capabilities: [],
        source: 'server-session',
      });
    };

    void loadSession();
    return () => {
      active = false;
    };
  }, [value]);

  return (
    <AccessActionsContext.Provider value={actions}>
      <AccessContext.Provider value={sessionAccess}>{children}</AccessContext.Provider>
    </AccessActionsContext.Provider>
  );
}

export function useVisibleAccess() {
  return useContext(AccessContext);
}

export function useVisibleAccessActions() {
  const actions = useContext(AccessActionsContext);
  if (!actions) {
    throw new Error('useVisibleAccessActions requiere AccessProvider.');
  }

  return actions;
}
