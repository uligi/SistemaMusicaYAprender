import { useEffect, useMemo, useRef, useState } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { AppLink } from '../../app/router/navigation';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './editorial-review.css';

const client = createHttpClient();

type ReviewComponent = {
  componentKind: string;
  checksumSha256: string;
};

type ReviewerCandidate = {
  accountId: string;
  label: string;
  eligible: boolean;
  ineligibilityReason: string | null;
};

type Assignment = {
  assignmentId: string;
  reviewerId: string;
  reviewerLabel: string;
  scopeCode: string;
  assignedAt: string;
  dueAt: string | null;
  conflictDeclared: boolean;
  isCurrent: boolean;
};

type Decision = {
  decisionId: string;
  assignmentId: string;
  decisionCode: string;
  reason: string;
  decidedAt: string;
  checklistResult: Record<string, unknown>;
};

type Checklist = {
  packageFrozen: boolean;
  submissionOpen: boolean;
  componentSetComplete: boolean;
  componentChecksumsPresent: boolean;
  activeRights: boolean;
  conflictFree: boolean;
  readyForApproval: boolean;
  issues: string[];
};

type ReviewSnapshot = {
  recordingId: string;
  packageId: string;
  packageNo: number;
  packageStatusCode: string;
  packageVersion: number;
  packageChecksumSha256: string;
  frozenAt: string;
  submissionId: string;
  submittedBy: string;
  submittedAt: string;
  submissionStatusCode: string;
  checklistVersion: string;
  components: ReviewComponent[];
  reviewerCandidates: ReviewerCandidate[];
  assignments: Assignment[];
  decisions: Decision[];
  checklist: Checklist;
  actorIsCurrentReviewer: boolean;
  currentReviewerHasConflict: boolean;
  eTag: string;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: ReviewSnapshot }
  | { phase: 'failed'; problem: ClientProblem };

type PreparedDecision = 'APPROVED' | 'REJECTED' | null;

export type EditorialReviewPageProps = {
  recordingId: string;
};

function formatDate(value: string | null) {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('es-CR');
}

function shortHash(value: string) {
  return value ? `${value.slice(0, 16)}…` : '—';
}

function statusText(value: boolean) {
  return value ? 'Cumple' : 'Bloqueado';
}

export function EditorialReviewPage({ recordingId }: EditorialReviewPageProps) {
  const access = useVisibleAccess();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [etag, setEtag] = useState('');
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [reviewerId, setReviewerId] = useState('');
  const [dueAt, setDueAt] = useState('');
  const [assignmentReason, setAssignmentReason] = useState('');
  const [conflictReason, setConflictReason] = useState('');
  const [decisionReason, setDecisionReason] = useState('');
  const [preparedDecision, setPreparedDecision] = useState<PreparedDecision>(null);

  const canReview = access.capabilities.includes('EDITORIAL.REVIEW');
  const canPublish = access.capabilities.includes('EDITORIAL.PUBLISH');

  async function read(signal?: AbortSignal) {
    return client.get<ReviewSnapshot>(
      `/administration/publications/${encodeURIComponent(recordingId)}/review`,
      {
        cacheMode: 'no-store',
        retry: 'safe',
        ...(signal ? { signal } : {}),
      },
    );
  }

  function accept(snapshot: ReviewSnapshot, responseEtag?: string | null) {
    setState({ phase: 'ready', data: snapshot });
    setEtag(responseEtag ?? snapshot.eTag);
    setProblem(null);
    setPreparedDecision(null);
  }

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await read(controller.signal);
      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      accept(result.data, result.etag);
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  const data = state.phase === 'ready' ? state.data : null;
  const currentAssignment = data?.assignments.find((assignment) => assignment.isCurrent) ?? null;
  const eligibleReviewers = useMemo(
    () => data?.reviewerCandidates.filter((candidate) => candidate.eligible) ?? [],
    [data],
  );

  async function csrf() {
    return client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });
  }

  async function assignReviewer() {
    if (!reviewerId || !assignmentReason.trim() || !etag) return;

    const token = await csrf();
    if (!token.ok) {
      if (token.kind === 'problem') setProblem(token.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, ReviewSnapshot>(
      `/administration/publications/${encodeURIComponent(recordingId)}/review/assignments`,
      {
        reviewerId,
        dueAt: dueAt ? new Date(`${dueAt}T23:59:59`).toISOString() : null,
        reason: assignmentReason.trim(),
      },
      {
        headers: { [token.data.headerName]: token.data.requestToken },
        ifMatch: etag,
        retry: 'never',
        invalidate: [`/administration/publications/${encodeURIComponent(recordingId)}/review`],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;
    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setReviewerId('');
    setDueAt('');
    setAssignmentReason('');
    accept(result.data, result.etag);
  }

  async function declareConflict() {
    if (!conflictReason.trim() || !etag) return;

    const token = await csrf();
    if (!token.ok) {
      if (token.kind === 'problem') setProblem(token.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, ReviewSnapshot>(
      `/administration/publications/${encodeURIComponent(recordingId)}/review/conflict`,
      { reason: conflictReason.trim() },
      {
        headers: { [token.data.headerName]: token.data.requestToken },
        ifMatch: etag,
        retry: 'never',
        invalidate: [`/administration/publications/${encodeURIComponent(recordingId)}/review`],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;
    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setConflictReason('');
    accept(result.data, result.etag);
  }

  async function confirmDecision() {
    if (!preparedDecision || !decisionReason.trim() || !etag) return;

    const token = await csrf();
    if (!token.ok) {
      if (token.kind === 'problem') setProblem(token.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, ReviewSnapshot>(
      `/administration/publications/${encodeURIComponent(recordingId)}/review/decisions`,
      {
        decisionCode: preparedDecision,
        reason: decisionReason.trim(),
      },
      {
        headers: { [token.data.headerName]: token.data.requestToken },
        ifMatch: etag,
        retry: 'never',
        invalidate: [`/administration/publications/${encodeURIComponent(recordingId)}/review`],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;
    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setDecisionReason('');
    accept(result.data, result.etag);
  }

  if (state.phase === 'loading') {
    return (
      <article className="route-surface editorial-review" data-route-id="UI-MVP-027">
        <h1 ref={headingRef} tabIndex={-1}>
          Revisión editorial
        </h1>
        <StateMessage
          description="Recuperando el paquete congelado y su checklist."
          state="UI-EST-01"
          title="Cargando revisión"
        />
      </article>
    );
  }

  if (state.phase === 'failed') {
    return (
      <article className="route-surface editorial-review" data-route-id="UI-MVP-027">
        <h1 ref={headingRef} tabIndex={-1}>
          Revisión editorial
        </h1>
        <StateMessage
          description={state.problem.correction}
          state="UI-EST-06"
          title={state.problem.summary}
        />
      </article>
    );
  }

  const readyData = state.data;

  return (
    <article className="route-surface editorial-review" data-route-id="UI-MVP-027">
      <header className="editorial-review__header">
        <div>
          <p className="eyebrow">BL-MVP-049 · UI-MVP-027</p>
          <h1 className="route-title" ref={headingRef} tabIndex={-1}>
            Revisión, checklist y decisión
          </h1>
          <p className="editorial-review__lead">
            Revisa exactamente el paquete congelado. Aprobar aquí no publica: BL-MVP-050 conserva la
            publicación atómica y la disponibilidad.
          </p>
        </div>
        <AppLink href={`/editorial/paquetes/${encodeURIComponent(recordingId)}`}>
          Ver paquete sometido
        </AppLink>
      </header>

      {problem ? (
        <StateMessage description={problem.correction} state="UI-EST-06" title={problem.summary} />
      ) : null}

      {mutation?.phase === 'saving' ? (
        <StateMessage
          description="La operación se confirma de forma transaccional."
          state="UI-EST-11"
          title="Guardando decisión segura"
        />
      ) : null}

      <p className="editorial-review__status" role="status">
        {readyData.message}
      </p>

      <div className="editorial-review__grid">
        <section className="editorial-review__panel" aria-labelledby="review-package-title">
          <h2 id="review-package-title">1. Paquete congelado</h2>
          <dl className="editorial-review__facts">
            <div>
              <dt>Paquete</dt>
              <dd>#{readyData.packageNo}</dd>
            </div>
            <div>
              <dt>Estado</dt>
              <dd>{readyData.packageStatusCode}</dd>
            </div>
            <div>
              <dt>Congelado</dt>
              <dd>{formatDate(readyData.frozenAt)}</dd>
            </div>
            <div>
              <dt>Checksum</dt>
              <dd title={readyData.packageChecksumSha256}>
                {shortHash(readyData.packageChecksumSha256)}
              </dd>
            </div>
            <div>
              <dt>Sometido</dt>
              <dd>{formatDate(readyData.submittedAt)}</dd>
            </div>
            <div>
              <dt>Checklist base</dt>
              <dd>{readyData.checklistVersion}</dd>
            </div>
          </dl>

          <h3>Componentes exactos</h3>
          <ul className="editorial-review__components">
            {readyData.components.map((component, index) => (
              <li key={`${component.componentKind}-${index}`}>
                <strong>{component.componentKind}</strong>
                <span title={component.checksumSha256}>{shortHash(component.checksumSha256)}</span>
              </li>
            ))}
          </ul>
        </section>

        <section className="editorial-review__panel" aria-labelledby="review-checklist-title">
          <h2 id="review-checklist-title">2. Checklist de revisión</h2>
          <ul className="editorial-review__checklist">
            <li>
              <span>Paquete congelado</span>
              <strong>{statusText(readyData.checklist.packageFrozen)}</strong>
            </li>
            <li>
              <span>Presentación abierta</span>
              <strong>{statusText(readyData.checklist.submissionOpen)}</strong>
            </li>
            <li>
              <span>Capas P0 completas</span>
              <strong>{statusText(readyData.checklist.componentSetComplete)}</strong>
            </li>
            <li>
              <span>Checksums presentes</span>
              <strong>{statusText(readyData.checklist.componentChecksumsPresent)}</strong>
            </li>
            <li>
              <span>Derechos vigentes</span>
              <strong>{statusText(readyData.checklist.activeRights)}</strong>
            </li>
            <li>
              <span>Sin conflicto</span>
              <strong>{statusText(readyData.checklist.conflictFree)}</strong>
            </li>
          </ul>

          {readyData.checklist.issues.length ? (
            <div className="editorial-review__issues" role="alert">
              <h3>Bloqueos</h3>
              <ul>
                {readyData.checklist.issues.map((issue) => (
                  <li key={issue}>{issue}</li>
                ))}
              </ul>
            </div>
          ) : (
            <p className="editorial-review__ok">
              El checklist no presenta bloqueos para una decisión del revisor asignado.
            </p>
          )}
        </section>

        <section className="editorial-review__panel" aria-labelledby="review-assignment-title">
          <h2 id="review-assignment-title">3. Asignación y conflicto</h2>

          {currentAssignment ? (
            <div className="editorial-review__current">
              <p>
                Revisor actual: <strong>{currentAssignment.reviewerLabel}</strong>
              </p>
              <p>
                Asignado: {formatDate(currentAssignment.assignedAt)}
                {currentAssignment.dueAt ? ` · límite ${formatDate(currentAssignment.dueAt)}` : ''}
              </p>
              <p>
                Conflicto:{' '}
                <strong>{currentAssignment.conflictDeclared ? 'Declarado' : 'No declarado'}</strong>
              </p>
            </div>
          ) : (
            <p>Aún no existe un revisor explícitamente asignado.</p>
          )}

          {canPublish && readyData.submissionStatusCode === 'SUBMITTED' ? (
            <div className="editorial-review__form">
              <label>
                Revisor
                <select value={reviewerId} onChange={(event) => setReviewerId(event.target.value)}>
                  <option value="">Selecciona una cuenta elegible</option>
                  {eligibleReviewers.map((candidate) => (
                    <option key={candidate.accountId} value={candidate.accountId}>
                      {candidate.label}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                Fecha límite opcional
                <input
                  type="date"
                  value={dueAt}
                  onChange={(event) => setDueAt(event.target.value)}
                />
              </label>

              <label>
                Motivo de asignación
                <textarea
                  value={assignmentReason}
                  onChange={(event) => setAssignmentReason(event.target.value)}
                  placeholder="Explica por qué esta persona revisará el paquete."
                />
              </label>

              <button
                type="button"
                className="editorial-review__button"
                disabled={!reviewerId || !assignmentReason.trim() || mutation?.phase === 'saving'}
                onClick={() => void assignReviewer()}
              >
                Asignar revisor
              </button>
            </div>
          ) : null}

          {canReview &&
          readyData.actorIsCurrentReviewer &&
          !readyData.currentReviewerHasConflict &&
          readyData.submissionStatusCode === 'SUBMITTED' ? (
            <div className="editorial-review__form editorial-review__conflict">
              <label>
                Motivo del conflicto
                <textarea
                  value={conflictReason}
                  onChange={(event) => setConflictReason(event.target.value)}
                  placeholder="Describe el conflicto. Declararlo bloquea tu decisión y no se puede deshacer."
                />
              </label>
              <button
                type="button"
                className="editorial-review__button editorial-review__button--secondary"
                disabled={!conflictReason.trim() || mutation?.phase === 'saving'}
                onClick={() => void declareConflict()}
              >
                Declarar conflicto de interés
              </button>
            </div>
          ) : null}

          {readyData.assignments.length > 0 ? (
            <>
              <h3>Historial de asignación</h3>
              <ol className="editorial-review__history">
                {readyData.assignments.map((assignment) => (
                  <li key={assignment.assignmentId}>
                    {assignment.reviewerLabel} · {formatDate(assignment.assignedAt)}
                    {assignment.conflictDeclared ? ' · conflicto declarado' : ''}
                  </li>
                ))}
              </ol>
            </>
          ) : null}
        </section>

        <section className="editorial-review__panel" aria-labelledby="review-decision-title">
          <h2 id="review-decision-title">4. Decisión append-only</h2>

          {readyData.decisions.length ? (
            <div className="editorial-review__decision-history">
              {readyData.decisions.map((decision) => (
                <div key={decision.decisionId}>
                  <strong>{decision.decisionCode}</strong>
                  <span>{formatDate(decision.decidedAt)}</span>
                  <p>{decision.reason}</p>
                </div>
              ))}
            </div>
          ) : (
            <p>No existe una decisión final para esta presentación.</p>
          )}

          {canReview &&
          readyData.actorIsCurrentReviewer &&
          !readyData.currentReviewerHasConflict &&
          readyData.submissionStatusCode === 'SUBMITTED' &&
          readyData.decisions.length === 0 ? (
            <div className="editorial-review__form">
              <label>
                Motivo de la decisión
                <textarea
                  value={decisionReason}
                  onChange={(event) => setDecisionReason(event.target.value)}
                  placeholder="Si rechazas, indica exactamente qué debe corregirse y cómo volver a revisión."
                />
              </label>

              {!preparedDecision ? (
                <div className="editorial-review__decision-actions">
                  <button
                    type="button"
                    className="editorial-review__button"
                    disabled={!readyData.checklist.readyForApproval || !decisionReason.trim()}
                    onClick={() => setPreparedDecision('APPROVED')}
                  >
                    Preparar aprobación
                  </button>
                  <button
                    type="button"
                    className="editorial-review__button editorial-review__button--secondary"
                    disabled={!decisionReason.trim()}
                    onClick={() => setPreparedDecision('REJECTED')}
                  >
                    Preparar rechazo
                  </button>
                </div>
              ) : (
                <div
                  className="editorial-review__confirm"
                  role="group"
                  aria-labelledby="review-confirm-title"
                >
                  <h3 id="review-confirm-title">
                    Confirmar {preparedDecision === 'APPROVED' ? 'aprobación' : 'rechazo'}
                  </h3>
                  <p>
                    Esta acción registra una decisión final append-only. No crea publication ni
                    publication_component.
                  </p>
                  <div className="editorial-review__decision-actions">
                    <button
                      type="button"
                      className="editorial-review__button"
                      disabled={mutation?.phase === 'saving'}
                      onClick={() => void confirmDecision()}
                    >
                      Confirmar decisión
                    </button>
                    <button
                      type="button"
                      className="editorial-review__button editorial-review__button--secondary"
                      onClick={() => setPreparedDecision(null)}
                    >
                      Volver
                    </button>
                  </div>
                </div>
              )}
            </div>
          ) : null}

          <p className="editorial-review__boundary">
            <strong>Frontera:</strong> BL-MVP-049 termina en APPROVED/REJECTED. La acción «Publicar»
            no existe todavía en esta pantalla.
          </p>
        </section>
      </div>
    </article>
  );
}
