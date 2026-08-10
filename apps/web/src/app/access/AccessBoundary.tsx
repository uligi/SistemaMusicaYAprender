import type { ReactNode } from 'react';
import { Link, StateMessage } from '../../components/ui';
import type { AppRoute } from '../router/route-manifest';
import type { VisibleAccessSnapshot } from './AccessContext';

export type AccessDecision = {
  allowed: boolean;
  reason: 'public' | 'token-shell' | 'session-required' | 'capability-required' | 'granted';
};

export function evaluateVisibleAccess(
  route: AppRoute,
  access: VisibleAccessSnapshot,
): AccessDecision {
  if (route.access === 'public' || route.access === 'public-or-student') {
    return { allowed: true, reason: 'public' };
  }

  if (route.access === 'one-time-token') {
    return { allowed: true, reason: 'token-shell' };
  }

  if (!access.isAuthenticated) {
    return { allowed: false, reason: 'session-required' };
  }

  if (route.access === 'student') {
    return { allowed: true, reason: 'granted' };
  }

  const required = route.requiredCapabilities ?? [];
  const allowed =
    required.length > 0 &&
    (route.capabilityMode === 'all'
      ? required.every((capability) => access.capabilities.includes(capability))
      : required.some((capability) => access.capabilities.includes(capability)));

  return {
    allowed,
    reason: allowed ? 'granted' : 'capability-required',
  };
}

export type AccessBoundaryProps = {
  route: AppRoute;
  access: VisibleAccessSnapshot;
  children: ReactNode;
};

export function AccessBoundary({ access, children, route }: AccessBoundaryProps) {
  const decision = evaluateVisibleAccess(route, access);

  if (decision.allowed) {
    return children;
  }

  if (access.source === 'anonymous-bootstrap') {
    return (
      <StateMessage
        state="UI-EST-01"
        title="Comprobando sesión"
        description="Validamos la cookie con el servidor antes de mostrar una ruta protegida."
      />
    );
  }

  if (decision.reason === 'session-required') {
    return (
      <StateMessage
        state="UI-EST-07"
        title="Necesitas iniciar sesión"
        description="Esta ruta requiere una sesión confirmada. La interfaz no concede acceso por conocer la URL."
        action={<Link href="/acceso">Ir al acceso</Link>}
      />
    );
  }

  return (
    <StateMessage
      state="UI-EST-08"
      title="Acceso no concedido"
      description="Tu sesión visible no contiene la capacidad necesaria. El servidor vuelve a autorizar cada operación protegida."
      action={<Link href="/">Volver al inicio</Link>}
    />
  );
}
