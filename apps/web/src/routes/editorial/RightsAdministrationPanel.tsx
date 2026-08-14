import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { useVisibleAccess } from '../../app/access/AccessContext';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import './rights-administration.css';

type RightsScopeEntry = {
  rightsScopeId: string;
  territoryCode: string;
  languageTag: string | null;
  channelCode: string;
  useCode: string;
};

type RightsEntry = {
  rightsRecordId: string;
  rightsHolderId: string;
  holderType: string;
  holderDisplayName: string;
  objectType: string;
  objectId: string;
  basisCode: string;
  statusCode: string;
  validFrom: string | null;
  validTo: string | null;
  evidenceObjectId: string;
  evidenceMediaType: string;
  evidenceSizeBytes: number;
  evidenceChecksumSha256: string;
  recordedAt: string | null;
  recordedBy: string | null;
  scopes: RightsScopeEntry[];
};

type RightsCreateResult = {
  rights: RightsEntry;
  alreadyApplied: boolean;
};

type RightsAvailability = {
  allowed: boolean;
  code: string;
  description: string;
  rightsRecordId: string | null;
  territoryCode: string;
  channelCode: string;
  useCode: string;
  languageTag: string | null;
  evaluatedAt: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type RightsRequest = {
  holderType: string;
  holderDisplayName: string;
  basisCode: string;
  validFrom: string | null;
  validTo: string | null;
  evidenceFileName: string;
  evidenceMediaType: string;
  evidenceBase64: string;
  scopes: {
    territoryCode: string;
    languageTag: string | null;
    channelCode: string;
    useCode: string;
  }[];
  reason: string;
  supersedesRightsRecordId: string | null;
};

const client = createHttpClient();
const maxEvidenceBytes = 2 * 1024 * 1024;

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

function toUtcOrNull(value: string): string | null {
  if (!value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
function formatDateTime(value: string | null) {
  if (!value) return 'Sin fecha declarada';
  return new Intl.DateTimeFormat('es-CR', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MiB`;
}

function displayBasis(value: string) {
  const labels: Record<string, string> = {
    AUTHORIZATION: 'Autorización',
    LICENSE: 'Licencia',
    PUBLIC_DOMAIN: 'Dominio público documentado',
    PERMITTED_USE: 'Uso permitido documentado',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

function displayStatus(value: string) {
  const labels: Record<string, string> = {
    ACTIVE: 'Activa',
    EXPIRED: 'Vencida',
    REVOKED: 'Revocada',
    SUPERSEDED: 'Sustituida',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

function displayChannel(value: string) {
  return value === 'WEB' ? 'Web' : value.replaceAll('_', ' ');
}

function displayUse(value: string) {
  const labels: Record<string, string> = {
    DISPLAY: 'Mostrar contenido',
    PLAYBACK: 'Reproducción',
    TRANSLATION: 'Traducción',
    ADAPTATION: 'Adaptación',
    DISTRIBUTION: 'Distribución',
    EXPORT: 'Exportación',
  };
  return labels[value] ?? value.replaceAll('_', ' ');
}

async function fileToBase64(file: File): Promise<string> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  let binary = '';
  const chunk = 0x8000;

  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunk));
  }

  return btoa(binary);
}

export type RightsAdministrationPanelProps = {
  recordingId: string;
};

export function RightsAdministrationPanel({ recordingId }: RightsAdministrationPanelProps) {
  const access = useVisibleAccess();
  const canWrite = access.capabilities.includes('EDITORIAL.DRAFT');

  const [rights, setRights] = useState<RightsEntry[]>([]);
  const [holderType, setHolderType] = useState('ORGANIZATION');
  const [holderDisplayName, setHolderDisplayName] = useState('');
  const [basisCode, setBasisCode] = useState('AUTHORIZATION');
  const [validFrom, setValidFrom] = useState('');
  const [validTo, setValidTo] = useState('');
  const [territoryCode, setTerritoryCode] = useState('');
  const [languageTag, setLanguageTag] = useState('');
  const [channelCode, setChannelCode] = useState('WEB');
  const [useCode, setUseCode] = useState('DISPLAY');
  const [reason, setReason] = useState('');
  const [supersedesRightsRecordId, setSupersedesRightsRecordId] = useState('');
  const [evidenceFile, setEvidenceFile] = useState<File | null>(null);
  const [requestKey, setRequestKey] = useState(() => crypto.randomUUID());

  const [evalTerritory, setEvalTerritory] = useState('');
  const [evalLanguage, setEvalLanguage] = useState('');
  const [evalChannel, setEvalChannel] = useState('WEB');
  const [evalUse, setEvalUse] = useState('DISPLAY');
  const [evaluation, setEvaluation] = useState<RightsAvailability | null>(null);

  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');

    const result = await client.get<RightsEntry[]>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/rights`,
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

    setRights(result.data);
  }, [recordingId]);

  useEffect(() => {
    void load();
  }, [load]);

  function renewRequestKey() {
    setRequestKey(crypto.randomUUID());
  }

  async function createRights(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    setMessage('');

    if (!evidenceFile) {
      setError('Adjunta la evidencia restringida que sustenta esta autorización.');
      return;
    }

    if (evidenceFile.size <= 0 || evidenceFile.size > maxEvidenceBytes) {
      setError('La evidencia debe pesar como máximo 2 MiB.');
      return;
    }

    if (!territoryCode.trim()) {
      setError(
        'El territorio es obligatorio. La ausencia de territorio nunca se interpreta como autorización mundial.',
      );
      return;
    }

    const from = toUtcOrNull(validFrom);
    const to = toUtcOrNull(validTo);
    if ((validFrom && !from) || (validTo && !to)) {
      setError('La vigencia contiene una fecha no válida.');
      return;
    }

    if (from && to && new Date(to).getTime() <= new Date(from).getTime()) {
      setError('El vencimiento debe ser posterior al inicio de vigencia.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    try {
      const evidenceBase64 = await fileToBase64(evidenceFile);
      const request: RightsRequest = {
        holderType: holderType.trim().toUpperCase(),
        holderDisplayName: holderDisplayName.trim(),
        basisCode: basisCode.trim().toUpperCase(),
        validFrom: from,
        validTo: to,
        evidenceFileName: evidenceFile.name,
        evidenceMediaType: evidenceFile.type || 'application/octet-stream',
        evidenceBase64,
        scopes: [
          {
            territoryCode: territoryCode.trim().toUpperCase(),
            languageTag: languageTag.trim() || null,
            channelCode: channelCode.trim().toUpperCase(),
            useCode: useCode.trim().toUpperCase(),
          },
        ],
        reason: reason.trim(),
        supersedesRightsRecordId: supersedesRightsRecordId.trim() || null,
      };

      const result = await client.post<RightsRequest, RightsCreateResult>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/rights`,
        request,
        {
          headers,
          idempotencyKey: requestKey,
          retry: 'never',
        },
      );

      if (!result.ok) {
        setError(problemMessage(result));
        return;
      }

      setMessage(
        result.data.alreadyApplied
          ? 'La misma operación ya estaba confirmada; no se duplicó el expediente.'
          : 'Derechos guardados con titular, uso, territorio, vigencia y evidencia privada.',
      );
      setHolderDisplayName('');
      setReason('');
      setSupersedesRightsRecordId('');
      setEvidenceFile(null);
      renewRequestKey();
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function evaluate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError('');
    setMessage('');
    setEvaluation(null);

    if (!evalTerritory.trim()) {
      setError('Indica el territorio exacto que quieres evaluar.');
      return;
    }

    const query = new URLSearchParams({
      territoryCode: evalTerritory.trim().toUpperCase(),
      channelCode: evalChannel.trim().toUpperCase(),
      useCode: evalUse.trim().toUpperCase(),
    });
    if (evalLanguage.trim()) query.set('languageTag', evalLanguage.trim());

    setBusy(true);
    const result = await client.get<RightsAvailability>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/rights/evaluate?${query.toString()}`,
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

    setEvaluation(result.data);
  }

  return (
    <section className="rights-admin" aria-labelledby="rights-admin-title">
      <header className="rights-admin__header">
        <p className="rights-admin__eyebrow">BL-MVP-040 · UI-MVP-020</p>
        <h2 id="rights-admin-title">Derechos, usos, territorios y vigencias</h2>
        <p>
          El expediente de derechos pertenece a M15. Una autorización solo habilita los usos y
          territorios declarados; la ausencia de territorio no significa permiso mundial.
        </p>
      </header>
      <ol className="rights-admin__guide" aria-label="Qué necesitas para registrar derechos">
        <li>
          <strong>1. Titular</strong>
          <span>Quién concede o sustenta el permiso.</span>
        </li>
        <li>
          <strong>2. Alcance</strong>
          <span>Territorio, idioma, canal y uso exactos.</span>
        </li>
        <li>
          <strong>3. Vigencia</strong>
          <span>Desde cuándo y, si aplica, hasta cuándo.</span>
        </li>
        <li>
          <strong>4. Evidencia</strong>
          <span>Documento privado que respalda la decisión.</span>
        </li>
      </ol>

      {error ? (
        <StateMessage state="UI-EST-04" title="No se confirmó el cambio" description={error} />
      ) : null}

      {message ? (
        <p className="rights-admin__status" role="status">
          {message}
        </p>
      ) : null}

      <div className="rights-admin__layout">
        <section className="rights-admin__panel" aria-labelledby="rights-existing-title">
          <div>
            <p className="rights-admin__eyebrow">Historial conservado</p>
            <h3 id="rights-existing-title">Autorizaciones registradas</h3>
          </div>

          {loading ? (
            <StateMessage
              state="UI-EST-01"
              title="Cargando derechos"
              description="Consultando el estado confirmado del expediente."
            />
          ) : null}

          {!loading && rights.length === 0 ? (
            <StateMessage
              state="UI-EST-02"
              title="Sin autorización vigente registrada"
              description="La publicación debe permanecer bloqueada hasta conservar alcance y evidencia suficientes."
            />
          ) : null}

          <ol className="rights-admin__records">
            {rights.map((right) => (
              <li className="rights-admin__record" key={right.rightsRecordId}>
                <div className="rights-admin__record-title">
                  <strong>{right.holderDisplayName}</strong>
                  <span>
                    {displayBasis(right.basisCode)} · {displayStatus(right.statusCode)}
                  </span>
                </div>
                <dl>
                  <div>
                    <dt>Expediente</dt>
                    <dd>
                      <code>{right.rightsRecordId}</code>
                    </dd>
                  </div>
                  <div>
                    <dt>Vigencia</dt>
                    <dd>
                      {right.validFrom ? formatDateTime(right.validFrom) : 'Sin inicio declarado'} →{' '}
                      {right.validTo ? formatDateTime(right.validTo) : 'Sin vencimiento declarado'}
                    </dd>
                  </div>
                  <div>
                    <dt>Evidencia privada</dt>
                    <dd>
                      <code>{right.evidenceObjectId}</code> · {right.evidenceMediaType} ·{' '}
                      {formatBytes(right.evidenceSizeBytes)}
                    </dd>
                  </div>
                  <div>
                    <dt>Alcance</dt>
                    <dd>
                      <ul className="rights-admin__scope-badges">
                        {right.scopes.map((scope) => (
                          <li key={scope.rightsScopeId}>
                            Territorio {scope.territoryCode} ·{' '}
                            {scope.languageTag ?? 'cualquier idioma'} ·{' '}
                            {displayChannel(scope.channelCode)} · {displayUse(scope.useCode)}
                          </li>
                        ))}
                      </ul>
                    </dd>
                  </div>
                </dl>
              </li>
            ))}
          </ol>
        </section>

        <section className="rights-admin__panel" aria-labelledby="rights-evaluate-title">
          <div>
            <p className="rights-admin__eyebrow">Revalidación territorial</p>
            <h3 id="rights-evaluate-title">Comprobar disponibilidad</h3>
          </div>

          <form className="rights-admin__form" onSubmit={evaluate}>
            <Field
              id="rights-eval-territory"
              label="Territorio"
              helpText="Código gobernado de país o región. La evaluación es estricta."
              value={evalTerritory}
              onChange={(event) =>
                setEvalTerritory(event.target.value.toUpperCase().replace(/[^A-Z0-9._-]/g, ''))
              }
              pattern="[A-Z0-9][A-Z0-9._-]{0,63}"
              required
            />
            <Field
              id="rights-eval-language"
              label="Idioma"
              helpText="Opcional, por ejemplo es o ja."
              value={evalLanguage}
              onChange={(event) =>
                setEvalLanguage(event.target.value.replace(/[^A-Za-z0-9-]/g, ''))
              }
              pattern="[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*"
              maxLength={35}
            />
            <SelectField
              id="rights-eval-channel"
              label="Canal"
              value={evalChannel}
              onChange={(event) => setEvalChannel(event.target.value)}
              required
            >
              <option value="WEB">Web</option>
            </SelectField>
            <SelectField
              id="rights-eval-use"
              label="Uso"
              value={evalUse}
              onChange={(event) => setEvalUse(event.target.value)}
              required
            >
              <option value="DISPLAY">Mostrar contenido</option>
              <option value="PLAYBACK">Reproducción</option>
              <option value="TRANSLATION">Traducción</option>
              <option value="ADAPTATION">Adaptación</option>
              <option value="DISTRIBUTION">Distribución</option>
              <option value="EXPORT">Exportación</option>
            </SelectField>
            <Button type="submit" variant="secondary" disabled={busy}>
              Evaluar alcance
            </Button>
          </form>

          {evaluation ? (
            <div
              className="rights-admin__evaluation"
              data-allowed={evaluation.allowed ? 'true' : 'false'}
              role="status"
            >
              <strong>{evaluation.allowed ? 'Uso autorizado' : 'Uso bloqueado'}</strong>
              <code className="rights-admin__technical-code">{evaluation.code}</code>
              <p>{evaluation.description}</p>
            </div>
          ) : null}
        </section>
      </div>

      {canWrite ? (
        <section
          className="rights-admin__panel rights-admin__panel--wide"
          aria-labelledby="rights-create-title"
        >
          <div>
            <p className="rights-admin__eyebrow">Nueva decisión versionada</p>
            <h3 id="rights-create-title">Registrar autorización</h3>
          </div>

          <form className="rights-admin__form rights-admin__form--grid" onSubmit={createRights}>
            <div className="rights-admin__form-step">
              <span>Paso 1</span>
              <strong>Titular y base de autorización</strong>
              <small>Identifica quién respalda la decisión y bajo qué figura.</small>
            </div>

            <SelectField
              id="rights-holder-type"
              label="Tipo de titular"
              value={holderType}
              onChange={(event) => {
                setHolderType(event.target.value);
                renewRequestKey();
              }}
            >
              <option value="ORGANIZATION">Organización</option>
              <option value="PERSON">Persona</option>
              <option value="RIGHTS_AGENCY">Agencia o representante</option>
            </SelectField>

            <Field
              id="rights-holder-name"
              label="Titular declarado"
              helpText="Registrar una declaración no equivale a afirmar que la titularidad fue verificada."
              value={holderDisplayName}
              onChange={(event) => {
                setHolderDisplayName(event.target.value);
                renewRequestKey();
              }}
              maxLength={512}
              required
            />

            <SelectField
              id="rights-basis-code"
              label="Base de autorización"
              value={basisCode}
              onChange={(event) => {
                setBasisCode(event.target.value);
                renewRequestKey();
              }}
            >
              <option value="AUTHORIZATION">Autorización</option>
              <option value="LICENSE">Licencia</option>
              <option value="PUBLIC_DOMAIN">Dominio público documentado</option>
              <option value="PERMITTED_USE">Uso permitido documentado</option>
            </SelectField>

            <div className="rights-admin__form-step">
              <span>Paso 2</span>
              <strong>Alcance y vigencia</strong>
              <small>Define exactamente dónde, cómo y durante cuánto tiempo aplica.</small>
            </div>

            <Field
              id="rights-valid-from"
              label="Inicio de vigencia"
              type="datetime-local"
              value={validFrom}
              onChange={(event) => {
                setValidFrom(event.target.value);
                renewRequestKey();
              }}
            />

            <Field
              id="rights-valid-to"
              label="Vencimiento"
              type="datetime-local"
              value={validTo}
              onChange={(event) => {
                setValidTo(event.target.value);
                renewRequestKey();
              }}
            />

            <Field
              id="rights-territory"
              label="Territorio autorizado"
              helpText="Obligatorio. No se interpreta un valor vacío como autorización mundial."
              value={territoryCode}
              onChange={(event) => {
                setTerritoryCode(event.target.value.toUpperCase().replace(/[^A-Z0-9._-]/g, ''));
                renewRequestKey();
              }}
              pattern="[A-Z0-9][A-Z0-9._-]{0,63}"
              required
            />

            <Field
              id="rights-language"
              label="Idioma del alcance"
              helpText="Opcional. Vacío significa que esta autorización no restringe por idioma."
              value={languageTag}
              onChange={(event) => {
                setLanguageTag(event.target.value.replace(/[^A-Za-z0-9-]/g, ''));
                renewRequestKey();
              }}
              pattern="[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*"
              maxLength={35}
            />

            <SelectField
              id="rights-channel"
              label="Canal autorizado"
              helpText="El MVP publica únicamente en el canal web; el código técnico no se escribe a mano."
              value={channelCode}
              onChange={(event) => {
                setChannelCode(event.target.value);
                renewRequestKey();
              }}
              required
            >
              <option value="WEB">Web</option>
            </SelectField>

            <SelectField
              id="rights-use"
              label="Uso autorizado"
              helpText="Elige el uso cubierto por la evidencia adjunta."
              value={useCode}
              onChange={(event) => {
                setUseCode(event.target.value);
                renewRequestKey();
              }}
              required
            >
              <option value="DISPLAY">Mostrar contenido</option>
              <option value="PLAYBACK">Reproducción</option>
              <option value="TRANSLATION">Traducción</option>
              <option value="ADAPTATION">Adaptación</option>
              <option value="DISTRIBUTION">Distribución</option>
              <option value="EXPORT">Exportación</option>
            </SelectField>

            <div className="rights-admin__form-step">
              <span>Paso 3</span>
              <strong>Motivo, versión y evidencia</strong>
              <small>
                Deja una justificación auditable y adjunta el documento que la sustenta.
              </small>
            </div>

            <Field
              id="rights-supersedes"
              label="Sustituye expediente"
              helpText="Opcional. Usa el UUID de una autorización activa para crear una nueva versión sin borrar la anterior."
              value={supersedesRightsRecordId}
              onChange={(event) => {
                setSupersedesRightsRecordId(event.target.value);
                renewRequestKey();
              }}
            />

            <Field
              id="rights-reason"
              label="Motivo de la decisión"
              value={reason}
              onChange={(event) => {
                setReason(event.target.value);
                renewRequestKey();
              }}
              maxLength={2000}
              required
            />

            <div className="rights-admin__file-field">
              <label htmlFor="rights-evidence">Evidencia de derechos *</label>
              <p id="rights-evidence-help">
                PDF, TXT, PNG o JPEG; máximo 2 MiB. Se cifra en el almacén privado y la pantalla
                solo expone su identificador y metadatos mínimos.
              </p>
              <input
                id="rights-evidence"
                type="file"
                accept="application/pdf,text/plain,image/png,image/jpeg"
                aria-describedby="rights-evidence-help rights-evidence-selected"
                onChange={(event) => {
                  setEvidenceFile(event.target.files?.[0] ?? null);
                  renewRequestKey();
                }}
                required
              />
              <p
                className="rights-admin__selected-file"
                id="rights-evidence-selected"
                role="status"
              >
                {evidenceFile
                  ? `Archivo seleccionado: ${evidenceFile.name} · ${formatBytes(evidenceFile.size)}`
                  : 'Todavía no has seleccionado evidencia.'}
              </p>
            </div>

            <div className="rights-admin__actions">
              <Button type="submit" disabled={busy}>
                {busy ? 'Confirmando…' : 'Guardar autorización'}
              </Button>
            </div>
          </form>
        </section>
      ) : (
        <StateMessage
          state="UI-EST-03"
          title="Modo de revisión"
          description="Puedes consultar y evaluar el alcance, pero la sesión no posee EDITORIAL.DRAFT para crear o sustituir autorizaciones."
        />
      )}
    </section>
  );
}
