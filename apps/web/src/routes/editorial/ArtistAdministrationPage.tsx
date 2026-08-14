import { useMemo, useState, type FormEvent } from 'react';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import { SongDraftComposer, type SelectedArtist } from './SongDraftComposer';
import './artist-administration.css';
import './song-draft-administration.css';

type ArtistAliasDraft = {
  aliasText: string;
  languageTag: string;
  scriptCode: string;
  preferred: boolean;
};

type ArtistDraftRequest = {
  canonicalName: string;
  sortName: string;
  artistType: string;
  canonicalLanguageTag: string;
  canonicalScriptCode: string;
  aliases: ArtistAliasDraft[];
  acknowledgePotentialDuplicates: boolean;
};

type DuplicateCandidate = {
  artistId: string;
  canonicalName: string;
  artistType: string;
  statusCode: string;
  matchedText: string;
  similarity: number;
};

type DuplicateReview = {
  candidates: DuplicateCandidate[];
  requiresAcknowledgement: boolean;
};

type ArtistSearchResult = DuplicateCandidate;

type ArtistCreatedResult = {
  artistId: string;
  canonicalName: string;
  artistType: string;
  statusCode: string;
  aliases: ArtistAliasDraft[];
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

function displayArtistType(value: string) {
  const labels: Record<string, string> = {
    PERSON: 'Persona',
    GROUP: 'Grupo',
    PROJECT: 'Proyecto',
    BAND: 'Banda',
    TEMPORARY_UNIT: 'Unidad temporal',
    VIRTUAL: 'Artista virtual',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

export function ArtistAdministrationPage() {
  const [canonicalName, setCanonicalName] = useState('');
  const [sortName, setSortName] = useState('');
  const [artistType, setArtistType] = useState('PERSON');
  const [canonicalLanguageTag, setCanonicalLanguageTag] = useState('ja');
  const [canonicalScriptCode, setCanonicalScriptCode] = useState('JPAN');
  const [kanaReading, setKanaReading] = useState('');
  const [romanizedName, setRomanizedName] = useState('');
  const [spanishName, setSpanishName] = useState('');
  const [duplicateReview, setDuplicateReview] = useState<DuplicateReview | null>(null);
  const [acknowledgePotentialDuplicates, setAcknowledgePotentialDuplicates] = useState(false);
  const [requestKey, setRequestKey] = useState(() => crypto.randomUUID());
  const [created, setCreated] = useState<ArtistCreatedResult | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<ArtistSearchResult[]>([]);
  const [selectedArtist, setSelectedArtist] = useState<SelectedArtist | null>(null);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const aliases = useMemo<ArtistAliasDraft[]>(() => {
    const values: ArtistAliasDraft[] = [];

    if (kanaReading.trim()) {
      values.push({
        aliasText: kanaReading.trim(),
        languageTag: 'ja',
        scriptCode: 'HIRA',
        preferred: false,
      });
    }

    if (romanizedName.trim()) {
      values.push({
        aliasText: romanizedName.trim(),
        languageTag: 'ja',
        scriptCode: 'LATN',
        preferred: false,
      });
    }

    if (spanishName.trim()) {
      values.push({
        aliasText: spanishName.trim(),
        languageTag: 'es',
        scriptCode: 'LATN',
        preferred: false,
      });
    }

    return values;
  }, [kanaReading, romanizedName, spanishName]);

  function markDraftChanged() {
    setDuplicateReview(null);
    setAcknowledgePotentialDuplicates(false);
    setCreated(null);
    setRequestKey(crypto.randomUUID());
    setMessage('');
    setError('');
  }

  function draftRequest(): ArtistDraftRequest {
    return {
      canonicalName: canonicalName.trim(),
      sortName: sortName.trim(),
      artistType: artistType.trim(),
      canonicalLanguageTag: canonicalLanguageTag.trim(),
      canonicalScriptCode: canonicalScriptCode.trim(),
      aliases,
      acknowledgePotentialDuplicates,
    };
  }

  async function checkDuplicates(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');
    setError('');

    if (!canonicalName.trim() || !artistType.trim()) {
      setError('Nombre canónico y tipo de artista son obligatorios.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<ArtistDraftRequest, DuplicateReview>(
      '/editorial/artists/duplicates',
      draftRequest(),
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

    setMessage(
      result.data.requiresAcknowledgement
        ? 'Se encontraron coincidencias. Revísalas antes de crear otra identidad.'
        : 'No se encontraron duplicados potenciales con los nombres proporcionados.',
    );
  }

  async function createArtist() {
    setMessage('');
    setError('');

    if (!duplicateReview) {
      setError('Primero revisa posibles duplicados.');
      return;
    }

    if (duplicateReview.requiresAcknowledgement && !acknowledgePotentialDuplicates) {
      setError('Debes confirmar que revisaste las coincidencias antes de continuar.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<ArtistDraftRequest, ArtistCreatedResult>(
      '/editorial/artists',
      draftRequest(),
      {
        headers,
        idempotencyKey: requestKey,
        retry: 'never',
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      setDuplicateReview(null);
      setAcknowledgePotentialDuplicates(false);
      return;
    }

    setCreated(result.data);
    setSelectedArtist({
      artistId: result.data.artistId,
      canonicalName: result.data.canonicalName,
    });
    setMessage(
      result.data.alreadyApplied
        ? 'Esta misma alta ya estaba confirmada; no se creó otra identidad.'
        : 'Identidad de artista creada. El identificador estable, y no el nombre, será la referencia interna.',
    );
  }

  async function searchExisting(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    setMessage('');

    const query = searchQuery.trim();
    if (!query) {
      setSearchResults([]);
      return;
    }

    setBusy(true);
    const result = await client.get<ArtistSearchResult[]>(
      `/editorial/artists?query=${encodeURIComponent(query)}`,
      {
        cacheMode: 'no-store',
        retry: 'never',
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setSearchResults(result.data);
  }

  return (
    <section className="artist-administration" aria-labelledby="artist-administration-title">
      <header className="artist-administration__header">
        <p className="artist-administration__eyebrow">Paso 1 de 3 · Artista canónico</p>
        <h2 id="artist-administration-title">1. Elige el artista</h2>
        <p>
          Busca primero si el artista ya existe. Si lo encuentras, selecciónalo y continúa; crea una
          identidad nueva únicamente cuando no haya una coincidencia correcta.
        </p>
      </header>

      {error ? (
        <StateMessage state="UI-EST-04" title="No se pudo continuar" description={error} />
      ) : null}

      {message ? (
        <p className="artist-administration__status" role="status">
          {message}
        </p>
      ) : null}

      <div className="artist-administration__layout">
        <form
          className="artist-administration__panel artist-administration__panel--search"
          onSubmit={searchExisting}
        >
          <div>
            <p className="artist-administration__eyebrow">Recomendado</p>
            <h2>Buscar un artista existente</h2>
            <p>
              Puedes buscar por nombre original, lectura en kana o romanización. Reutilizar una
              identidad evita duplicados y mantiene todo el catálogo conectado.
            </p>
          </div>

          <Field
            id="artist-search-query"
            label="Nombre, lectura o romanización"
            helpText="Ejemplo: サカナクション, さかなくしょん o Sakanaction."
            value={searchQuery}
            onChange={(event) => setSearchQuery(event.target.value)}
            maxLength={512}
          />

          <Button type="submit" disabled={busy || !searchQuery.trim()}>
            Buscar artista
          </Button>

          {searchResults.length > 0 ? (
            <ul className="artist-administration__search-results" aria-label="Artistas encontrados">
              {searchResults.map((artist) => (
                <li key={artist.artistId}>
                  <strong>{artist.canonicalName}</strong>
                  <span>
                    {displayArtistType(artist.artistType)} · coincidencia «{artist.matchedText}»
                  </span>
                  <details className="artist-administration__technical">
                    <summary>Ver identificador técnico</summary>
                    <code>{artist.artistId}</code>
                  </details>
                  <Button
                    type="button"
                    variant="secondary"
                    onClick={() =>
                      setSelectedArtist({
                        artistId: artist.artistId,
                        canonicalName: artist.canonicalName,
                      })
                    }
                  >
                    Usar {artist.canonicalName}
                  </Button>
                </li>
              ))}
            </ul>
          ) : searchQuery.trim() && !busy ? (
            <p className="artist-administration__eyebrow">
              Si no aparece el artista correcto, usa el formulario de registro que está debajo.
            </p>
          ) : null}
        </form>

        <form
          className="artist-administration__panel artist-administration__panel--create"
          onSubmit={checkDuplicates}
        >
          <div>
            <p className="artist-administration__eyebrow">Solo si no existe</p>
            <h2>Registrar un artista nuevo</h2>
            <p>
              Conserva el nombre original y agrega lecturas o alias solo cuando los conozcas. Antes
              de crear la identidad revisaremos posibles coincidencias.
            </p>
          </div>

          <Field
            id="artist-canonical-name"
            label="Nombre original del artista"
            helpText="Escríbelo como aparece oficialmente."
            value={canonicalName}
            onChange={(event) => {
              setCanonicalName(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
            required
          />

          <Field
            id="artist-sort-name"
            label="Nombre para ordenar"
            helpText="Opcional. Úsalo solo si quieres una forma distinta para ordenar listas."
            value={sortName}
            onChange={(event) => {
              setSortName(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
          />

          <SelectField
            id="artist-type"
            label="Tipo de artista"
            helpText="Elige la categoría que mejor describe esta identidad."
            value={artistType}
            onChange={(event) => {
              setArtistType(event.target.value);
              markDraftChanged();
            }}
            required
          >
            <option value="PERSON">Persona</option>
            <option value="GROUP">Grupo</option>
            <option value="PROJECT">Proyecto</option>
            <option value="BAND">Banda</option>
            <option value="TEMPORARY_UNIT">Unidad temporal</option>
            <option value="VIRTUAL">Artista virtual</option>
          </SelectField>

          <div className="artist-administration__two-columns">
            <SelectField
              id="artist-language"
              label="Idioma del nombre"
              helpText="Elige el idioma principal del nombre original."
              value={canonicalLanguageTag}
              onChange={(event) => {
                setCanonicalLanguageTag(event.target.value);
                markDraftChanged();
              }}
              required
            >
              <option value="ja">Japonés</option>
              <option value="es">Español</option>
              <option value="en">Inglés</option>
              <option value="it">Italiano</option>
            </SelectField>

            <SelectField
              id="artist-script"
              label="Cómo está escrito"
              helpText="Elige el sistema de escritura del nombre principal."
              value={canonicalScriptCode}
              onChange={(event) => {
                setCanonicalScriptCode(event.target.value);
                markDraftChanged();
              }}
              required
            >
              <option value="JPAN">Japonés mixto (kanji/kana)</option>
              <option value="HIRA">Hiragana</option>
              <option value="KANA">Katakana</option>
              <option value="LATN">Alfabeto latino</option>
            </SelectField>
          </div>

          <Field
            id="artist-kana-reading"
            label="Lectura en hiragana"
            helpText="Opcional. Ayuda a buscar y leer el nombre japonés."
            value={kanaReading}
            onChange={(event) => {
              setKanaReading(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
          />

          <Field
            id="artist-romaji"
            label="Romanización"
            helpText="Opcional. Ejemplo: Sakanaction."
            value={romanizedName}
            onChange={(event) => {
              setRomanizedName(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
          />

          <Field
            id="artist-spanish-name"
            label="Nombre en español"
            helpText="Opcional. Solo si existe una forma localizada útil."
            value={spanishName}
            onChange={(event) => {
              setSpanishName(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
          />

          {duplicateReview ? (
            <section
              className="artist-administration__duplicates"
              aria-labelledby="artist-duplicates-title"
            >
              <h3 id="artist-duplicates-title">Revisa estas posibles coincidencias</h3>

              {duplicateReview.candidates.length > 0 ? (
                <>
                  <ul>
                    {duplicateReview.candidates.map((candidate) => (
                      <li key={candidate.artistId}>
                        <strong>{candidate.canonicalName}</strong>
                        <span>
                          {displayArtistType(candidate.artistType)} · coincidencia «
                          {candidate.matchedText}» · {Math.round(candidate.similarity * 100)}%
                        </span>
                        <details className="artist-administration__technical">
                          <summary>Ver identificador técnico</summary>
                          <code>{candidate.artistId}</code>
                        </details>
                      </li>
                    ))}
                  </ul>

                  <label className="artist-administration__confirmation">
                    <input
                      type="checkbox"
                      checked={acknowledgePotentialDuplicates}
                      onChange={(event) => setAcknowledgePotentialDuplicates(event.target.checked)}
                    />
                    Revisé estas coincidencias y confirmo que debe crearse una identidad distinta.
                  </label>
                </>
              ) : (
                <p>No encontramos otra identidad que requiera confirmación.</p>
              )}
            </section>
          ) : null}

          {created ? (
            <section className="artist-administration__created" aria-label="Artista confirmado">
              <p className="artist-administration__eyebrow">Artista listo</p>
              <h3>{created.canonicalName}</h3>
              <p>La identidad quedó seleccionada y ya puedes continuar con la canción.</p>
              <details className="artist-administration__technical">
                <summary>Ver identificador técnico</summary>
                <code>{created.artistId}</code>
                <p>Estado interno: {created.statusCode}</p>
              </details>
            </section>
          ) : null}

          <div className="artist-administration__actions">
            <Button type="submit" disabled={busy}>
              Revisar duplicados
            </Button>
            <Button
              type="button"
              variant="secondary"
              disabled={
                busy ||
                !duplicateReview ||
                (duplicateReview.requiresAcknowledgement && !acknowledgePotentialDuplicates)
              }
              onClick={() => void createArtist()}
            >
              Crear identidad de artista
            </Button>
          </div>
        </form>
      </div>

      {selectedArtist ? <SongDraftComposer artist={selectedArtist} /> : null}
    </section>
  );
}
