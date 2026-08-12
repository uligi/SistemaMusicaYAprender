import { useEffect, useRef, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import './public-song-detail.css';

const httpClient = createHttpClient();
const publicTerritory = 'CR';
const publicLanguage = 'es';

type PublicSongDetail = {
  slug: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  recordingDurationMs: number | null;
  artistName: string;
  providerCode: string;
  territoryCode: string;
  languageTag: string | null;
  availabilityValidFrom: string;
  availabilityValidTo: string | null;
  availableComponents: string[];
};

type DetailState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicSongDetail }
  | { phase: 'unavailable' }
  | { phase: 'failed'; problem: ClientProblem };

const componentLabels: Readonly<Record<string, string>> = {
  CATALOG: 'Ficha y metadatos editoriales',
  LYRICS: 'Letra japonesa',
  TIMING: 'Sincronización',
  TRANSLATION: 'Traducción',
  ANALYSIS: 'Análisis contextual',
  EXERCISE: 'Ejercicios',
};

export type PublicSongDetailPageProps = {
  slug: string;
};

function formatDuration(durationMs: number | null) {
  if (durationMs === null || durationMs < 0) {
    return 'No informada';
  }

  const seconds = Math.round(durationMs / 1000);
  const minutes = Math.floor(seconds / 60);
  const remainder = String(seconds % 60).padStart(2, '0');
  return `${minutes}:${remainder}`;
}

function formatProvider(providerCode: string) {
  return providerCode === 'YOUTUBE' ? 'YouTube' : providerCode;
}

function componentLabel(component: string) {
  return componentLabels[component] ?? component;
}

export function PublicSongDetailPage({ slug }: PublicSongDetailPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<DetailState>({ phase: 'loading' });

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      setState({ phase: 'loading' });
      const params = new URLSearchParams({
        territory: publicTerritory,
        language: publicLanguage,
      });
      const result = await httpClient.get<PublicSongDetail>(
        `/public/catalog/songs/${encodeURIComponent(slug)}?${params.toString()}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') {
        return;
      }

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

  const title = state.phase === 'ready' ? state.data.canonicalTitle : 'Ficha pública de canción';

  return (
    <article className="route-surface public-song-detail" data-route-id="UI-MVP-004">
      <header className="public-song-detail__intro">
        <p className="eyebrow">BL-MVP-043 · UI-MVP-004</p>
        <h1
          className="route-title"
          id="route-title"
          lang={state.phase === 'ready' ? 'ja' : undefined}
          ref={headingRef}
          tabIndex={-1}
        >
          {title}
        </h1>
        <p>
          Esta ficha se vuelve a comprobar contra la publicación, el territorio y la fuente canónica
          antes de mostrar datos públicos.
        </p>
      </header>

      <AppLink href="/canciones">Volver al catálogo</AppLink>

      {state.phase === 'loading' ? (
        <StateMessage
          description="Comprobando que la publicación y su disponibilidad siguen vigentes."
          state="UI-EST-01"
          title="Cargando ficha pública"
        />
      ) : null}

      {state.phase === 'unavailable' ? (
        <StateMessage
          description="La publicación fue retirada, cambió de disponibilidad o el enlace ya no corresponde a una ficha pública vigente."
          state="UI-EST-06"
          title="Canción no disponible"
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          description={state.problem.correction}
          state="UI-EST-06"
          title={state.problem.summary}
        />
      ) : null}

      {state.phase === 'ready' ? (
        <>
          <section aria-labelledby="public-song-identity" className="public-song-detail__panel">
            <h2 id="public-song-identity">Grabación publicada</h2>
            <dl className="public-song-detail__facts">
              <div>
                <dt>Artista</dt>
                <dd>{state.data.artistName}</dd>
              </div>
              <div>
                <dt>Grabación</dt>
                <dd>{state.data.recordingTitle ?? 'Grabación principal'}</dd>
              </div>
              <div>
                <dt>Duración de referencia</dt>
                <dd>{formatDuration(state.data.recordingDurationMs)}</dd>
              </div>
              <div>
                <dt>Fuente audiovisual</dt>
                <dd>{formatProvider(state.data.providerCode)}</dd>
              </div>
            </dl>
          </section>

          <section aria-labelledby="public-song-availability" className="public-song-detail__panel">
            <h2 id="public-song-availability">Disponibilidad</h2>
            <p className="public-song-detail__availability">
              Disponible · {state.data.territoryCode}
              {state.data.languageTag ? ` · ${state.data.languageTag}` : ''}
            </p>
            <p>
              La disponibilidad se evalúa al abrir la ficha; un resultado antiguo no concede acceso
              a una publicación retirada o fuera de territorio.
            </p>
          </section>

          <section aria-labelledby="public-song-sample" className="public-song-detail__panel">
            <h2 id="public-song-sample">Muestra educativa propia</h2>
            {state.data.availableComponents.length > 0 ? (
              <ul className="public-song-detail__components">
                {state.data.availableComponents.map((component) => (
                  <li key={component}>{componentLabel(component)}</li>
                ))}
              </ul>
            ) : (
              <StateMessage
                description="La ficha pública está disponible, pero esta publicación todavía no declara componentes educativos propios en su paquete."
                state="UI-EST-02"
                title="Sin componentes educativos declarados"
              />
            )}
          </section>

          <aside
            className="public-song-detail__youtube-note"
            aria-label="Estado de la fuente YouTube"
          >
            <strong>YouTube es una fuente externa.</strong>
            <span>
              Esta ficha y su información propia permanecen utilizables sin cargar el reproductor.
              La reproducción incrustada se integra en la fase de contenido educativo.
            </span>
          </aside>
        </>
      ) : null}
    </article>
  );
}
