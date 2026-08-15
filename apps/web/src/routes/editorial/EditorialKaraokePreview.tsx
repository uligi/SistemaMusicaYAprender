import { useEffect, useMemo, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import type { LocalSynchronizationSnapshot } from '../../features/player/synchronization/LocalSynchronizationEngine';
import type { SynchronizationTimeline } from '../../features/player/synchronization/LocalSynchronizationEngine';
import { SynchronizedYouTubePreview } from '../../features/player/synchronization/SynchronizedYouTubePreview';
import {
  EducationalKaraoke,
  defaultVisibleEducationalLayers,
  type EducationalLayers,
  type VisibleEducationalLayers,
} from '../student/EducationalKaraoke';
import './editorial-karaoke-preview.css';

const client = createHttpClient();

type PreviewSource = {
  sourceId: string;
  providerCode: string;
  externalRef: string;
  statusCode: string;
};

type EditorialKaraokePreviewData = {
  previewMode: string;
  providerCode: string;
  externalRef: string;
  lyricsRevisionNo: number;
  lyricsStatusCode: string;
  timingStatusCode: string;
  translationStatusCode: string;
  analysisStatusCode: string;
  timeline: SynchronizationTimeline;
  layers: EducationalLayers;
};

type PreviewState =
  | { phase: 'idle' }
  | { phase: 'loading' }
  | { phase: 'ready'; data: EditorialKaraokePreviewData }
  | { phase: 'failed'; problem: ClientProblem };

export type EditorialKaraokePreviewProps = {
  recordingId: string;
  sources: PreviewSource[];
};

const emptySnapshot: LocalSynchronizationSnapshot = {
  positionMs: 0,
  level: 'NONE',
  line: null,
  token: null,
};

function statusLabel(value: string) {
  if (value === 'MISSING') return 'No disponible';
  if (value === 'STALE') return 'Desactualizada';
  return value.replaceAll('_', ' ');
}

export function EditorialKaraokePreview({ recordingId, sources }: EditorialKaraokePreviewProps) {
  const youtubeSources = useMemo(
    () => sources.filter((source) => source.providerCode === 'YOUTUBE'),
    [sources],
  );
  const [selectedSourceId, setSelectedSourceId] = useState(youtubeSources[0]?.sourceId ?? '');
  const [reloadKey, setReloadKey] = useState(0);
  const [state, setState] = useState<PreviewState>({ phase: 'idle' });
  const [snapshot, setSnapshot] = useState<LocalSynchronizationSnapshot>(emptySnapshot);
  const [visibleLayers, setVisibleLayers] = useState<VisibleEducationalLayers>({
    ...defaultVisibleEducationalLayers,
  });

  useEffect(() => {
    if (youtubeSources.length === 0) {
      setSelectedSourceId('');
      return;
    }

    if (!youtubeSources.some((source) => source.sourceId === selectedSourceId)) {
      setSelectedSourceId(youtubeSources[0]!.sourceId);
    }
  }, [selectedSourceId, youtubeSources]);

  useEffect(() => {
    if (!selectedSourceId) {
      setState({ phase: 'idle' });
      return;
    }

    const controller = new AbortController();

    const load = async () => {
      setState({ phase: 'loading' });
      setSnapshot(emptySnapshot);
      setVisibleLayers({ ...defaultVisibleEducationalLayers });

      const params = new URLSearchParams({
        sourceId: selectedSourceId,
        language: 'es',
      });

      const result = await client.get<EditorialKaraokePreviewData>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/karaoke-preview?${params.toString()}`,
        {
          cacheMode: 'no-store',
          retry: 'safe',
          signal: controller.signal,
        },
      );

      if (result.kind === 'cancelled') return;

      setState(
        result.ok
          ? { phase: 'ready', data: result.data }
          : { phase: 'failed', problem: result.problem },
      );
    };

    void load();
    return () => controller.abort();
  }, [recordingId, reloadKey, selectedSourceId]);

  if (youtubeSources.length === 0) {
    return (
      <section className="editorial-karaoke-preview" data-editorial-karaoke-preview>
        <StateMessage
          state="UI-EST-12"
          title="Sin fuente de YouTube"
          description="Agrega una fuente de YouTube a la grabación para poder probar el karaoke sin publicar."
        />
      </section>
    );
  }

  return (
    <section
      className="editorial-karaoke-preview"
      aria-labelledby="editorial-karaoke-preview-title"
      data-editorial-karaoke-preview
    >
      <header className="editorial-karaoke-preview__header">
        <div>
          <p className="eyebrow">VISTA PREVIA EDITORIAL · NO PUBLICA</p>
          <h2 id="editorial-karaoke-preview-title">Previsualización de Karaoke</h2>
          <p>
            Prueba el reproductor educativo con las revisiones DRAFT compatibles. Esta vista no crea
            una publicación, no necesita slug público y no consulta el catálogo público.
          </p>
        </div>

        <div className="editorial-karaoke-preview__actions">
          <label>
            <span>Fuente de YouTube</span>
            <select
              aria-label="Fuente para previsualización de karaoke"
              value={selectedSourceId}
              onChange={(event) => setSelectedSourceId(event.target.value)}
            >
              {youtubeSources.map((source) => (
                <option key={source.sourceId} value={source.sourceId}>
                  {source.externalRef} · {statusLabel(source.statusCode)}
                </option>
              ))}
            </select>
          </label>

          <button type="button" onClick={() => setReloadKey((current) => current + 1)}>
            Actualizar previsualización
          </button>
        </div>
      </header>

      {state.phase === 'loading' ? (
        <StateMessage
          state="UI-EST-01"
          title="Preparando karaoke"
          description="Comprobando letra, tiempos, traducción y lecturas de la misma revisión editorial."
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
          <dl className="editorial-karaoke-preview__status">
            <div>
              <dt>Letra</dt>
              <dd>
                Revisión {state.data.lyricsRevisionNo || '—'} ·{' '}
                {statusLabel(state.data.lyricsStatusCode)}
              </dd>
            </div>
            <div>
              <dt>Sincronización</dt>
              <dd>{statusLabel(state.data.timingStatusCode)}</dd>
            </div>
            <div>
              <dt>Traducción</dt>
              <dd>{statusLabel(state.data.translationStatusCode)}</dd>
            </div>
            <div>
              <dt>Lecturas</dt>
              <dd>{statusLabel(state.data.analysisStatusCode)}</dd>
            </div>
          </dl>

          <div className="editorial-karaoke-preview__workspace">
            <div className="editorial-karaoke-preview__player">
              <SynchronizedYouTubePreview
                externalRef={state.data.externalRef}
                title={`Previsualización editorial ${state.data.externalRef}`}
                timeline={state.data.timeline}
                headingLevel={3}
                presentation="learning"
                onSnapshotChange={setSnapshot}
              />
            </div>

            <div className="editorial-karaoke-preview__lyrics">
              <EducationalKaraoke
                layers={state.data.layers}
                snapshot={snapshot}
                visibleLayers={visibleLayers}
                onVisibleLayersChange={setVisibleLayers}
              />
            </div>
          </div>

          <p className="editorial-karaoke-preview__notice" role="status">
            Estás viendo borradores editoriales. Nada en esta previsualización se considera
            publicado.
          </p>
        </>
      ) : null}
    </section>
  );
}
