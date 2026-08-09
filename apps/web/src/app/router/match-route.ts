import type { AppRoute } from './route-manifest';
import { routeManifest } from './route-manifest';

export type RouteMatch = {
  route: AppRoute;
  params: Readonly<Record<string, string>>;
};

function normalizePath(pathname: string) {
  if (!pathname || pathname === '/') {
    return '/';
  }

  const trimmed = pathname.replace(/\/+$/, '');
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
}

function decodeSegment(value: string) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function matchPath(pattern: string, pathname: string): Readonly<Record<string, string>> | null {
  const normalizedPattern = normalizePath(pattern);
  const normalizedPathname = normalizePath(pathname);

  if (normalizedPattern === '/' || normalizedPathname === '/') {
    return normalizedPattern === normalizedPathname ? {} : null;
  }

  const patternSegments = normalizedPattern.slice(1).split('/');
  const pathnameSegments = normalizedPathname.slice(1).split('/');

  if (patternSegments.length !== pathnameSegments.length) {
    return null;
  }

  const params: Record<string, string> = {};

  for (let index = 0; index < patternSegments.length; index += 1) {
    const expected = patternSegments[index];
    const actual = pathnameSegments[index];

    if (expected === undefined || actual === undefined) {
      return null;
    }

    if (expected.startsWith('{') && expected.endsWith('}')) {
      const parameterName = expected.slice(1, -1);

      if (!actual) {
        return null;
      }

      params[parameterName] = decodeSegment(actual);
      continue;
    }

    if (expected !== actual) {
      return null;
    }
  }

  return params;
}

export function matchRoute(pathname: string, search: string): RouteMatch | null {
  const searchParams = new URLSearchParams(search);

  for (const route of routeManifest) {
    if (route.queryKey && !searchParams.has(route.queryKey)) {
      continue;
    }

    const params = matchPath(route.path, pathname);

    if (params) {
      return { route, params };
    }
  }

  return null;
}
