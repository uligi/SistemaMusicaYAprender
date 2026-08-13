import { useEffect, useRef, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import { YouTubeIframeAdapter } from '../../integrations/youtube/YouTubeIframeAdapter';
import './educational-player.css';

const httpClient = createHttpClient();
const territory = 'CR';
const language = 'es';

type PublicEducationalSource = {
  slug: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  recordingDurationMs: number | null;
  artistName: string;
  providerCode: string;
  territoryCode: string;
  languageTag: string | null;
  availableComponents: string[];
  sourceExternalRef: string;
};

type PlayerState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicEducationalSource }
  | { phase: 'unavailable' }
  | { phase: 'failed'; problem: ClientProblem };

export type EducationalPlayerPageProps = {
  slug: string;
};

export function EducationalPlayerPage({ slug }: EducationalPlayerPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PlayerState>({ phase: 'loading' });

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      const params = new URLSearchParams({ territory, language });
      const result = await httpClient.get<PublicEducationalSource>(
        `/public/catalog/songs/${encodeURIComponent(slug)}?${params.toString()}`,
        { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
      );

      if (result.kind === 'cancelled') return;

      if (result.ok) {
        setState({ phase: 'ready', data: result.data });
      } else if (result.problem.status === 404) {
        setState({ phase: 'unavailable' });
      } else {
        setState({ phase: 'failed', problem: result.problem });
      }
    };

    void load();
    return () => controller.abort();
  }, [slug]);

  useEffect(() => {
    headingRef.current?.focus();
  }, [state.phase]);

  return (
    <article className="route-surface educational-player" data-route-id="UI-MVP-009">
      <header className="educational-player__header">
        <p className="eyebrow">BL-MVP-058 · UI-MVP-009</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Reproductor educativo
        </h1>
        <p>
          El contenido propio se presenta antes de cualquier dependencia externa. Este incremento
          aísla YouTube; la sincronización automática de línea llega en BL-MVP-059.
        </p>
      </header>

      <AppLink href={`/canciones/${encodeURIComponent(slug)}`}>Volver a la ficha pública</AppLink>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando contenido propio"
          description="Validando la publicación y la referencia exacta de la fuente sin cargar YouTube."
        />
      ) : null}

      {state.phase === 'unavailable' ? (
        <StateMessage
          state="UI-EST-06"
          title="Canción no disponible"
          description="La publicación no está vigente para esta ruta o territorio."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-06"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {state.phase === 'ready' ? (
        <>
          <section className="educational-player__owned" aria-labelledby="owned-content">
            <p className="eyebrow">CONTENIDO PROPIO</p>
            <h2 id="owned-content" lang="ja">
              {state.data.canonicalTitle}
            </h2>
            <p>
              {state.data.artistName} · {state.data.recordingTitle ?? 'Grabación principal'}
            </p>
            <p>
              Esta información, la letra y las demás capas educativas no dependen del estado del
              reproductor externo.
            </p>
          </section>

          {state.data.providerCode === 'YOUTUBE' ? (
            <YouTubeIframeAdapter
              externalRef={state.data.sourceExternalRef}
              title={state.data.canonicalTitle}
            />
          ) : (
            <StateMessage
              state="UI-EST-06"
              title="Fuente no compatible en este incremento"
              description="BL-MVP-058 encapsula únicamente el reproductor incrustado de YouTube."
            />
          )}

          <StateMessage
            state="UI-EST-11"
            title="Adaptador listo para sincronización local"
            description="BL-MVP-059 consumirá tiempo y eventos del adaptador sin exponer detalles de YouTube al contenido educativo."
          />
        </>
      ) : null}
    </article>
  );
}
