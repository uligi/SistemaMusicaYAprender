import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import './role-management.css';

type Scope = {
  scopeId: string;
  scopeType: string;
  moduleCode?: string | null;
  objectId?: string | null;
};

type Catalog = {
  roles: string[];
  scopes: Scope[];
};

type Assignment = {
  assignmentId: string;
  accountId: string;
  roleCode: string;
  scope?: Scope | null;
  validFrom: string;
  validTo?: string | null;
  reason: string;
  state: string;
};

type Mutation = {
  assignment: Assignment;
  alreadyApplied: boolean;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

const client = createHttpClient();

function scopeLabel(scope: Scope): string {
  if (scope.scopeType === 'GLOBAL') return 'Global';
  if (scope.scopeType === 'MODULE') return `Módulo ${scope.moduleCode ?? 'sin código'}`;
  if (scope.scopeType === 'OBJECT') {
    return `${scope.moduleCode ?? 'Objeto'} · ${scope.objectId ?? scope.scopeId}`;
  }
  return `${scope.scopeType} · ${scope.scopeId}`;
}

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

export function RoleManagementPage() {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [targetAccount, setTargetAccount] = useState('');
  const [roleCode, setRoleCode] = useState('');
  const [scopeId, setScopeId] = useState('');
  const [validUntil, setValidUntil] = useState('');
  const [reason, setReason] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;

    void (async () => {
      const result = await client.get<Catalog>('/security/role-assignments/catalog', {
        cacheMode: 'no-store',
        retry: 'never',
      });

      if (!active) return;

      if (!result.ok) {
        setError(problemMessage(result));
        return;
      }

      setCatalog(result.data);
      setRoleCode(result.data.roles[0] ?? '');
    })();

    return () => {
      active = false;
    };
  }, []);

  const targetValid = useMemo(
    () => /^[0-9a-fA-F-]{36}$/.test(targetAccount.trim()),
    [targetAccount],
  );

  async function loadAssignments(): Promise<void> {
    setMessage('');
    setError('');

    if (!targetValid) {
      setError('Ingresa un UUID de cuenta válido.');
      return;
    }

    setBusy(true);
    const result = await client.get<Assignment[]>(
      `/security/role-assignments/${encodeURIComponent(targetAccount.trim())}`,
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

    setAssignments(result.data);
  }

  async function grant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage('');
    setError('');

    if (!targetValid || !roleCode || !reason.trim()) {
      setError('Cuenta, rol y motivo son obligatorios.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    const parsedValidUntil = validUntil ? new Date(validUntil) : null;
    if (parsedValidUntil && Number.isNaN(parsedValidUntil.getTime())) {
      setError('La vigencia final no es válida.');
      return;
    }

    setBusy(true);
    const result = await client.post<
      {
        accountId: string;
        roleCode: string;
        scopeId: string | null;
        validUntil: string | null;
        reason: string;
      },
      Mutation
    >(
      '/security/role-assignments',
      {
        accountId: targetAccount.trim(),
        roleCode,
        scopeId: scopeId || null,
        validUntil: parsedValidUntil?.toISOString() ?? null,
        reason: reason.trim(),
      },
      {
        headers,
        idempotencyKey: crypto.randomUUID(),
        invalidate: ['/security/role-assignments'],
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setAssignments((current) => {
      const withoutSameAssignment = current.filter(
        (assignment) => assignment.assignmentId !== result.data.assignment.assignmentId,
      );

      return [result.data.assignment, ...withoutSameAssignment];
    });
    setReason('');
    setMessage(
      result.data.alreadyApplied
        ? 'La asignación ya existía con la misma vigencia y motivo.'
        : 'Asignación aplicada y auditada.',
    );
  }

  async function revoke(assignmentId: string) {
    setMessage('');
    setError('');

    if (!revokeReason.trim()) {
      setError('Escribe el motivo del retiro antes de revocar.');
      return;
    }

    const headers = await csrfHeaders();
    if (!headers) {
      setError('No fue posible obtener la protección CSRF. Actualiza la página.');
      return;
    }

    setBusy(true);
    const result = await client.post<{ reason: string }, Mutation>(
      `/security/role-assignments/${assignmentId}/revoke`,
      { reason: revokeReason.trim() },
      {
        headers,
        idempotencyKey: crypto.randomUUID(),
        invalidate: ['/security/role-assignments'],
      },
    );
    setBusy(false);

    if (!result.ok) {
      setError(problemMessage(result));
      return;
    }

    setAssignments((current) =>
      current.map((assignment) =>
        assignment.assignmentId === result.data.assignment.assignmentId
          ? result.data.assignment
          : assignment,
      ),
    );
    setRevokeReason('');
    setMessage(
      result.data.alreadyApplied
        ? 'La asignación ya no estaba vigente.'
        : 'Asignación retirada y auditada.',
    );
  }

  return (
    <section className="role-management" aria-labelledby="role-management-title">
      <header className="role-management__header">
        <p className="role-management__eyebrow">Gobierno · M18</p>
        <h1 id="role-management-title">Roles y permisos</h1>
        <p>
          Asigna roles existentes con alcance y vigencia explícitos. El servidor vuelve a comprobar
          <code> SECURITY.MANAGE_ROLES </code>
          en cada operación; ocultar esta pantalla no concede privilegios.
        </p>
      </header>

      {error ? (
        <StateMessage state="UI-EST-04" title="No se aplicó el cambio" description={error} />
      ) : null}
      {message ? (
        <p className="role-management__success" role="status">
          {message}
        </p>
      ) : null}

      <div className="role-management__grid">
        <form className="role-management__panel" onSubmit={grant}>
          <h2>Nueva asignación</h2>

          <Field
            id="role-target-account"
            label="Cuenta objetivo"
            helpText="UUID de la cuenta. Este flujo no busca ni expone correos."
            value={targetAccount}
            onChange={(event) => setTargetAccount(event.target.value)}
            required
          />

          <SelectField
            id="role-code"
            label="Rol"
            value={roleCode}
            onChange={(event) => setRoleCode(event.target.value)}
            required
          >
            {(catalog?.roles ?? []).map((role) => (
              <option key={role} value={role}>
                {role}
              </option>
            ))}
          </SelectField>

          <SelectField
            id="role-scope"
            label="Alcance"
            helpText="Global usa la asignación sin scope_id. Los demás alcances provienen del catálogo."
            value={scopeId}
            onChange={(event) => setScopeId(event.target.value)}
          >
            <option value="">Global</option>
            {(catalog?.scopes ?? []).map((scope) => (
              <option key={scope.scopeId} value={scope.scopeId}>
                {scopeLabel(scope)}
              </option>
            ))}
          </SelectField>

          <Field
            id="role-valid-until"
            label="Vigente hasta"
            helpText="Opcional. Si se omite, la asignación permanece vigente hasta ser retirada."
            type="datetime-local"
            value={validUntil}
            onChange={(event) => setValidUntil(event.target.value)}
          />

          <Field
            id="role-reason"
            label="Motivo"
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            maxLength={1000}
            required
          />

          <div className="role-management__actions">
            <Button type="submit" disabled={busy || !catalog}>
              Asignar rol
            </Button>
            <Button
              type="button"
              variant="secondary"
              disabled={busy}
              onClick={() => void loadAssignments()}
            >
              Consultar asignaciones
            </Button>
          </div>
        </form>

        <section className="role-management__panel" aria-labelledby="current-assignments-title">
          <h2 id="current-assignments-title">Asignaciones de la cuenta</h2>

          <Field
            id="role-revoke-reason"
            label="Motivo para retirar"
            helpText="Se conserva en la auditoría de la revocación."
            value={revokeReason}
            onChange={(event) => setRevokeReason(event.target.value)}
            maxLength={1000}
          />

          {assignments.length === 0 ? (
            <p className="role-management__empty">
              Consulta una cuenta para ver sus asignaciones, o no existen asignaciones registradas.
            </p>
          ) : (
            <ul className="role-management__assignments">
              {assignments.map((assignment) => (
                <li key={assignment.assignmentId}>
                  <div>
                    <strong>{assignment.roleCode}</strong>
                    <span>{assignment.scope ? scopeLabel(assignment.scope) : 'Global'}</span>
                    <span>Estado: {assignment.state}</span>
                    <span>
                      Desde {new Date(assignment.validFrom).toLocaleString('es-CR')}
                      {assignment.validTo
                        ? ` hasta ${new Date(assignment.validTo).toLocaleString('es-CR')}`
                        : ' · sin vencimiento'}
                    </span>
                    <small>Motivo de asignación: {assignment.reason}</small>
                  </div>
                  <Button
                    variant="danger"
                    disabled={busy || assignment.state !== 'ACTIVE'}
                    onClick={() => void revoke(assignment.assignmentId)}
                  >
                    Retirar
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </section>
  );
}
