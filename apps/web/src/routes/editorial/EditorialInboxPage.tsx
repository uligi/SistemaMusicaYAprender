import { useEffect, useMemo, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import './editorial-inbox.css';

const httpClient = createHttpClient();

type EditorialInboxAction = {
  code: string;
  label: string;
  href: string;
};

type EditorialInboxItem = {
  recordingId: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  artistName: string;
  stateCode: string;
  ownerLabel: string;
  lock: {
    active: boolean;
    operationCode: string | null;
    expiresAt: string | null;
  };
  provenanceLabel: string;
  providerCode: string | null;
  lastActivityAt: string | null;
  nextAction: string;
  actions: EditorialInboxAction[];
};

type EditorialInboxResponse = {
  items: EditorialInboxItem[];
  candidateCount: number;
  visibleCount: number;
};

type InboxState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: EditorialInboxResponse }
  | { phase: 'failed'; problem: ClientProblem };

function formatState(value: string) {
  const [, raw = value] = value.split(':', 2);
  return raw.replaceAll('_', ' ');
}

function formatDate(value: string | null) {
  if (!value) {
    return 'Sin actividad fechada';
  }

  return new Intl.DateTimeFormat('es-CR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

export function EditorialInboxPage() {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<InboxState>({ phase: 'loading' });
  const [filter, setFilter] = useState('');

  useEffect(() => {
    headingRef.current?.focus();

    const controller = new AbortController();

    const load = async () => {
      const result = await httpClient.get<EditorialInboxResponse>('/editorial/inbox', {
        cacheMode: 'no-store',
        retry: 'safe',
        signal: controller.signal,
      });

      if (result.kind === 'cancelled') {
        return;
      }

      if (result.ok) {
        setState({ phase: 'ready', data: result.data });
      } else {
        setState({ phase: 'failed', problem: result.problem });
      }
    };

    void load();
    return () => controller.abort();
  }, []);

  const visibleItems = useMemo(() => {
    if (state.phase !== 'ready') {
      return [];
    }

    const term = filter.trim().toLocaleLowerCase('es');

    if (!term) {
      return state.data.items;
    }

    return state.data.items.filter((item) =>
      [item.canonicalTitle, item.recordingTitle ?? '', item.artistName, item.stateCode]
        .join(' ')
        .toLocaleLowerCase('es')
        .includes(term),
    );
  }, [filter, state]);

  return (
    <article className="route-surface editorial-inbox" data-route-id="UI-MVP-017">
      <header className="editorial-inbox__intro">
        <p className="eyebrow">BL-MVP-044 · UI-MVP-017</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Bandeja editorial
        </h1>
        <p>
          Reúne únicamente los objetos que tu sesión puede trabajar. El servidor vuelve a comprobar
          capacidad y alcance por grabación antes de devolver cada fila y cada acción.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          description="Resolviendo objetos, permisos, bloqueo y siguiente acción."
          state="UI-EST-01"
          title="Cargando bandeja"
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
          description="No hay objetos editoriales dentro de tus capacidades y alcance vigentes."
          state="UI-EST-02"
          title="Bandeja vacía"
        />
      ) : null}

      {state.phase === 'ready' && state.data.items.length > 0 ? (
        <>
          <div className="editorial-inbox__toolbar">
            <label htmlFor="editorial-inbox-filter">Filtrar objetos visibles</label>
            <input
              id="editorial-inbox-filter"
              onChange={(event) => setFilter(event.target.value)}
              placeholder="Título, artista o estado"
              type="search"
              value={filter}
            />
            <p>
              {visibleItems.length} de {state.data.visibleCount} objetos permitidos.
            </p>
          </div>

          {visibleItems.length === 0 ? (
            <StateMessage
              description="Cambia el texto del filtro; los permisos no se amplían por buscar."
              state="UI-EST-02"
              title="Sin coincidencias visibles"
            />
          ) : (
            <ul className="editorial-inbox__list">
              {visibleItems.map((item) => (
                <li key={item.recordingId}>
                  <article className="editorial-inbox__card">
                    <header>
                      <p className="editorial-inbox__artist">{item.artistName}</p>
                      <h2 lang="ja">{item.canonicalTitle}</h2>
                      {item.recordingTitle ? (
                        <p className="editorial-inbox__recording">{item.recordingTitle}</p>
                      ) : null}
                    </header>

                    <dl className="editorial-inbox__facts">
                      <div>
                        <dt>Estado</dt>
                        <dd>{formatState(item.stateCode)}</dd>
                      </div>
                      <div>
                        <dt>Propietario</dt>
                        <dd>{item.ownerLabel}</dd>
                      </div>
                      <div>
                        <dt>Bloqueo</dt>
                        <dd>
                          {item.lock.active
                            ? `${item.lock.operationCode ?? 'Operación editorial'} · hasta ${formatDate(
                                item.lock.expiresAt,
                              )}`
                            : 'Sin bloqueo activo'}
                        </dd>
                      </div>
                      <div>
                        <dt>Procedencia</dt>
                        <dd>{item.provenanceLabel}</dd>
                      </div>
                      <div>
                        <dt>Fuente</dt>
                        <dd>{item.providerCode ?? 'Sin fuente seleccionada'}</dd>
                      </div>
                      <div>
                        <dt>Última actividad</dt>
                        <dd>{formatDate(item.lastActivityAt)}</dd>
                      </div>
                    </dl>

                    <section
                      aria-labelledby={`next-${item.recordingId}`}
                      className="editorial-inbox__next"
                    >
                      <h3 id={`next-${item.recordingId}`}>Siguiente acción</h3>
                      <p>{item.nextAction}</p>
                    </section>

                    {item.actions.length > 0 ? (
                      <nav aria-label={`Acciones permitidas para ${item.canonicalTitle}`}>
                        <ul className="editorial-inbox__actions">
                          {item.actions.map((action) => (
                            <li key={action.code}>
                              <a className="ma-button ma-button--secondary" href={action.href}>
                                {action.label}
                              </a>
                            </li>
                          ))}
                        </ul>
                      </nav>
                    ) : (
                      <p className="editorial-inbox__no-action">
                        No hay una acción navegable disponible para tu capacidad actual.
                      </p>
                    )}
                  </article>
                </li>
              ))}
            </ul>
          )}
        </>
      ) : null}
    </article>
  );
}
