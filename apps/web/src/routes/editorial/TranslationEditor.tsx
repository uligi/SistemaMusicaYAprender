import { useEffect, useMemo, useState } from 'react';
import { Button, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import type {
  TranslationContext,
  TranslationLine,
  TranslationNote,
  TranslationSourceLine,
} from './TranslationStructurePage';
import './translation-editor.css';

const client = createHttpClient();

type Csrf = {
  requestToken: string;
  headerName: string;
};

type EditorUnit = {
  lineId: string;
  literalText: string;
  naturalText: string;
  noteText: string;
};

type EditorDraft = {
  lyricsRevisionId: string;
  units: EditorUnit[];
};

type Comparison = {
  data: TranslationContext;
  etag: string;
};

type EditorError = {
  key: string;
  message: string;
};

function findVariant(
  context: TranslationContext,
  lineId: string,
  variantCode: 'LITERAL' | 'NATURAL',
): TranslationLine | undefined {
  return context.revision?.lines.find(
    (line) => line.anchorLineId === lineId && line.variantCode === variantCode,
  );
}

function findEditableNote(
  context: TranslationContext,
  lineId: string,
): TranslationNote | undefined {
  return context.revision?.notes.find(
    (note) => note.lineId === lineId && note.tokenId === null && note.noteType === 'EDITORIAL',
  );
}

function fromContext(context: TranslationContext): EditorDraft {
  return {
    lyricsRevisionId: context.lyricsRevisionId ?? '',
    units: context.sourceLines.map((source) => ({
      lineId: source.lineId,
      literalText: findVariant(context, source.lineId, 'LITERAL')?.translatedText ?? '',
      naturalText: findVariant(context, source.lineId, 'NATURAL')?.translatedText ?? '',
      noteText: findEditableNote(context, source.lineId)?.noteText ?? '',
    })),
  };
}

function lineLabel(source: TranslationSourceLine): string {
  return `Línea ${source.lineNo}`;
}

function unitStatus(unit: EditorUnit): {
  code: 'complete' | 'partial' | 'pending';
  label: string;
} {
  const hasLiteral = Boolean(unit.literalText.trim());
  const hasNatural = Boolean(unit.naturalText.trim());

  if (hasLiteral && hasNatural) {
    return { code: 'complete', label: 'Completa' };
  }

  if (hasLiteral || hasNatural) {
    return { code: 'partial', label: 'Parcial' };
  }

  return { code: 'pending', label: 'Pendiente' };
}

function validate(draft: EditorDraft): EditorError[] {
  const errors: EditorError[] = [];
  let translatedUnits = 0;

  draft.units.forEach((unit, index) => {
    if (unit.literalText.length > 8000) {
      errors.push({
        key: `${unit.lineId}-literal`,
        message: `La traducción literal de la fuente ${index + 1} supera 8000 caracteres.`,
      });
    }

    if (unit.naturalText.length > 8000) {
      errors.push({
        key: `${unit.lineId}-natural`,
        message: `La traducción natural de la fuente ${index + 1} supera 8000 caracteres.`,
      });
    }

    if (unit.noteText.length > 4000) {
      errors.push({
        key: `${unit.lineId}-note`,
        message: `La nota de la fuente ${index + 1} supera 4000 caracteres.`,
      });
    }

    if (unit.literalText.trim() || unit.naturalText.trim()) {
      translatedUnits += 1;
    }
  });

  if (translatedUnits === 0) {
    errors.push({
      key: 'translation-required',
      message: 'Agrega al menos una traducción literal o natural antes de guardar.',
    });
  }

  return errors;
}

function requestBody(context: TranslationContext, draft: EditorDraft) {
  return {
    lyricsRevisionId: draft.lyricsRevisionId,
    targetLanguage: context.targetLanguage,
    translationType: context.translationType,
    units: draft.units.map((unit) => ({
      lineId: unit.lineId,
      literalText: unit.literalText.trim() || null,
      naturalText: unit.naturalText.trim() || null,
      noteText: unit.noteText.trim() || null,
    })),
  };
}

function sourceSummary(context: TranslationContext): string {
  if (!context.lyricsRevisionId) return 'Sin fuente japonesa';
  return `Letra japonesa · revisión ${context.lyricsRevisionNo ?? '—'}`;
}

function translationSummary(context: TranslationContext): string {
  if (!context.revision) return 'Sin traducción compatible';
  return `Traducción · revisión ${context.revision.revisionNo} · ${context.revision.statusCode}`;
}

export type TranslationEditorProps = {
  recordingId: string;
  context: TranslationContext;
  etag: string;
  onSaved: (context: TranslationContext, etag: string) => void;
};

export function TranslationEditor({ recordingId, context, etag, onSaved }: TranslationEditorProps) {
  const [draft, setDraft] = useState<EditorDraft>(() => fromContext(context));
  const [baseEtag, setBaseEtag] = useState(etag);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [comparison, setComparison] = useState<Comparison | null>(null);
  const [comparisonError, setComparisonError] = useState('');

  useEffect(() => {
    setDraft(fromContext(context));
    setBaseEtag(etag);
    setMutation((current) => (current?.phase === 'confirmed' ? current : null));
    setProblem(null);
    setComparison(null);
    setComparisonError('');
  }, [context, etag]);

  const errors = useMemo(() => validate(draft), [draft]);
  const progress = useMemo(() => {
    let complete = 0;
    let partial = 0;

    for (const unit of draft.units) {
      const status = unitStatus(unit);
      if (status.code === 'complete') complete += 1;
      if (status.code === 'partial') partial += 1;
    }

    return {
      complete,
      partial,
      pending: draft.units.length - complete - partial,
    };
  }, [draft.units]);
  const sourceByLineId = useMemo(
    () => new Map(context.sourceLines.map((line) => [line.lineId, line])),
    [context.sourceLines],
  );

  function markChanged() {
    setMutation(null);
    setProblem(null);
    setComparison(null);
    setComparisonError('');
  }

  function updateUnit(
    lineId: string,
    field: 'literalText' | 'naturalText' | 'noteText',
    value: string,
  ) {
    setDraft((current) => ({
      ...current,
      units: current.units.map((unit) =>
        unit.lineId === lineId ? { ...unit, [field]: value } : unit,
      ),
    }));
    markChanged();
  }

  async function save() {
    setProblem(null);
    setComparison(null);
    setComparisonError('');

    if (!context.lyricsRevisionId || errors.length > 0 || !baseEtag) {
      return;
    }

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') setProblem(csrf.problem);
      return;
    }

    const result = await client.post<ReturnType<typeof requestBody>, TranslationContext>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/translation-revisions`,
      requestBody(context, draft),
      {
        headers: {
          [csrf.data.headerName]: csrf.data.requestToken,
        },
        ifMatch: baseEtag,
        retry: 'never',
        invalidate: [
          `/editorial/song-drafts/${encodeURIComponent(recordingId)}/translation-context`,
        ],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') return;

    if (!result.ok) {
      setProblem(result.problem);
      return;
    }

    const nextEtag = result.etag ?? baseEtag;
    setBaseEtag(nextEtag);
    onSaved(result.data, nextEtag);
  }

  async function compareWithServer() {
    setComparisonError('');

    const params = new URLSearchParams({
      language: context.targetLanguage,
      translationType: context.translationType,
    });

    const result = await client.get<TranslationContext>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/translation-context?${params.toString()}`,
      {
        cacheMode: 'no-store',
        retry: 'never',
      },
    );

    if (!result.ok || !result.etag) {
      setComparisonError(
        result.kind === 'problem'
          ? result.problem.correction
          : 'No fue posible recuperar la traducción vigente.',
      );
      return;
    }

    setComparison({
      data: result.data,
      etag: result.etag,
    });
  }

  function useServerVersion() {
    if (!comparison) return;

    setDraft(fromContext(comparison.data));
    setBaseEtag(comparison.etag);
    setMutation(null);
    setProblem(null);
    setComparison(null);
    setComparisonError('');
  }

  function rebaseLocalVersion() {
    if (!comparison || comparison.data.lyricsRevisionId !== draft.lyricsRevisionId) {
      return;
    }

    setBaseEtag(comparison.etag);
    setMutation(null);
    setProblem(null);
    setComparison(null);
    setComparisonError('');
  }

  return (
    <section className="translation-editor" aria-labelledby="translation-editor-title">
      <header className="translation-editor__header">
        <div>
          <p className="eyebrow">BL-MVP-062 · edición en español</p>
          <h2 id="translation-editor-title">Editor de traducción</h2>
          <p className="translation-editor__intro">
            Trabaja línea por línea. La fuente japonesa siempre permanece bloqueada y el guardado
            crea una nueva revisión de borrador.
          </p>
        </div>
        <div className="translation-editor__source-badge">
          <strong>{sourceSummary(context)}</strong>
          <span>{translationSummary(context)}</span>
        </div>
      </header>

      <div className="translation-editor__toolbar" aria-label="Progreso y guardado">
        <div className="translation-editor__progress">
          <strong>
            {progress.complete} de {draft.units.length}{' '}
            {draft.units.length === 1 ? 'completa' : 'completas'}
          </strong>
          <span>
            {progress.partial} {progress.partial === 1 ? 'parcial' : 'parciales'} ·{' '}
            {progress.pending} {progress.pending === 1 ? 'pendiente' : 'pendientes'}
          </span>
        </div>
        <Button
          type="button"
          onClick={() => void save()}
          disabled={
            !context.lyricsRevisionId ||
            !baseEtag ||
            errors.length > 0 ||
            mutation?.phase === 'saving'
          }
        >
          Guardar nueva revisión
        </Button>
      </div>

      <div className="translation-editor__legend" aria-label="Guía rápida de traducción">
        <p id="translation-literal-guidance">
          <strong>Literal:</strong> conserva de cerca la estructura y el sentido del japonés.
        </p>
        <p id="translation-natural-guidance">
          <strong>Natural:</strong> prioriza una redacción fluida y natural en español.
        </p>
      </div>

      {mutation?.phase === 'saving' ? (
        <StateMessage
          state="UI-EST-11"
          title="Guardando traducción"
          description="Creando una nueva revisión DRAFT asociada a la fuente japonesa exacta."
        />
      ) : null}

      {mutation?.phase === 'confirmed' ? (
        <StateMessage
          state="UI-EST-12"
          title="Borrador de traducción guardado"
          description="La nueva revisión quedó confirmada sin publicar ni modificar la letra japonesa."
        />
      ) : null}

      {mutation?.phase === 'conflict' ? (
        <StateMessage
          state="UI-EST-10"
          title="La fuente o traducción cambió"
          description="Tu borrador local permanece intacto. Compara el servidor antes de decidir cómo continuar."
        />
      ) : null}

      {problem && mutation?.phase !== 'conflict' ? (
        <StateMessage state="UI-EST-04" title={problem.summary} description={problem.correction} />
      ) : null}

      {errors.length > 0 ? (
        <div
          className="translation-editor__validation"
          role="alert"
          aria-labelledby="translation-editor-validation"
        >
          <strong id="translation-editor-validation">Revisa el borrador</strong>
          <ul>
            {errors.map((error) => (
              <li key={error.key}>{error.message}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <ol className="translation-editor__units">
        {draft.units.map((unit, sourceIndex) => {
          const source = sourceByLineId.get(unit.lineId);
          if (!source) return null;

          const literalId = `translation-literal-${unit.lineId}`;
          const naturalId = `translation-natural-${unit.lineId}`;
          const noteId = `translation-note-${unit.lineId}`;
          const status = unitStatus(unit);

          return (
            <li key={unit.lineId}>
              <article
                className={`translation-editor__unit translation-editor__unit--${status.code}`}
              >
                <div className="translation-editor__source">
                  <header className="translation-editor__unit-heading">
                    <span className="translation-editor__unit-number" aria-hidden="true">
                      {sourceIndex + 1}
                    </span>
                    <div>
                      <strong>{lineLabel(source)}</strong>
                      <span>Solo lectura</span>
                    </div>
                    <span className="translation-editor__unit-status">{status.label}</span>
                  </header>

                  <p className="translation-editor__japanese" lang="ja">
                    {source.japaneseText}
                  </p>
                </div>

                <div className="translation-editor__edit">
                  <div className="translation-editor__fields">
                    <div className="translation-editor__field">
                      <label htmlFor={literalId}>Español literal</label>
                      <textarea
                        id={literalId}
                        aria-describedby="translation-literal-guidance"
                        lang="es"
                        rows={2}
                        placeholder="Escribe una traducción cercana al japonés…"
                        value={unit.literalText}
                        onChange={(event) =>
                          updateUnit(unit.lineId, 'literalText', event.currentTarget.value)
                        }
                      />
                    </div>

                    <div className="translation-editor__field">
                      <label htmlFor={naturalId}>Español natural</label>
                      <textarea
                        id={naturalId}
                        aria-describedby="translation-natural-guidance"
                        lang="es"
                        rows={2}
                        placeholder="Escribe una versión natural en español…"
                        value={unit.naturalText}
                        onChange={(event) =>
                          updateUnit(unit.lineId, 'naturalText', event.currentTarget.value)
                        }
                      />
                    </div>
                  </div>

                  <details
                    className="translation-editor__note"
                    open={Boolean(unit.noteText.trim())}
                  >
                    <summary>
                      <span>Nota editorial</span>
                      <span>{unit.noteText.trim() ? 'Añadida' : 'Opcional'}</span>
                    </summary>
                    <div className="translation-editor__note-body">
                      <label htmlFor={noteId}>Nota editorial</label>
                      <span id={`${noteId}-help`}>
                        Úsala solo para decisiones, matices o ambigüedades de esta unidad.
                      </span>
                      <textarea
                        id={noteId}
                        aria-describedby={`${noteId}-help`}
                        rows={2}
                        placeholder="Añade contexto solo si hace falta…"
                        value={unit.noteText}
                        onChange={(event) =>
                          updateUnit(unit.lineId, 'noteText', event.currentTarget.value)
                        }
                      />
                    </div>
                  </details>
                </div>
              </article>
            </li>
          );
        })}
      </ol>

      {mutation?.phase === 'conflict' ? (
        <div className="translation-editor__conflict-actions">
          <Button type="button" variant="secondary" onClick={() => void compareWithServer()}>
            Comparar con servidor
          </Button>
        </div>
      ) : null}

      {comparison ? (
        <section
          className="translation-editor__comparison"
          aria-labelledby="translation-comparison-title"
        >
          <h3 id="translation-comparison-title">Comparación con el servidor</h3>
          <dl>
            <div>
              <dt>Tu fuente base</dt>
              <dd>revisión {context.lyricsRevisionNo ?? '—'}</dd>
            </div>
            <div>
              <dt>Fuente vigente</dt>
              <dd>revisión {comparison.data.lyricsRevisionNo ?? '—'}</dd>
            </div>
            <div>
              <dt>Traducción vigente</dt>
              <dd>{translationSummary(comparison.data)}</dd>
            </div>
          </dl>

          {comparison.data.lyricsRevisionId !== draft.lyricsRevisionId ? (
            <StateMessage
              state="UI-EST-09"
              title="La letra japonesa cambió"
              description="No se puede rebasar automáticamente este borrador porque sus anclas pertenecen a otra revisión. Carga la fuente vigente y revisa las unidades explícitamente."
            />
          ) : null}

          <div className="translation-editor__comparison-actions">
            <Button type="button" variant="secondary" onClick={useServerVersion}>
              Usar revisión vigente
            </Button>
            <Button
              type="button"
              onClick={rebaseLocalVersion}
              disabled={comparison.data.lyricsRevisionId !== draft.lyricsRevisionId}
            >
              Conservar mi borrador sobre esta fuente
            </Button>
          </div>
        </section>
      ) : null}

      {comparisonError ? (
        <p className="translation-editor__comparison-error" role="alert">
          {comparisonError}
        </p>
      ) : null}

      <footer className="translation-editor__footer">
        <p>
          Guardar crea una revisión DRAFT con autoría y procedencia. No publica, no modifica japonés
          y no usa servicios de traducción externos.
        </p>
      </footer>
    </section>
  );
}
