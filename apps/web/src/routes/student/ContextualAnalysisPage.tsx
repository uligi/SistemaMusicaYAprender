import { useEffect, useRef } from 'react';
import { AppLink } from '../../app/router/navigation';
import { ContextualAnalysisPanel } from './ContextualAnalysisPanel';

export type ContextualAnalysisPageProps = {
  slug: string;
  token: string;
};

export function ContextualAnalysisPage({ slug, token }: ContextualAnalysisPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    headingRef.current?.focus();
  }, [slug, token]);

  return (
    <article className="route-surface" data-route-id="UI-MVP-010">
      <header>
        <p className="eyebrow">COMPRENDER LA CANCIÓN</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Análisis contextual
        </h1>
        <p>
          Consulta el análisis publicado del token sin sustituir referencias rotas ni usar servicios
          lingüísticos externos.
        </p>
      </header>

      <AppLink href={`/aprender/${encodeURIComponent(slug)}`}>
        Volver al reproductor educativo
      </AppLink>

      <ContextualAnalysisPanel slug={slug} tokenKey={token} showStandaloneLink={false} />
    </article>
  );
}
