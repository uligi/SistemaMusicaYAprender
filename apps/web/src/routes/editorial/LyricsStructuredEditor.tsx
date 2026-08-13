import { useEffect, useMemo, useState } from 'react';
import { Button, Field, SelectField, StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem, MutationState } from '../../data/http/types';
import type { LyricsRevision, LyricsStructureResponse } from './LyricsStructurePage';
import './lyrics-structured-editor.css';

const client = createHttpClient();

type UnknownContentCode = '' | 'INAUDIBLE' | 'UNKNOWN' | 'OMITTED' | 'PENDING_TRANSCRIPTION';

const unknownOptions: readonly {
  value: UnknownContentCode;
  label: string;
}[] = [
  { value: '', label: 'Texto conocido' },
  { value: 'INAUDIBLE', label: 'Inaudible' },
  { value: 'UNKNOWN', label: 'Desconocido' },
  { value: 'OMITTED', label: 'Omitido en la fuente' },
  { value: 'PENDING_TRANSCRIPTION', label: 'Pendiente de transcripción' },
];

type EditorLine = {
  clientId: string;
  japaneseText: string;
  speakerLabel: string;
  unknownContentCode: UnknownContentCode;
};

type EditorSection = {
  clientId: string;
  sectionType: string;
  label: string;
  lines: EditorLine[];
};

type EditorDraft = {
  sections: EditorSection[];
};

type EditorError = {
  key: string;
  message: string;
};

type Csrf = {
  requestToken: string;
  headerName: string;
};

type ServerComparison = {
  data: LyricsStructureResponse;
  etag: string;
};

const unknownPattern = /^\[UNKNOWN:(INAUDIBLE|UNKNOWN|OMITTED|PENDING_TRANSCRIPTION)\]$/;

function newLine(): EditorLine {
  return {
    clientId: crypto.randomUUID(),
    japaneseText: '',
    speakerLabel: '',
    unknownContentCode: '',
  };
}

function newSection(): EditorSection {
  return {
    clientId: crypto.randomUUID(),
    sectionType: 'VERSE',
    label: '',
    lines: [newLine()],
  };
}

function decodeUnknown(value: string): UnknownContentCode {
  const match = unknownPattern.exec(value);
  return (match?.[1] as UnknownContentCode | undefined) ?? '';
}

function unknownLabel(code: UnknownContentCode): string {
  switch (code) {
    case 'INAUDIBLE':
      return 'Inaudible';
    case 'UNKNOWN':
      return 'Desconocido';
    case 'OMITTED':
      return 'Omitido en la fuente';
    case 'PENDING_TRANSCRIPTION':
      return 'Pendiente de transcripción';
    default:
      return '';
  }
}

function fromRevision(revision: LyricsRevision | null): EditorDraft {
  if (!revision) {
    return { sections: [newSection()] };
  }

  return {
    sections: revision.sections.map((section) => ({
      clientId: crypto.randomUUID(),
      sectionType: section.sectionType,
      label: section.label ?? '',
      lines: section.lines.map((line) => {
        const unknownContentCode = decodeUnknown(line.japaneseText);
        return {
          clientId: crypto.randomUUID(),
          japaneseText: unknownContentCode ? '' : line.japaneseText,
          speakerLabel: line.speakerLabel ?? '',
          unknownContentCode,
        };
      }),
    })),
  };
}

function unknownMarker(code: UnknownContentCode): string {
  return code ? `[UNKNOWN:${code}]` : '';
}

function previewText(line: EditorLine): string {
  return line.unknownContentCode ? unknownLabel(line.unknownContentCode) : line.japaneseText;
}

function countLines(draft: EditorDraft): number {
  return draft.sections.reduce((total, section) => total + section.lines.length, 0);
}

function validate(draft: EditorDraft): EditorError[] {
  const errors: EditorError[] = [];

  if (draft.sections.length === 0) {
    errors.push({
      key: 'sections',
      message: 'Agrega al menos una sección.',
    });
  }

  draft.sections.forEach((section, sectionIndex) => {
    if (!/^[A-Z0-9][A-Z0-9._-]{0,63}$/.test(section.sectionType.trim().toUpperCase())) {
      errors.push({
        key: `section-${sectionIndex}-type`,
        message: `La sección ${sectionIndex + 1} necesita un tipo editorial válido.`,
      });
    }

    if (section.lines.length === 0) {
      errors.push({
        key: `section-${sectionIndex}-lines`,
        message: `La sección ${sectionIndex + 1} necesita al menos una línea.`,
      });
    }

    section.lines.forEach((line, lineIndex) => {
      if (!line.unknownContentCode && !line.japaneseText.trim()) {
        errors.push({
          key: `section-${sectionIndex}-line-${lineIndex}`,
          message: `La línea ${lineIndex + 1} de la sección ${sectionIndex + 1} necesita texto japonés o un tipo de contenido desconocido.`,
        });
      }

      if (line.unknownContentCode && line.japaneseText) {
        errors.push({
          key: `section-${sectionIndex}-line-${lineIndex}-unknown`,
          message: `La línea ${lineIndex + 1} no puede mezclar texto inventado con una marca de contenido desconocido.`,
        });
      }
    });
  });

  return errors;
}

function requestBody(draft: EditorDraft) {
  return {
    sections: draft.sections.map((section) => ({
      sectionType: section.sectionType.trim().toUpperCase(),
      label: section.label.trim() || null,
      lines: section.lines.map((line) => ({
        japaneseText: line.unknownContentCode
          ? unknownMarker(line.unknownContentCode)
          : line.japaneseText,
        speakerLabel: line.speakerLabel.trim() || null,
        tokens: [],
      })),
    })),
  };
}

function summary(revision: LyricsRevision | null): string {
  if (!revision) {
    return 'Sin revisión en servidor';
  }

  const lines = revision.sections.reduce((total, section) => total + section.lines.length, 0);
  return `Revisión ${revision.revisionNo}: ${revision.sections.length} secciones, ${lines} líneas`;
}

export type LyricsStructuredEditorProps = {
  recordingId: string;
  revision: LyricsRevision | null;
  etag: string;
  onSaved: (response: LyricsStructureResponse, etag: string) => void;
};

export function LyricsStructuredEditor({
  recordingId,
  revision,
  etag,
  onSaved,
}: LyricsStructuredEditorProps) {
  const [draft, setDraft] = useState<EditorDraft>(() => fromRevision(revision));
  const [baseEtag, setBaseEtag] = useState(etag);
  const [previewOpen, setPreviewOpen] = useState(false);
  const [mutation, setMutation] = useState<MutationState | null>(null);
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [comparison, setComparison] = useState<ServerComparison | null>(null);
  const [comparisonError, setComparisonError] = useState('');

  useEffect(() => {
    setDraft(fromRevision(revision));
    setBaseEtag(etag);
    setProblem(null);
    setComparison(null);
    setComparisonError('');
    setMutation((current) => (current?.phase === 'confirmed' ? current : null));
  }, [etag, revision]);

  const errors = useMemo(() => validate(draft), [draft]);

  function markChanged() {
    setMutation(null);
    setProblem(null);
    setComparison(null);
    setComparisonError('');
  }

  function updateSection(index: number, patch: Partial<EditorSection>) {
    setDraft((current) => ({
      sections: current.sections.map((section, position) =>
        position === index ? { ...section, ...patch } : section,
      ),
    }));
    markChanged();
  }

  function updateLine(sectionIndex: number, lineIndex: number, patch: Partial<EditorLine>) {
    setDraft((current) => ({
      sections: current.sections.map((section, position) => {
        if (position !== sectionIndex) return section;
        return {
          ...section,
          lines: section.lines.map((line, linePosition) =>
            linePosition === lineIndex ? { ...line, ...patch } : line,
          ),
        };
      }),
    }));
    markChanged();
  }

  function addSection() {
    setDraft((current) => ({
      sections: [...current.sections, newSection()],
    }));
    markChanged();
  }

  function removeSection(index: number) {
    setDraft((current) => ({
      sections: current.sections.filter((_, position) => position !== index),
    }));
    markChanged();
  }

  function moveSection(index: number, delta: number) {
    setDraft((current) => {
      const target = index + delta;
      const sourceItem = current.sections[index];
      const targetItem = current.sections[target];

      if (!sourceItem || !targetItem) {
        return current;
      }

      const sections = [...current.sections];
      sections[index] = targetItem;
      sections[target] = sourceItem;
      return { sections };
    });
    markChanged();
  }

  function addLine(sectionIndex: number) {
    setDraft((current) => ({
      sections: current.sections.map((section, position) =>
        position === sectionIndex ? { ...section, lines: [...section.lines, newLine()] } : section,
      ),
    }));
    markChanged();
  }

  function removeLine(sectionIndex: number, lineIndex: number) {
    setDraft((current) => ({
      sections: current.sections.map((section, position) =>
        position === sectionIndex
          ? {
              ...section,
              lines: section.lines.filter((_, linePosition) => linePosition !== lineIndex),
            }
          : section,
      ),
    }));
    markChanged();
  }

  function moveLine(sectionIndex: number, lineIndex: number, delta: number) {
    setDraft((current) => ({
      sections: current.sections.map((section, position) => {
        if (position !== sectionIndex) return section;

        const target = lineIndex + delta;
        const sourceItem = section.lines[lineIndex];
        const targetItem = section.lines[target];

        if (!sourceItem || !targetItem) {
          return section;
        }

        const lines = [...section.lines];
        lines[lineIndex] = targetItem;
        lines[target] = sourceItem;
        return { ...section, lines };
      }),
    }));
    markChanged();
  }

  async function save() {
    setProblem(null);
    setComparison(null);
    setComparisonError('');

    if (errors.length > 0) {
      return;
    }

    const csrf = await client.get<Csrf>('/auth/csrf', {
      cacheMode: 'no-store',
      retry: 'never',
    });

    if (!csrf.ok) {
      if (csrf.kind === 'problem') {
        setProblem(csrf.problem);
      }
      return;
    }

    const result = await client.post<ReturnType<typeof requestBody>, LyricsStructureResponse>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/lyrics-revisions`,
      requestBody(draft),
      {
        headers: {
          [csrf.data.headerName]: csrf.data.requestToken,
        },
        ifMatch: baseEtag,
        retry: 'never',
        invalidate: [
          `/editorial/song-drafts/${encodeURIComponent(recordingId)}/lyrics-revisions/latest`,
        ],
        onStateChange: setMutation,
      },
    );

    if (result.kind === 'cancelled') {
      return;
    }

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

    const result = await client.get<LyricsStructureResponse>(
      `/editorial/song-drafts/${encodeURIComponent(recordingId)}/lyrics-revisions/latest`,
      {
        cacheMode: 'no-store',
        retry: 'never',
      },
    );

    if (!result.ok || !result.etag) {
      setComparisonError(
        result.kind === 'problem'
          ? result.problem.correction
          : 'No fue posible recuperar la revisión vigente.',
      );
      return;
    }

    setComparison({
      data: result.data,
      etag: result.etag,
    });
  }

  function useServerVersion() {
    if (!comparison) {
      return;
    }

    setDraft(fromRevision(comparison.data.revision));
    setBaseEtag(comparison.etag);
    setMutation(null);
    setProblem(null);
    setComparison(null);
  }

  function rebaseLocalVersion() {
    if (!comparison) {
      return;
    }

    setBaseEtag(comparison.etag);
    setMutation(null);
    setProblem(null);
    setComparison(null);
  }

  return (
    <section className="lyrics-editor" aria-labelledby="lyrics-editor-title">
      <header className="lyrics-editor__header">
        <div>
          <p className="eyebrow">BL-MVP-054 · edición estructurada</p>
          <h2 id="lyrics-editor-title">Editor estructurado</h2>
          <p>
            Organiza secciones, líneas y voces. El texto desconocido se marca de forma explícita
            para no inventar contenido.
          </p>
        </div>
        <Button type="button" variant="secondary" onClick={addSection}>
          Agregar sección
        </Button>
      </header>

      {mutation?.phase === 'saving' ? (
        <StateMessage
          state="UI-EST-11"
          title="Guardando revisión"
          description="Confirmando una nueva revisión sin publicar contenido."
        />
      ) : null}

      {mutation?.phase === 'confirmed' ? (
        <StateMessage
          state="UI-EST-12"
          title="Revisión guardada"
          description="La revisión quedó confirmada como borrador y continúa fuera de publicación."
        />
      ) : null}

      {mutation?.phase === 'conflict' ? (
        <StateMessage
          state="UI-EST-10"
          title="Conflicto de edición"
          description="Tus cambios permanecen en este editor. Compara la revisión vigente antes de decidir."
        />
      ) : null}

      {problem && mutation?.phase !== 'conflict' ? (
        <StateMessage state="UI-EST-04" title={problem.summary} description={problem.correction} />
      ) : null}

      {errors.length > 0 ? (
        <div className="lyrics-editor__validation" role="alert" aria-labelledby="lyrics-validation">
          <strong id="lyrics-validation">Revisa el borrador</strong>
          <ul>
            {errors.map((error) => (
              <li key={error.key}>{error.message}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <ol className="lyrics-editor__sections">
        {draft.sections.map((section, sectionIndex) => (
          <li key={section.clientId}>
            <article className="lyrics-editor__section">
              <header>
                <h3>Sección {sectionIndex + 1}</h3>
                <div className="lyrics-editor__actions">
                  <Button
                    type="button"
                    variant="secondary"
                    disabled={sectionIndex === 0}
                    onClick={() => moveSection(sectionIndex, -1)}
                  >
                    Subir sección
                  </Button>
                  <Button
                    type="button"
                    variant="secondary"
                    disabled={sectionIndex === draft.sections.length - 1}
                    onClick={() => moveSection(sectionIndex, 1)}
                  >
                    Bajar sección
                  </Button>
                  <Button
                    type="button"
                    variant="secondary"
                    onClick={() => removeSection(sectionIndex)}
                  >
                    Quitar sección
                  </Button>
                </div>
              </header>

              <div className="lyrics-editor__section-fields">
                <SelectField
                  id={`lyrics-section-${section.clientId}-type`}
                  label="Tipo de sección"
                  value={section.sectionType}
                  onChange={(event) =>
                    updateSection(sectionIndex, { sectionType: event.target.value })
                  }
                >
                  <option value="INTRO">Introducción</option>
                  <option value="VERSE">Verso</option>
                  <option value="PRE_CHORUS">Pre-coro</option>
                  <option value="CHORUS">Coro</option>
                  <option value="BRIDGE">Puente</option>
                  <option value="INTERLUDE">Interludio</option>
                  <option value="SOLO">Solo</option>
                  <option value="OUTRO">Cierre</option>
                  <option value="OTHER">Otro</option>
                </SelectField>

                <Field
                  id={`lyrics-section-${section.clientId}-label`}
                  label="Etiqueta opcional"
                  value={section.label}
                  onChange={(event) => updateSection(sectionIndex, { label: event.target.value })}
                />
              </div>

              <ol className="lyrics-editor__lines">
                {section.lines.map((line, lineIndex) => (
                  <li key={line.clientId}>
                    <article className="lyrics-editor__line">
                      <header>
                        <h4>Línea {lineIndex + 1}</h4>
                        <div className="lyrics-editor__actions">
                          <Button
                            type="button"
                            variant="secondary"
                            disabled={lineIndex === 0}
                            onClick={() => moveLine(sectionIndex, lineIndex, -1)}
                          >
                            Subir línea
                          </Button>
                          <Button
                            type="button"
                            variant="secondary"
                            disabled={lineIndex === section.lines.length - 1}
                            onClick={() => moveLine(sectionIndex, lineIndex, 1)}
                          >
                            Bajar línea
                          </Button>
                          <Button
                            type="button"
                            variant="secondary"
                            onClick={() => removeLine(sectionIndex, lineIndex)}
                          >
                            Quitar línea
                          </Button>
                        </div>
                      </header>

                      <div className="ma-field">
                        <label
                          className="ma-field__label"
                          htmlFor={`lyrics-line-${line.clientId}-japanese`}
                        >
                          Japonés original
                        </label>
                        <span
                          className="ma-field__help"
                          id={`lyrics-line-${line.clientId}-japanese-help`}
                        >
                          Se conserva exactamente como lo escribes. No introduzcas una suposición si
                          el audio no se entiende.
                        </span>
                        <textarea
                          className="ma-field__control lyrics-editor__textarea"
                          id={`lyrics-line-${line.clientId}-japanese`}
                          lang="ja"
                          rows={3}
                          aria-describedby={`lyrics-line-${line.clientId}-japanese-help`}
                          disabled={Boolean(line.unknownContentCode)}
                          value={line.japaneseText}
                          onChange={(event) =>
                            updateLine(sectionIndex, lineIndex, {
                              japaneseText: event.target.value,
                            })
                          }
                        />
                      </div>

                      <div className="lyrics-editor__line-fields">
                        <Field
                          id={`lyrics-line-${line.clientId}-speaker`}
                          label="Voz / intérprete"
                          helpText="Ejemplos: voz principal, coro, respuesta o personaje."
                          value={line.speakerLabel}
                          onChange={(event) =>
                            updateLine(sectionIndex, lineIndex, {
                              speakerLabel: event.target.value,
                            })
                          }
                        />

                        <SelectField
                          id={`lyrics-line-${line.clientId}-unknown`}
                          label="Contenido desconocido"
                          helpText="Úsalo solo si la superficie no puede transcribirse sin inventar."
                          value={line.unknownContentCode}
                          onChange={(event) => {
                            const unknownContentCode = event.target.value as UnknownContentCode;
                            updateLine(sectionIndex, lineIndex, {
                              unknownContentCode,
                              ...(unknownContentCode ? { japaneseText: '' } : {}),
                            });
                          }}
                        >
                          {unknownOptions.map((option) => (
                            <option key={option.value || 'known'} value={option.value}>
                              {option.label}
                            </option>
                          ))}
                        </SelectField>
                      </div>
                    </article>
                  </li>
                ))}
              </ol>

              <Button type="button" variant="secondary" onClick={() => addLine(sectionIndex)}>
                Agregar línea
              </Button>
            </article>
          </li>
        ))}
      </ol>

      <div className="lyrics-editor__footer-actions">
        <Button
          type="button"
          variant="secondary"
          onClick={() => setPreviewOpen((current) => !current)}
        >
          {previewOpen ? 'Cerrar previsualización' : 'Previsualizar borrador'}
        </Button>
        <Button
          type="button"
          disabled={errors.length > 0 || mutation?.phase === 'saving'}
          onClick={() => void save()}
        >
          Guardar nueva revisión
        </Button>
      </div>

      {previewOpen ? (
        <section className="lyrics-editor__preview" aria-labelledby="lyrics-preview-title">
          <header>
            <h3 id="lyrics-preview-title">Previsualización del borrador</h3>
            <p>Esta vista no publica ni envía el contenido al flujo de aprobación.</p>
          </header>

          {draft.sections.map((section, sectionIndex) => (
            <section key={section.clientId} className="lyrics-editor__preview-section">
              <h4>{section.label || `Sección ${sectionIndex + 1}`}</h4>
              {section.lines.map((line) => (
                <p key={line.clientId}>
                  {line.speakerLabel ? <strong>{line.speakerLabel}: </strong> : null}
                  {line.unknownContentCode ? (
                    <span className="lyrics-editor__unknown">{previewText(line)}</span>
                  ) : (
                    <span lang="ja">{previewText(line)}</span>
                  )}
                </p>
              ))}
            </section>
          ))}
        </section>
      ) : null}

      {mutation?.phase === 'conflict' ? (
        <div className="lyrics-editor__conflict-actions">
          <Button type="button" variant="secondary" onClick={() => void compareWithServer()}>
            Comparar con servidor
          </Button>
        </div>
      ) : null}

      {comparisonError ? (
        <StateMessage state="UI-EST-04" title="No se pudo comparar" description={comparisonError} />
      ) : null}

      {comparison ? (
        <section className="lyrics-editor__compare" aria-labelledby="lyrics-compare-title">
          <h3 id="lyrics-compare-title">Comparar revisiones</h3>
          <div className="lyrics-editor__compare-grid">
            <article>
              <h4>Tu borrador local</h4>
              <p>
                {draft.sections.length} secciones · {countLines(draft)} líneas
              </p>
            </article>
            <article>
              <h4>Versión vigente del servidor</h4>
              <p>{summary(comparison.data.revision)}</p>
            </article>
          </div>
          <div className="lyrics-editor__actions">
            <Button type="button" variant="secondary" onClick={useServerVersion}>
              Usar versión del servidor
            </Button>
            <Button type="button" onClick={rebaseLocalVersion}>
              Mantener mis cambios sobre la versión vigente
            </Button>
          </div>
        </section>
      ) : null}
    </section>
  );
}
