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

export type SongEditorialDossierPageProps = {
  recordingId: string;
};

function displayState(value: string) {
  return value.replaceAll('_', ' ');
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('es-CR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

export function SongEditorialDossierPage({ recordingId }: SongEditorialDossierPageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<DossierState>({ phase: 'loading' });

  useEffect(() => {
    headingRef.current?.focus();

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

  return (
    <article className="route-surface song-dossier" data-route-id="UI-MVP-019">
      <header className="song-dossier__header">
        <p className="eyebrow">BL-MVP-046 · UI-MVP-019</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Expediente editorial de canción
        </h1>
        <p>
          Reúne el estado editorial de la grabación sin congelar ni publicar nada. Las revisiones,
          incidencias y accesos se vuelven a resolver desde el servidor.
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

      {state.phase === 'ready' ? (
        <>
          <section className="song-dossier__identity" aria-labelledby="song-dossier-identity">
            <div>
              <p className="song-dossier__artist">{state.data.artistName}</p>
              <h2 id="song-dossier-identity" lang="ja">
                {state.data.canonicalTitle}
              </h2>
              <p>{state.data.recordingTitle ?? 'Sin título adicional de grabación'}</p>
            </div>
            <dl>
              <div>
                <dt>Grabación</dt>
                <dd>{displayState(state.data.recordingStatusCode)}</dd>
              </div>
              <div>
                <dt>Fuente</dt>
                <dd>
                  {state.data.providerCode ?? 'Sin fuente'} ·{' '}
                  {state.data.sourceStatusCode
                    ? displayState(state.data.sourceStatusCode)
                    : 'sin estado'}
                </dd>
              </div>
            </dl>
          </section>

          <RecordingAutosavePanel recordingId={recordingId} />

          <section aria-labelledby="song-dossier-components">
            <header className="song-dossier__section-heading">
              <h2 id="song-dossier-components">Componentes por revisión</h2>
              <p>
                Una ausencia queda visible como “Sin revisión”; no se inventa contenido faltante.
              </p>
            </header>

            <ul className="song-dossier__components">
              {state.data.components.map((component) => (
                <li key={component.code}>
                  <article className="song-dossier__component">
                    <header>
                      <h3>{component.label}</h3>
                      <span>{component.revisionLabel}</span>
                    </header>
                    <dl>
                      <div>
                        <dt>Estado</dt>
                        <dd>{displayState(component.stateCode)}</dd>
                      </div>
                      <div>
                        <dt>Propietario</dt>
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
          </section>

          <section className="song-dossier__rights" aria-labelledby="song-dossier-rights">
            <header className="song-dossier__section-heading">
              <h2 id="song-dossier-rights">Derechos y procedencia</h2>
              <p>Resumen editorial; la vigencia efectiva se vuelve a validar al publicar.</p>
            </header>
            <dl>
              <div>
                <dt>Registros de derechos</dt>
                <dd>{state.data.rights.totalRecords}</dd>
              </div>
              <div>
                <dt>Derechos activos ahora</dt>
                <dd>{state.data.rights.activeRecords}</dd>
              </div>
              <div>
                <dt>Registros de procedencia</dt>
                <dd>{state.data.rights.provenanceRecords}</dd>
              </div>
              <div>
                <dt>Responsable</dt>
                <dd>{state.data.rights.ownerLabel}</dd>
              </div>
            </dl>
          </section>

          <section aria-labelledby="song-dossier-incidents">
            <header className="song-dossier__section-heading">
              <h2 id="song-dossier-incidents">Incidencias abiertas</h2>
              <p>Hallazgos de calidad vinculados a la grabación o a sus revisiones visibles.</p>
            </header>

            {state.data.incidents.length === 0 ? (
              <StateMessage
                state="UI-EST-12"
                title="Sin incidencias abiertas"
                description="No hay hallazgos OPEN o ACKNOWLEDGED asociados al expediente."
              />
            ) : (
              <ul className="song-dossier__incidents">
                {state.data.incidents.map((incident, index) => (
                  <li key={`${incident.componentCode}-${incident.ruleCode}-${index}`}>
                    <strong>
                      {incident.componentCode} · {incident.ruleCode}
                    </strong>
                    <span>
                      {incident.severityCode} · {displayState(incident.statusCode)}
                    </span>
                    <time dateTime={incident.detectedAt}>{formatDate(incident.detectedAt)}</time>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section aria-labelledby="song-dossier-access">
            <header className="song-dossier__section-heading">
              <h2 id="song-dossier-access">Accesos permitidos</h2>
              <p>Esta lista la deriva el servidor de capacidad y alcance por grabación.</p>
            </header>

            <nav aria-label="Accesos permitidos del expediente">
              <ul className="song-dossier__access">
                {state.data.allowedAccesses.map((access) => (
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
