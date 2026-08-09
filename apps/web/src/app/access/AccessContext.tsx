import { createContext, useContext, type ReactNode } from 'react';

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

export type AccessProviderProps = {
  children: ReactNode;
  value?: VisibleAccessSnapshot;
};

export function AccessProvider({ children, value = anonymousAccess }: AccessProviderProps) {
  return <AccessContext.Provider value={value}>{children}</AccessContext.Provider>;
}

export function useVisibleAccess() {
  return useContext(AccessContext);
}
