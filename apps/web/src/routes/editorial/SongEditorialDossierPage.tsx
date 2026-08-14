import { useEffect, useRef, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { RecordingAutosavePanel } from './RecordingAutosavePanel';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import './song-editorial-dossier.css';

const client = createHttpClient();

type DossierComponent = {
  code: string;
  label: string;
  revisionLabel: string;
  stateCode: string;
  ownerLabel: string;
  exists: boolean;
  href: string | null;
};

type DossierAccess = {
  code: string;
  label: string;
  href: string;
};

type DossierResponse = {
  canonicalTitle: string;
  recordingTitle: string | null;
  artistName: string;
  recordingStatusCode: string;
  providerCode: string | null;
  externalRef: string | null;
  sourceStatusCode: string | null;
  components: DossierComponent[];
  rights: {
    totalRecords: number;
    activeRecords: number;
    provenanceRecords: number;
    ownerLabel: string;
    stateCode: string;
  };
  incidents: Array<{
    componentCode: string;
    ruleCode: string;
    severityCode: string;
    statusCode: string;
    detectedAt: string;
  }>;
  allowedAccesses: DossierAccess[];
};

type DossierState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: DossierResponse }
  | { phase: 'failed'; problem: ClientProblem };

type ComponentFilter = 'ALL' | 'READY' | 'PENDING';

export type SongEditorialDossierPageProps = {
  recordingId: string;
};

const stateLabels: Record<string, string> = {
  ACTIVE: 'Activo',
  BLOCKED: 'Bloqueado',
  DRAFT: 'Borrador',
  NOT_STARTED: 'Sin iniciar',
  PUBLISHED: 'Publicado',
  READY: 'Listo',
  REVIEW: 'En revisión',
};

const severityLabels: Record<string, string> = {
  ERROR: 'Error',
  WARNING: 'Advertencia',
  INFO: 'Información',
};

function displayState(value: string) {
  return stateLabels[value] ?? value.replaceAll('_', ' ').toLocaleLowerCase('es');
}

function displaySeverity(value: string) {
  return severityLabels[value] ?? displayState(value);
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('es-CR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

function scrollToSection(id: string) {
  const target = document.getElementById(id);
  if (!target) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  target.scrollIntoView({
    behavior: reducedMotion ? 'auto' : 'smooth',
    block: 'start',
  });
}

export function SongEditorialDossierPage({ recordingId }: SongEditorialDossierPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<DossierState>({ phase: 'loading' });
  const [componentFilter, setComponentFilter] = useState<ComponentFilter>('ALL');

  useEffect(() => {
    headingRef.current?.focus();
    setComponentFilter('ALL');

    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<DossierResponse>(
        `/editorial/song-dossiers/${encodeURIComponent(recordingId)}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') {
        return;
      }

      setState(
        result.ok
          ? { phase: 'ready', data: result.data }
          : { phase: 'failed', problem: result.problem },
      );
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  const data = state.phase === 'ready' ? state.data : null;
  const readyComponents = data?.components.filter((component) => component.exists).length ?? 0;
  const totalComponents = data?.components.length ?? 0;
  const pendingComponents = totalComponents - readyComponents;
  const completion =
    totalComponents === 0 ? 0 : Math.round((readyComponents / totalComponents) * 100);
  const filteredComponents =
    data?.components.filter((component) => {
      if (componentFilter === 'READY') return component.exists;
      if (componentFilter === 'PENDING') return !component.exists;
      return true;
    }) ?? [];
  const recommendedComponent =
    data?.components.find((component) => !component.exists && component.href) ?? null;
  const rightsAccess = data?.allowedAccesses.find((access) => access.code === 'RIGHTS') ?? null;

  return (
    <article className="route-surface song-dossier" data-route-id="UI-MVP-019">
      <header className="song-dossier__header">
        <p className="eyebrow">BL-MVP-046 · UI-MVP-019</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Expediente editorial de canción
        </h1>
        <p>
          Usa este panel como centro de control: identifica qué está listo, qué falta y abre
          directamente la siguiente tarea sin recorrer todo el expediente.
        </p>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando expediente"
          description="Resolviendo componentes, responsables, derechos e incidencias."
        />
      ) : null}

      {state.phase === 'failed' ? (
        <StateMessage
          state="UI-EST-04"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      ) : null}

      {data ? (
        <>
          <section className="song-dossier__identity" aria-labelledby="song-dossier-identity">
            <div>
              <p className="song-dossier__artist">{data.artistName}</p>
              <h2 id="song-dossier-identity" lang="ja">
                {data.canonicalTitle}
              </h2>
              <p>{data.recordingTitle ?? 'Sin título adicional de grabación'}</p>
            </div>
            <dl>
              <div>
                <dt>Grabación</dt>
                <dd>
                  <span className="song-dossier__status-pill">
                    {displayState(data.recordingStatusCode)}
                  </span>
                </dd>
              </div>
              <div>
                <dt>Fuente</dt>
                <dd>
                  {data.providerCode ?? 'Sin fuente'} ·{' '}
                  {data.sourceStatusCode ? displayState(data.sourceStatusCode) : 'sin estado'}
                </dd>
              </div>
            </dl>
          </section>

          <section className="song-dossier__overview" aria-label="Resumen operativo del expediente">
            <button type="button" onClick={() => scrollToSection('song-dossier-components')}>
              <strong>
                {readyComponents}/{totalComponents}
              </strong>
              <span>componentes con revisión</span>
            </button>
            <button type="button" onClick={() => scrollToSection('song-dossier-rights')}>
              <strong>{data.rights.activeRecords}</strong>
              <span>derechos activos</span>
            </button>
            <button type="button" onClick={() => scrollToSection('song-dossier-incidents')}>
              <strong>{data.incidents.length}</strong>
              <span>incidencias abiertas</span>
            </button>
            <button type="button" onClick={() => scrollToSection('song-dossier-access')}>
              <strong>{data.allowedAccesses.length}</strong>
              <span>accesos disponibles</span>
            </button>
          </section>

          <section className="song-dossier__progress-card" aria-labelledby="song-dossier-progress">
            <div className="song-dossier__progress-copy">
              <div>
                <p className="eyebrow">Avance visible</p>
                <h2 id="song-dossier-progress">Estado del expediente</h2>
              </div>
              <strong>{completion}%</strong>
            </div>
            <div
              className="song-dossier__progress-track"
              role="progressbar"
              aria-label="Componentes con revisión disponible"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={completion}
            >
              <span style={{ width: `${completion}%` }} />
            </div>
            <p>
              {pendingComponents === 0
                ? 'Todos los componentes visibles tienen una revisión o registro asociado.'
                : `Quedan ${pendingComponents} componente(s) sin revisión visible.`}
            </p>
          </section>

          <section className="song-dossier__next-step" aria-labelledby="song-dossier-next-step">
            <div>
              <p className="eyebrow">Siguiente paso sugerido</p>
              <h2 id="song-dossier-next-step">
                {recommendedComponent
                  ? `Continuar con ${recommendedComponent.label}`
                  : data.incidents.length > 0
                    ? 'Revisar incidencias abiertas'
                    : 'Expediente sin tareas pendientes visibles'}
              </h2>
              <p>
                {recommendedComponent
                  ? 'Es el primer componente navegable que todavía no tiene revisión.'
                  : data.incidents.length > 0
                    ? 'Los componentes tienen revisión; quedan hallazgos de calidad por atender.'
                    : 'No hay componentes pendientes ni incidencias abiertas en este resumen.'}
              </p>
            </div>
            {recommendedComponent?.href ? (
              <a className="ma-button ma-button--primary" href={recommendedComponent.href}>
                Abrir {recommendedComponent.label.toLocaleLowerCase('es')}
              </a>
            ) : data.incidents.length > 0 ? (
              <button
                type="button"
                className="ma-button ma-button--secondary"
                onClick={() => scrollToSection('song-dossier-incidents')}
              >
                Ver incidencias
              </button>
            ) : null}
          </section>

          <nav className="song-dossier__quick-nav" aria-label="Navegación rápida del expediente">
            <span>Ir a</span>
            <a href="#song-dossier-components">Componentes</a>
            <a href="#song-dossier-rights">Derechos</a>
            <a href="#song-dossier-incidents">Incidencias</a>
            <a href="#song-dossier-access">Accesos</a>
          </nav>

          <RecordingAutosavePanel recordingId={recordingId} />

          <section aria-labelledby="song-dossier-components">
            <header className="song-dossier__section-heading">
              <div>
                <h2 id="song-dossier-components">Componentes por revisión</h2>
                <p>Filtra la lista para concentrarte solo en lo pendiente o en lo ya preparado.</p>
              </div>
              <div className="song-dossier__filters" role="group" aria-label="Filtrar componentes">
                <button
                  type="button"
                  aria-pressed={componentFilter === 'ALL'}
                  onClick={() => setComponentFilter('ALL')}
                >
                  Todos ({totalComponents})
                </button>
                <button
                  type="button"
                  aria-pressed={componentFilter === 'PENDING'}
                  onClick={() => setComponentFilter('PENDING')}
                >
                  Pendientes ({pendingComponents})
                </button>
                <button
                  type="button"
                  aria-pressed={componentFilter === 'READY'}
                  onClick={() => setComponentFilter('READY')}
                >
                  Con revisión ({readyComponents})
                </button>
              </div>
            </header>

            {filteredComponents.length === 0 ? (
              <StateMessage
                state="UI-EST-12"
                title="No hay componentes en este filtro"
                description="Cambia el filtro para ver el resto del expediente."
              />
            ) : (
              <ul className="song-dossier__components">
                {filteredComponents.map((component) => (
                  <li key={component.code}>
                    <article
                      className="song-dossier__component"
                      data-complete={component.exists ? 'true' : 'false'}
                    >
                      <header>
                        <h3>{component.label}</h3>
                        <span className="song-dossier__revision-pill">
                          {component.revisionLabel}
                        </span>
                      </header>
                      <dl>
                        <div>
                          <dt>Estado</dt>
                          <dd>{displayState(component.stateCode)}</dd>
                        </div>
                        <div>
                          <dt>Responsable</dt>
                          <dd>{component.ownerLabel}</dd>
                        </div>
                      </dl>
                      {component.href ? (
                        <a className="ma-link" href={component.href}>
                          Abrir {component.label.toLocaleLowerCase('es')}
                        </a>
                      ) : component.code === 'CATALOG' ? (
                        <p className="song-dossier__restricted">
                          Resumen incluido en este expediente.
                        </p>
                      ) : (
                        <p className="song-dossier__restricted">
                          Sin acceso navegable para tu alcance actual.
                        </p>
                      )}
                    </article>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="song-dossier__rights" aria-labelledby="song-dossier-rights">
            <header className="song-dossier__section-heading">
              <div>
                <h2 id="song-dossier-rights">Derechos y procedencia</h2>
                <p>Resumen editorial; la vigencia efectiva se vuelve a validar al publicar.</p>
              </div>
              {rightsAccess ? (
                <a className="ma-button ma-button--secondary" href={rightsAccess.href}>
                  Gestionar derechos
                </a>
              ) : null}
            </header>
            <dl>
              <div>
                <dt>Registros de derechos</dt>
                <dd>{data.rights.totalRecords}</dd>
              </div>
              <div>
                <dt>Derechos activos ahora</dt>
                <dd>{data.rights.activeRecords}</dd>
              </div>
              <div>
                <dt>Registros de procedencia</dt>
                <dd>{data.rights.provenanceRecords}</dd>
              </div>
              <div>
                <dt>Responsable</dt>
                <dd>{data.rights.ownerLabel}</dd>
              </div>
            </dl>
          </section>

          <section aria-labelledby="song-dossier-incidents">
            <header className="song-dossier__section-heading">
              <div>
                <h2 id="song-dossier-incidents">Incidencias abiertas</h2>
                <p>Hallazgos de calidad vinculados a la grabación o a sus revisiones visibles.</p>
              </div>
            </header>

            {data.incidents.length === 0 ? (
              <StateMessage
                state="UI-EST-12"
                title="Sin incidencias abiertas"
                description="No hay hallazgos OPEN o ACKNOWLEDGED asociados al expediente."
              />
            ) : (
              <ul className="song-dossier__incidents">
                {data.incidents.map((incident, index) => (
                  <li key={`${incident.componentCode}-${incident.ruleCode}-${index}`}>
                    <div>
                      <strong>{incident.ruleCode}</strong>
                      <span>{incident.componentCode}</span>
                    </div>
                    <span>
                      {displaySeverity(incident.severityCode)} · {displayState(incident.statusCode)}
                    </span>
                    <time dateTime={incident.detectedAt}>{formatDate(incident.detectedAt)}</time>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section aria-labelledby="song-dossier-access">
            <header className="song-dossier__section-heading">
              <div>
                <h2 id="song-dossier-access">Accesos permitidos</h2>
                <p>Abre directamente una herramienta autorizada para esta grabación.</p>
              </div>
            </header>

            <nav aria-label="Accesos permitidos del expediente">
              <ul className="song-dossier__access">
                {data.allowedAccesses.map((access) => (
                  <li key={access.code}>
                    <a className="ma-button ma-button--secondary" href={access.href}>
                      {access.label}
                    </a>
                  </li>
                ))}
              </ul>
            </nav>
          </section>
        </>
      ) : null}
    </article>
  );
}
