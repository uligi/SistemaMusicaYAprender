import { useEffect, useRef, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './publication-lifecycle.css';

const client = createHttpClient();

type Availability = {
  territoryCode: string;
  languageTag: string | null;
  audienceCode: string;
  validFrom: string;
  validTo: string | null;
  statusCode: string;
};

type Publication = {
  publicationId: string;
  packageId: string;
  publicationNo: number;
  statusCode: string;
  activeFrom: string;
  activeTo: string | null;
  publishedAt: string;
  checksumSha256: string;
  availability: Availability[];
};

type PublicationAction = {
  actionId: string;
  publicationId: string;
  caseId: string | null;
  actionCode: string;
  fromStatus: string;
  toStatus: string;
  effectiveAt: string;
  reason: string;
  correlationId: string;
};

type ApprovedPackage = {
  packageId: string;
  packageNo: number;
  checksumSha256: string;
};

type CorrectionState = {
  recordingId: string;
  activePublication: Publication | null;
  history: Publication[];
  actions: PublicationAction[];
  approvedPackages: ApprovedPackage[];
  eTag: string;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: CorrectionState }
  | { phase: 'failed'; problem: ClientProblem };

type CorrectionAction = 'WITHDRAW' | 'RESTORE' | 'REVERT' | 'SUBSTITUTE';

export type PublicationCorrectionPageProps = {
  recordingId: string;
};

function formatDate(value: string | null) {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('es-CR');
}

export function PublicationCorrectionPage({ recordingId }: PublicationCorrectionPageProps) {
  const endpoint = `/administration/corrections/${encodeURIComponent(recordingId)}`;
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [etag, setEtag] = useState('');
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [action, setAction] = useState<CorrectionAction>('WITHDRAW');
  const [targetPublicationId, setTargetPublicationId] = useState('');
  const [targetPackageId, setTargetPackageId] = useState('');
  const [territory, setTerritory] = useState('CR');
  const [language, setLanguage] = useState('es');
  const [audience, setAudience] = useState('PUBLIC');
  const [reason, setReason] = useState('');
  const [prepared, setPrepared] = useState(false);
  const [operationKey, setOperationKey] = useState<string | null>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);

  function accept(data: CorrectionState, responseEtag?: string | null) {
    setState({ phase: 'ready', data });
    setEtag(responseEtag ?? data.eTag);
    setProblem(null);
  }

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<CorrectionState>(endpoint, {
        cacheMode: 'no-store',
        retry: 'safe',
        signal: controller.signal,
      });

      if (result.kind === 'cancelled') return;
      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      accept(result.data, result.etag);
    };

    void load();
    return () => controller.abort();
  }, [endpoint]);

  useEffect(() => {
    if (prepared) confirmRef.current?.focus();
  }, [prepared]);

  const needsPublication = action === 'RESTORE' || action === 'REVERT';
  const needsPackage = action === 'SUBSTITUTE';
  const readyToPrepare =
    Boolean(reason.trim()) &&
    (!needsPublication || Boolean(targetPublicationId)) &&
    (!needsPackage || Boolean(targetPackageId));

  function prepare() {
    if (!readyToPrepare) return;
    setOperationKey(crypto.randomUUID());
    setPrepared(true);
  }

  async function confirm() {
    if (!etag || !operationKey || !readyToPrepare) return;

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, CorrectionState>(
      `${endpoint}/actions`,
      {
        actionCode: action,
        targetPublicationId: needsPublication ? targetPublicationId : null,
        targetPackageId: needsPackage ? targetPackageId : null,
        territoryCode: needsPackage ? territory : null,
        languageTag: needsPackage ? language || null : null,
        audienceCode: needsPackage ? audience : null,
        reason: reason.trim(),
      },
      {
        headers: { [csrf.data.headerName]: csrf.data.requestToken },
        ifMatch: etag,
        idempotencyKey: operationKey,
        retry: 'safe',
        invalidate: [endpoint],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;
    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setPrepared(false);
    setOperationKey(null);
    setReason('');
    setTargetPublicationId('');
    setTargetPackageId('');
    accept(result.data, result.etag);
  }

  if (state.phase === 'loading') {
    return (
      <article className="route-surface publication-correction" data-route-id="UI-MVP-028">
        <h1 ref={headingRef} tabIndex={-1}>
          Corrección o reversión
        </h1>
        <StateMessage
          state="UI-EST-01"
          title="Cargando historial"
          description="Recuperando publicación activa, versiones históricas y acciones trazables."
        />
      </article>
    );
  }

  if (state.phase === 'failed') {
    return (
      <article className="route-surface publication-correction" data-route-id="UI-MVP-028">
        <h1 ref={headingRef} tabIndex={-1}>
          Corrección o reversión
        </h1>
        <StateMessage
          state="UI-EST-06"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      </article>
    );
  }

  const readyData = state.data;
  const historicalTargets = readyData.history.filter(
    (publication) => publication.statusCode !== 'ACTIVE',
  );

  return (
    <article className="route-surface publication-correction" data-route-id="UI-MVP-028">
      <header className="publication-lifecycle__header">
        <div>
          <p className="eyebrow">BL-MVP-051 · UI-MVP-028 · CA-MVP-127-132</p>
          <h1 className="route-title" ref={headingRef} tabIndex={-1}>
            Corrección, retiro y reversión
          </h1>
          <p>
            Ninguna acción reescribe una publicación histórica. Restaurar o revertir crea una nueva
            publicación efectiva y conserva las posteriores.
          </p>
        </div>
        <AppLink href={`/administracion/publicaciones/${encodeURIComponent(recordingId)}`}>
          Volver a revisión/publicación
        </AppLink>
      </header>

      {problem ? (
        <StateMessage state="UI-EST-06" title={problem.summary} description={problem.correction} />
      ) : null}

      {mutation?.phase === 'saving' ? (
        <StateMessage
          state="UI-EST-11"
          title="Confirmando corrección"
          description="Caso, acción, auditoría y outbox se guardan de forma transaccional."
        />
      ) : null}

      <p className="publication-lifecycle__success" role="status">
        {readyData.message}
      </p>

      <section className="publication-lifecycle" aria-labelledby="current-publication-title">
        <h2 id="current-publication-title">Publicación actual</h2>
        {readyData.activePublication ? (
          <dl className="publication-lifecycle__facts">
            <div>
              <dt>Número</dt>
              <dd>#{readyData.activePublication.publicationNo}</dd>
            </div>
            <div>
              <dt>Estado</dt>
              <dd>{readyData.activePublication.statusCode}</dd>
            </div>
            <div>
              <dt>Activa desde</dt>
              <dd>{formatDate(readyData.activePublication.activeFrom)}</dd>
            </div>
            <div>
              <dt>Paquete</dt>
              <dd>{readyData.activePublication.packageId.slice(0, 8)}…</dd>
            </div>
          </dl>
        ) : (
          <p>No hay publicación activa.</p>
        )}
      </section>

      <section className="publication-lifecycle" aria-labelledby="correction-action-title">
        <h2 id="correction-action-title">Preparar acción</h2>

        <div className="publication-lifecycle__form">
          <label>
            Acción
            <select
              value={action}
              onChange={(event) => {
                setAction(event.target.value as CorrectionAction);
                setPrepared(false);
                setOperationKey(null);
              }}
            >
              <option value="WITHDRAW">Retirar publicación activa</option>
              <option value="RESTORE">Restaurar publicación histórica</option>
              <option value="REVERT">Revertir a publicación histórica</option>
              <option value="SUBSTITUTE">Sustituir por paquete corregido aprobado</option>
            </select>
          </label>

          {needsPublication ? (
            <label>
              Publicación histórica
              <select
                value={targetPublicationId}
                onChange={(event) => setTargetPublicationId(event.target.value)}
              >
                <option value="">Selecciona una versión exacta</option>
                {historicalTargets.map((publication) => (
                  <option key={publication.publicationId} value={publication.publicationId}>
                    #{publication.publicationNo} · {publication.statusCode}
                  </option>
                ))}
              </select>
            </label>
          ) : null}

          {needsPackage ? (
            <>
              <label>
                Paquete aprobado
                <select
                  value={targetPackageId}
                  onChange={(event) => setTargetPackageId(event.target.value)}
                >
                  <option value="">Selecciona paquete corregido</option>
                  {readyData.approvedPackages.map((item) => (
                    <option key={item.packageId} value={item.packageId}>
                      Paquete #{item.packageNo}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Territorio
                <input value={territory} onChange={(event) => setTerritory(event.target.value)} />
              </label>
              <label>
                Idioma
                <input value={language} onChange={(event) => setLanguage(event.target.value)} />
              </label>
              <label>
                Audiencia
                <select value={audience} onChange={(event) => setAudience(event.target.value)}>
                  <option value="PUBLIC">Público</option>
                </select>
              </label>
            </>
          ) : null}

          <label className="publication-lifecycle__wide">
            Motivo de la corrección
            <textarea
              value={reason}
              rows={4}
              maxLength={2000}
              onChange={(event) => setReason(event.target.value)}
            />
          </label>

          <button type="button" onClick={prepare} disabled={!readyToPrepare}>
            Preparar acción
          </button>
        </div>

        {prepared ? (
          <div
            className="publication-lifecycle__confirm"
            role="alertdialog"
            aria-labelledby="correction-confirm-title"
          >
            <h3 id="correction-confirm-title">Confirmar {action}</h3>
            <p>
              Se conservarán publicación anterior, motivo, actor, correlación y evidencia. No existe
              last-write-wins silencioso.
            </p>
            <div className="publication-lifecycle__actions">
              <button ref={confirmRef} type="button" onClick={() => void confirm()}>
                Confirmar acción
              </button>
              <button
                type="button"
                onClick={() => {
                  setPrepared(false);
                  setOperationKey(null);
                }}
              >
                Cancelar
              </button>
            </div>
          </div>
        ) : null}
      </section>

      <section className="publication-lifecycle" aria-labelledby="publication-history-title">
        <h2 id="publication-history-title">Historial inmutable</h2>
        {readyData.history.length ? (
          <div
            className="publication-lifecycle__table-wrap"
            role="region"
            aria-label="Historial de publicaciones"
            tabIndex={0}
          >
            <table>
              <caption>Publicaciones de esta grabación</caption>
              <thead>
                <tr>
                  <th scope="col">Versión</th>
                  <th scope="col">Estado</th>
                  <th scope="col">Desde</th>
                  <th scope="col">Hasta</th>
                </tr>
              </thead>
              <tbody>
                {readyData.history.map((publication) => (
                  <tr key={publication.publicationId}>
                    <td>#{publication.publicationNo}</td>
                    <td>{publication.statusCode}</td>
                    <td>{formatDate(publication.activeFrom)}</td>
                    <td>{formatDate(publication.activeTo)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p>Todavía no hay publicaciones históricas.</p>
        )}
      </section>

      <section className="publication-lifecycle" aria-labelledby="publication-actions-title">
        <h2 id="publication-actions-title">Acciones trazables</h2>
        {readyData.actions.length ? (
          <ul className="publication-lifecycle__history">
            {readyData.actions.map((item) => (
              <li key={item.actionId}>
                <strong>{item.actionCode}</strong> · {item.fromStatus} → {item.toStatus} ·{' '}
                {formatDate(item.effectiveAt)}
                <span>{item.reason}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p>No hay acciones de corrección registradas.</p>
        )}
      </section>
    </article>
  );
}
