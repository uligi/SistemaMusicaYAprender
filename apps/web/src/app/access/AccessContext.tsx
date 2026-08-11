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
  roles: readonly string[];
  capabilities: readonly string[];
};

export type AccessProviderProps = {
  children: ReactNode;
  value?: VisibleAccessSnapshot;
};

function snapshotFromSession(
  result: Awaited<ReturnType<typeof httpClient.get<SessionResponse>>>,
): VisibleAccessSnapshot {
  if (!result.ok || result.data.status !== 'AUTHENTICATED') {
    return signedOutAccess;
  }

  return {
    isAuthenticated: true,
    capabilities: [...result.data.capabilities],
    source: 'server-session',
  };
}

export function AccessProvider({ children, value = anonymousAccess }: AccessProviderProps) {
  const [sessionAccess, setSessionAccess] = useState<VisibleAccessSnapshot>(value);

  const refreshSession = useCallback(async () => {
    const result = await httpClient.get<SessionResponse>('/auth/session', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    const snapshot = snapshotFromSession(result);
    setSessionAccess(snapshot);

    return snapshot.isAuthenticated;
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

      setSessionAccess(snapshotFromSession(result));
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
