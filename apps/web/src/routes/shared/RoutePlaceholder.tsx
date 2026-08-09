import { useEffect, useRef } from 'react';
import type { RouteMatch } from '../../app/router/match-route';

export type RoutePlaceholderProps = {
  match: RouteMatch;
  areaLabel: string;
  description: string;
  showJapaneseReference?: boolean;
};

export function RoutePlaceholder({
  areaLabel,
  description,
  match,
  showJapaneseReference = false,
}: RoutePlaceholderProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const canonicalPath = match.route.canonicalPath ?? match.route.path;

  useEffect(() => {
    headingRef.current?.focus();
  }, [match.route.id]);

  return (
    <article className="route-surface" data-route-id={match.route.id}>
      <p className="eyebrow">
        {match.route.id} · {areaLabel}
      </p>
      <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
        {match.route.title}
      </h1>
      <p>{description}</p>
      {showJapaneseReference ? (
        <p className="route-surface__japanese" lang="ja">
          音楽で日本語を学ぶ
        </p>
      ) : null}
      <ul aria-label="Contrato de esta ruta" className="route-surface__meta">
        <li>Ruta: {canonicalPath}</li>
        <li>Acceso visible: {match.route.accessLabel}</li>
        <li>Autoridad: servidor</li>
      </ul>
    </article>
  );
}
