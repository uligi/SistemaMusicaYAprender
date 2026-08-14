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

type InboxView = 'ALL' | 'READY' | 'LOCKED';

function formatState(value: string) {
  const [, raw = value] = value.split(':', 2);
  const normalized = raw.replaceAll('_', ' ');
  const labels: Record<string, string> = {
    DRAFT: 'Borrador',
    IN_REVIEW: 'En revisión',
    REVIEW: 'En revisión',
    APPROVED: 'Aprobado',
    PUBLISHED: 'Publicado',
    ARCHIVED: 'Archivado',
    BLOCKED: 'Bloqueado',
  };
  return labels[raw] ?? normalized.charAt(0) + normalized.slice(1).toLocaleLowerCase('es');
}

function formatOperation(value: string | null) {
  if (!value) return 'Operación editorial';
  const labels: Record<string, string> = {
    EDIT_METADATA: 'Edición de metadatos',
    EDIT_LYRICS: 'Edición de letra',
    EDIT_TRANSLATION: 'Edición de traducción',
    EDIT_TIMING: 'Edición de sincronización',
    EDIT_ANALYSIS: 'Edición de análisis lingüístico',
    EDIT_RIGHTS: 'Edición de derechos',
  };
  return labels[value] ?? value.replaceAll('_', ' ').toLocaleLowerCase('es');
}

function formatProvider(value: string | null) {
  if (!value) return 'Sin fuente seleccionada';
  const labels: Record<string, string> = {
    YOUTUBE: 'YouTube',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

function formatDate(value: string | null) {
  if (!value) {
    return 'Sin actividad registrada';
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
  const [view, setView] = useState<InboxView>('ALL');

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

  const summary = useMemo(() => {
    if (state.phase !== 'ready') {
      return { ready: 0, locked: 0, total: 0 };
    }

    return {
      ready: state.data.items.filter((item) => !item.lock.active && item.actions.length > 0).length,
      locked: state.data.items.filter((item) => item.lock.active).length,
      total: state.data.visibleCount,
    };
  }, [state]);

  const visibleItems = useMemo(() => {
    if (state.phase !== 'ready') {
      return [];
    }

    const term = filter.trim().toLocaleLowerCase('es');

    return state.data.items.filter((item) => {
      if (view === 'READY' && (item.lock.active || item.actions.length === 0)) {
        return false;
      }

      if (view === 'LOCKED' && !item.lock.active) {
        return false;
      }

      if (!term) {
        return true;
      }

      return [
        item.canonicalTitle,
        item.recordingTitle ?? '',
        item.artistName,
        item.stateCode,
        item.ownerLabel,
        item.provenanceLabel,
        item.providerCode ?? '',
        item.nextAction,
      ]
        .join(' ')
        .toLocaleLowerCase('es')
        .includes(term);
    });
  }, [filter, state, view]);

  return (
    <article className="route-surface editorial-inbox" data-route-id="UI-MVP-017">
      <header className="editorial-inbox__intro">
        <p className="eyebrow">BL-MVP-044 · UI-MVP-017</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Bandeja editorial
        </h1>
        <p>
          Aquí aparecen las canciones que puedes trabajar ahora. Empieza por la siguiente tarea
          sugerida; los permisos y el alcance se vuelven a comprobar en el servidor al abrir cada
          acción.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          description="Preparando tus canciones, bloqueos y siguientes tareas."
          state="UI-EST-01"
          title="Preparando tu bandeja"
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
          description="No hay canciones disponibles para tu sesión en este momento."
          state="UI-EST-02"
          title="No tienes tareas editoriales pendientes"
        />
      ) : null}

      {state.phase === 'ready' && state.data.items.length > 0 ? (
        <>
          <section className="editorial-inbox__summary" aria-label="Resumen de la bandeja">
            <div>
              <strong>{summary.total}</strong>
              <span>canciones disponibles</span>
            </div>
            <div>
              <strong>{summary.ready}</strong>
              <span>listas para continuar</span>
            </div>
            <div>
              <strong>{summary.locked}</strong>
              <span>en edición ahora</span>
            </div>
          </section>

          <section className="editorial-inbox__controls" aria-label="Buscar y filtrar">
            <div className="editorial-inbox__toolbar">
              <label htmlFor="editorial-inbox-filter">Buscar en mi bandeja</label>
              <input
                id="editorial-inbox-filter"
                onChange={(event) => setFilter(event.target.value)}
                placeholder="Canción, artista, responsable o estado"
                type="search"
                value={filter}
              />
              <p>
                Mostrando {visibleItems.length} de {state.data.visibleCount} canciones disponibles.
              </p>
            </div>

            <div
              className="editorial-inbox__view-filter"
              role="group"
              aria-label="Filtrar por situación"
            >
              <button
                type="button"
                className={view === 'ALL' ? 'is-active' : ''}
                aria-pressed={view === 'ALL'}
                onClick={() => setView('ALL')}
              >
                Todas ({summary.total})
              </button>
              <button
                type="button"
                className={view === 'READY' ? 'is-active' : ''}
                aria-pressed={view === 'READY'}
                onClick={() => setView('READY')}
              >
                Listas para continuar ({summary.ready})
              </button>
              <button
                type="button"
                className={view === 'LOCKED' ? 'is-active' : ''}
                aria-pressed={view === 'LOCKED'}
                onClick={() => setView('LOCKED')}
              >
                En edición ({summary.locked})
              </button>
            </div>
          </section>

          {visibleItems.length === 0 ? (
            <StateMessage
              description="Prueba otro término o cambia el filtro. Buscar no modifica tus permisos."
              state="UI-EST-02"
              title="No hay coincidencias con este filtro"
            />
          ) : (
            <ul className="editorial-inbox__list">
              {visibleItems.map((item) => {
                const primaryAction = item.actions[0];
                const secondaryActions = item.actions.slice(1);

                return (
                  <li key={item.recordingId}>
                    <article className="editorial-inbox__card">
                      <header className="editorial-inbox__card-header">
                        <div>
                          <p className="editorial-inbox__artist">{item.artistName}</p>
                          <h2 lang="ja">{item.canonicalTitle}</h2>
                          {item.recordingTitle ? (
                            <p className="editorial-inbox__recording">{item.recordingTitle}</p>
                          ) : null}
                        </div>
                        <span className="editorial-inbox__state">
                          {formatState(item.stateCode)}
                        </span>
                      </header>

                      <div className="editorial-inbox__signals" aria-label="Situación editorial">
                        <span>{item.lock.active ? 'En edición' : 'Disponible'}</span>
                        <span>Responsable: {item.ownerLabel}</span>
                        <span>{item.provenanceLabel}</span>
                        <span>{formatProvider(item.providerCode)}</span>
                      </div>

                      <section
                        aria-labelledby={`next-${item.recordingId}`}
                        className="editorial-inbox__next"
                      >
                        <p className="eyebrow">Siguiente paso sugerido</p>
                        <h3 id={`next-${item.recordingId}`}>{item.nextAction}</h3>

                        {primaryAction ? (
                          <a className="ma-button ma-button--primary" href={primaryAction.href}>
                            {primaryAction.label}
                          </a>
                        ) : (
                          <p className="editorial-inbox__no-action">
                            No hay una acción navegable disponible para tu capacidad actual.
                          </p>
                        )}

                        {secondaryActions.length > 0 ? (
                          <nav aria-label={`Otras acciones para ${item.canonicalTitle}`}>
                            <ul className="editorial-inbox__actions">
                              {secondaryActions.map((action) => (
                                <li key={action.code}>
                                  <a className="ma-button ma-button--secondary" href={action.href}>
                                    {action.label}
                                  </a>
                                </li>
                              ))}
                            </ul>
                          </nav>
                        ) : null}
                      </section>

                      <details className="editorial-inbox__details">
                        <summary>Ver datos editoriales</summary>
                        <dl className="editorial-inbox__facts">
                          <div>
                            <dt>Estado</dt>
                            <dd>
                              {formatState(item.stateCode)} <code>{item.stateCode}</code>
                            </dd>
                          </div>
                          <div>
                            <dt>Responsable</dt>
                            <dd>{item.ownerLabel}</dd>
                          </div>
                          <div>
                            <dt>Bloqueo</dt>
                            <dd>
                              {item.lock.active
                                ? `${formatOperation(item.lock.operationCode)} · hasta ${formatDate(
                                    item.lock.expiresAt,
                                  )}`
                                : 'Sin bloqueo activo'}
                              {item.lock.operationCode ? (
                                <code>{item.lock.operationCode}</code>
                              ) : null}
                            </dd>
                          </div>
                          <div>
                            <dt>Procedencia</dt>
                            <dd>{item.provenanceLabel}</dd>
                          </div>
                          <div>
                            <dt>Fuente</dt>
                            <dd>{formatProvider(item.providerCode)}</dd>
                          </div>
                          <div>
                            <dt>Última actividad</dt>
                            <dd>{formatDate(item.lastActivityAt)}</dd>
                          </div>
                        </dl>
                        <p className="editorial-inbox__technical-id">
                          Identificador técnico: <code>{item.recordingId}</code>
                        </p>
                      </details>
                    </article>
                  </li>
                );
              })}
            </ul>
          )}
        </>
      ) : null}
    </article>
  );
}
