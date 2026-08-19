import { useEffect, useState } from 'react';
import { Button, Field, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import { normalizeDirectoryQuery } from '../../domain/identity/username';
import './account-directory-picker.css';

const client = createHttpClient();

export type AccountDirectoryItem = {
  accountId: string;
  username: string;
  displayName: string | null;
  statusCode: string;
  roleCodes: string[];
};

type AccountDirectoryPickerProps = {
  selected: AccountDirectoryItem | null;
  disabled?: boolean;
  onSelect: (item: AccountDirectoryItem | null) => void;
};

export function AccountDirectoryPicker({
  selected,
  disabled = false,
  onSelect,
}: AccountDirectoryPickerProps) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<AccountDirectoryItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => {
    if (disabled || selected) return;

    const normalized = normalizeDirectoryQuery(query);
    if (normalized.length < 2) {
      setResults([]);
      setLoading(false);
      setMessage('');
      return;
    }

    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      setLoading(true);
      setMessage('');

      void (async () => {
        const result = await client.get<AccountDirectoryItem[]>(
          `/security/account-directory?query=${encodeURIComponent(normalized)}`,
          {
            cacheMode: 'no-store',
            retry: 'never',
            signal: controller.signal,
          },
        );

        if (result.kind === 'cancelled') return;
        setLoading(false);

        if (!result.ok) {
          setResults([]);
          setMessage(result.problem.correction);
          return;
        }

        setResults(result.data);
        setMessage(
          result.data.length === 0
            ? 'No hay cuentas activas con un nombre de usuario que empiece así.'
            : '',
        );
      })();
    }, 250);

    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [disabled, query, selected]);

  if (selected) {
    return (
      <div className="account-directory-picker">
        <span className="account-directory-picker__label">Cuenta objetivo</span>
        <div className="account-directory-picker__selected">
          <div>
            <strong>@{selected.username}</strong>
            {selected.displayName ? <span>{selected.displayName}</span> : null}
            <small>
              {selected.roleCodes.length > 0
                ? `Roles vigentes: ${selected.roleCodes.join(', ')}`
                : 'Sin roles vigentes'}
            </small>
          </div>
          <Button
            disabled={disabled}
            onClick={() => {
              onSelect(null);
              setQuery('');
              setResults([]);
            }}
            type="button"
            variant="secondary"
          >
            Cambiar cuenta
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="account-directory-picker">
      <Field
        autoComplete="off"
        helpText="Busca por @username. El directorio administrativo no devuelve correos ni credenciales."
        id="role-target-account"
        label="Buscar cuenta por nombre de usuario"
        maxLength={33}
        onChange={(event) => setQuery(event.currentTarget.value)}
        placeholder="@reviewer01"
        spellCheck={false}
        value={query}
      />

      {loading ? <p className="account-directory-picker__status">Buscando cuentas…</p> : null}

      {message ? (
        <StateMessage description={message} state="UI-EST-02" title="Sin cuenta seleccionada" />
      ) : null}

      {results.length > 0 ? (
        <ul className="account-directory-picker__results" aria-label="Resultados de cuentas">
          {results.map((item) => (
            <li key={item.accountId}>
              <button type="button" disabled={disabled} onClick={() => onSelect(item)}>
                <strong>@{item.username}</strong>
                {item.displayName ? <span>{item.displayName}</span> : null}
                <small>
                  {item.roleCodes.length > 0 ? item.roleCodes.join(' · ') : 'Sin roles vigentes'}
                </small>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
