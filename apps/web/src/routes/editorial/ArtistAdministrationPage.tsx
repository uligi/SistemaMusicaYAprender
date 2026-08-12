import { useMemo, useState, type FormEvent } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import './artist-administration.css';

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
        <p className="artist-administration__eyebrow">F2 · Catálogo musical · M02</p>
        <h1 id="artist-administration-title">Artista canónico para una nueva canción</h1>
        <p>
          Registra o localiza primero la identidad estable del artista. Los nombres sirven para
          mostrar y buscar; nunca sustituyen al identificador interno.
        </p>
      </header>

      {error ? (
        <StateMessage state="UI-EST-04" title="No se confirmó el cambio" description={error} />
      ) : null}

      {message ? (
        <p className="artist-administration__status" role="status">
          {message}
        </p>
      ) : null}

      <div className="artist-administration__layout">
        <form className="artist-administration__panel" onSubmit={checkDuplicates}>
          <div>
            <p className="artist-administration__eyebrow">Crear identidad</p>
            <h2>Nombre principal, lectura y alias</h2>
          </div>

          <Field
            id="artist-canonical-name"
            label="Nombre canónico"
            helpText="Conserva la escritura original. El servidor genera la identidad estable."
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
            label="Nombre de ordenación"
            helpText="Opcional. Si se omite, se usa el nombre canónico."
            value={sortName}
            onChange={(event) => {
              setSortName(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
          />

          <Field
            id="artist-type"
            label="Tipo de artista"
            helpText="Código administrable. Ejemplos: PERSON, GROUP, PROJECT, BAND, TEMPORARY_UNIT, VIRTUAL."
            list="artist-type-options"
            value={artistType}
            onChange={(event) => {
              setArtistType(event.target.value.toUpperCase());
              markDraftChanged();
            }}
            maxLength={64}
            required
          />
          <datalist id="artist-type-options">
            <option value="PERSON" />
            <option value="GROUP" />
            <option value="PROJECT" />
            <option value="BAND" />
            <option value="TEMPORARY_UNIT" />
            <option value="VIRTUAL" />
          </datalist>

          <div className="artist-administration__two-columns">
            <Field
              id="artist-language"
              label="Idioma del nombre principal"
              value={canonicalLanguageTag}
              onChange={(event) => {
                setCanonicalLanguageTag(event.target.value);
                markDraftChanged();
              }}
              maxLength={35}
              required
            />
            <Field
              id="artist-script"
              label="Sistema de escritura"
              helpText="Ejemplos: JPAN, HIRA, KANA, LATN."
              list="artist-script-options"
              value={canonicalScriptCode}
              onChange={(event) => {
                setCanonicalScriptCode(event.target.value.toUpperCase());
                markDraftChanged();
              }}
              maxLength={64}
              required
            />
            <datalist id="artist-script-options">
              <option value="JPAN" />
              <option value="HIRA" />
              <option value="KANA" />
              <option value="LATN" />
            </datalist>
          </div>

          <Field
            id="artist-kana-reading"
            label="Lectura en hiragana"
            helpText="Opcional. Se conserva como forma japonesa buscable."
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
            helpText="Opcional. No reemplaza el nombre original."
            value={romanizedName}
            onChange={(event) => {
              setRomanizedName(event.target.value);
              markDraftChanged();
            }}
            maxLength={512}
          />

          <Field
            id="artist-spanish-name"
            label="Nombre localizado en español"
            helpText="Opcional. Se almacena como alias localizado, no como clave."
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
              <h3 id="artist-duplicates-title">Revisión de posibles duplicados</h3>

              {duplicateReview.candidates.length > 0 ? (
                <>
                  <ul>
                    {duplicateReview.candidates.map((candidate) => (
                      <li key={candidate.artistId}>
                        <strong>{candidate.canonicalName}</strong>{' '}
                        <span>
                          ({candidate.artistType}) · coincidencia «{candidate.matchedText}» ·{' '}
                          {Math.round(candidate.similarity * 100)}%
                        </span>
                        <code>{candidate.artistId}</code>
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
                <p>No hay coincidencias que requieran confirmación.</p>
              )}
            </section>
          ) : null}

          {created ? (
            <section className="artist-administration__created" aria-label="Artista confirmado">
              <h3>{created.canonicalName}</h3>
              <p>
                Identificador estable: <code>{created.artistId}</code>
              </p>
              <p>
                Estado interno: {created.statusCode}. Esto no publica una canción ni crea una
                grabación.
              </p>
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

        <form className="artist-administration__panel" onSubmit={searchExisting}>
          <div>
            <p className="artist-administration__eyebrow">Reutilizar identidad</p>
            <h2>Buscar un artista existente</h2>
            <p>
              Revisa nombres canónicos, lecturas y alias antes de crear otro registro. La asociación
              con obra y grabación se completa en la siguiente etapa editorial.
            </p>
          </div>

          <Field
            id="artist-search-query"
            label="Nombre, lectura o romanización"
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
                    {artist.artistType} · coincidencia «{artist.matchedText}»
                  </span>
                  <code>{artist.artistId}</code>
                </li>
              ))}
            </ul>
          ) : null}
        </form>
      </div>
    </section>
  );
}
