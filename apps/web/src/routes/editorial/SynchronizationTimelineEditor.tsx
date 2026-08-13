import { useEffect, useMemo, useState } from 'react';
import { StateMessage } from '../../components/ui';
import { createHttpClient } from '../../data/http';
import type { ClientProblem } from '../../data/http/types';
import type {
  YouTubePlayerController,
  YouTubePlayerState,
} from '../../integrations/youtube/YouTubeIframeAdapter';
import type { LyricsRevision, LyricsStructureResponse } from './LyricsStructurePage';
import './synchronization-timeline-editor.css';

const client = createHttpClient();

type Csrf = {
  requestToken: string;
  headerName: string;
};

export type TimingTokenEditorSnapshot = {
  tokenId: string;
  tokenNo: number;
  surface: string;
  startMs: number;
  endMs: number;
};

export type TimingLineEditorSnapshot = {
  lineId: string;
  sectionOrder: number;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
  precisionCode: string;
  startMs: number;
  endMs: number;
  tokens: TimingTokenEditorSnapshot[];
};

export type TimingRevisionEditorSnapshot = {
  timingRevisionId: string;
  lyricsRevisionId: string;
  sourceId: string;
  revisionNo: number;
  offsetMs: number;
  statusCode: string;
  checksumSha256: string;
  lines: TimingLineEditorSnapshot[];
};

export type TimelineSourceInput = {
  sourceId: string;
  providerCode: string;
  externalRef: string;
  durationMs: number | null;
  sourceOffsetMs: number;
  statusCode: string;
  timingRevision: TimingRevisionEditorSnapshot | null;
};

type EditableToken = {
  tokenId: string;
  tokenNo: number;
  surface: string;
  startMs: string;
  endMs: string;
};

type EditableLine = {
  lineId: string;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
  precision: 'LINE' | 'TOKEN';
  startMs: string;
  endMs: string;
  tokens: EditableToken[];
  selected: boolean;
};

type EditorError = {
  key: string;
  message: string;
};

type LyricsState =
  | { phase: 'loading' }
  | { phase: 'ready'; revision: LyricsRevision }
  | { phase: 'failed'; problem: ClientProblem };

export type SynchronizationTimelineEditorProps = {
  recordingId: string;
  lyricsRevisionId: string;
  source: TimelineSourceInput;
  onSaved: (revision: TimingRevisionEditorSnapshot) => void;
  playerController?: YouTubePlayerController | null;
  playerState?: YouTubePlayerState;
  playbackPositionMs?: number | null;
};

function toInteger(value: string): number | null {
  if (!/^-?\d+$/.test(value.trim())) {
    return null;
  }

  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function timingByLine(source: TimelineSourceInput) {
  return new Map((source.timingRevision?.lines ?? []).map((line) => [line.lineId, line]));
}

function buildDraft(revision: LyricsRevision, source: TimelineSourceInput): EditableLine[] {
  const existing = timingByLine(source);

  return revision.sections.flatMap((section) =>
    section.lines.map((line) => {
      const current = existing.get(line.lineId);
      const tokenTimes = new Map((current?.tokens ?? []).map((token) => [token.tokenId, token]));

      return {
        lineId: line.lineId,
        lineNo: line.lineNo,
        japaneseText: line.japaneseText,
        speakerLabel: line.speakerLabel,
        precision: current?.precisionCode === 'TOKEN' ? 'TOKEN' : 'LINE',
        startMs: current ? String(current.startMs) : '',
        endMs: current ? String(current.endMs) : '',
        selected: false,
        tokens: line.tokens.map((token) => {
          const timed = tokenTimes.get(token.tokenId);
          return {
            tokenId: token.tokenId,
            tokenNo: token.tokenNo,
            surface: token.surface,
            startMs: timed ? String(timed.startMs) : '',
            endMs: timed ? String(timed.endMs) : '',
          };
        }),
      } satisfies EditableLine;
    }),
  );
}

function lineInterval(line: EditableLine): { startMs: number; endMs: number } | null {
  if (line.precision === 'LINE') {
    const startMs = toInteger(line.startMs);
    const endMs = toInteger(line.endMs);
    return startMs === null || endMs === null ? null : { startMs, endMs };
  }

  if (line.tokens.length === 0) {
    return null;
  }

  const intervals = line.tokens.map((token) => ({
    startMs: toInteger(token.startMs),
    endMs: toInteger(token.endMs),
  }));

  if (intervals.some((token) => token.startMs === null || token.endMs === null)) {
    return null;
  }

  return {
    startMs: intervals[0]!.startMs!,
    endMs: intervals[intervals.length - 1]!.endMs!,
  };
}

function isUntimed(line: EditableLine): boolean {
  if (line.precision === 'LINE') {
    return line.startMs.trim() === '' && line.endMs.trim() === '';
  }

  return line.tokens.every((token) => token.startMs.trim() === '' && token.endMs.trim() === '');
}

function validateInterval(
  label: string,
  startMs: number,
  endMs: number,
  durationMs: number,
  offsetMs: number,
  errors: EditorError[],
) {
  if (startMs < 0) {
    errors.push({
      key: `${label}-negative`,
      message: `${label}: el inicio no puede ser negativo.`,
    });
  }

  if (endMs <= startMs) {
    errors.push({
      key: `${label}-inverted`,
      message: `${label}: el fin debe ser posterior al inicio.`,
    });
  }

  if (startMs + offsetMs < 0 || endMs + offsetMs > durationMs) {
    errors.push({
      key: `${label}-duration`,
      message: `${label}: el intervalo queda fuera de la duración confirmada de la fuente.`,
    });
  }
}

function validate(lines: EditableLine[], durationMs: number, offsetMs: number): EditorError[] {
  const errors: EditorError[] = [];
  let previousStart: number | null = null;
  let previousTimedLine: EditableLine | null = null;
  let previousInterval: { startMs: number; endMs: number } | null = null;

  for (const line of lines) {
    if (isUntimed(line)) continue;

    if (line.precision === 'LINE') {
      const startMs = toInteger(line.startMs);
      const endMs = toInteger(line.endMs);

      if (startMs === null || endMs === null) {
        errors.push({
          key: `line-${line.lineId}-required`,
          message: `Línea ${line.lineNo}: completa inicio y fin o deja ambos vacíos.`,
        });
        continue;
      }

      validateInterval(`Línea ${line.lineNo}`, startMs, endMs, durationMs, offsetMs, errors);
    } else {
      if (line.tokens.length === 0) {
        errors.push({
          key: `line-${line.lineId}-tokens`,
          message: `Línea ${line.lineNo}: no tiene tokens canónicos para precisión por token.`,
        });
        continue;
      }

      let previousTokenEnd: number | null = null;
      for (const token of line.tokens) {
        const startMs = toInteger(token.startMs);
        const endMs = toInteger(token.endMs);

        if (startMs === null || endMs === null) {
          errors.push({
            key: `token-${token.tokenId}-required`,
            message: `Línea ${line.lineNo}, token ${token.tokenNo}: la precisión TOKEN exige todos los tiempos.`,
          });
          continue;
        }

        validateInterval(
          `Línea ${line.lineNo}, token ${token.tokenNo}`,
          startMs,
          endMs,
          durationMs,
          offsetMs,
          errors,
        );

        if (previousTokenEnd !== null && startMs < previousTokenEnd) {
          errors.push({
            key: `token-${token.tokenId}-overlap`,
            message: `Línea ${line.lineNo}: el token ${token.tokenNo} se solapa con el anterior.`,
          });
        }

        previousTokenEnd = endMs;
      }
    }

    const interval = lineInterval(line);
    if (!interval) continue;

    if (previousStart !== null && interval.startMs < previousStart) {
      errors.push({
        key: `line-${line.lineId}-order`,
        message: `Línea ${line.lineNo}: su inicio rompe el orden de la revisión de letra.`,
      });
    }

    if (
      previousInterval &&
      previousTimedLine &&
      interval.startMs < previousInterval.endMs &&
      !(
        previousTimedLine.speakerLabel &&
        line.speakerLabel &&
        previousTimedLine.speakerLabel !== line.speakerLabel
      )
    ) {
      errors.push({
        key: `line-${line.lineId}-overlap`,
        message: `Línea ${line.lineNo}: el solapamiento requiere voces simultáneas diferenciadas.`,
      });
    }

    previousStart = interval.startMs;
    previousTimedLine = line;
    previousInterval = interval;
  }

  return errors;
}

function requestLines(lines: EditableLine[]) {
  return lines
    .filter((line) => !isUntimed(line))
    .map((line) =>
      line.precision === 'TOKEN'
        ? {
            lineId: line.lineId,
            startMs: null,
            endMs: null,
            tokens: line.tokens.map((token) => ({
              tokenId: token.tokenId,
              startMs: toInteger(token.startMs),
              endMs: toInteger(token.endMs),
            })),
          }
        : {
            lineId: line.lineId,
            startMs: toInteger(line.startMs),
            endMs: toInteger(line.endMs),
            tokens: [],
          },
    );
}

function activeLineAt(
  lines: EditableLine[],
  cursorMs: number,
  offsetMs: number,
): EditableLine | null {
  return (
    lines.find((line) => {
      const interval = lineInterval(line);
      if (!interval) return false;
      const effectiveStart = interval.startMs + offsetMs;
      const effectiveEnd = interval.endMs + offsetMs;
      return cursorMs >= effectiveStart && cursorMs < effectiveEnd;
    }) ?? null
  );
}

export function SynchronizationTimelineEditor({
  recordingId,
  lyricsRevisionId,
  source,
  onSaved,
  playerController = null,
  playerState = 'unstarted',
  playbackPositionMs = null,
}: SynchronizationTimelineEditorProps) {
  const [lyrics, setLyrics] = useState<LyricsState>({ phase: 'loading' });
  const [lines, setLines] = useState<EditableLine[]>([]);
  const [focusedLineId, setFocusedLineId] = useState<string | null>(null);
  const [autoAdvance, setAutoAdvance] = useState(true);
  const [offsetMs, setOffsetMs] = useState(
    String(source.timingRevision?.offsetMs ?? source.sourceOffsetMs ?? 0),
  );
  const [expectedRevisionNo, setExpectedRevisionNo] = useState<number | null>(
    source.timingRevision?.revisionNo ?? null,
  );
  const [cursorMs, setCursorMs] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [bulkDelta, setBulkDelta] = useState('0');
  const [saving, setSaving] = useState(false);
  const [problem, setProblem] = useState<ClientProblem | null>(null);
  const [confirmedRevisionNo, setConfirmedRevisionNo] = useState<number | null>(null);
  const [serverRevisionNo, setServerRevisionNo] = useState<number | null>(null);

  useEffect(() => {
    const controller = new AbortController();

    const load = async () => {
      const result = await client.get<LyricsStructureResponse>(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/lyrics-revisions/latest`,
        { cacheMode: 'no-store', retry: 'safe', signal: controller.signal },
      );

      if (result.kind === 'cancelled') return;

      if (
        !result.ok ||
        !result.data.exists ||
        !result.data.revision ||
        result.data.revision.lyricsRevisionId !== lyricsRevisionId
      ) {
        if (!result.ok) {
          setLyrics({ phase: 'failed', problem: result.problem });
        } else {
          setLyrics({
            phase: 'failed',
            problem: {
              kind: 'conflict',
              status: 409,
              code: 'content.timing.lyrics-revision.changed',
              summary: 'La revisión de letra cambió',
              cause: 'El editor temporal ya no apunta a la revisión exacta que abrió.',
              correction:
                'Vuelve a abrir sincronización para trabajar sobre una revisión compatible.',
              dataPreserved: true,
              retryable: false,
              fieldErrors: [],
            },
          });
        }
        return;
      }

      const draft = buildDraft(result.data.revision, source);
      setLyrics({ phase: 'ready', revision: result.data.revision });
      setLines(draft);
      setFocusedLineId((current) =>
        current && draft.some((line) => line.lineId === current)
          ? current
          : (draft[0]?.lineId ?? null),
      );
    };

    void load();
    return () => controller.abort();
  }, [lyricsRevisionId, recordingId, source]);

  const durationMs = source.durationMs ?? 0;
  const parsedOffset = toInteger(offsetMs);
  const errors = useMemo(
    () =>
      parsedOffset === null
        ? [{ key: 'offset', message: 'El offset debe ser un entero.' }]
        : validate(lines, durationMs, parsedOffset),
    [durationMs, lines, parsedOffset],
  );
  const timedCount = useMemo(() => lines.filter((line) => !isUntimed(line)).length, [lines]);
  const activeLine = useMemo(
    () => activeLineAt(lines, cursorMs, parsedOffset ?? 0),
    [cursorMs, lines, parsedOffset],
  );
  const focusedIndex = Math.max(
    0,
    lines.findIndex((line) => line.lineId === focusedLineId),
  );
  const focusedLine = lines[focusedIndex] ?? null;
  const externalPlayerReady = playerController !== null;
  const isPlaying = externalPlayerReady ? playerState === 'playing' : playing;

  useEffect(() => {
    if (playbackPositionMs === null || !Number.isFinite(playbackPositionMs)) return;
    setCursorMs(Math.min(durationMs, Math.max(0, Math.round(playbackPositionMs))));
  }, [durationMs, playbackPositionMs]);

  useEffect(() => {
    if (externalPlayerReady || !playing || durationMs <= 0) return;

    const timer = window.setInterval(() => {
      setCursorMs((current) => {
        const next = Math.min(durationMs, current + 100);
        if (next >= durationMs) setPlaying(false);
        return next;
      });
    }, 100);

    return () => window.clearInterval(timer);
  }, [durationMs, externalPlayerReady, playing]);

  function updateLine(lineId: string, patch: Partial<EditableLine>) {
    setLines((current) =>
      current.map((line) => (line.lineId === lineId ? { ...line, ...patch } : line)),
    );
    setProblem(null);
    setConfirmedRevisionNo(null);
  }

  function updateToken(lineId: string, tokenId: string, patch: Partial<EditableToken>) {
    setLines((current) =>
      current.map((line) =>
        line.lineId !== lineId
          ? line
          : {
              ...line,
              tokens: line.tokens.map((token) =>
                token.tokenId === tokenId ? { ...token, ...patch } : token,
              ),
            },
      ),
    );
    setProblem(null);
    setConfirmedRevisionNo(null);
  }

  function moveFocus(delta: number) {
    if (lines.length === 0) return;
    const next = Math.min(lines.length - 1, Math.max(0, focusedIndex + delta));
    setFocusedLineId(lines[next]!.lineId);
  }

  function changePrecision(line: EditableLine, precision: 'LINE' | 'TOKEN') {
    updateLine(line.lineId, {
      precision,
      ...(precision === 'TOKEN' ? { startMs: '', endMs: '' } : {}),
    });
  }

  function markLine(line: EditableLine, boundary: 'startMs' | 'endMs') {
    const raw = Math.max(0, cursorMs - (parsedOffset ?? 0));
    updateLine(line.lineId, { [boundary]: String(raw) });

    if (boundary === 'endMs' && autoAdvance) {
      window.setTimeout(() => moveFocus(1), 0);
    }
  }

  function markToken(line: EditableLine, token: EditableToken, boundary: 'startMs' | 'endMs') {
    const raw = Math.max(0, cursorMs - (parsedOffset ?? 0));
    updateToken(line.lineId, token.tokenId, { [boundary]: String(raw) });

    const lastToken = line.tokens.at(-1)?.tokenId === token.tokenId;
    if (boundary === 'endMs' && lastToken && autoAdvance) {
      window.setTimeout(() => moveFocus(1), 0);
    }
  }

  function seekTo(nextMs: number) {
    const safe = Math.min(durationMs, Math.max(0, Math.round(nextMs)));
    setCursorMs(safe);
    if (externalPlayerReady) playerController.seek(safe / 1000);
  }

  function togglePlayback() {
    if (externalPlayerReady) {
      if (playerState === 'playing') playerController.pause();
      else playerController.play();
      return;
    }

    setPlaying((value) => !value);
  }

  function seekToFocusedLine() {
    if (!focusedLine) return;
    const interval = lineInterval(focusedLine);
    if (!interval) return;
    seekTo(interval.startMs + (parsedOffset ?? 0));
  }

  function applyBulkShift() {
    const delta = toInteger(bulkDelta);
    if (delta === null) return;

    setLines((current) =>
      current.map((line) => {
        if (!line.selected || isUntimed(line)) return line;

        if (line.precision === 'TOKEN') {
          return {
            ...line,
            tokens: line.tokens.map((token) => ({
              ...token,
              startMs:
                toInteger(token.startMs) === null
                  ? token.startMs
                  : String(toInteger(token.startMs)! + delta),
              endMs:
                toInteger(token.endMs) === null
                  ? token.endMs
                  : String(toInteger(token.endMs)! + delta),
            })),
          };
        }

        return {
          ...line,
          startMs:
            toInteger(line.startMs) === null
              ? line.startMs
              : String(toInteger(line.startMs)! + delta),
          endMs:
            toInteger(line.endMs) === null ? line.endMs : String(toInteger(line.endMs)! + delta),
        };
      }),
    );
    setProblem(null);
    setConfirmedRevisionNo(null);
  }

  async function refreshServerRevisionNumber() {
    const result = await client.get<{
      recordingId: string;
      lyricsRevisionId: string | null;
      lyricsRevisionNo: number | null;
      sources: TimelineSourceInput[];
    }>(`/editorial/song-drafts/${encodeURIComponent(recordingId)}/synchronization-context`, {
      cacheMode: 'no-store',
      retry: 'safe',
    });

    if (result.ok) {
      const current = result.data.sources.find(
        (candidate) => candidate.sourceId === source.sourceId,
      );
      setServerRevisionNo(current?.timingRevision?.revisionNo ?? null);
    }
  }

  async function save() {
    setProblem(null);
    setConfirmedRevisionNo(null);

    if (errors.length > 0 || timedCount === 0 || parsedOffset === null || saving) return;

    setSaving(true);
    try {
      const csrf = await client.get<Csrf>('/auth/csrf', { cacheMode: 'no-store', retry: 'safe' });
      if (!csrf.ok) {
        if (csrf.kind === 'problem') setProblem(csrf.problem);
        return;
      }

      const result = await client.post<
        {
          lyricsRevisionId: string;
          sourceId: string;
          offsetMs: number;
          expectedRevisionNo: number | null;
          lines: ReturnType<typeof requestLines>;
        },
        TimingRevisionEditorSnapshot
      >(
        `/editorial/song-drafts/${encodeURIComponent(recordingId)}/timing-revisions`,
        {
          lyricsRevisionId,
          sourceId: source.sourceId,
          offsetMs: parsedOffset,
          expectedRevisionNo,
          lines: requestLines(lines),
        },
        {
          headers: { [csrf.data.headerName]: csrf.data.requestToken },
          retry: 'never',
          invalidate: [
            `/editorial/song-drafts/${encodeURIComponent(recordingId)}/synchronization-context`,
          ],
        },
      );

      if (result.kind === 'cancelled') return;

      if (!result.ok) {
        setProblem(result.problem);
        if (result.problem.code === 'content.timing.revision.conflict') {
          await refreshServerRevisionNumber();
        }
        return;
      }

      setExpectedRevisionNo(result.data.revisionNo);
      setConfirmedRevisionNo(result.data.revisionNo);
      onSaved(result.data);

      if (lyrics.phase === 'ready') {
        const draft = buildDraft(lyrics.revision, { ...source, timingRevision: result.data });
        setLines(draft);
        setFocusedLineId((current) =>
          current && draft.some((line) => line.lineId === current)
            ? current
            : (draft[0]?.lineId ?? null),
        );
      }
    } finally {
      setSaving(false);
    }
  }

  if (lyrics.phase === 'loading') {
    return (
      <StateMessage
        state="UI-EST-01"
        title="Preparando editor temporal"
        description="Cargando la revisión exacta de letra y sus tokens canónicos."
      />
    );
  }

  if (lyrics.phase === 'failed') {
    return (
      <StateMessage
        state="UI-EST-04"
        title={lyrics.problem.summary}
        description={lyrics.problem.correction}
      />
    );
  }

  return (
    <section
      className="synchronization-timeline-editor"
      aria-labelledby={`timeline-editor-${source.sourceId}`}
    >
      <header className="synchronization-timeline-editor__header">
        <div>
          <p className="eyebrow">BL-MVP-057 · EDICIÓN TEMPORAL</p>
          <h4 id={`timeline-editor-${source.sourceId}`}>Editor de línea de tiempo</h4>
        </div>
        <p>
          Mantén el video y la línea que editas en la misma vista. Usa la posición real del
          reproductor para marcar inicio y fin y cambia de línea sin recorrer toda la página.
        </p>
        <div className="synchronization-timeline-editor__coverage" aria-label="Cobertura temporal">
          <strong>
            {timedCount} / {lines.length}
          </strong>
          <span>líneas temporizadas</span>
          <progress value={timedCount} max={Math.max(1, lines.length)}>
            {timedCount} de {lines.length}
          </progress>
        </div>
        <p className="synchronization-timeline-editor__status">
          {timedCount === lines.length
            ? `Cobertura completa: ${timedCount} de ${lines.length} líneas.`
            : `Borrador parcial: ${timedCount} de ${lines.length} líneas temporizadas.`}
        </p>
      </header>

      <section
        className="synchronization-timeline-editor__preview"
        aria-labelledby={`timeline-preview-${source.sourceId}`}
      >
        <div className="synchronization-timeline-editor__preview-heading">
          <div>
            <h5 id={`timeline-preview-${source.sourceId}`}>Control del reproductor</h5>
            <p>
              Posición actual: <strong>{cursorMs} ms</strong>
              {externalPlayerReady ? ` · ${playerState}` : ' · vista previa local'}
            </p>
          </div>
          {activeLine ? (
            <p className="synchronization-timeline-editor__active-line" aria-live="polite">
              Línea activa: <strong>línea {activeLine.lineNo}</strong>{' '}
              <span lang="ja">{activeLine.japaneseText}</span>
            </p>
          ) : (
            <p className="synchronization-timeline-editor__active-line" aria-live="polite">
              Sin línea activa en este instante.
            </p>
          )}
        </div>

        <label className="synchronization-timeline-editor__field synchronization-timeline-editor__scrubber-value">
          <span>Posición del reproductor (ms)</span>
          <input
            aria-label="Tiempo de vista previa (ms)"
            type="number"
            min="0"
            max={durationMs}
            value={cursorMs}
            onChange={(event) => seekTo(Number(event.target.value) || 0)}
          />
        </label>

        <input
          type="range"
          aria-label="Cursor de vista previa"
          min="0"
          max={durationMs}
          step="100"
          value={cursorMs}
          onChange={(event) => seekTo(Number(event.target.value))}
        />

        <div
          className="synchronization-timeline-editor__transport"
          role="group"
          aria-label="Controles rápidos del reproductor"
        >
          <button type="button" onClick={() => seekTo(cursorMs - 2000)}>
            −2 s
          </button>
          <button type="button" onClick={() => seekTo(cursorMs - 500)}>
            −0,5 s
          </button>
          <button type="button" onClick={togglePlayback}>
            {isPlaying ? 'Pausar video' : 'Reproducir video'}
          </button>
          <button type="button" onClick={() => seekTo(cursorMs + 500)}>
            +0,5 s
          </button>
          <button type="button" onClick={() => seekTo(cursorMs + 2000)}>
            +2 s
          </button>
        </div>
      </section>

      <section
        className="synchronization-timeline-editor__navigator"
        aria-label="Navegación por líneas"
      >
        <button
          type="button"
          onClick={() => moveFocus(-1)}
          disabled={focusedIndex <= 0}
          aria-label="Línea anterior"
        >
          ← Anterior
        </button>

        <label className="synchronization-timeline-editor__field synchronization-timeline-editor__line-select">
          <span>Línea que estás editando</span>
          <select
            value={focusedLine?.lineId ?? ''}
            onChange={(event) => setFocusedLineId(event.target.value)}
          >
            {lines.map((line) => (
              <option value={line.lineId} key={line.lineId}>
                {`Línea ${line.lineNo} — ${line.japaneseText}`}
              </option>
            ))}
          </select>
        </label>

        <button
          type="button"
          onClick={() => moveFocus(1)}
          disabled={focusedIndex >= lines.length - 1}
          aria-label="Línea siguiente"
        >
          Siguiente →
        </button>
      </section>

      <label className="synchronization-timeline-editor__auto-advance">
        <input
          type="checkbox"
          checked={autoAdvance}
          onChange={(event) => setAutoAdvance(event.target.checked)}
        />
        Avanzar automáticamente a la siguiente línea al marcar el fin
      </label>

      {errors.length > 0 ? (
        <div className="synchronization-timeline-editor__validation" role="alert">
          <strong>Revisa los tiempos ({errors.length})</strong>
          <ul className="synchronization-timeline-editor__error-list">
            {errors.map((error) => (
              <li key={error.key}>{error.message}</li>
            ))}
          </ul>
        </div>
      ) : null}

      <ol className="synchronization-timeline-editor__lines">
        {focusedLine ? (
          <li key={focusedLine.lineId}>
            <article
              className={`synchronization-timeline-editor__line${activeLine?.lineId === focusedLine.lineId ? ' is-active' : ''}`}
            >
              <header className="synchronization-timeline-editor__line-heading">
                <div>
                  <p className="eyebrow">
                    Línea {focusedIndex + 1} de {lines.length}
                  </p>
                  <strong>Línea {focusedLine.lineNo}</strong>{' '}
                  {focusedLine.speakerLabel ? <span>{focusedLine.speakerLabel}</span> : null}
                </div>
                <label>
                  <input
                    type="checkbox"
                    checked={focusedLine.selected}
                    onChange={(event) =>
                      updateLine(focusedLine.lineId, { selected: event.target.checked })
                    }
                  />{' '}
                  Seleccionar línea {focusedLine.lineNo} para desplazamiento
                </label>
              </header>

              <p className="synchronization-timeline-editor__japanese" lang="ja">
                {focusedLine.japaneseText}
              </p>

              <div className="synchronization-timeline-editor__line-toolbar">
                <label className="synchronization-timeline-editor__field">
                  <span>Precisión línea {focusedLine.lineNo}</span>
                  <select
                    value={focusedLine.precision}
                    onChange={(event) =>
                      changePrecision(focusedLine, event.target.value as 'LINE' | 'TOKEN')
                    }
                  >
                    <option value="LINE">Por línea</option>
                    <option value="TOKEN" disabled={focusedLine.tokens.length === 0}>
                      Por token
                    </option>
                  </select>
                </label>

                <button
                  type="button"
                  onClick={seekToFocusedLine}
                  disabled={lineInterval(focusedLine) === null}
                >
                  Ir al inicio guardado
                </button>
              </div>

              {focusedLine.precision === 'LINE' ? (
                <div className="synchronization-timeline-editor__boundary-grid">
                  <div className="synchronization-timeline-editor__boundary-card">
                    <label className="synchronization-timeline-editor__field">
                      <span>Inicio línea {focusedLine.lineNo} (ms)</span>
                      <input
                        type="number"
                        value={focusedLine.startMs}
                        onChange={(event) =>
                          updateLine(focusedLine.lineId, { startMs: event.target.value })
                        }
                      />
                    </label>
                    <button type="button" onClick={() => markLine(focusedLine, 'startMs')}>
                      Marcar inicio línea {focusedLine.lineNo}
                    </button>
                  </div>

                  <div className="synchronization-timeline-editor__boundary-card">
                    <label className="synchronization-timeline-editor__field">
                      <span>Fin línea {focusedLine.lineNo} (ms)</span>
                      <input
                        type="number"
                        value={focusedLine.endMs}
                        onChange={(event) =>
                          updateLine(focusedLine.lineId, { endMs: event.target.value })
                        }
                      />
                    </label>
                    <button type="button" onClick={() => markLine(focusedLine, 'endMs')}>
                      Marcar fin línea {focusedLine.lineNo}
                    </button>
                  </div>
                </div>
              ) : (
                <section className="synchronization-timeline-editor__tokens">
                  <h5>Tiempos por token de la línea {focusedLine.lineNo}</h5>
                  <div className="synchronization-timeline-editor__token-grid">
                    {focusedLine.tokens.map((token) => (
                      <article
                        className="synchronization-timeline-editor__token"
                        key={token.tokenId}
                      >
                        <span className="synchronization-timeline-editor__token-surface" lang="ja">
                          {token.surface}
                        </span>
                        <label className="synchronization-timeline-editor__field">
                          <span>
                            Inicio token {token.tokenNo} línea {focusedLine.lineNo} (ms)
                          </span>
                          <input
                            type="number"
                            value={token.startMs}
                            onChange={(event) =>
                              updateToken(focusedLine.lineId, token.tokenId, {
                                startMs: event.target.value,
                              })
                            }
                          />
                        </label>
                        <button
                          type="button"
                          onClick={() => markToken(focusedLine, token, 'startMs')}
                        >
                          Inicio aquí
                        </button>
                        <label className="synchronization-timeline-editor__field">
                          <span>
                            Fin token {token.tokenNo} línea {focusedLine.lineNo} (ms)
                          </span>
                          <input
                            type="number"
                            value={token.endMs}
                            onChange={(event) =>
                              updateToken(focusedLine.lineId, token.tokenId, {
                                endMs: event.target.value,
                              })
                            }
                          />
                        </label>
                        <button
                          type="button"
                          onClick={() => markToken(focusedLine, token, 'endMs')}
                        >
                          Fin aquí
                        </button>
                      </article>
                    ))}
                  </div>
                </section>
              )}
            </article>
          </li>
        ) : null}
      </ol>

      <section
        className="synchronization-timeline-editor__bulk"
        aria-labelledby={`bulk-${source.sourceId}`}
      >
        <div>
          <h5 id={`bulk-${source.sourceId}`}>Ajustes rápidos</h5>
          <p>Opcional: desplaza varias líneas ya temporizadas o corrige el offset global.</p>
        </div>
        <div className="synchronization-timeline-editor__line-controls">
          <label className="synchronization-timeline-editor__field">
            <span>Desplazamiento múltiple (ms)</span>
            <input
              type="number"
              value={bulkDelta}
              onChange={(event) => setBulkDelta(event.target.value)}
            />
          </label>
          <button
            type="button"
            onClick={applyBulkShift}
            disabled={!lines.some((line) => line.selected && !isUntimed(line))}
          >
            Desplazar selección
          </button>
          <label className="synchronization-timeline-editor__field">
            <span>Offset global de la revisión (ms)</span>
            <input
              type="number"
              value={offsetMs}
              onChange={(event) => {
                setOffsetMs(event.target.value);
                setProblem(null);
                setConfirmedRevisionNo(null);
              }}
            />
          </label>
        </div>
      </section>

      {problem ? (
        <StateMessage
          state={problem.code === 'content.timing.revision.conflict' ? 'UI-EST-10' : 'UI-EST-04'}
          title={
            problem.code === 'content.timing.revision.conflict'
              ? 'Conflicto de sincronización'
              : problem.summary
          }
          description={
            problem.code === 'content.timing.revision.conflict' && serverRevisionNo !== null
              ? `${problem.correction} Servidor: revisión ${serverRevisionNo}; borrador basado en ${expectedRevisionNo ?? 'ninguna revisión previa'}.`
              : problem.correction
          }
        />
      ) : null}

      {confirmedRevisionNo !== null ? (
        <StateMessage
          state="UI-EST-12"
          title={`Borrador temporal guardado · revisión ${confirmedRevisionNo}`}
          description="La revisión sigue en DRAFT y no se ha publicado."
        />
      ) : null}

      <div className="synchronization-timeline-editor__actions">
        <div>
          <strong>
            {timedCount > 0
              ? `${timedCount} línea${timedCount === 1 ? '' : 's'} listas`
              : 'Aún sin tiempos'}
          </strong>
          <span>
            {errors.length > 0 ? ` · ${errors.length} error${errors.length === 1 ? '' : 'es'}` : ''}
          </span>
        </div>
        <button
          type="button"
          onClick={() => void save()}
          disabled={saving || timedCount === 0 || errors.length > 0}
        >
          {saving ? 'Guardando…' : 'Guardar borrador temporal'}
        </button>
      </div>
    </section>
  );
}
