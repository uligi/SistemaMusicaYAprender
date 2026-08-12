import { useCallback, useEffect, useState } from 'react';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';

type SongDraftDetails = {
  workId: string;
  recordingId: string;
  sourceId: string;
  artistId: string;
  artistName: string;
  canonicalTitle: string;
  languageTag: string;
  recordingTitle: string | null;
  recordingDurationMs: number | null;
  providerCode: string;
  externalRef: string;
  sourceDurationMs: number | null;
  offsetMs: number;
  workStatusCode: string;
  recordingStatusCode: string;
  sourceStatusCode: string;
};

const client = createHttpClient();

function problemMessage(result: unknown): string {
  if (
    typeof result === 'object' &&
    result !== null &&
    'kind' in result &&
    (result as { kind?: string }).kind === 'problem' &&
    'problem' in result
  ) {
    const problem = (
      result as {
        problem?: {
          detail?: string;
          title?: string;
        };
      }
    ).problem;

    return problem?.detail ?? problem?.title ?? 'No fue posible cargar el expediente.';
  }

  return 'No fue posible cargar el expediente.';
}

function seconds(milliseconds: number | null): string {
  return milliseconds === null ? 'No informada' : `${(milliseconds / 1000).toFixed(3)} s`;
}

export type SongDraftDetailPageProps = {
  recordingId: string;
};

export function SongDraftDetailPage({ recordingId }: SongDraftDetailPageProps) {
  const [draft, setDraft] = useState<SongDraftDetails | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(true);

  const load = useCallback(async () => {
    setBusy(true);
    setError('');

    const result = await client.get<SongDraftDetails>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}`,
      {
        cacheMode: 'no-store',
        retry: 'never',
      },
    );

    setBusy(false);

    if (!result.ok) {
      setDraft(null);
      setError(problemMessage(result));
      return;
    }

    setDraft(result.data);
  }, [recordingId]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <section className="song-draft-detail" aria-labelledby="song-draft-detail-title">
      <header className="song-draft__header">
        <p className="song-draft__eyebrow">UI-MVP-019 · Expediente de canción</p>
        <h1 id="song-draft-detail-title">Obra, grabación y fuente</h1>
        <p>
          Este expediente muestra objetos canónicos separados. Estar en DRAFT no equivale a estar
          publicado.
        </p>
      </header>

      {busy ? (
        <StateMessage
          state="UI-EST-01"
          title="Cargando expediente"
          description="Consultando el último estado confirmado."
        />
      ) : null}

      {error ? (
        <StateMessage
          state="UI-EST-04"
          title="No se pudo abrir el expediente"
          description={error}
        />
      ) : null}

      {draft ? (
        <div className="song-draft-detail__content">
          <section className="song-draft-detail__card" aria-labelledby="song-detail-work">
            <h2 id="song-detail-work">Obra</h2>
            <p>
              <strong>{draft.canonicalTitle}</strong> · <span lang="ja">{draft.languageTag}</span>
            </p>
            <p>
              ID estable: <code>{draft.workId}</code>
            </p>
            <p>Estado: {draft.workStatusCode}</p>
          </section>

          <section className="song-draft-detail__card" aria-labelledby="song-detail-recording">
            <h2 id="song-detail-recording">Grabación</h2>
            <p>{draft.recordingTitle ?? 'Sin título de versión adicional'}</p>
            <p>Duración de referencia: {seconds(draft.recordingDurationMs)}</p>
            <p>
              ID estable: <code>{draft.recordingId}</code>
            </p>
            <p>Estado: {draft.recordingStatusCode}</p>
          </section>

          <section className="song-draft-detail__card" aria-labelledby="song-detail-source">
            <h2 id="song-detail-source">Fuente de YouTube</h2>
            <p>
              {draft.providerCode} · <code>{draft.externalRef}</code>
            </p>
            <p>Duración de fuente: {seconds(draft.sourceDurationMs)}</p>
            <p>Desplazamiento: {seconds(draft.offsetMs)}</p>
            <p>
              ID estable: <code>{draft.sourceId}</code>
            </p>
            <p>Estado: {draft.sourceStatusCode}</p>
            <a
              className="ma-link"
              href={`https://www.youtube.com/watch?v=${encodeURIComponent(draft.externalRef)}`}
              target="_blank"
              rel="noreferrer"
            >
              Abrir referencia en YouTube
            </a>
          </section>

          <section className="song-draft-detail__card" aria-labelledby="song-detail-artist">
            <h2 id="song-detail-artist">Artista principal</h2>
            <p>{draft.artistName}</p>
            <p>
              ID estable: <code>{draft.artistId}</code>
            </p>
          </section>
        </div>
      ) : null}

      <div className="song-draft__actions">
        <Button type="button" variant="secondary" disabled={busy} onClick={() => void load()}>
          Volver a cargar
        </Button>
        <a className="ma-link" href="/editorial/canciones/nueva">
          Registrar otra canción
        </a>
      </div>
    </section>
  );
}
