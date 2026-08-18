import { useEffect, useRef, useState } from 'react';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './publication-lifecycle.css';

const client = createHttpClient();

type PublicationComponent = {
  sourceComponentId: string;
  sourceRevisionId: string;
  componentKind: string;
  checksumSha256: string;
  displayOrder: number;
};

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

type Candidate = {
  packageId: string;
  packageNo: number;
  statusCode: string;
  version: number;
  checksumSha256: string;
  frozen: boolean;
  approvedReview: boolean;
  componentsComplete: boolean;
  componentsCurrent: boolean;
  hasActiveRights: boolean;
  readyToPublish: boolean;
  components: PublicationComponent[];
  issues: string[];
};

type PublicationState = {
  recordingId: string;
  candidate: Candidate | null;
  activePublication: Publication | null;
  history: Publication[];
  eTag: string;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: PublicationState }
  | { phase: 'failed'; problem: ClientProblem };

export type EditorialPublicationPanelProps = {
  recordingId: string;
  packageId: string;
};

function shortHash(value: string) {
  return value ? `${value.slice(0, 16)}…` : '—';
}

export function EditorialPublicationPanel({
  recordingId,
  packageId,
}: EditorialPublicationPanelProps) {
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [etag, setEtag] = useState('');
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [territory, setTerritory] = useState('CR');
  const [language, setLanguage] = useState('es');
  const [audience, setAudience] = useState('PUBLIC');
  const [reason, setReason] = useState('');
  const [prepared, setPrepared] = useState(false);
  const [operationKey, setOperationKey] = useState<string | null>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);

  const endpoint = `/administration/publications/${encodeURIComponent(recordingId)}/publication`;

  function accept(data: PublicationState, responseEtag?: string | null) {
    setState({ phase: 'ready', data });
    setEtag(responseEtag ?? data.eTag);
    setProblem(null);
  }

  useEffect(() => {
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<PublicationState>(
        `${endpoint}?packageId=${encodeURIComponent(packageId)}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;
      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      accept(result.data, result.etag);
    };

    void load();
    return () => controller.abort();
  }, [endpoint, packageId]);

  useEffect(() => {
    if (prepared) confirmRef.current?.focus();
  }, [prepared]);

  function prepare() {
    if (!reason.trim()) return;
    setOperationKey(crypto.randomUUID());
    setPrepared(true);
  }

  async function publish() {
    if (!etag || !operationKey || !reason.trim()) return;

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, PublicationState>(
      endpoint,
      {
        packageId,
        territoryCode: territory,
        languageTag: language || null,
        audienceCode: audience,
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
    accept(result.data, result.etag);
  }

  if (state.phase === 'loading') {
    return (
      <section className="publication-lifecycle" aria-labelledby="publication-title">
        <h2 id="publication-title">5. Publicación atómica</h2>
        <StateMessage
          state="UI-EST-01"
          title="Cargando publicación"
          description="Revalidando paquete aprobado, derechos y publicación activa."
        />
      </section>
    );
  }

  if (state.phase === 'failed') {
    return (
      <section className="publication-lifecycle" aria-labelledby="publication-title">
        <h2 id="publication-title">5. Publicación atómica</h2>
        <StateMessage
          state="UI-EST-06"
          title={state.problem.summary}
          description={state.problem.correction}
        />
      </section>
    );
  }

  const data = state.data;
  const candidate = data.candidate;
  const activeIsCandidate =
    Boolean(candidate) && data.activePublication?.packageId === candidate?.packageId;

  return (
    <section className="publication-lifecycle" aria-labelledby="publication-title">
      <header className="publication-lifecycle__header">
        <div>
          <p className="eyebrow">BL-MVP-050 · CA-MVP-121-126</p>
          <h2 id="publication-title">5. Publicación atómica</h2>
          <p>{data.message}</p>
        </div>
        {data.activePublication ? (
          <AppLink href={`/administracion/correcciones/${encodeURIComponent(recordingId)}`}>
            Abrir corrección o reversión
          </AppLink>
        ) : null}
      </header>

      {problem ? (
        <StateMessage state="UI-EST-06" title={problem.summary} description={problem.correction} />
      ) : null}

      {mutation?.phase === 'saving' ? (
        <StateMessage
          state="UI-EST-11"
          title="Publicando"
          description="Paquete, disponibilidad, auditoría y outbox se confirman juntos."
        />
      ) : null}

      {candidate ? (
        <>
          <dl className="publication-lifecycle__facts">
            <div>
              <dt>Paquete exacto</dt>
              <dd>#{candidate.packageNo}</dd>
            </div>
            <div>
              <dt>Estado</dt>
              <dd>{candidate.statusCode}</dd>
            </div>
            <div>
              <dt>Checksum</dt>
              <dd title={candidate.checksumSha256}>{shortHash(candidate.checksumSha256)}</dd>
            </div>
            <div>
              <dt>Componentes</dt>
              <dd>{candidate.components.length}</dd>
            </div>
          </dl>

          {candidate.issues.length ? (
            <div className="publication-lifecycle__issues" role="alert">
              <h3>Bloqueos de publicación</h3>
              <ul>
                {candidate.issues.map((issue) => (
                  <li key={issue}>{issue}</li>
                ))}
              </ul>
            </div>
          ) : null}
        </>
      ) : null}

      {data.activePublication ? (
        <p className="publication-lifecycle__success" role="status">
          Publicación #{data.activePublication.publicationNo} · {data.activePublication.statusCode}
        </p>
      ) : null}

      {candidate?.readyToPublish && !activeIsCandidate ? (
        <div className="publication-lifecycle__form">
          <label>
            Territorio
            <input
              value={territory}
              maxLength={64}
              onChange={(event) => setTerritory(event.target.value)}
            />
          </label>
          <label>
            Idioma
            <input
              value={language}
              maxLength={35}
              onChange={(event) => setLanguage(event.target.value)}
            />
          </label>
          <label>
            Audiencia
            <select value={audience} onChange={(event) => setAudience(event.target.value)}>
              <option value="PUBLIC">Público</option>
            </select>
          </label>
          <label className="publication-lifecycle__wide">
            Motivo de publicación
            <textarea
              value={reason}
              maxLength={2000}
              rows={3}
              onChange={(event) => setReason(event.target.value)}
            />
          </label>

          <button type="button" onClick={prepare} disabled={!reason.trim()}>
            Preparar publicación
          </button>
        </div>
      ) : null}

      {prepared ? (
        <div
          className="publication-lifecycle__confirm"
          role="alertdialog"
          aria-labelledby="publish-confirm-title"
        >
          <h3 id="publish-confirm-title">Confirmar publicación</h3>
          <p>
            Se activará el paquete #{candidate?.packageNo} para {territory} /{' '}
            {language || 'sin idioma'}/ {audience}. La publicación anterior quedará histórica.
          </p>
          <div className="publication-lifecycle__actions">
            <button ref={confirmRef} type="button" onClick={() => void publish()}>
              Confirmar publicación
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
  );
}
