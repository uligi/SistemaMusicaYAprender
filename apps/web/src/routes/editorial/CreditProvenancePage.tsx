import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import './credit-provenance.css';

type CreditEntry = {
  creditId: string;
  recordingId: string;
  artistId: string | null;
  displayName: string;
  roleCode: string;
  displayOrder: number;
  sourceReferenceId: string;
  sourceType: string;
  citation: string;
  locator: string | null;
  retrievedAt: string | null;
  provenanceId: string;
  verificationCode: 'VERIFIED' | 'UNVERIFIED' | 'PENDING_IDENTITY';
  pendingIdentity: boolean;
};

type CreditCreateResult = {
  credit: CreditEntry;
  alreadyApplied: boolean;
};

type CreditRequest = {
  artistId: string | null;
  displayName: string;
  roleCode: string;
  displayOrder: number;
  sourceType: string;
  citation: string;
  locator: string | null;
  verificationCode: string;
};

type ArtistSearchResult = {
  artistId: string;
  canonicalName: string;
  artistType: string;
  statusCode: string;
  matchedText: string;
  similarity: number;
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

export type CreditProvenancePageProps = {
  recordingId: string;
};

export function CreditProvenancePage({ recordingId }: CreditProvenancePageProps) {
  const access = useVisibleAccess();
  const canWrite = access.capabilities.includes('EDITORIAL.DRAFT');
  const [credits, setCredits] = useState<CreditEntry[]>([]);
  const [participantMode, setParticipantMode] = useState<'KNOWN' | 'PENDING'>('KNOWN');
  const [artistQuery, setArtistQuery] = useState('');
  const [artistResults, setArtistResults] = useState<ArtistSearchResult[]>([]);
  const [selectedArtist, setSelectedArtist] = useState<ArtistSearchResult | null>(null);
  const [displayName, setDisplayName] = useState('');
  const [roleCode, setRoleCode] = useState('PERFORMER');
  const [displayOrder, setDisplayOrder] = useState('0');
  const [sourceType, setSourceType] = useState('OFFICIAL_CREDIT');
  const [citation, setCitation] = useState('');
  const [locator, setLocator] = useState('');
  const [verificationCode, setVerificationCode] = useState<'VERIFIED' | 'UNVERIFIED'>('VERIFIED');
  const [requestKey, setRequestKey] = useState(() => crypto.randomUUID());
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const effectiveVerification =
    participantMode === 'PENDING' ? 'PENDING_IDENTITY' : verificationCode;

  const nextOrder = useMemo(
    () =>
      credits.length === 0 ? 0 : Math.max(...credits.map((credit) => credit.displayOrder)) + 1,
    [credits],
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError('');

    const result = await client.get<CreditEntry[]>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/credits`,
      {
        cacheMode: 'no-store',
        retry: 'never',
      },
    );

    setLoading(false);
    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setCredits(result.data);
  }, [recordingId]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    setDisplayOrder(String(nextOrder));
  }, [nextOrder]);

  async function searchArtist(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    setMessage('');

    const query = artistQuery.trim();
    if (!query) {
      setArtistResults([]);
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

    setArtistResults(result.data);
  }

  function chooseKnownArtist(artist: ArtistSearchResult) {
    setSelectedArtist(artist);
    setDisplayName(artist.canonicalName);
    setMessage(`Participante enlazado a la identidad estable ${artist.artistId}.`);
    setRequestKey(crypto.randomUUID());
  }

  function changeParticipantMode(mode: 'KNOWN' | 'PENDING') {
    setParticipantMode(mode);
    setSelectedArtist(null);
    setArtistResults([]);
    setMessage('');
    setError('');
    setRequestKey(crypto.randomUUID());
    if (mode === 'PENDING') {
      setDisplayName('');
    }
  }

  async function createCredit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    setMessage('');

    if (participantMode === 'KNOWN' && !selectedArtist) {
      setError('Selecciona una identidad canónica existente para el participante.');
      return;
    }

    const order = Number(displayOrder);
    if (!Number.isInteger(order) || order < 0) {
      setError('El orden de presentación debe ser un entero mayor o igual a cero.');
      return;
    }

    if (!displayName.trim() || !roleCode.trim() || !sourceType.trim() || !citation.trim()) {
      setError('Nombre, rol, tipo de fuente y cita son obligatorios.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    const request: CreditRequest = {
      artistId: participantMode === 'KNOWN' ? (selectedArtist?.artistId ?? null) : null,
      displayName: displayName.trim(),
      roleCode: roleCode.trim(),
      displayOrder: order,
      sourceType: sourceType.trim(),
      citation: citation.trim(),
      locator: locator.trim() || null,
      verificationCode: effectiveVerification,
    };

    setBusy(true);
    const result = await client.post<CreditRequest, CreditCreateResult>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/credits`,
      request,
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

    setMessage(
      result.data.alreadyApplied
        ? 'Esta misma alta ya estaba confirmada; no se duplicó el crédito.'
        : result.data.credit.pendingIdentity
          ? 'Crédito guardado con identidad explícitamente pendiente y procedencia conservada.'
          : 'Crédito guardado con identidad estable, rol, orden, procedencia y verificación.',
    );
    setCitation('');
    setLocator('');
    setRequestKey(crypto.randomUUID());
    await load();
  }

  return (
    <section className="credit-provenance" aria-labelledby="credit-provenance-title">
      <header className="credit-provenance__header">
        <p className="credit-provenance__eyebrow">BL-MVP-039 · UI-MVP-020</p>
        <h1 id="credit-provenance-title">Créditos, participantes y procedencia</h1>
        <p>
          Registra quién participa, en qué orden se acredita y de dónde proviene la información. Los
          Los derechos, territorios, usos y vigencias se administran en esta misma pantalla.
        </p>
        <p>
          Grabación: <code>{recordingId}</code>
        </p>
      </header>

      {error ? (
        <StateMessage state="UI-EST-04" title="No se confirmó el cambio" description={error} />
      ) : null}

      {message ? (
        <p className="credit-provenance__status" role="status">
          {message}
        </p>
      ) : null}

      <div className="credit-provenance__layout">
        <section className="credit-provenance__panel" aria-labelledby="credit-existing-title">
          <div>
            <p className="credit-provenance__eyebrow">Estado confirmado</p>
            <h2 id="credit-existing-title">Créditos registrados</h2>
          </div>

          {loading ? (
            <StateMessage
              state="UI-EST-01"
              title="Cargando créditos"
              description="Consultando el estado confirmado del expediente."
            />
          ) : null}

          {!loading && credits.length === 0 ? (
            <StateMessage
              state="UI-EST-02"
              title="Todavía no hay créditos"
              description="Registra el primer participante y su procedencia."
            />
          ) : null}

          <ol className="credit-provenance__credits">
            {credits.map((credit) => (
              <li className="credit-provenance__credit" key={credit.creditId}>
                <div className="credit-provenance__credit-title">
                  <strong>{credit.displayName}</strong>
                  <span>
                    {credit.roleCode} · orden {credit.displayOrder}
                  </span>
                </div>
                <dl>
                  <div>
                    <dt>Identidad</dt>
                    <dd>{credit.artistId ? <code>{credit.artistId}</code> : 'PENDING_IDENTITY'}</dd>
                  </div>
                  <div>
                    <dt>Verificación</dt>
                    <dd>{credit.verificationCode}</dd>
                  </div>
                  <div>
                    <dt>Fuente</dt>
                    <dd>
                      {credit.sourceType}: {credit.citation}
                    </dd>
                  </div>
                  {credit.locator ? (
                    <div>
                      <dt>Localizador</dt>
                      <dd>{credit.locator}</dd>
                    </div>
                  ) : null}
                  <div>
                    <dt>Referencia de procedencia</dt>
                    <dd>
                      <code>{credit.sourceReferenceId}</code>
                    </dd>
                  </div>
                </dl>
              </li>
            ))}
          </ol>
        </section>

        {canWrite ? (
          <section className="credit-provenance__panel" aria-labelledby="credit-create-title">
            <div>
              <p className="credit-provenance__eyebrow">Alta editorial</p>
              <h2 id="credit-create-title">Añadir participante</h2>
            </div>

            <SelectField
              id="credit-participant-mode"
              label="Estado de identidad"
              helpText="No inventes una identidad: si todavía no existe, conserva el nombre como pendiente."
              value={participantMode}
              onChange={(event) => changeParticipantMode(event.target.value as 'KNOWN' | 'PENDING')}
            >
              <option value="KNOWN">Identidad canónica existente</option>
              <option value="PENDING">Identidad todavía desconocida o sin resolver</option>
            </SelectField>

            {participantMode === 'KNOWN' ? (
              <form className="credit-provenance__artist-search" onSubmit={searchArtist}>
                <Field
                  id="credit-artist-query"
                  label="Buscar artista existente"
                  value={artistQuery}
                  onChange={(event) => setArtistQuery(event.target.value)}
                  maxLength={512}
                />
                <Button type="submit" variant="secondary" disabled={busy}>
                  Buscar identidad
                </Button>
                {artistResults.length > 0 ? (
                  <ul className="credit-provenance__artist-results">
                    {artistResults.map((artist) => (
                      <li key={artist.artistId}>
                        <div>
                          <strong>{artist.canonicalName}</strong>
                          <code>{artist.artistId}</code>
                        </div>
                        <Button
                          type="button"
                          variant="secondary"
                          onClick={() => chooseKnownArtist(artist)}
                        >
                          Usar {artist.canonicalName}
                        </Button>
                      </li>
                    ))}
                  </ul>
                ) : null}
              </form>
            ) : (
              <p className="credit-provenance__pending-note">
                El crédito se guardará con <code>artist_id = NULL</code> y estado PENDING_IDENTITY.
                El nombre visible no se convierte en clave.
              </p>
            )}

            <form className="credit-provenance__form" onSubmit={createCredit}>
              <Field
                id="credit-display-name"
                label="Nombre tal como debe acreditarse"
                value={displayName}
                onChange={(event) => {
                  setDisplayName(event.target.value);
                  setRequestKey(crypto.randomUUID());
                }}
                maxLength={512}
                required
              />

              <Field
                id="credit-role-code"
                label="Rol del crédito"
                helpText="Código extensible, por ejemplo PERFORMER, COMPOSER, LYRICIST, ARRANGER o PRODUCER."
                value={roleCode}
                onChange={(event) => {
                  setRoleCode(event.target.value.toUpperCase());
                  setRequestKey(crypto.randomUUID());
                }}
                pattern="[A-Z0-9][A-Z0-9._-]{0,63}"
                list="credit-role-suggestions"
                required
              />
              <datalist id="credit-role-suggestions">
                <option value="PERFORMER" />
                <option value="COMPOSER" />
                <option value="LYRICIST" />
                <option value="ARRANGER" />
                <option value="PRODUCER" />
              </datalist>

              <Field
                id="credit-display-order"
                label="Orden de presentación"
                type="number"
                min={0}
                step={1}
                value={displayOrder}
                onChange={(event) => {
                  setDisplayOrder(event.target.value);
                  setRequestKey(crypto.randomUUID());
                }}
                required
              />

              <Field
                id="credit-source-type"
                label="Tipo de fuente"
                helpText="Código estable de la procedencia; por ejemplo OFFICIAL_CREDIT, BOOKLET o OFFICIAL_SITE."
                value={sourceType}
                onChange={(event) => {
                  setSourceType(event.target.value.toUpperCase());
                  setRequestKey(crypto.randomUUID());
                }}
                pattern="[A-Z0-9][A-Z0-9._-]{0,63}"
                required
              />

              <Field
                id="credit-citation"
                label="Cita o referencia de procedencia"
                value={citation}
                onChange={(event) => {
                  setCitation(event.target.value);
                  setRequestKey(crypto.randomUUID());
                }}
                maxLength={2048}
                required
              />

              <Field
                id="credit-locator"
                label="Localizador de la fuente"
                helpText="Opcional: página, URL, edición, folleto u otro localizador verificable."
                value={locator}
                onChange={(event) => {
                  setLocator(event.target.value);
                  setRequestKey(crypto.randomUUID());
                }}
                maxLength={2048}
              />

              {participantMode === 'KNOWN' ? (
                <SelectField
                  id="credit-verification"
                  label="Verificación"
                  value={verificationCode}
                  onChange={(event) => {
                    setVerificationCode(event.target.value as 'VERIFIED' | 'UNVERIFIED');
                    setRequestKey(crypto.randomUUID());
                  }}
                >
                  <option value="VERIFIED">Verificado contra la fuente indicada</option>
                  <option value="UNVERIFIED">Pendiente de verificar la atribución</option>
                </SelectField>
              ) : (
                <div className="credit-provenance__verification-fixed">
                  <span>Verificación</span>
                  <strong>PENDING_IDENTITY</strong>
                </div>
              )}

              <Button type="submit" disabled={busy}>
                Guardar crédito y procedencia
              </Button>
            </form>
          </section>
        ) : (
          <section className="credit-provenance__panel" aria-labelledby="credit-readonly-title">
            <h2 id="credit-readonly-title">Consulta editorial</h2>
            <StateMessage
              state="UI-EST-03"
              title="Modo de revisión"
              description="Puedes consultar créditos y procedencia. El alta requiere EDITORIAL.DRAFT."
            />
          </section>
        )}
      </div>
    </section>
  );
}
