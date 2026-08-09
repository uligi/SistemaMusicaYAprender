import { useEffect, useState, type MouseEvent as ReactMouseEvent, type ReactNode } from 'react';
import { Link } from '../../components/ui';

export type BrowserLocation = {
  pathname: string;
  search: string;
  hash: string;
};

function readLocation(): BrowserLocation {
  return {
    pathname: window.location.pathname,
    search: window.location.search,
    hash: window.location.hash,
  };
}

export function navigate(href: string, replace = false) {
  const target = new URL(href, window.location.href);

  if (target.origin !== window.location.origin) {
    window.location.assign(target.href);
    return;
  }

  if (replace) {
    window.history.replaceState(null, '', `${target.pathname}${target.search}${target.hash}`);
  } else {
    window.history.pushState(null, '', `${target.pathname}${target.search}${target.hash}`);
  }

  window.dispatchEvent(new PopStateEvent('popstate'));
}

export function useBrowserLocation() {
  const [location, setLocation] = useState<BrowserLocation>(() => readLocation());

  useEffect(() => {
    const handleLocationChange = () => setLocation(readLocation());
    window.addEventListener('popstate', handleLocationChange);

    return () => window.removeEventListener('popstate', handleLocationChange);
  }, []);

  return location;
}

export type AppLinkProps = {
  href: string;
  children: ReactNode;
  className?: string;
  current?: boolean;
};

export function AppLink({ children, className, current = false, href }: AppLinkProps) {
  const handleClick = (event: ReactMouseEvent<HTMLAnchorElement>) => {
    if (
      event.defaultPrevented ||
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    ) {
      return;
    }

    const target = new URL(href, window.location.href);

    if (target.origin !== window.location.origin) {
      return;
    }

    event.preventDefault();
    navigate(href);
  };

  return (
    <Link
      aria-current={current ? 'page' : undefined}
      className={className}
      href={href}
      onClick={handleClick}
    >
      {children}
    </Link>
  );
}
