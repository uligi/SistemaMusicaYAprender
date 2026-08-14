import { useState, type FormEvent } from 'react';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';

export type SelectedArtist = {
  artistId: string;
  canonicalName: string;
};

type SongDraftRequest = {
  artistId: string;
  canonicalTitle: string;
  languageTag: string;
  recordingTitle: string | null;
  recordingDurationMs: number | null;
  youtubeReference: string;
  sourceDurationMs: number | null;
  offsetMs: number;
  exactRecordingConfirmed: boolean;
  acknowledgePotentialDuplicates: boolean;
};

type DuplicateCandidate = {
  recordingId: string;
  workId: string;
  artistId: string;
  artistName: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  externalRef: string | null;
  similarity: number;
  exactSourceMatch: boolean;
};

type DuplicateReview = {
  candidates: DuplicateCandidate[];
  requiresAcknowledgement: boolean;
  hasExactSourceConflict: boolean;
};

type CreatedSongDraft = {
  workId: string;
  recordingId: string;
  sourceId: string;
  artistId: string;
  canonicalTitle: string;
  recordingTitle: string | null;
  providerCode: string;
  externalRef: string;
  statusCode: string;
  duplicateWarningAcknowledged: boolean;
  alreadyApplied: boolean;
};

type Csrf = {
  requestToken: string;
  headerName: string;
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

    return problem?.detail ?? problem?.title ?? 'La operación no pudo completarse.';
  }

  return 'La operación no pudo completarse.';
}

async function csrfHeaders(): Promise<Readonly<Record<string, string>> | null> {
  const result = await client.get<Csrf>('/auth/csrf', {
    cacheMode: 'no-store',
    retry: 'never',
  });

  if (!result.ok) return null;

  return {
    [result.data.headerName]: result.data.requestToken,
  };
}

function secondsToMilliseconds(value: string, allowZero = false): number | null {
  if (!value.trim()) return null;

  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds < 0 || (!allowZero && seconds === 0)) {
    return Number.NaN;
  }

  return Math.round(seconds * 1000);
}

export type SongDraftComposerProps = {
  artist: SelectedArtist;
};

export function SongDraftComposer({ artist }: SongDraftComposerProps) {
  const [canonicalTitle, setCanonicalTitle] = useState('');
  const [languageTag, setLanguageTag] = useState('ja');
  const [recordingTitle, setRecordingTitle] = useState('');
  const [recordingDuration, setRecordingDuration] = useState('');
  const [youtubeReference, setYoutubeReference] = useState('');
  const [sourceDuration, setSourceDuration] = useState('');
  const [offset, setOffset] = useState('0');
  const [exactRecordingConfirmed, setExactRecordingConfirmed] = useState(false);
  const [duplicateReview, setDuplicateReview] = useState<DuplicateReview | null>(null);
  const [acknowledgePotentialDuplicates, setAcknowledgePotentialDuplicates] = useState(false);
  const [requestKey, setRequestKey] = useState(() => crypto.randomUUID());
  const [created, setCreated] = useState<CreatedSongDraft | null>(null);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  function markChanged() {
    setDuplicateReview(null);
    setAcknowledgePotentialDuplicates(false);
    setCreated(null);
    setRequestKey(crypto.randomUUID());
    setMessage('');
    setError('');
  }

  function buildRequest(): SongDraftRequest | null {
    const recordingDurationMs = secondsToMilliseconds(recordingDuration);
    const sourceDurationMs = secondsToMilliseconds(sourceDuration);
    const offsetMs = secondsToMilliseconds(offset, true);

    if (
      Number.isNaN(recordingDurationMs ?? 0) ||
      Number.isNaN(sourceDurationMs ?? 0) ||
      Number.isNaN(offsetMs ?? 0)
    ) {
      setError(
        'Las duraciones deben ser números positivos y el desplazamiento no puede ser negativo.',
      );
      return null;
    }

    return {
      artistId: artist.artistId,
      canonicalTitle: canonicalTitle.trim(),
      languageTag: languageTag.trim(),
      recordingTitle: recordingTitle.trim() || null,
      recordingDurationMs,
      youtubeReference: youtubeReference.trim(),
      sourceDurationMs,
      offsetMs: offsetMs ?? 0,
      exactRecordingConfirmed,
      acknowledgePotentialDuplicates,
    };
  }

  async function checkDuplicates(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');
    setError('');

    if (!canonicalTitle.trim() || !youtubeReference.trim()) {
      setError('Título original y referencia de YouTube son obligatorios.');
      return;
    }

    if (!exactRecordingConfirmed) {
      setError('Confirma que el video corresponde exactamente a esta grabación.');
      return;
    }

    const request = buildRequest();
    if (!request) return;

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<SongDraftRequest, DuplicateReview>(
      '/editorial/song-drafts/duplicates',
      request,
      {
        headers,
        retry: 'never',
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setDuplicateReview(result.data);
    setAcknowledgePotentialDuplicates(false);

    if (result.data.hasExactSourceConflict) {
      setError(
        'Esa referencia de YouTube ya está vinculada a otra grabación. No puede duplicarse como una fuente nueva.',
      );
      return;
    }

    setMessage(
      result.data.requiresAcknowledgement
        ? 'Se encontraron grabaciones parecidas. Revísalas antes de crear otra versión.'
        : 'No se encontraron grabaciones potencialmente duplicadas.',
    );
  }

  async function createSongDraft() {
    setMessage('');
    setError('');

    if (!duplicateReview) {
      setError('Primero revisa posibles duplicados.');
      return;
    }

    if (duplicateReview.hasExactSourceConflict) {
      setError('La fuente exacta ya existe y no puede duplicarse.');
      return;
    }

    if (duplicateReview.requiresAcknowledgement && !acknowledgePotentialDuplicates) {
      setError('Confirma que revisaste las coincidencias antes de crear una versión distinta.');
      return;
    }

    const request = buildRequest();
    if (!request) return;

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<SongDraftRequest, CreatedSongDraft>(
      '/editorial/song-drafts',
      {
        ...request,
        acknowledgePotentialDuplicates,
      },
      {
        headers,
        idempotencyKey: requestKey,
        retry: 'never',
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setCreated(result.data);
    setMessage(
      result.data.alreadyApplied
        ? 'Esta misma alta ya estaba confirmada; no se duplicó obra, grabación ni fuente.'
        : 'Borrador creado. Obra, grabación y fuente de YouTube tienen identidades separadas.',
    );
  }

  return (
    <section className="song-draft" aria-labelledby="song-draft-title">
      <header className="song-draft__header">
        <p className="song-draft__eyebrow">Paso 2 de 3 · Obra, grabación y fuente</p>
        <h2 id="song-draft-title">2. Completa los datos de la canción</h2>
        <div className="song-draft__selected-artist">
          Artista seleccionado: <strong>{artist.canonicalName}</strong>
          <details>
            <summary>Ver identificador técnico</summary>
            <code>{artist.artistId}</code>
          </details>
        </div>
      </header>

      {error ? (
        <StateMessage
          state="UI-EST-04"
          title="No se pudo guardar el borrador"
          description={error}
        />
      ) : null}

      {message ? (
        <p className="song-draft__status" role="status">
          {message}
        </p>
      ) : null}

      <form className="song-draft__form" onSubmit={checkDuplicates}>
        <div className="song-draft__form-step">
          <span>Paso 2A</span>
          <strong>Datos básicos</strong>
          <small>Indica el título y, si aplica, qué versión concreta estás registrando.</small>
        </div>

        <Field
          id="song-work-title"
          label="Título original de la canción"
          helpText="Escríbelo como aparece oficialmente; preferiblemente en su idioma original."
          value={canonicalTitle}
          onChange={(event) => {
            setCanonicalTitle(event.target.value);
            markChanged();
          }}
          maxLength={512}
          required
        />

        <SelectField
          id="song-work-language"
          label="Idioma principal"
          helpText="Elige el idioma principal del título y de la obra."
          value={languageTag}
          onChange={(event) => {
            setLanguageTag(event.target.value);
            markChanged();
          }}
          required
        >
          <option value="ja">Japonés</option>
          <option value="es">Español</option>
          <option value="en">Inglés</option>
          <option value="it">Italiano</option>
        </SelectField>

        <Field
          id="song-recording-title"
          label="Nombre de esta versión"
          helpText="Opcional. Úsalo para distinguir live, acústica, remix u otra versión."
          value={recordingTitle}
          onChange={(event) => {
            setRecordingTitle(event.target.value);
            markChanged();
          }}
          maxLength={512}
        />

        <div className="song-draft__two-columns">
          <Field
            id="song-recording-duration"
            label="Duración de la canción (segundos)"
            helpText="Opcional. Puede ser distinta a la duración completa del video."
            type="number"
            min="0.001"
            step="0.001"
            value={recordingDuration}
            onChange={(event) => {
              setRecordingDuration(event.target.value);
              markChanged();
            }}
          />

          <Field
            id="song-source-duration"
            label="Duración del video (segundos)"
            helpText="Opcional. Úsala solo si la conoces."
            type="number"
            min="0.001"
            step="0.001"
            value={sourceDuration}
            onChange={(event) => {
              setSourceDuration(event.target.value);
              markChanged();
            }}
          />
        </div>

        <div className="song-draft__form-step">
          <span>Paso 2B</span>
          <strong>Video de YouTube</strong>
          <small>Pega el enlace del video que corresponde exactamente a esta grabación.</small>
        </div>

        <Field
          id="song-youtube-reference"
          label="Enlace de YouTube"
          helpText="Puedes pegar la URL completa o el identificador del video."
          value={youtubeReference}
          onChange={(event) => {
            setYoutubeReference(event.target.value);
            markChanged();
          }}
          maxLength={512}
          required
        />

        <Field
          id="song-source-offset"
          label="La canción empieza en el segundo"
          helpText="Usa 0 si empieza al inicio del video. Si hay una introducción antes, indica aquí cuándo comienza."
          type="number"
          min="0"
          step="0.001"
          value={offset}
          onChange={(event) => {
            setOffset(event.target.value);
            markChanged();
          }}
          required
        />

        <div className="song-draft__form-step">
          <span>Paso 2C</span>
          <strong>Confirma la grabación</strong>
          <small>Esto evita enlazar por error un live, remix o versión diferente.</small>
        </div>

        <label className="song-draft__confirmation">
          <input
            type="checkbox"
            checked={exactRecordingConfirmed}
            onChange={(event) => {
              setExactRecordingConfirmed(event.target.checked);
              markChanged();
            }}
          />
          Confirmo editorialmente que esta referencia de YouTube corresponde exactamente a la
          grabación que estoy registrando.
        </label>

        {duplicateReview ? (
          <section className="song-draft__duplicates" aria-labelledby="song-duplicates-title">
            <h3 id="song-duplicates-title">Revisa estas posibles coincidencias</h3>

            {duplicateReview.candidates.length > 0 ? (
              <ul>
                {duplicateReview.candidates.map((candidate) => (
                  <li key={candidate.recordingId}>
                    <strong>{candidate.canonicalTitle}</strong>
                    <span>
                      {candidate.artistName} ·{' '}
                      {candidate.exactSourceMatch
                        ? 'usa la misma fuente de YouTube'
                        : `${Math.round(candidate.similarity * 100)}% de similitud`}
                    </span>
                    <details className="song-draft__created-technical">
                      <summary>Ver datos técnicos</summary>
                      <code>{candidate.recordingId}</code>
                      {candidate.externalRef ? <code>YouTube: {candidate.externalRef}</code> : null}
                    </details>
                  </li>
                ))}
              </ul>
            ) : (
              <p>No encontramos otra grabación que requiera revisión.</p>
            )}

            {duplicateReview.requiresAcknowledgement && !duplicateReview.hasExactSourceConflict ? (
              <label className="song-draft__confirmation">
                <input
                  type="checkbox"
                  checked={acknowledgePotentialDuplicates}
                  onChange={(event) => setAcknowledgePotentialDuplicates(event.target.checked)}
                />
                Revisé las coincidencias y confirmo que se trata de una grabación o versión
                distinta.
              </label>
            ) : null}
          </section>
        ) : null}

        {created ? (
          <section className="song-draft__created" aria-label="Borrador de canción confirmado">
            <p className="song-draft__eyebrow">Paso 3 de 3 · Borrador guardado</p>
            <h3>Borrador listo: {created.canonicalTitle}</h3>
            <p>
              La canción quedó guardada como borrador. Ahora puedes abrir su expediente y continuar
              con letra, derechos, traducción, sincronización y análisis.
            </p>
            <div className="song-draft__created-links">
              <a className="ma-link" href={`/editorial/canciones/${created.recordingId}`}>
                Abrir expediente de la canción
              </a>
              <a className="ma-link" href={`/editorial/canciones/${created.recordingId}/derechos`}>
                Continuar con derechos y procedencia
              </a>
            </div>
            <details className="song-draft__created-technical">
              <summary>Ver identificadores técnicos</summary>
              <dl>
                <div>
                  <dt>Obra</dt>
                  <dd>
                    <code>{created.workId}</code>
                  </dd>
                </div>
                <div>
                  <dt>Grabación</dt>
                  <dd>
                    <code>{created.recordingId}</code>
                  </dd>
                </div>
                <div>
                  <dt>Fuente</dt>
                  <dd>
                    <code>{created.sourceId}</code>
                  </dd>
                </div>
                <div>
                  <dt>YouTube</dt>
                  <dd>
                    {created.providerCode} · <code>{created.externalRef}</code>
                  </dd>
                </div>
              </dl>
            </details>
            <p>Guardar este borrador no publica contenido.</p>
          </section>
        ) : null}

        <div className="song-draft__actions">
          <Button type="submit" disabled={busy}>
            Comprobar coincidencias
          </Button>
          <Button
            type="button"
            variant="secondary"
            disabled={
              busy ||
              !duplicateReview ||
              duplicateReview.hasExactSourceConflict ||
              (duplicateReview.requiresAcknowledgement && !acknowledgePotentialDuplicates)
            }
            onClick={() => void createSongDraft()}
          >
            Guardar borrador de canción
          </Button>
        </div>
      </form>
    </section>
  );
}
