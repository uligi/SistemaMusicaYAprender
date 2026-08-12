import { useEffect, useRef, useState } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import './public-song-catalog.css';

const httpClient = createHttpClient();
const publicTerritory = 'CR';
const publicLanguage = 'es';
const pageSize = 12;

type PublicCatalogSearchItem = {
  publicationId: string;
  recordingId: string;
  workId: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  artistId: string;
  artistName: string;
  providerCode: string;
  externalRef: string;
  territoryCode: string;
  languageTag: string | null;
  indexedAt: string;
};

type PublicCatalogSearchPage = {
  items: PublicCatalogSearchItem[];
  nextCursor: string | null;
  pageSize: number;
  hasMore: boolean;
};

type CatalogState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicCatalogSearchPage }
  | { phase: 'failed'; problem: ClientProblem };

export type PublicSongCatalogPageProps = {
  routeId: 'UI-MVP-002' | 'UI-MVP-003';
};

function readQuery(routeId: PublicSongCatalogPageProps['routeId']) {
  if (routeId !== 'UI-MVP-003') {
    return '';
  }

  return new URLSearchParams(window.location.search).get('consulta')?.trim() ?? '';
}

export function PublicSongCatalogPage({ routeId }: PublicSongCatalogPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const activeRequestRef = useRef<AbortController | null>(null);
  const query = readQuery(routeId);
  const [state, setState] = useState<CatalogState>({ phase: 'loading' });
  const [loadingMore, setLoadingMore] = useState(false);

  useEffect(() => {
    headingRef.current?.focus();

    activeRequestRef.current?.abort();
    const controller = new AbortController();
    activeRequestRef.current = controller;

    const load = async () => {
      setState({ phase: 'loading' });
      const params = new URLSearchParams({
        query,
        territory: publicTerritory,
        language: publicLanguage,
        pageSize: String(pageSize),
      });

      const result = await httpClient.get<PublicCatalogSearchPage>(
        `/public/catalog/search?${params.toString()}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (activeRequestRef.current !== controller || result.kind === 'cancelled') {
        return;
      }

      activeRequestRef.current = null;
      if (result.ok) {
        setState({ phase: 'ready', data: result.data });
      } else {
        setState({ phase: 'failed', problem: result.problem });
      }
    };

    void load();

    return () => {
      controller.abort();
    };
  }, [query, routeId]);

  const loadMore = async () => {
    if (state.phase !== 'ready' || !state.data.nextCursor || loadingMore) {
      return;
    }

    const controller = new AbortController();
    activeRequestRef.current?.abort();
    activeRequestRef.current = controller;
    setLoadingMore(true);

    const params = new URLSearchParams({
      query,
      territory: publicTerritory,
      language: publicLanguage,
      pageSize: String(pageSize),
      cursor: state.data.nextCursor,
    });

    const result = await httpClient.get<PublicCatalogSearchPage>(
      `/public/catalog/search?${params.toString()}`,
      {
        cacheMode: 'no-store',
        retry: 'safe',
        signal: controller.signal,
      },
    );

    if (activeRequestRef.current !== controller || result.kind === 'cancelled') {
      setLoadingMore(false);
      return;
    }

    activeRequestRef.current = null;
    setLoadingMore(false);

    if (!result.ok) {
      setState({ phase: 'failed', problem: result.problem });
      return;
    }

    setState({
      phase: 'ready',
      data: {
        ...result.data,
        items: [...state.data.items, ...result.data.items],
      },
    });
  };

  const heading = routeId === 'UI-MVP-003' ? 'Resultados de búsqueda' : 'Catálogo de canciones';

  return (
    <article className="route-surface public-catalog" data-route-id={routeId}>
      <header className="public-catalog__intro">
        <p className="eyebrow">BL-MVP-042 · {routeId}</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          {heading}
        </h1>
        <p>
          Busca dentro del catálogo propio por título, artista, alias o lectura. Los resultados se
          vuelven a comprobar contra publicación, territorio y fuente canónica antes de mostrarse.
        </p>
      </header>

      <form action="/canciones" className="public-catalog__search" method="get" role="search">
        <Field
          defaultValue={query}
          helpText="Admite japonés, kana, romaji y nombres alternativos. La búsqueda no usa servicios externos."
          id="catalog-query"
          label="Buscar por título, artista, alias o lectura"
          maxLength={256}
          name="consulta"
          type="search"
        />
        <Button type="submit">Buscar canciones</Button>
      </form>

      <p className="public-catalog__context">
        Disponibilidad evaluada para <strong>CR</strong> · interfaz <strong>es</strong>.
      </p>

      {state.phase === 'loading' ? (
        <StateMessage
          description="Consultando el índice PostgreSQL y revalidando la disponibilidad pública."
          state="UI-EST-01"
          title="Buscando canciones"
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          description={state.problem.correction}
          state="UI-EST-06"
          title={state.problem.summary}
        />
      ) : null}

      {state.phase === 'ready' && state.data.items.length === 0 ? (
        <StateMessage
          description={
            query
              ? `No encontramos canciones publicadas disponibles para “${query}”.`
              : 'Todavía no hay canciones publicadas disponibles para este territorio.'
          }
          state="UI-EST-02"
          title={query ? 'Sin coincidencias' : 'Catálogo vacío'}
        />
      ) : null}

      {state.phase === 'ready' && state.data.items.length > 0 ? (
        <section aria-labelledby="catalog-results-title" className="public-catalog__results">
          <div className="public-catalog__results-heading">
            <h2 id="catalog-results-title">
              {query ? `Coincidencias para “${query}”` : 'Canciones disponibles'}
            </h2>
            <span aria-label={`${state.data.items.length} resultados cargados`}>
              {state.data.items.length} cargadas
            </span>
          </div>

          <ul className="public-catalog__list">
            {state.data.items.map((item) => (
              <li key={item.recordingId}>
                <article className="public-catalog__song">
                  <div>
                    <p className="public-catalog__artist">{item.artistName}</p>
                    <h3 lang="ja">{item.canonicalTitle}</h3>
                  </div>
                  <dl>
                    <div>
                      <dt>Grabación</dt>
                      <dd>{item.recordingTitle ?? 'Grabación principal'}</dd>
                    </div>
                    <div>
                      <dt>Fuente</dt>
                      <dd>{item.providerCode === 'YOUTUBE' ? 'YouTube' : item.providerCode}</dd>
                    </div>
                  </dl>
                  <p className="public-catalog__availability">
                    Disponible · {item.territoryCode}
                    {item.languageTag ? ` · ${item.languageTag}` : ''}
                  </p>
                </article>
              </li>
            ))}
          </ul>

          {state.data.hasMore && state.data.nextCursor ? (
            <Button disabled={loadingMore} onClick={() => void loadMore()} type="button">
              {loadingMore ? 'Cargando más…' : 'Cargar más canciones'}
            </Button>
          ) : null}

          <p className="public-catalog__handoff">
            La apertura de la ficha pública UI-MVP-004 se completa en BL-MVP-043; esta pantalla no
            inventa un slug ni expone identificadores internos.
          </p>
        </section>
      ) : null}
    </article>
  );
}
