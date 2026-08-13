import { Button, Field } from '../../components/ui';
import type { LyricsToken } from './LyricsStructurePage';
import './lyrics-token-segmentation.css';

export type EditableTokenRange = {
  clientId: string;
  startOffset: string;
  endOffset: string;
};

export type PersistedTokenRange = {
  surface: string;
  startOffset: number;
  endOffset: number;
};

export type LyricsTokenSegmentationEditorProps = {
  japaneseText: string;
  tokens: EditableTokenRange[];
  disabled?: boolean;
  onChange: (tokens: EditableTokenRange[]) => void;
};

function parseOffset(value: string): number | null {
  if (!/^\d+$/.test(value.trim())) {
    return null;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function isUtf16Boundary(text: string, index: number): boolean {
  if (index <= 0 || index >= text.length) {
    return true;
  }

  const before = text.charCodeAt(index - 1);
  const after = text.charCodeAt(index);

  return !(before >= 0xd800 && before <= 0xdbff && after >= 0xdc00 && after <= 0xdfff);
}

function nextUtf16Boundary(text: string, index: number): number {
  if (index >= text.length) {
    return text.length;
  }

  const codePoint = text.codePointAt(index);
  return Math.min(text.length, index + (codePoint !== undefined && codePoint > 0xffff ? 2 : 1));
}

function parsedRange(token: EditableTokenRange) {
  return {
    startOffset: parseOffset(token.startOffset),
    endOffset: parseOffset(token.endOffset),
  };
}

function ordered(tokens: EditableTokenRange[]) {
  return [...tokens].sort((left, right) => {
    const leftStart = parseOffset(left.startOffset) ?? Number.MAX_SAFE_INTEGER;
    const rightStart = parseOffset(right.startOffset) ?? Number.MAX_SAFE_INTEGER;
    return leftStart - rightStart;
  });
}

export function editableTokensFromRevision(tokens: LyricsToken[]): EditableTokenRange[] {
  return tokens.map((token) => ({
    clientId: crypto.randomUUID(),
    startOffset: token.startOffset.toString(),
    endOffset: token.endOffset.toString(),
  }));
}

export function validateTokenRanges(japaneseText: string, tokens: EditableTokenRange[]): string[] {
  const errors: string[] = [];
  let previousEnd = 0;

  ordered(tokens).forEach((token, index) => {
    const { startOffset, endOffset } = parsedRange(token);
    const tokenNumber = index + 1;

    if (startOffset === null || endOffset === null) {
      errors.push(`El token ${tokenNumber} necesita offsets enteros.`);
      return;
    }

    if (startOffset < 0 || endOffset <= startOffset || endOffset > japaneseText.length) {
      errors.push(`El token ${tokenNumber} queda fuera de la superficie japonesa.`);
      return;
    }

    if (!isUtf16Boundary(japaneseText, startOffset) || !isUtf16Boundary(japaneseText, endOffset)) {
      errors.push(`El token ${tokenNumber} corta un carácter Unicode por la mitad.`);
      return;
    }

    if (startOffset < previousEnd) {
      errors.push(`El token ${tokenNumber} se solapa con el token anterior.`);
      return;
    }

    previousEnd = endOffset;
  });

  return errors;
}

export function serializeTokenRanges(
  japaneseText: string,
  tokens: EditableTokenRange[],
): PersistedTokenRange[] {
  if (validateTokenRanges(japaneseText, tokens).length > 0) {
    return [];
  }

  return ordered(tokens).map((token) => {
    const startOffset = parseOffset(token.startOffset) ?? 0;
    const endOffset = parseOffset(token.endOffset) ?? 0;

    return {
      surface: japaneseText.slice(startOffset, endOffset),
      startOffset,
      endOffset,
    };
  });
}

function tokenSurface(japaneseText: string, token: EditableTokenRange): string {
  const { startOffset, endOffset } = parsedRange(token);

  if (
    startOffset === null ||
    endOffset === null ||
    startOffset < 0 ||
    endOffset <= startOffset ||
    endOffset > japaneseText.length ||
    !isUtf16Boundary(japaneseText, startOffset) ||
    !isUtf16Boundary(japaneseText, endOffset)
  ) {
    return 'Rango inválido';
  }

  return japaneseText.slice(startOffset, endOffset);
}

export function LyricsTokenSegmentationEditor({
  japaneseText,
  tokens,
  disabled = false,
  onChange,
}: LyricsTokenSegmentationEditorProps) {
  const orderedTokens = ordered(tokens);
  const errors = validateTokenRanges(japaneseText, tokens);
  const lastEnd =
    orderedTokens.length > 0
      ? (parseOffset(orderedTokens[orderedTokens.length - 1]?.endOffset ?? '') ?? 0)
      : 0;

  function updateToken(clientId: string, patch: Partial<EditableTokenRange>) {
    onChange(tokens.map((token) => (token.clientId === clientId ? { ...token, ...patch } : token)));
  }

  function removeToken(clientId: string) {
    onChange(tokens.filter((token) => token.clientId !== clientId));
  }

  function addNextToken() {
    if (disabled || !japaneseText || lastEnd >= japaneseText.length) {
      return;
    }

    const endOffset = nextUtf16Boundary(japaneseText, lastEnd);
    onChange([
      ...orderedTokens,
      {
        clientId: crypto.randomUUID(),
        startOffset: lastEnd.toString(),
        endOffset: endOffset.toString(),
      },
    ]);
  }

  function segmentRemainingCharacters() {
    if (disabled || !japaneseText || lastEnd >= japaneseText.length) {
      return;
    }

    const additions: EditableTokenRange[] = [];
    let start = lastEnd;

    while (start < japaneseText.length) {
      const end = nextUtf16Boundary(japaneseText, start);
      additions.push({
        clientId: crypto.randomUUID(),
        startOffset: start.toString(),
        endOffset: end.toString(),
      });
      start = end;
    }

    onChange([...orderedTokens, ...additions]);
  }

  function mergeWithNext(index: number) {
    const current = orderedTokens[index];
    const next = orderedTokens[index + 1];

    if (!current || !next) {
      return;
    }

    const currentEnd = parseOffset(current.endOffset);
    const nextStart = parseOffset(next.startOffset);

    if (currentEnd === null || nextStart === null || currentEnd !== nextStart) {
      return;
    }

    onChange(
      orderedTokens
        .filter((token) => token.clientId !== next.clientId)
        .map((token) =>
          token.clientId === current.clientId ? { ...token, endOffset: next.endOffset } : token,
        ),
    );
  }

  if (disabled) {
    return (
      <section className="lyrics-token-editor" aria-label="Segmentación manual">
        <h5>Segmentación manual</h5>
        <p>Una línea marcada como contenido desconocido no crea tokens ficticios.</p>
      </section>
    );
  }

  return (
    <section className="lyrics-token-editor" aria-label="Segmentación manual">
      <header>
        <div>
          <h5>Segmentación manual</h5>
          <p>
            Los offsets usan unidades UTF-16. La superficie se deriva siempre del japonés original y
            nunca se escribe por separado.
          </p>
        </div>
        <strong>
          {tokens.length} {tokens.length === 1 ? 'token' : 'tokens'}
        </strong>
      </header>

      {errors.length > 0 ? (
        <div className="lyrics-token-editor__errors" role="alert">
          <strong>Revisa la segmentación</strong>
          <ul>
            {errors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </div>
      ) : null}

      {orderedTokens.length > 0 ? (
        <ol className="lyrics-token-editor__tokens">
          {orderedTokens.map((token, index) => {
            const next = orderedTokens[index + 1];
            const currentEnd = parseOffset(token.endOffset);
            const nextStart = next ? parseOffset(next.startOffset) : null;
            const canMerge =
              next !== undefined &&
              currentEnd !== null &&
              nextStart !== null &&
              currentEnd === nextStart;

            return (
              <li key={token.clientId}>
                <article className="lyrics-token-editor__token">
                  <header>
                    <strong>Token {index + 1}</strong>
                    <div className="lyrics-token-editor__actions">
                      <Button
                        type="button"
                        variant="secondary"
                        disabled={!canMerge}
                        onClick={() => mergeWithNext(index)}
                      >
                        Unir con siguiente
                      </Button>
                      <Button
                        type="button"
                        variant="secondary"
                        onClick={() => removeToken(token.clientId)}
                      >
                        Quitar token
                      </Button>
                    </div>
                  </header>

                  <div className="lyrics-token-editor__range">
                    <Field
                      id={`lyrics-token-${token.clientId}-start`}
                      label="Inicio"
                      type="number"
                      min="0"
                      value={token.startOffset}
                      onChange={(event) =>
                        updateToken(token.clientId, {
                          startOffset: event.target.value,
                        })
                      }
                    />
                    <Field
                      id={`lyrics-token-${token.clientId}-end`}
                      label="Fin"
                      type="number"
                      min="1"
                      value={token.endOffset}
                      onChange={(event) =>
                        updateToken(token.clientId, {
                          endOffset: event.target.value,
                        })
                      }
                    />
                  </div>

                  <p className="lyrics-token-editor__surface">
                    <strong>Superficie exacta:</strong>{' '}
                    <span lang="ja">{tokenSurface(japaneseText, token)}</span>
                  </p>
                </article>
              </li>
            );
          })}
        </ol>
      ) : (
        <p className="lyrics-token-editor__empty">
          Sin tokens manuales. Puedes comenzar por caracteres y luego unir rangos contiguos para
          conservar una palabra o expresión como unidad.
        </p>
      )}

      <div className="lyrics-token-editor__footer">
        <Button
          type="button"
          variant="secondary"
          disabled={!japaneseText || lastEnd >= japaneseText.length}
          onClick={addNextToken}
        >
          Agregar siguiente carácter
        </Button>
        <Button
          type="button"
          variant="secondary"
          disabled={!japaneseText || lastEnd >= japaneseText.length}
          onClick={segmentRemainingCharacters}
        >
          Segmentar caracteres restantes
        </Button>
      </div>
    </section>
  );
}
