import { useEffect, useMemo, useRef, useState } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { AppLink } from '../../app/router/navigation';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import './compatible-package.css';

const client = createHttpClient();

type Candidate = {
  componentKind: 'LYRICS' | 'TIMING' | 'TRANSLATION' | 'ANALYSIS' | 'EXERCISE';
  revisionId: string;
  revisionNo: number;
  statusCode: string;
  checksumSha256: string;
  sourceLyricsRevisionId: string;
  label: string;
  preview: string | null;
  eligible: boolean;
  issues: string[];
};

type Selection = {
  lyricsRevisionId: string | null;
  timingRevisionId: string | null;
  translationRevisionId: string | null;
  analysisRevisionId: string | null;
  exerciseRevisionIds: string[];
};

type Checklist = {
  hasLyrics: boolean;
  hasTiming: boolean;
  hasTranslation: boolean;
  hasAnalysis: boolean;
  hasExercise: boolean;
  sourcesCompatible: boolean;
  exercisesEligible: boolean;
  hasActiveRights: boolean;
  hasBrokenLinks: boolean;
  packageChecksumCurrent: boolean;
  readyForFreeze: boolean;
  issues: string[];
};

type SubmissionSnapshot = {
  recordingId: string;
  exists: boolean;
  packageId: string | null;
  packageNo: number | null;
  packageStatusCode: string | null;
  packageVersion: number;
  packageChecksumSha256: string | null;
  frozenAt: string | null;
  submissionId: string | null;
  submissionStatusCode: string | null;
  submittedAt: string | null;
  checklistVersion: string | null;
  eTag: string;
  message: string;
};

type Snapshot = {
  recordingId: string;
  catalogVersion: number;
  packageId: string | null;
  packageNo: number | null;
  statusCode: string;
  version: number;
  checksumSha256: string | null;
  eTag: string;
  selection: Selection;
  candidates: Candidate[];
  checklist: Checklist;
  message: string;
  latestSubmission?: SubmissionSnapshot;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type PageState =
  | { phase: 'loading' }
  | { phase: 'ready'; data: Snapshot }
  | { phase: 'failed'; problem: ClientProblem };

type Draft = {
  lyricsRevisionId: string;
  timingRevisionId: string;
  translationRevisionId: string;
  analysisRevisionId: string;
  exerciseRevisionIds: string[];
  reason: string;
};

export type CompatiblePackagePageProps = {
  recordingId: string;
};

const emptyDraft: Draft = {
  lyricsRevisionId: '',
  timingRevisionId: '',
  translationRevisionId: '',
  analysisRevisionId: '',
  exerciseRevisionIds: [],
  reason: '',
};

function draftFrom(snapshot: Snapshot): Draft {
  return {
    lyricsRevisionId: snapshot.selection.lyricsRevisionId ?? '',
    timingRevisionId: snapshot.selection.timingRevisionId ?? '',
    translationRevisionId: snapshot.selection.translationRevisionId ?? '',
    analysisRevisionId: snapshot.selection.analysisRevisionId ?? '',
    exerciseRevisionIds: snapshot.selection.exerciseRevisionIds,
    reason: '',
  };
}

function displayCode(value: string | null) {
  return value ? value.replaceAll('_', ' ') : 'Pendiente';
}

function shortChecksum(value: string | null) {
  return value ? `${value.slice(0, 16)}…` : '—';
}

function formatDate(value: string | null) {
  if (!value) return '—';

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('es-CR');
}

function sameSelection(selection: Selection, draft: Draft) {
  const savedExercises = [...selection.exerciseRevisionIds].sort();
  const draftExercises = [...draft.exerciseRevisionIds].sort();

  return (
    (selection.lyricsRevisionId ?? '') === draft.lyricsRevisionId &&
    (selection.timingRevisionId ?? '') === draft.timingRevisionId &&
    (selection.translationRevisionId ?? '') === draft.translationRevisionId &&
    (selection.analysisRevisionId ?? '') === draft.analysisRevisionId &&
    savedExercises.length === draftExercises.length &&
    savedExercises.every((value, index) => value === draftExercises[index])
  );
}

export function CompatiblePackagePage({ recordingId }: CompatiblePackagePageProps) {
  const access = useVisibleAccess();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [etag, setEtag] = useState('');
  const [latestSubmission, setLatestSubmission] = useState<SubmissionSnapshot | null>(null);
  const [submitReason, setSubmitReason] = useState('');
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [submitMutation, setSubmitMutation] = useState<MutationState | null>(null);

  const canSubmit = access.capabilities.includes('EDITORIAL.SUBMIT');

  async function readCurrent(signal?: AbortSignal) {
    return client.get<Snapshot>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/compatible-package`,
      {
        cacheMode: 'no-store',
        retry: 'safe',
        ...(signal ? { signal } : {}),
      },
    );
  }

  function acceptSnapshot(snapshot: Snapshot, responseEtag?: string | null) {
    setState({ phase: 'ready', data: snapshot });
    setDraft(draftFrom(snapshot));
    setEtag(responseEtag ?? snapshot.eTag);
    setLatestSubmission(snapshot.latestSubmission?.exists ? snapshot.latestSubmission : null);
  }

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await readCurrent(controller.signal);

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      acceptSnapshot(result.data, result.etag);
    };

    void load();
    return () => controller.abort();
  }, [recordingId]);

  const data = state.phase === 'ready' ? state.data : null;
  const candidates = data?.candidates ?? [];

  const byKind = (kind: Candidate['componentKind']) =>
    candidates.filter((candidate) => candidate.componentKind === kind);

  const selectedLyricsId = draft.lyricsRevisionId;

  const compatibleCandidates = useMemo(
    () =>
      candidates.filter(
        (candidate) =>
          candidate.componentKind === 'LYRICS' ||
          !selectedLyricsId ||
          candidate.sourceLyricsRevisionId === selectedLyricsId,
      ),
    [candidates, selectedLyricsId],
  );

  const compatibleByKind = (kind: Candidate['componentKind']) =>
    compatibleCandidates.filter(
      (candidate) => candidate.componentKind === kind && candidate.eligible,
    );

  const exerciseCandidates = byKind('EXERCISE');

  function changeLyrics(value: string) {
    setDraft((current) => ({
      ...current,
      lyricsRevisionId: value,
      timingRevisionId: '',
      translationRevisionId: '',
      analysisRevisionId: '',
      exerciseRevisionIds: [],
    }));
    setProblem(null);
  }

  function toggleExercise(id: string) {
    setDraft((current) => ({
      ...current,
      exerciseRevisionIds: current.exerciseRevisionIds.includes(id)
        ? current.exerciseRevisionIds.filter((candidate) => candidate !== id)
        : [...current.exerciseRevisionIds, id],
    }));
    setProblem(null);
  }

  const complete =
    Boolean(draft.lyricsRevisionId) &&
    Boolean(draft.timingRevisionId) &&
    Boolean(draft.translationRevisionId) &&
    Boolean(draft.analysisRevisionId) &&
    draft.exerciseRevisionIds.length > 0 &&
    Boolean(draft.reason.trim());

  const hasUnsavedSelection = data ? !sameSelection(data.selection, draft) : false;

  const currentWasSubmitted =
    Boolean(data?.packageId) &&
    latestSubmission?.exists === true &&
    latestSubmission.packageId === data?.packageId;

  const canSubmitCurrent =
    canSubmit &&
    Boolean(data?.packageId) &&
    data?.checklist.readyForFreeze === true &&
    !hasUnsavedSelection &&
    !currentWasSubmitted &&
    submitReason.trim().length >= 3;

  async function save() {
    if (!complete || !etag || currentWasSubmitted) return;

    setProblem(null);

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, Snapshot>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/compatible-package`,
      {
        lyricsRevisionId: draft.lyricsRevisionId,
        timingRevisionId: draft.timingRevisionId,
        translationRevisionId: draft.translationRevisionId,
        analysisRevisionId: draft.analysisRevisionId,
        exerciseRevisionIds: draft.exerciseRevisionIds,
        reason: draft.reason.trim(),
      },
      {
        headers: { [csrf.data.headerName]: csrf.data.requestToken },
        ifMatch: etag,
        retry: 'never',
        invalidate: [
          `/editorial/song-drafts/${encodeURIComponent(recordingId)}/compatible-package`,
        ],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setState({ phase: 'ready', data: result.data });
    setDraft(draftFrom(result.data));
    setEtag(result.etag ?? result.data.eTag);
  }

  async function submitForReview() {
    if (!data?.packageId || !canSubmitCurrent || !etag) return;

    setProblem(null);

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return;
    }

    const result = await client.post<Record<string, unknown>, SubmissionSnapshot>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/compatible-package/submit`,
      { reason: submitReason.trim() },
      {
        headers: { [csrf.data.headerName]: csrf.data.requestToken },
        ifMatch: etag,
        retry: 'never',
        invalidate: [
          `/editorial/song-drafts/${encodeURIComponent(recordingId)}/compatible-package`,
        ],
        onStateChange: setSubmitMutation,
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    setLatestSubmission(result.data);
    setSubmitReason('');

    const refreshed = await readCurrent();
    if (refreshed.ok) {
      acceptSnapshot(refreshed.data, refreshed.etag);
    }
  }

  return (
    <article className="route-surface compatible-package" data-route-id="UI-MVP-026">
      <header className="compatible-package__header">
        <div>
          <p className="eyebrow">BL-MVP-047 + BL-MVP-048 + BL-MVP-079 · UI-MVP-026</p>
          <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
            Paquete educativo compatible
          </h1>
          <p className="compatible-package__lead">
            Reúne revisiones exactas, comprueba compatibilidad y, cuando todo esté listo, congela el
            conjunto para revisión. Congelar no publica la canción.
          </p>
        </div>
        <AppLink href={`/editorial/canciones/${encodeURIComponent(recordingId)}`}>
          Volver al expediente
        </AppLink>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando compatibilidad"
          description="Leyendo revisiones exactas y verificando enlaces sin modificar el paquete."
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
          <section className="compatible-package__status" aria-labelledby="package-status-title">
            <div className="compatible-package__status-copy">
              <p className="eyebrow">BORRADOR ACTUAL</p>
              <h2 id="package-status-title">
                {data.packageNo ? `Paquete ${data.packageNo}` : 'Nuevo paquete'}
              </h2>
              <p>{data.message}</p>
              {hasUnsavedSelection ? (
                <p className="compatible-package__notice" role="status">
                  Tienes cambios sin guardar. El checklist refleja el último DRAFT confirmado.
                </p>
              ) : null}
            </div>
            <dl>
              <div>
                <dt>Estado</dt>
                <dd>{displayCode(data.statusCode)}</dd>
              </div>
              <div>
                <dt>Catálogo</dt>
                <dd>v{data.catalogVersion}</dd>
              </div>
              <div>
                <dt>Paquete</dt>
                <dd>{data.version ? `v${data.version}` : '—'}</dd>
              </div>
              <div>
                <dt>Checksum</dt>
                <dd>
                  <code>{shortChecksum(data.checksumSha256)}</code>
                </dd>
              </div>
            </dl>
          </section>

          <div className="compatible-package__workspace">
            <form
              className="compatible-package__form"
              onSubmit={(event) => {
                event.preventDefault();
                void save();
              }}
            >
              <fieldset disabled={currentWasSubmitted}>
                <legend>
                  <span>1</span>
                  Fija la revisión japonesa
                </legend>
                <label>
                  Letra exacta
                  <select
                    value={draft.lyricsRevisionId}
                    onChange={(event) => changeLyrics(event.target.value)}
                  >
                    <option value="">Selecciona una revisión</option>
                    {byKind('LYRICS')
                      .filter((candidate) => candidate.eligible)
                      .map((candidate) => (
                        <option key={candidate.revisionId} value={candidate.revisionId}>
                          {candidate.label} · {displayCode(candidate.statusCode)}
                        </option>
                      ))}
                  </select>
                </label>
                <p className="compatible-package__help">
                  Si cambias la letra, las dependencias se limpian para impedir mezclas de
                  revisiones.
                </p>
              </fieldset>

              <fieldset disabled={!draft.lyricsRevisionId || currentWasSubmitted}>
                <legend>
                  <span>2</span>
                  Elige dependencias compatibles
                </legend>
                {(
                  [
                    ['TIMING', 'Sincronización', 'timingRevisionId'],
                    ['TRANSLATION', 'Traducción', 'translationRevisionId'],
                    ['ANALYSIS', 'Análisis', 'analysisRevisionId'],
                  ] as const
                ).map(([kind, label, field]) => (
                  <label key={kind}>
                    {label}
                    <select
                      value={draft[field]}
                      onChange={(event) =>
                        setDraft((current) => ({ ...current, [field]: event.target.value }))
                      }
                    >
                      <option value="">Selecciona una revisión</option>
                      {compatibleByKind(kind).map((candidate) => (
                        <option key={candidate.revisionId} value={candidate.revisionId}>
                          {candidate.label} · {displayCode(candidate.statusCode)}
                        </option>
                      ))}
                    </select>
                  </label>
                ))}
              </fieldset>

              <fieldset
                className="compatible-package__step--wide"
                disabled={!draft.lyricsRevisionId || currentWasSubmitted}
              >
                <legend>
                  <span>3</span>
                  Elige ejercicios válidos
                </legend>
                <p className="compatible-package__help">
                  Solo puedes marcar ejercicios P0 compatibles con la letra exacta.{' '}
                  <span>La aprobación es específica de este paquete.</span> No reescribe la revisión
                  fuente. Los bloqueos se muestran aquí mismo para que sepas qué corregir.
                </p>
                <ul className="compatible-package__exercises">
                  {exerciseCandidates.length === 0 ? (
                    <li>No existen revisiones de ejercicio para esta grabación.</li>
                  ) : (
                    exerciseCandidates.map((candidate) => {
                      const sourceMatches =
                        candidate.sourceLyricsRevisionId === draft.lyricsRevisionId;
                      const canChoose = candidate.eligible && sourceMatches;

                      return (
                        <li key={candidate.revisionId}>
                          <label>
                            <input
                              type="checkbox"
                              checked={draft.exerciseRevisionIds.includes(candidate.revisionId)}
                              disabled={!canChoose}
                              onChange={() => toggleExercise(candidate.revisionId)}
                            />
                            <span>
                              <strong>{candidate.label}</strong>
                              <span>{candidate.preview ?? 'Vista previa no disponible.'}</span>
                            </span>
                          </label>
                          {!sourceMatches && draft.lyricsRevisionId ? (
                            <p role="status">Fuente incompatible con la letra seleccionada.</p>
                          ) : null}
                          {candidate.issues.length > 0 ? (
                            <ul aria-label={`Bloqueos de ${candidate.label}`}>
                              {candidate.issues.map((issue) => (
                                <li key={issue}>{issue}</li>
                              ))}
                            </ul>
                          ) : (
                            <p>Validación P0 superada; puede entrar en este paquete.</p>
                          )}
                        </li>
                      );
                    })
                  )}
                </ul>
              </fieldset>

              <fieldset className="compatible-package__step--wide" disabled={currentWasSubmitted}>
                <legend>
                  <span>4</span>
                  Guarda el borrador
                </legend>
                <label>
                  Motivo del guardado
                  <textarea
                    value={draft.reason}
                    maxLength={1000}
                    rows={3}
                    onChange={(event) =>
                      setDraft((current) => ({ ...current, reason: event.target.value }))
                    }
                    placeholder="Ej.: componentes comprobados contra la misma letra y ejercicio validado."
                  />
                </label>
                <Button type="submit" disabled={!complete || mutation?.phase === 'saving'}>
                  {mutation?.phase === 'saving'
                    ? 'Guardando paquete…'
                    : 'Guardar paquete compatible'}
                </Button>
              </fieldset>
            </form>

            <aside
              className="compatible-package__sidebar"
              aria-label="Estado y acciones del paquete"
            >
              {latestSubmission ? (
                <section
                  className="compatible-package__submission-history"
                  aria-labelledby="latest-submission-title"
                >
                  <p className="eyebrow">ÚLTIMO SOMETIMIENTO</p>
                  <h2 id="latest-submission-title">
                    Paquete {latestSubmission.packageNo} sometido
                  </h2>
                  <dl>
                    <div>
                      <dt>Estado</dt>
                      <dd>{displayCode(latestSubmission.submissionStatusCode)}</dd>
                    </div>
                    <div>
                      <dt>Congelado</dt>
                      <dd>{formatDate(latestSubmission.frozenAt)}</dd>
                    </div>
                    <div>
                      <dt>Checklist</dt>
                      <dd>{latestSubmission.checklistVersion ?? '—'}</dd>
                    </div>
                    <div>
                      <dt>Checksum</dt>
                      <dd>
                        <code>{shortChecksum(latestSubmission.packageChecksumSha256)}</code>
                      </dd>
                    </div>
                  </dl>
                  <p>{latestSubmission.message}</p>
                </section>
              ) : null}

              <section
                className="compatible-package__checklist"
                aria-labelledby="package-checklist-title"
              >
                <p className="eyebrow">CHECKLIST BL-MVP-047 / 079</p>
                <h2 id="package-checklist-title">
                  {data.checklist.readyForFreeze
                    ? 'Compatible para congelar'
                    : 'Todavía tiene pendientes'}
                </h2>
                <ul className="compatible-package__checklist-grid">
                  <li>
                    <span>Componentes</span>
                    <strong>
                      {data.checklist.hasLyrics &&
                      data.checklist.hasTiming &&
                      data.checklist.hasTranslation &&
                      data.checklist.hasAnalysis
                        ? 'Completos'
                        : 'Pendientes'}
                    </strong>
                  </li>
                  <li>
                    <span>Misma fuente</span>
                    <strong>{data.checklist.sourcesCompatible ? 'Sí' : 'No'}</strong>
                  </li>
                  <li>
                    <span>Ejercicios</span>
                    <strong>{data.checklist.exercisesEligible ? 'Elegibles' : 'Pendientes'}</strong>
                  </li>
                  <li>
                    <span>Derechos</span>
                    <strong>{data.checklist.hasActiveRights ? 'Vigentes' : 'Pendientes'}</strong>
                  </li>
                  <li>
                    <span>Checksum</span>
                    <strong>
                      {data.checklist.packageChecksumCurrent ? 'Vigente' : 'Revalidar'}
                    </strong>
                  </li>
                  <li>
                    <span>Enlaces</span>
                    <strong>{data.checklist.hasBrokenLinks ? 'Revisar' : 'Sin roturas'}</strong>
                  </li>
                </ul>

                {data.checklist.issues.length > 0 ? (
                  <ul className="compatible-package__issues" aria-label="Pendientes del paquete">
                    {data.checklist.issues.map((issue) => (
                      <li key={issue}>{issue}</li>
                    ))}
                  </ul>
                ) : null}

                <p className="compatible-package__help">
                  “Compatible para congelar” no equivale a publicado.
                </p>
              </section>

              <section
                className="compatible-package__submit"
                aria-labelledby="package-submit-title"
              >
                <p className="eyebrow">BL-MVP-048 · SOMETIMIENTO</p>
                <h2 id="package-submit-title">Congelar y someter a revisión</h2>
                <p>
                  Esta acción fija las revisiones exactas y el checksum. Después, cualquier edición
                  continuará en un nuevo DRAFT. No publica contenido.
                </p>

                {canSubmit ? (
                  <>
                    <label>
                      Motivo del sometimiento
                      <textarea
                        value={submitReason}
                        maxLength={1000}
                        rows={3}
                        onChange={(event) => setSubmitReason(event.target.value)}
                        placeholder="Ej.: paquete completo, derechos vigentes y checklist revisado."
                      />
                    </label>
                    <Button
                      type="button"
                      disabled={!canSubmitCurrent || submitMutation?.phase === 'saving'}
                      onClick={() => void submitForReview()}
                    >
                      {submitMutation?.phase === 'saving'
                        ? 'Congelando paquete…'
                        : 'Congelar y someter a revisión'}
                    </Button>
                    {!data.packageId ? (
                      <p className="compatible-package__help">
                        Primero guarda una selección compatible para crear el DRAFT.
                      </p>
                    ) : !data.checklist.readyForFreeze ? (
                      <p className="compatible-package__help">
                        Resuelve el checklist antes de congelar.
                      </p>
                    ) : hasUnsavedSelection ? (
                      <p className="compatible-package__help">
                        Guarda tus cambios antes de someter.
                      </p>
                    ) : null}
                  </>
                ) : (
                  <p className="compatible-package__help">
                    Puedes inspeccionar el paquete, pero necesitas EDITORIAL.SUBMIT para someterlo.
                  </p>
                )}
              </section>

              {problem ? (
                <StateMessage
                  state="UI-EST-04"
                  title={problem.summary}
                  description={problem.correction}
                />
              ) : null}
            </aside>
          </div>
        </>
      ) : null}
    </article>
  );
}
