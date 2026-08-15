import type { ReactNode } from 'react';
import type { LocalSynchronizationSnapshot } from '../../features/player/synchronization/LocalSynchronizationEngine';
import { romanizeApprovedReading } from '../editorial/ContextualReading';
import './educational-karaoke.css';

export type EducationalReading = {
  readingKana: string;
  furigana: string | null;
  romaji: string | null;
  readingType: string;
};

export type EducationalToken = {
  tokenNo: number;
  surface: string;
  startOffset: number;
  endOffset: number;
  analysisKey?: string | null;
  readings: EducationalReading[];
};

export type EducationalTranslation = {
  variantCode: string;
  translatedText: string;
  displayOrder: number;
};

export type EducationalLine = {
  sectionOrder: number;
  sectionLabel: string | null;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
  tokens: EducationalToken[];
  translations: EducationalTranslation[];
};

export type EducationalLayers = {
  available: boolean;
  targetLanguage: string;
  hasFurigana: boolean;
  hasRomaji: boolean;
  hasSpanish: boolean;
  lines: EducationalLine[];
};

export type VisibleEducationalLayers = {
  japanese: boolean;
  furigana: boolean;
  romaji: boolean;
  spanish: boolean;
};

export const defaultVisibleEducationalLayers: VisibleEducationalLayers = {
  japanese: true,
  furigana: true,
  romaji: true,
  spanish: true,
};

type FuriganaSegment = {
  text: string;
  reading?: string;
};

export type EducationalAnalysisSelection = {
  analysisKey: string;
  surface: string;
  sectionOrder: number;
  lineNo: number;
  tokenNo: number;
};

export type EducationalKaraokeProps = {
  layers: EducationalLayers;
  snapshot: LocalSynchronizationSnapshot;
  visibleLayers: VisibleEducationalLayers;
  onVisibleLayersChange: (next: VisibleEducationalLayers) => void;
  selectedAnalysisKey?: string | null;
  onTokenAnalysis?: (selection: EducationalAnalysisSelection) => void;
};

function lineKey(sectionOrder: number, lineNo: number) {
  return `${sectionOrder}:${lineNo}`;
}

function hasKanji(value: string) {
  return /\p{Script=Han}/u.test(value);
}

function isLatinOriginal(value: string) {
  return (
    /\p{Script=Latin}/u.test(value) &&
    !/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/u.test(value)
  );
}

function readingRank(readingType: string) {
  const normalized = readingType.toUpperCase();
  if (normalized === 'PRIMARY') return 0;
  if (normalized === 'CONTEXTUAL') return 1;
  return 2;
}

function orderedReadings(readings: EducationalReading[]) {
  return [...readings].sort(
    (left, right) =>
      readingRank(left.readingType) - readingRank(right.readingType) ||
      left.readingType.localeCompare(right.readingType) ||
      left.readingKana.localeCompare(right.readingKana),
  );
}

function parseBracketFurigana(surface: string, furigana: string): FuriganaSegment[] | null {
  if (!furigana.includes('[') || !furigana.includes(']')) return null;

  const segments: FuriganaSegment[] = [];
  const pattern = /([^\[\]]+)\[([^\[\]]+)\]/gu;
  let cursor = 0;
  let visible = '';
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(furigana)) !== null) {
    if (match.index > cursor) {
      const plain = furigana.slice(cursor, match.index);
      segments.push({ text: plain });
      visible += plain;
    }

    const text = match[1];
    const reading = match[2];
    if (text && reading) {
      segments.push({ text, reading });
      visible += text;
    }

    cursor = pattern.lastIndex;
  }

  if (cursor < furigana.length) {
    const plain = furigana.slice(cursor);
    segments.push({ text: plain });
    visible += plain;
  }

  return segments.some((segment) => segment.reading) && visible === surface ? segments : null;
}

function resolveFurigana(surface: string, reading: EducationalReading): FuriganaSegment[] {
  if (!hasKanji(surface) || isLatinOriginal(surface)) return [{ text: surface }];

  const explicit = reading.furigana?.trim();
  if (explicit) {
    const parsed = parseBracketFurigana(surface, explicit);
    return parsed ?? [{ text: surface, reading: explicit }];
  }

  if (/^\p{Script=Han}+$/u.test(surface)) {
    return [{ text: surface, reading: reading.readingKana }];
  }

  return [{ text: surface }];
}

function renderRuby(segments: FuriganaSegment[]): ReactNode {
  return segments.map((segment, index) =>
    segment.reading ? (
      <ruby key={`${segment.text}-${index}`} lang="ja">
        {segment.text}
        <rp>(</rp>
        <rt>{segment.reading}</rt>
        <rp>)</rp>
      </ruby>
    ) : (
      <span key={`${segment.text}-${index}`} lang="ja">
        {segment.text}
      </span>
    ),
  );
}

function preferredTranslation(line: EducationalLine) {
  return (
    line.translations.find((item) => item.variantCode === 'NATURAL') ??
    line.translations.find((item) => item.variantCode === 'LITERAL') ??
    line.translations[0] ??
    null
  );
}

function renderJapaneseLine(
  line: EducationalLine,
  showFurigana: boolean,
  activeTokenNo: number | null,
  selectedAnalysisKey: string | null,
  onTokenAnalysis: ((selection: EducationalAnalysisSelection) => void) | undefined,
) {
  if (line.tokens.length === 0) {
    return <span lang="ja">{line.japaneseText}</span>;
  }

  const characters = Array.from(line.japaneseText);
  const orderedTokens = [...line.tokens].sort(
    (left, right) => left.startOffset - right.startOffset || left.tokenNo - right.tokenNo,
  );
  const nodes: ReactNode[] = [];
  let cursor = 0;

  for (const token of orderedTokens) {
    const start = Math.max(cursor, Math.min(token.startOffset, characters.length));
    const end = Math.max(start, Math.min(token.endOffset, characters.length));

    if (start > cursor) {
      nodes.push(
        <span key={`gap-${cursor}-${start}`} lang="ja">
          {characters.slice(cursor, start).join('')}
        </span>,
      );
    }

    const surface = characters.slice(start, end).join('') || token.surface;
    const readings = orderedReadings(token.readings);
    const active = activeTokenNo === token.tokenNo;
    const selected = Boolean(token.analysisKey && token.analysisKey === selectedAnalysisKey);
    const content =
      readings.length === 1 && showFurigana
        ? renderRuby(resolveFurigana(surface, readings[0]!))
        : surface;
    const className = [
      'educational-karaoke__token',
      active ? 'is-active' : '',
      selected ? 'is-selected' : '',
      token.analysisKey && onTokenAnalysis ? 'is-analyzable' : '',
    ]
      .filter(Boolean)
      .join(' ');

    if (token.analysisKey && onTokenAnalysis) {
      nodes.push(
        <button
          type="button"
          key={`token-${token.tokenNo}`}
          className={className}
          data-karaoke-token={token.tokenNo}
          data-analysis-key={token.analysisKey}
          data-active={active ? 'true' : 'false'}
          aria-label={`Analizar ${surface}`}
          aria-pressed={selected}
          aria-controls="contextual-analysis-panel"
          title={readings.length > 1 ? 'Lectura contextual ambigua' : 'Abrir análisis contextual'}
          onClick={() =>
            onTokenAnalysis({
              analysisKey: token.analysisKey!,
              surface,
              sectionOrder: line.sectionOrder,
              lineNo: line.lineNo,
              tokenNo: token.tokenNo,
            })
          }
        >
          {content}
        </button>,
      );
    } else {
      nodes.push(
        <span
          key={`token-${token.tokenNo}`}
          className={className}
          data-karaoke-token={token.tokenNo}
          data-active={active ? 'true' : 'false'}
          title={readings.length > 1 ? 'Lectura contextual ambigua' : undefined}
          lang="ja"
        >
          {content}
        </span>,
      );
    }

    cursor = end;
  }

  if (cursor < characters.length) {
    nodes.push(
      <span key={`tail-${cursor}`} lang="ja">
        {characters.slice(cursor).join('')}
      </span>,
    );
  }

  return nodes;
}
function romajiForLine(line: EducationalLine) {
  if (line.tokens.length === 0) return null;

  return [...line.tokens]
    .sort((left, right) => left.tokenNo - right.tokenNo)
    .map((token) => {
      const readings = orderedReadings(token.readings);
      if (readings.length === 0) return '—';
      if (readings.length > 1) return '〔lectura ambigua〕';

      const reading = readings[0]!;
      return reading.romaji?.trim() || romanizeApprovedReading(reading.readingKana);
    })
    .join(' ');
}

function LayerButton({
  pressed,
  disabled,
  label,
  onClick,
}: {
  pressed: boolean;
  disabled?: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      className="educational-karaoke__layer-button"
      aria-pressed={pressed}
      disabled={disabled}
      onClick={onClick}
    >
      <span aria-hidden="true">{pressed ? '✓' : '○'}</span>
      {label}
    </button>
  );
}

export function EducationalKaraoke({
  layers,
  snapshot,
  visibleLayers,
  onVisibleLayersChange,
  selectedAnalysisKey = null,
  onTokenAnalysis,
}: EducationalKaraokeProps) {
  const activeLineKey = snapshot.line
    ? lineKey(snapshot.line.sectionOrder, snapshot.line.lineNo)
    : null;
  const activeTokenNo = snapshot.level === 'TOKEN' ? (snapshot.token?.tokenNo ?? null) : null;

  return (
    <section
      className="educational-karaoke"
      aria-labelledby="educational-karaoke-title"
      data-educational-karaoke
      data-sync-level={snapshot.level}
    >
      <header className="educational-karaoke__header">
        <div>
          <p className="eyebrow">LETRA Y AYUDAS DE LECTURA</p>
          <h2 id="educational-karaoke-title">Sigue la canción a tu manera</h2>
          <p>
            Activa solo las ayudas que necesites. Cambiar una capa no reinicia el video ni modifica
            el contenido publicado.
          </p>
        </div>

        <div className="educational-karaoke__controls" aria-label="Capas de lectura">
          <LayerButton
            label="Japonés"
            pressed={visibleLayers.japanese}
            onClick={() =>
              onVisibleLayersChange({
                ...visibleLayers,
                japanese: !visibleLayers.japanese,
              })
            }
          />
          <LayerButton
            label="Furigana"
            pressed={visibleLayers.furigana}
            disabled={!layers.hasFurigana}
            onClick={() =>
              onVisibleLayersChange({
                ...visibleLayers,
                furigana: !visibleLayers.furigana,
              })
            }
          />
          <LayerButton
            label="Romaji"
            pressed={visibleLayers.romaji}
            disabled={!layers.hasRomaji}
            onClick={() =>
              onVisibleLayersChange({
                ...visibleLayers,
                romaji: !visibleLayers.romaji,
              })
            }
          />
          <LayerButton
            label="Español"
            pressed={visibleLayers.spanish}
            disabled={!layers.hasSpanish}
            onClick={() =>
              onVisibleLayersChange({
                ...visibleLayers,
                spanish: !visibleLayers.spanish,
              })
            }
          />
        </div>
      </header>

      {!layers.available || layers.lines.length === 0 ? (
        <div className="educational-karaoke__empty" role="status">
          <strong>La letra todavía no está disponible.</strong>
          <span>El reproductor puede seguir funcionando sin inventar contenido educativo.</span>
        </div>
      ) : (
        <ol className="educational-karaoke__lines">
          {layers.lines.map((line) => {
            const key = lineKey(line.sectionOrder, line.lineNo);
            const active = key === activeLineKey;
            const translation = preferredTranslation(line);
            const romaji = romajiForLine(line);

            return (
              <li
                key={key}
                className={
                  active ? 'educational-karaoke__line is-active' : 'educational-karaoke__line'
                }
                aria-current={active ? 'true' : undefined}
                data-karaoke-line={key}
                data-active={active ? 'true' : 'false'}
              >
                <div className="educational-karaoke__line-meta">
                  <span>
                    {line.sectionLabel?.trim() || `Sección ${line.sectionOrder + 1}`} · línea{' '}
                    {line.lineNo}
                  </span>
                  {line.speakerLabel ? <span>{line.speakerLabel}</span> : null}
                  {active ? <strong>Ahora</strong> : null}
                </div>

                {visibleLayers.japanese ? (
                  <p className="educational-karaoke__japanese" lang="ja">
                    {renderJapaneseLine(
                      line,
                      visibleLayers.furigana && layers.hasFurigana,
                      active ? activeTokenNo : null,
                      selectedAnalysisKey,
                      onTokenAnalysis,
                    )}
                  </p>
                ) : null}

                {visibleLayers.romaji && layers.hasRomaji ? (
                  <p className="educational-karaoke__romaji" data-layer="romaji">
                    <span className="educational-karaoke__sr-only">Romaji: </span>
                    {romaji || 'Sin romaji registrado para esta línea.'}
                  </p>
                ) : null}

                {visibleLayers.spanish && layers.hasSpanish ? (
                  <p
                    className="educational-karaoke__spanish"
                    lang={layers.targetLanguage}
                    data-layer="translation"
                  >
                    <span className="educational-karaoke__sr-only">Traducción al español: </span>
                    {translation?.translatedText || 'Sin traducción publicada para esta línea.'}
                  </p>
                ) : null}
              </li>
            );
          })}
        </ol>
      )}

      {layers.hasFurigana || layers.hasRomaji || layers.hasSpanish ? null : (
        <p className="educational-karaoke__notice">
          Esta publicación conserva la letra japonesa, pero todavía no incluye ayudas de lectura o
          traducción compatibles.
        </p>
      )}
    </section>
  );
}
