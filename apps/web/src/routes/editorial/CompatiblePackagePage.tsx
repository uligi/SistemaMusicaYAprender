import { useEffect, useMemo, useRef, useState } from 'react';
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

function displayCode(value: string) {
  return value.replaceAll('_', ' ');
}

export function CompatiblePackagePage({ recordingId }: CompatiblePackagePageProps) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [state, setState] = useState<PageState>({ phase: 'loading' });
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [etag, setEtag] = useState('');
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [mutation, setMutation] = useState<MutationState | null>(null);

  useEffect(() => {
    headingRef.current?.focus();
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<Snapshot>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/compatible-package`,
        { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
      );

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setState({ phase: 'failed', problem: result.problem });
        return;
      }

      setState({ phase: 'ready', data: result.data });
      setDraft(draftFrom(result.data));
      setEtag(result.etag ?? result.data.eTag);
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

  async function save() {
    if (!complete || !etag) return;

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

  return (
    <article className="route-surface compatible-package" data-route-id="UI-MVP-026">
      <header className="compatible-package__header">
        <p className="eyebrow">BL-MVP-047 + BL-MVP-079 · UI-MVP-026</p>
        <h1 className="route-title" id="route-title" ref={headingRef} tabIndex={-1}>
          Paquete educativo compatible
        </h1>
        <p>
          Elige revisiones exactas. El sistema no sustituye una referencia por “la última” y no
          publica contenido: BL-MVP-048, 049 y 050 conservan congelación, revisión y publicación
          final.
        </p>
        <AppLink href={`/editorial/canciones/${encodeURIComponent(recordingId)}/ejercicios`}>
          Volver al banco de ejercicios
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
            <div>
              <p className="eyebrow">PAQUETE DRAFT</p>
              <h2 id="package-status-title">
                {data.packageNo ? `Paquete ${data.packageNo}` : 'Todavía no creado'}
              </h2>
              <p>{data.message}</p>
            </div>
            <dl>
              <div>
                <dt>Estado</dt>
                <dd>{displayCode(data.statusCode)}</dd>
              </div>
              <div>
                <dt>Catálogo</dt>
                <dd>versión {data.catalogVersion}</dd>
              </div>
              <div>
                <dt>Paquete</dt>
                <dd>versión {data.version || '—'}</dd>
              </div>
              <div>
                <dt>Checksum</dt>
                <dd>
                  <code>{data.checksumSha256 ? `${data.checksumSha256.slice(0, 16)}…` : '—'}</code>
                </dd>
              </div>
            </dl>
          </section>

          <form
            className="compatible-package__form"
            onSubmit={(event) => {
              event.preventDefault();
              void save();
            }}
          >
            <fieldset>
              <legend>1. Fija la revisión japonesa</legend>
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
              <p>Al cambiar la letra se limpian las dependencias para evitar mezclar revisiones.</p>
            </fieldset>

            <fieldset disabled={!draft.lyricsRevisionId}>
              <legend>2. Elige dependencias compatibles</legend>
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

            <fieldset disabled={!draft.lyricsRevisionId}>
              <legend>3. Aprueba ejercicios para este paquete</legend>
              <p>
                La aprobación es específica de esta selección de paquete. La revisión fuente no se
                reescribe.
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
                          <p>Validación P0 superada; puede aprobarse para este paquete.</p>
                        )}
                      </li>
                    );
                  })
                )}
              </ul>
            </fieldset>

            <fieldset>
              <legend>4. Motivo y guardado</legend>
              <label>
                Motivo trazable
                <textarea
                  value={draft.reason}
                  maxLength={1000}
                  rows={3}
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, reason: event.target.value }))
                  }
                  placeholder="Ej.: componentes revisados contra la misma letra y ejercicio validado."
                />
              </label>
              <Button type="submit" disabled={!complete || mutation?.phase === 'saving'}>
                {mutation?.phase === 'saving' ? 'Guardando paquete…' : 'Guardar paquete compatible'}
              </Button>
            </fieldset>
          </form>

          {problem ? (
            <StateMessage
              state="UI-EST-04"
              title={problem.summary}
              description={problem.correction}
            />
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
            <ul>
              <li>
                Letra, tiempos, traducción y análisis:{' '}
                <strong>
                  {data.checklist.hasLyrics &&
                  data.checklist.hasTiming &&
                  data.checklist.hasTranslation &&
                  data.checklist.hasAnalysis
                    ? 'completos'
                    : 'pendientes'}
                </strong>
              </li>
              <li>
                Misma revisión fuente:{' '}
                <strong>{data.checklist.sourcesCompatible ? 'sí' : 'no'}</strong>
              </li>
              <li>
                Ejercicios elegibles:{' '}
                <strong>{data.checklist.exercisesEligible ? 'sí' : 'no'}</strong>
              </li>
              <li>
                Derechos vigentes: <strong>{data.checklist.hasActiveRights ? 'sí' : 'no'}</strong>
              </li>
              <li>
                Integridad del checksum:{' '}
                <strong>
                  {data.checklist.packageChecksumCurrent ? 'vigente' : 'requiere revalidación'}
                </strong>
              </li>
              <li>
                Enlaces rotos:{' '}
                <strong>{data.checklist.hasBrokenLinks ? 'detectados' : 'ninguno'}</strong>
              </li>
            </ul>

            {data.checklist.issues.length > 0 ? (
              <ul className="compatible-package__issues" aria-label="Pendientes del paquete">
                {data.checklist.issues.map((issue) => (
                  <li key={issue}>{issue}</li>
                ))}
              </ul>
            ) : null}

            <p>
              “Compatible para congelar” no equivale a publicado. El siguiente incremento congelará
              componentes y checksum antes de someterlos.
            </p>
          </section>
        </>
      ) : null}
    </article>
  );
}
