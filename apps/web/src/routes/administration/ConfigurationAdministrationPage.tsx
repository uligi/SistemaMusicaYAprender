import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import { PrivilegedAssurancePanel } from './PrivilegedAssurancePanel';
import './role-management.css';
import './configuration-administration.css';

type ParameterView = {
  parameterKey: string;
  ownerModule: string;
  valueType: string;
  validationSchemaJson: string;
  parameterVersionId: string;
  currentVersionNo: number;
  scopeCode: string;
  scopeValue?: string | null;
  currentValueJson: string;
  validFrom: string;
  validTo?: string | null;
  projectionVersion: number;
};

type CatalogEntryView = {
  catalogEntryId: string;
  entryCode: string;
  labelsJson: string;
  valueJson: string;
  validFrom: string;
  validTo?: string | null;
  version: number;
};

type CatalogView = {
  catalogCode: string;
  ownerModule: string;
  valueSchemaJson: string;
  definitionVersion: number;
  entries: CatalogEntryView[];
};

type Snapshot = {
  parameters: ParameterView[];
  catalogs: CatalogView[];
};

type Simulation = {
  objectType: string;
  objectKey: string;
  ownerModule: string;
  canActivate: boolean;
  checks: string[];
  beforeJson: string;
  afterJson: string;
  expectedVersion: number;
  currentValidUntil?: string | null;
  proposedValidUntil?: string | null;
  historicalValueWillBePreserved: boolean;
};

type Activation = {
  objectType: string;
  objectKey: string;
  ownerModule: string;
  activeObjectId: string;
  activeVersion: number;
  effectiveFrom: string;
  effectiveUntil?: string | null;
  previousObjectId: string;
  changeSetId: string;
  activationId: string;
  historicalValuePreserved: boolean;
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
    const problem = (result as { problem?: { detail?: string; title?: string } }).problem;
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

function toIsoOrNull(value: string): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

export function ConfigurationAdministrationPage() {
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [privilegedReady, setPrivilegedReady] = useState(false);

  const [parameterKey, setParameterKey] = useState('');
  const [parameterValue, setParameterValue] = useState('');
  const [parameterValidUntil, setParameterValidUntil] = useState('');
  const [parameterReason, setParameterReason] = useState('');
  const [parameterImpact, setParameterImpact] = useState('');
  const [parameterSimulation, setParameterSimulation] = useState<Simulation | null>(null);

  const [catalogCode, setCatalogCode] = useState('');
  const [entryCode, setEntryCode] = useState('');
  const [catalogLabels, setCatalogLabels] = useState('');
  const [catalogValue, setCatalogValue] = useState('');
  const [catalogValidUntil, setCatalogValidUntil] = useState('');
  const [catalogReason, setCatalogReason] = useState('');
  const [catalogImpact, setCatalogImpact] = useState('');
  const [catalogSimulation, setCatalogSimulation] = useState<Simulation | null>(null);

  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const selectedParameter = useMemo(
    () =>
      snapshot?.parameters.find(
        (parameter) =>
          parameter.parameterKey === parameterKey &&
          parameter.scopeCode === 'GLOBAL' &&
          !parameter.scopeValue,
      ) ?? null,
    [parameterKey, snapshot],
  );

  const selectedCatalog = useMemo(
    () => snapshot?.catalogs.find((catalog) => catalog.catalogCode === catalogCode) ?? null,
    [catalogCode, snapshot],
  );

  const selectedEntry = useMemo(
    () => selectedCatalog?.entries.find((entry) => entry.entryCode === entryCode) ?? null,
    [entryCode, selectedCatalog],
  );

  const loadSnapshot = useCallback(async () => {
    setError('');
    const result = await client.get<Snapshot>('/administration/configuration', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!result.ok) {
      setSnapshot(null);
      setError(problemMessage(result));
      return;
    }

    setSnapshot(result.data);

    const firstParameter =
      result.data.parameters.find(
        (parameter) => parameter.scopeCode === 'GLOBAL' && !parameter.scopeValue,
      ) ?? result.data.parameters[0];
    if (firstParameter) {
      setParameterKey((current) => current || firstParameter.parameterKey);
    }

    const firstCatalog = result.data.catalogs[0];
    if (firstCatalog) {
      setCatalogCode((current) => current || firstCatalog.catalogCode);
    }
  }, []);

  useEffect(() => {
    if (!privilegedReady) {
      setSnapshot(null);
      return;
    }

    void loadSnapshot();
  }, [loadSnapshot, privilegedReady]);

  useEffect(() => {
    if (!selectedParameter) return;

    setParameterValue(selectedParameter.currentValueJson);
    setParameterSimulation(null);
  }, [selectedParameter]);

  useEffect(() => {
    const firstEntry = selectedCatalog?.entries[0];
    setEntryCode(firstEntry?.entryCode ?? '');
    setCatalogSimulation(null);
  }, [selectedCatalog]);

  useEffect(() => {
    if (!selectedEntry) return;

    setCatalogLabels(selectedEntry.labelsJson);
    setCatalogValue(selectedEntry.valueJson);
    setCatalogSimulation(null);
  }, [selectedEntry]);

  function clearStatus() {
    setMessage('');
    setError('');
  }

  async function simulateParameter(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    clearStatus();

    if (!selectedParameter || !parameterReason.trim() || !parameterImpact.trim()) {
      setError('Parámetro, motivo e impacto son obligatorios.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<Record<string, unknown>, Simulation>(
      '/administration/configuration/parameters/simulate',
      {
        parameterKey: selectedParameter.parameterKey,
        scopeCode: selectedParameter.scopeCode,
        scopeValue: selectedParameter.scopeValue ?? null,
        typedValueJson: parameterValue,
        validUntil: toIsoOrNull(parameterValidUntil),
        reason: parameterReason.trim(),
        impact: parameterImpact.trim(),
        expectedVersionNo: selectedParameter.currentVersionNo,
      },
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

    setParameterSimulation(result.data);
    setMessage(
      result.data.canActivate
        ? 'Simulación aprobada. Revisa el antes/después y confirma la activación.'
        : 'La simulación detectó condiciones que bloquean la activación.',
    );
  }

  async function activateParameter() {
    clearStatus();

    if (!selectedParameter || !parameterSimulation?.canActivate) {
      setError('Simula nuevamente el cambio antes de activarlo.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<Record<string, unknown>, Activation>(
      '/administration/configuration/parameters/activate',
      {
        parameterKey: selectedParameter.parameterKey,
        scopeCode: selectedParameter.scopeCode,
        scopeValue: selectedParameter.scopeValue ?? null,
        typedValueJson: parameterValue,
        validUntil: toIsoOrNull(parameterValidUntil),
        reason: parameterReason.trim(),
        impact: parameterImpact.trim(),
        expectedVersionNo: selectedParameter.currentVersionNo,
      },
      {
        headers,
        idempotencyKey: crypto.randomUUID(),
        invalidate: ['/administration/configuration'],
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      setParameterSimulation(null);
      return;
    }

    setMessage(
      result.data.alreadyApplied
        ? 'La misma versión ya estaba efectiva; no se creó una versión duplicada.'
        : `Parámetro activado como versión ${result.data.activeVersion}. La versión anterior permanece en el historial.`,
    );
    setParameterSimulation(null);
    setParameterReason('');
    setParameterImpact('');
    await loadSnapshot();
  }

  async function simulateCatalog(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    clearStatus();

    if (!selectedCatalog || !selectedEntry || !catalogReason.trim() || !catalogImpact.trim()) {
      setError('Catálogo, entrada, motivo e impacto son obligatorios.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<Record<string, unknown>, Simulation>(
      '/administration/configuration/catalogs/simulate',
      {
        catalogCode: selectedCatalog.catalogCode,
        entryCode: selectedEntry.entryCode,
        labelsJson: catalogLabels,
        valueJson: catalogValue,
        validUntil: toIsoOrNull(catalogValidUntil),
        reason: catalogReason.trim(),
        impact: catalogImpact.trim(),
        expectedEntryId: selectedEntry.catalogEntryId,
        expectedVersion: selectedEntry.version,
      },
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

    setCatalogSimulation(result.data);
    setMessage(
      result.data.canActivate
        ? 'Simulación del catálogo aprobada. La versión vigente no se sobrescribirá.'
        : 'La simulación detectó condiciones que bloquean la activación.',
    );
  }

  async function activateCatalog() {
    clearStatus();

    if (!selectedCatalog || !selectedEntry || !catalogSimulation?.canActivate) {
      setError('Simula nuevamente el cambio antes de activarlo.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<Record<string, unknown>, Activation>(
      '/administration/configuration/catalogs/activate',
      {
        catalogCode: selectedCatalog.catalogCode,
        entryCode: selectedEntry.entryCode,
        labelsJson: catalogLabels,
        valueJson: catalogValue,
        validUntil: toIsoOrNull(catalogValidUntil),
        reason: catalogReason.trim(),
        impact: catalogImpact.trim(),
        expectedEntryId: selectedEntry.catalogEntryId,
        expectedVersion: selectedEntry.version,
      },
      {
        headers,
        idempotencyKey: crypto.randomUUID(),
        invalidate: ['/administration/configuration'],
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      setCatalogSimulation(null);
      return;
    }

    setMessage(
      result.data.alreadyApplied
        ? 'La misma entrada ya estaba efectiva; no se creó un duplicado.'
        : 'Entrada activada y auditada. La entrada histórica anterior permanece almacenada.',
    );
    setCatalogSimulation(null);
    setCatalogReason('');
    setCatalogImpact('');
    await loadSnapshot();
  }

  return (
    <section className="configuration-administration" aria-labelledby="configuration-title">
      <header className="configuration-administration__header">
        <p className="configuration-administration__eyebrow">Gobierno · M19</p>
        <h1 id="configuration-title">Catálogos y parámetros</h1>
        <p>
          Cada activación exige permisos efectivos, verificación reforzada, simulación, impacto,
          vigencia y motivo. Una versión usada históricamente se cierra por vigencia, pero no se
          elimina ni se sobrescribe.
        </p>
      </header>

      <PrivilegedAssurancePanel onReadyChange={setPrivilegedReady} />

      {error ? (
        <StateMessage state="UI-EST-04" title="No se aplicó el cambio" description={error} />
      ) : null}
      {message ? (
        <p className="configuration-administration__success" role="status">
          {message}
        </p>
      ) : null}

      {privilegedReady && snapshot ? (
        <div className="configuration-administration__grid">
          <form className="configuration-administration__panel" onSubmit={simulateParameter}>
            <div>
              <p className="configuration-administration__eyebrow">Parámetros versionados</p>
              <h2>Cambiar valor efectivo</h2>
            </div>

            <SelectField
              id="configuration-parameter"
              label="Parámetro"
              value={parameterKey}
              onChange={(event) => setParameterKey(event.target.value)}
              required
            >
              {snapshot.parameters
                .filter((parameter) => parameter.scopeCode === 'GLOBAL' && !parameter.scopeValue)
                .map((parameter) => (
                  <option key={parameter.parameterKey} value={parameter.parameterKey}>
                    {parameter.parameterKey} · {parameter.ownerModule}
                  </option>
                ))}
            </SelectField>

            {selectedParameter ? (
              <p className="configuration-administration__meta">
                Tipo: {selectedParameter.valueType} · versión efectiva{' '}
                {selectedParameter.currentVersionNo} · proyección{' '}
                {selectedParameter.projectionVersion}
              </p>
            ) : null}

            <label className="configuration-administration__field" htmlFor="parameter-value">
              <span>Valor JSON</span>
              <textarea
                id="parameter-value"
                value={parameterValue}
                onChange={(event) => {
                  setParameterValue(event.target.value);
                  setParameterSimulation(null);
                }}
                rows={4}
                maxLength={8192}
                required
              />
            </label>

            <Field
              id="parameter-valid-until"
              label="Vigente hasta"
              helpText="Opcional. La versión entra en vigor al activarse; esta fecha define su fin."
              type="datetime-local"
              value={parameterValidUntil}
              onChange={(event) => {
                setParameterValidUntil(event.target.value);
                setParameterSimulation(null);
              }}
            />

            <Field
              id="parameter-reason"
              label="Motivo"
              value={parameterReason}
              onChange={(event) => {
                setParameterReason(event.target.value);
                setParameterSimulation(null);
              }}
              maxLength={160}
              required
            />

            <label className="configuration-administration__field" htmlFor="parameter-impact">
              <span>Impacto y dependencias</span>
              <textarea
                id="parameter-impact"
                value={parameterImpact}
                onChange={(event) => {
                  setParameterImpact(event.target.value);
                  setParameterSimulation(null);
                }}
                rows={4}
                maxLength={240}
                required
              />
              <small>
                Describe consumidores, datos, procesos, integraciones, seguridad y recuperación
                afectados.
              </small>
            </label>

            {parameterSimulation ? <SimulationResult simulation={parameterSimulation} /> : null}

            <div className="configuration-administration__actions">
              <Button type="submit" disabled={busy || !selectedParameter}>
                Simular cambio de parámetro
              </Button>
              <Button
                type="button"
                variant="secondary"
                disabled={busy || !parameterSimulation?.canActivate}
                onClick={() => void activateParameter()}
              >
                Activar parámetro
              </Button>
            </div>
          </form>

          <form className="configuration-administration__panel" onSubmit={simulateCatalog}>
            <div>
              <p className="configuration-administration__eyebrow">Catálogos versionados</p>
              <h2>Cambiar entrada</h2>
            </div>

            <SelectField
              id="configuration-catalog"
              label="Catálogo"
              value={catalogCode}
              onChange={(event) => setCatalogCode(event.target.value)}
              required
            >
              {snapshot.catalogs.map((catalog) => (
                <option key={catalog.catalogCode} value={catalog.catalogCode}>
                  {catalog.catalogCode} · {catalog.ownerModule}
                </option>
              ))}
            </SelectField>

            <SelectField
              id="configuration-entry"
              label="Entrada vigente"
              value={entryCode}
              onChange={(event) => setEntryCode(event.target.value)}
              required
            >
              {(selectedCatalog?.entries ?? []).map((entry) => (
                <option key={entry.catalogEntryId} value={entry.entryCode}>
                  {entry.entryCode} · row v{entry.version}
                </option>
              ))}
            </SelectField>

            <label className="configuration-administration__field" htmlFor="catalog-labels">
              <span>Etiquetas JSON</span>
              <textarea
                id="catalog-labels"
                value={catalogLabels}
                onChange={(event) => {
                  setCatalogLabels(event.target.value);
                  setCatalogSimulation(null);
                }}
                rows={4}
                maxLength={8192}
                required
              />
              <small>Debe conservar como mínimo una etiqueta española no vacía.</small>
            </label>

            <label className="configuration-administration__field" htmlFor="catalog-value">
              <span>Valor JSON</span>
              <textarea
                id="catalog-value"
                value={catalogValue}
                onChange={(event) => {
                  setCatalogValue(event.target.value);
                  setCatalogSimulation(null);
                }}
                rows={4}
                maxLength={8192}
                required
              />
            </label>

            <Field
              id="catalog-valid-until"
              label="Vigente hasta"
              helpText="Opcional. La versión anterior conserva su valor y recibe fin de vigencia."
              type="datetime-local"
              value={catalogValidUntil}
              onChange={(event) => {
                setCatalogValidUntil(event.target.value);
                setCatalogSimulation(null);
              }}
            />

            <Field
              id="catalog-reason"
              label="Motivo del catálogo"
              value={catalogReason}
              onChange={(event) => {
                setCatalogReason(event.target.value);
                setCatalogSimulation(null);
              }}
              maxLength={160}
              required
            />

            <label className="configuration-administration__field" htmlFor="catalog-impact">
              <span>Impacto y dependencias del catálogo</span>
              <textarea
                id="catalog-impact"
                value={catalogImpact}
                onChange={(event) => {
                  setCatalogImpact(event.target.value);
                  setCatalogSimulation(null);
                }}
                rows={4}
                maxLength={240}
                required
              />
            </label>

            {catalogSimulation ? <SimulationResult simulation={catalogSimulation} /> : null}

            <div className="configuration-administration__actions">
              <Button type="submit" disabled={busy || !selectedCatalog || !selectedEntry}>
                Simular cambio de catálogo
              </Button>
              <Button
                type="button"
                variant="secondary"
                disabled={busy || !catalogSimulation?.canActivate}
                onClick={() => void activateCatalog()}
              >
                Activar entrada
              </Button>
            </div>
          </form>
        </div>
      ) : null}

      {privilegedReady && !snapshot && !error ? (
        <p role="status">Cargando configuración gobernada…</p>
      ) : null}

      {!privilegedReady ? (
        <p className="configuration-administration__locked">
          Confirma la verificación reforzada antes de consultar o cambiar configuración.
        </p>
      ) : null}
    </section>
  );
}

function SimulationResult({ simulation }: { simulation: Simulation }) {
  return (
    <section
      className="configuration-administration__simulation"
      aria-label={`Simulación ${simulation.objectKey}`}
    >
      <h3>{simulation.canActivate ? 'Simulación válida' : 'Simulación bloqueada'}</h3>
      <p>
        Propietario: {simulation.ownerModule} · versión base {simulation.expectedVersion}
      </p>
      <dl>
        <div>
          <dt>Antes</dt>
          <dd>
            <code>{simulation.beforeJson}</code>
          </dd>
        </div>
        <div>
          <dt>Después</dt>
          <dd>
            <code>{simulation.afterJson}</code>
          </dd>
        </div>
      </dl>
      {simulation.checks.length > 0 ? (
        <ul>
          {simulation.checks.map((check) => (
            <li key={check}>{check}</li>
          ))}
        </ul>
      ) : (
        <p>Esquema, vigencia, alcance, impacto e historial: conformes.</p>
      )}
    </section>
  );
}
