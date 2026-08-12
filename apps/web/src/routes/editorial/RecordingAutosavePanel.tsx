import { useCallback, useState } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ApiResult } from '../../data/http/types';
import { useEditorialAutosave } from './useEditorialAutosave';
import './recording-autosave.css';

const client = createHttpClient();

type RecordingDraftSnapshot = {
  recordingId: string;
  sourceId: string;
  recordingTitle: string | null;
  recordingDurationMs: number | null;
  sourceDurationMs: number | null;
  offsetMs: number;
  recordingStatusCode: string;
  sourceStatusCode: string;
  recordingVersion: number;
  sourceVersion: number;
};

type EditableRecordingDraft = {
  recordingTitle: string;
  recordingDurationMs: string;
  sourceDurationMs: string;
  offsetMs: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

export type RecordingAutosavePanelProps = {
  recordingId: string;
};

function editable(snapshot: RecordingDraftSnapshot): EditableRecordingDraft {
  return {
    recordingTitle: snapshot.recordingTitle ?? '',
    recordingDurationMs: snapshot.recordingDurationMs?.toString() ?? '',
    sourceDurationMs: snapshot.sourceDurationMs?.toString() ?? '',
    offsetMs: snapshot.offsetMs.toString(),
  };
}

function integerOrNull(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const parsed = Number.parseInt(trimmed, 10);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function requestBody(draft: EditableRecordingDraft) {
  return {
    recordingTitle: draft.recordingTitle.trim() || null,
    recordingDurationMs: integerOrNull(draft.recordingDurationMs),
    sourceDurationMs: integerOrNull(draft.sourceDurationMs),
    offsetMs: integerOrNull(draft.offsetMs) ?? 0,
  };
}

function valueLabel(value: string) {
  return value.trim() || 'Sin valor';
}

export function RecordingAutosavePanel({ recordingId }: RecordingAutosavePanelProps) {
  const access = useVisibleAccess();
  const canEdit = access.capabilities.includes('EDITORIAL.DRAFT');

  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [draft, setDraft] = useState<EditableRecordingDraft | null>(null);
  const [serverDraft, setServerDraft] = useState<EditableRecordingDraft | null>(null);
  const [serverEtag, setServerEtag] = useState<string | null>(null);
  const [loadError, setLoadError] = useState('');

  const save = useCallback(
    async (
      value: EditableRecordingDraft,
      etag: string,
      signal: AbortSignal,
    ): Promise<ApiResult<RecordingDraftSnapshot>> => {
      const csrf = await client.get<Csrf>('/auth/csrf', {
        cacheMode: 'no-store',
        retry: 'never',
        signal,
      });

      if (!csrf.ok) {
        return csrf;
      }

      return client.put<ReturnType<typeof requestBody>, RecordingDraftSnapshot>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/autosave`,
        requestBody(value),
        {
          headers: {
            [csrf.data.headerName]: csrf.data.requestToken,
          },
          ifMatch: etag,
          retry: 'never',
          signal,
        },
      );
    },
    [recordingId],
  );

  const autosave = useEditorialAutosave<EditableRecordingDraft, RecordingDraftSnapshot>({
    save,
    delayMs: 800,
  });

  const loadServer = useCallback(async () => {
    const result = await client.get<RecordingDraftSnapshot>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/autosave`,
      {
        cacheMode: 'no-store',
        retry: 'never',
      },
    );

    if (!result.ok || !result.etag) {
      return null;
    }

    return {
      draft: editable(result.data),
      etag: result.etag,
    };
  }, [recordingId]);

  async function openEditor() {
    setOpen(true);
    setLoading(true);
    setLoadError('');
    setServerDraft(null);
    setServerEtag(null);

    const current = await loadServer();
    setLoading(false);

    if (!current) {
      setLoadError('No fue posible cargar la versión editable de la grabación.');
      return;
    }

    setDraft(current.draft);
    autosave.prime(current.etag);
  }

  function updateDraft(patch: Partial<EditableRecordingDraft>) {
    if (!draft) return;
    const next = {
      ...draft,
      ...patch,
    };
    setDraft(next);
    autosave.schedule(next);
  }

  async function compareWithServer() {
    const current = await loadServer();
    if (!current) {
      setLoadError('No fue posible recuperar la versión vigente para comparar.');
      return;
    }

    setServerDraft(current.draft);
    setServerEtag(current.etag);
  }

  function useServerVersion() {
    if (!serverDraft || !serverEtag) return;
    setDraft(serverDraft);
    autosave.prime(serverEtag);
    setServerDraft(null);
    setServerEtag(null);
  }

  async function retryLocalVersion() {
    if (!draft || !serverEtag) return;
    autosave.rebase(serverEtag);
    setServerDraft(null);
    setServerEtag(null);
    await autosave.flush(draft);
  }

  if (!canEdit) {
    return null;
  }

  return (
    <section className="recording-autosave" aria-labelledby="recording-autosave-title">
      <header>
        <div>
          <p className="eyebrow">BL-MVP-052 · concurrencia editorial</p>
          <h2 id="recording-autosave-title">Autoguardado de la grabación</h2>
        </div>
        {!open ? (
          <Button type="button" variant="secondary" onClick={() => void openEditor()}>
            Editar metadatos
          </Button>
        ) : null}
      </header>

      {!open ? (
        <p>
          Los cambios editables usan ETag e If-Match; una versión más reciente nunca se sobrescribe
          silenciosamente.
        </p>
      ) : null}

      {loading ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando versión editable"
          description="Recuperando el ETag confirmado antes de permitir cambios."
        />
      ) : null}

      {loadError ? (
        <StateMessage state="UI-EST-04" title="No se pudo cargar" description={loadError} />
      ) : null}

      {draft ? (
        <>
          <div className="recording-autosave__status" aria-live="polite" aria-atomic="true">
            {autosave.state.phase === 'saving' ? <strong>Guardando…</strong> : null}
            {autosave.state.phase === 'saved' ? <strong>Guardado</strong> : null}
            {autosave.state.phase === 'idle' ? <span>Cambios locales pendientes</span> : null}
          </div>

          {autosave.state.phase === 'failed' && autosave.state.problem ? (
            <StateMessage
              state="UI-EST-04"
              title={autosave.state.problem.summary}
              description={autosave.state.problem.correction}
            />
          ) : null}

          {autosave.state.phase === 'conflict' && autosave.state.problem ? (
            <StateMessage
              state="UI-EST-10"
              title="Conflicto de edición"
              description="Tus cambios permanecen locales. Compara la versión vigente antes de decidir."
            />
          ) : null}

          <div className="recording-autosave__fields">
            <Field
              id="recording-autosave-title-input"
              label="Título de la grabación"
              value={draft.recordingTitle}
              onChange={(event) => updateDraft({ recordingTitle: event.target.value })}
            />
            <Field
              id="recording-autosave-duration"
              label="Duración de la grabación (ms)"
              type="number"
              min="1"
              value={draft.recordingDurationMs}
              onChange={(event) => updateDraft({ recordingDurationMs: event.target.value })}
            />
            <Field
              id="recording-autosave-source-duration"
              label="Duración de la fuente (ms)"
              type="number"
              min="1"
              value={draft.sourceDurationMs}
              onChange={(event) => updateDraft({ sourceDurationMs: event.target.value })}
            />
            <Field
              id="recording-autosave-offset"
              label="Desplazamiento de la fuente (ms)"
              type="number"
              min="0"
              value={draft.offsetMs}
              onChange={(event) => updateDraft({ offsetMs: event.target.value })}
            />
          </div>

          {autosave.state.phase === 'conflict' ? (
            <div className="recording-autosave__conflict-actions">
              <Button type="button" variant="secondary" onClick={() => void compareWithServer()}>
                Comparar con servidor
              </Button>
            </div>
          ) : null}

          {serverDraft ? (
            <section
              className="recording-autosave__compare"
              aria-labelledby="autosave-compare-title"
            >
              <h3 id="autosave-compare-title">Comparar cambios</h3>
              <div className="recording-autosave__compare-grid">
                <div>
                  <h4>Tu versión local</h4>
                  <dl>
                    <div>
                      <dt>Título</dt>
                      <dd>{valueLabel(draft.recordingTitle)}</dd>
                    </div>
                    <div>
                      <dt>Duración grabación</dt>
                      <dd>{valueLabel(draft.recordingDurationMs)}</dd>
                    </div>
                    <div>
                      <dt>Duración fuente</dt>
                      <dd>{valueLabel(draft.sourceDurationMs)}</dd>
                    </div>
                    <div>
                      <dt>Offset</dt>
                      <dd>{valueLabel(draft.offsetMs)}</dd>
                    </div>
                  </dl>
                </div>
                <div>
                  <h4>Versión vigente del servidor</h4>
                  <dl>
                    <div>
                      <dt>Título</dt>
                      <dd>{valueLabel(serverDraft.recordingTitle)}</dd>
                    </div>
                    <div>
                      <dt>Duración grabación</dt>
                      <dd>{valueLabel(serverDraft.recordingDurationMs)}</dd>
                    </div>
                    <div>
                      <dt>Duración fuente</dt>
                      <dd>{valueLabel(serverDraft.sourceDurationMs)}</dd>
                    </div>
                    <div>
                      <dt>Offset</dt>
                      <dd>{valueLabel(serverDraft.offsetMs)}</dd>
                    </div>
                  </dl>
                </div>
              </div>
              <div className="recording-autosave__compare-actions">
                <Button type="button" variant="secondary" onClick={useServerVersion}>
                  Usar versión del servidor
                </Button>
                <Button type="button" onClick={() => void retryLocalVersion()}>
                  Aplicar mis cambios sobre la versión vigente
                </Button>
              </div>
            </section>
          ) : null}
        </>
      ) : null}
    </section>
  );
}
