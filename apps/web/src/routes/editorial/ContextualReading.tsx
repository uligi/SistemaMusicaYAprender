import type { ReactNode } from 'react';
import './contextual-reading.css';

export const READING_RESOLVER_VERSION = 'READING.LOCAL.V1';
export const DEFAULT_ROMAJI_SYSTEM = 'Hepburn modificado';

export type ContextualReadingItem = {
  tokenReadingId: string;
  readingKana: string;
  furigana: string | null;
  romaji: string | null;
  readingType: string;
};

export type ContextualReadingProps = {
  surface: string;
  readings: ContextualReadingItem[];
  analysisRevisionId: string;
  revisionNo: number;
};

export type ContextualReadingStatusProps = {
  sourceTokenCount: number;
  readingCoveredTokens: number;
  revisionNo: number | null;
};

type FuriganaSegment = {
  text: string;
  reading?: string;
};

const kanaMap: Record<string, string> = {
  あ: 'a',
  い: 'i',
  う: 'u',
  え: 'e',
  お: 'o',
  か: 'ka',
  き: 'ki',
  く: 'ku',
  け: 'ke',
  こ: 'ko',
  さ: 'sa',
  し: 'shi',
  す: 'su',
  せ: 'se',
  そ: 'so',
  た: 'ta',
  ち: 'chi',
  つ: 'tsu',
  て: 'te',
  と: 'to',
  な: 'na',
  に: 'ni',
  ぬ: 'nu',
  ね: 'ne',
  の: 'no',
  は: 'ha',
  ひ: 'hi',
  ふ: 'fu',
  へ: 'he',
  ほ: 'ho',
  ま: 'ma',
  み: 'mi',
  む: 'mu',
  め: 'me',
  も: 'mo',
  や: 'ya',
  ゆ: 'yu',
  よ: 'yo',
  ら: 'ra',
  り: 'ri',
  る: 'ru',
  れ: 're',
  ろ: 'ro',
  わ: 'wa',
  ゐ: 'i',
  ゑ: 'e',
  を: 'o',
  が: 'ga',
  ぎ: 'gi',
  ぐ: 'gu',
  げ: 'ge',
  ご: 'go',
  ざ: 'za',
  じ: 'ji',
  ず: 'zu',
  ぜ: 'ze',
  ぞ: 'zo',
  だ: 'da',
  ぢ: 'ji',
  づ: 'zu',
  で: 'de',
  ど: 'do',
  ば: 'ba',
  び: 'bi',
  ぶ: 'bu',
  べ: 'be',
  ぼ: 'bo',
  ぱ: 'pa',
  ぴ: 'pi',
  ぷ: 'pu',
  ぺ: 'pe',
  ぽ: 'po',
  ゔ: 'vu',
  きゃ: 'kya',
  きゅ: 'kyu',
  きょ: 'kyo',
  しゃ: 'sha',
  しゅ: 'shu',
  しょ: 'sho',
  ちゃ: 'cha',
  ちゅ: 'chu',
  ちょ: 'cho',
  にゃ: 'nya',
  にゅ: 'nyu',
  にょ: 'nyo',
  ひゃ: 'hya',
  ひゅ: 'hyu',
  ひょ: 'hyo',
  みゃ: 'mya',
  みゅ: 'myu',
  みょ: 'myo',
  りゃ: 'rya',
  りゅ: 'ryu',
  りょ: 'ryo',
  ぎゃ: 'gya',
  ぎゅ: 'gyu',
  ぎょ: 'gyo',
  じゃ: 'ja',
  じゅ: 'ju',
  じょ: 'jo',
  びゃ: 'bya',
  びゅ: 'byu',
  びょ: 'byo',
  ぴゃ: 'pya',
  ぴゅ: 'pyu',
  ぴょ: 'pyo',
  ふぁ: 'fa',
  ふぃ: 'fi',
  ふぇ: 'fe',
  ふぉ: 'fo',
  てぃ: 'ti',
  でぃ: 'di',
  とぅ: 'tu',
  どぅ: 'du',
  うぃ: 'wi',
  うぇ: 'we',
  うぉ: 'wo',
  しぇ: 'she',
  じぇ: 'je',
  ちぇ: 'che',
  つぁ: 'tsa',
  つぃ: 'tsi',
  つぇ: 'tse',
  つぉ: 'tso',
  ゔぁ: 'va',
  ゔぃ: 'vi',
  ゔぇ: 've',
  ゔぉ: 'vo',
};

const smallKana = new Set(['ゃ', 'ゅ', 'ょ', 'ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ']);

function toHiragana(value: string): string {
  return [...value]
    .map((character) => {
      const code = character.codePointAt(0) ?? 0;
      return code >= 0x30a1 && code <= 0x30f6 ? String.fromCodePoint(code - 0x60) : character;
    })
    .join('');
}

function syllableAt(value: string, index: number): { value: string; consumed: number } {
  const current = value[index] ?? '';
  const next = value[index + 1] ?? '';
  const combined = kanaMap[current + next];

  if (smallKana.has(next) && combined) {
    return { value: combined, consumed: 2 };
  }

  return { value: kanaMap[current] ?? current, consumed: 1 };
}

function lastVowel(value: string): string | null {
  const match = value.match(/[aiueo](?!.*[aiueo])/);
  return match?.[0] ?? null;
}

function withMacron(value: string): string {
  const vowel = lastVowel(value);
  if (!vowel) return value;
  const replacement: Record<string, string> = {
    a: 'ā',
    i: 'ī',
    u: 'ū',
    e: 'ē',
    o: 'ō',
  };
  const index = value.lastIndexOf(vowel);
  return `${value.slice(0, index)}${replacement[vowel]}${value.slice(index + 1)}`;
}

export function romanizeApprovedReading(readingKana: string): string {
  const value = toHiragana(readingKana.trim());
  let output = '';
  let geminate = false;

  for (let index = 0; index < value.length;) {
    const character = value[index];

    if (character === 'っ') {
      geminate = true;
      index += 1;
      continue;
    }

    if (character === 'ー') {
      output = withMacron(output);
      index += 1;
      continue;
    }

    if (character === 'ん') {
      const next = syllableAt(value, index + 1).value;
      output += /^[aiueoy]/.test(next) ? "n'" : 'n';
      index += 1;
      continue;
    }

    const syllable = syllableAt(value, index);
    let romaji = syllable.value;

    if (geminate && /^[a-z]/.test(romaji)) {
      if (romaji.startsWith('ch')) {
        romaji = `t${romaji}`;
      } else {
        romaji = `${romaji[0]}${romaji}`;
      }
      geminate = false;
    }

    output += romaji;
    index += syllable.consumed;
  }

  return output;
}

function hasKanji(value: string): boolean {
  return /\p{Script=Han}/u.test(value);
}

function isLatinOriginal(value: string): boolean {
  return (
    /\p{Script=Latin}/u.test(value) &&
    !/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/u.test(value)
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
    if (!text || !reading) {
      cursor = pattern.lastIndex;
      continue;
    }

    segments.push({ text, reading });
    visible += text;
    cursor = pattern.lastIndex;
  }

  if (cursor < furigana.length) {
    const plain = furigana.slice(cursor);
    segments.push({ text: plain });
    visible += plain;
  }

  return segments.some((segment) => segment.reading) && visible === surface ? segments : null;
}

function resolveFurigana(
  surface: string,
  readingKana: string,
  explicitFurigana: string | null,
): FuriganaSegment[] {
  if (!hasKanji(surface) || isLatinOriginal(surface)) return [{ text: surface }];

  if (explicitFurigana?.trim()) {
    const parsed = parseBracketFurigana(surface, explicitFurigana.trim());
    if (parsed) return parsed;
    return [{ text: surface, reading: explicitFurigana.trim() }];
  }

  if (/^\p{Script=Han}+$/u.test(surface)) {
    return [{ text: surface, reading: readingKana }];
  }

  return [{ text: surface }];
}

function renderFurigana(segments: FuriganaSegment[]): ReactNode {
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

function readingRank(readingType: string): number {
  const normalized = readingType.toUpperCase();
  if (normalized === 'PRIMARY') return 0;
  if (normalized === 'CONTEXTUAL') return 1;
  return 2;
}

function orderedReadings(readings: ContextualReadingItem[]): ContextualReadingItem[] {
  return [...readings].sort(
    (left, right) =>
      readingRank(left.readingType) - readingRank(right.readingType) ||
      left.readingType.localeCompare(right.readingType) ||
      left.tokenReadingId.localeCompare(right.tokenReadingId),
  );
}

export function ContextualReadingStatus({
  sourceTokenCount,
  readingCoveredTokens,
  revisionNo,
}: ContextualReadingStatusProps) {
  return (
    <section
      className="contextual-reading-status"
      aria-labelledby="contextual-reading-status-title"
    >
      <div>
        <p className="eyebrow">BL-MVP-065 · AYUDAS LOCALES</p>
        <h2 id="contextual-reading-status-title">Lecturas, furigana y romaji</h2>
        <p>
          Solo se resuelven ayudas desde una lectura editorial aprobada. Si falta o es ambigua, la
          interfaz lo mantiene explícito y no consulta servicios externos.
        </p>
      </div>
      <dl>
        <div>
          <dt>Cobertura</dt>
          <dd>
            {readingCoveredTokens}/{sourceTokenCount} tokens
          </dd>
        </div>
        <div>
          <dt>Revisión</dt>
          <dd>{revisionNo === null ? 'Pendiente' : `Análisis ${revisionNo}`}</dd>
        </div>
        <div>
          <dt>Resolver</dt>
          <dd>{READING_RESOLVER_VERSION}</dd>
        </div>
      </dl>
    </section>
  );
}

export function ContextualReading({
  surface,
  readings,
  analysisRevisionId,
  revisionNo,
}: ContextualReadingProps) {
  if (readings.length === 0) {
    return (
      <p className="contextual-reading__empty">
        Sin lectura contextual registrada. No se genera pronunciación desde los kanji por defecto.
      </p>
    );
  }

  const ordered = orderedReadings(readings);
  const ambiguous = ordered.length > 1;

  return (
    <div
      className="contextual-reading"
      data-analysis-revision-id={analysisRevisionId}
      data-resolver-version={READING_RESOLVER_VERSION}
    >
      <div className="contextual-reading__state">
        <strong>
          {ambiguous ? `Lectura ambigua · ${ordered.length} alternativas` : 'Lectura contextual'}
        </strong>
        <span>
          Análisis r{revisionNo} · {READING_RESOLVER_VERSION}
        </span>
      </div>

      <ol className="contextual-reading__alternatives">
        {ordered.map((item, index) => {
          const generatedRomaji = romanizeApprovedReading(item.readingKana);
          const romaji = item.romaji?.trim() || generatedRomaji;
          const furigana = resolveFurigana(surface, item.readingKana, item.furigana);
          const latinOriginal = isLatinOriginal(surface);
          const hasRenderedRuby = furigana.some((segment) => Boolean(segment.reading));

          return (
            <li key={item.tokenReadingId} className="contextual-reading__alternative">
              <header>
                <strong>{ambiguous ? `Alternativa ${index + 1}` : 'Aprobada'}</strong>
                <span>{item.readingType.replaceAll('_', ' ')}</span>
              </header>

              <div className="contextual-reading__japanese">
                <span className="contextual-reading__surface">{renderFurigana(furigana)}</span>
                <span lang="ja">{item.readingKana}</span>
              </div>

              <dl>
                <div>
                  <dt>Furigana</dt>
                  <dd>
                    {latinOriginal
                      ? 'Texto latino original'
                      : hasRenderedRuby
                        ? 'Contextual'
                        : hasKanji(surface)
                          ? 'Pendiente de alineación'
                          : 'No necesario'}
                  </dd>
                </div>
                <div>
                  <dt>Romaji</dt>
                  <dd lang="en">{romaji || 'Pendiente'}</dd>
                </div>
                <div>
                  <dt>Origen del romaji</dt>
                  <dd>{item.romaji?.trim() ? 'Excepción editorial' : DEFAULT_ROMAJI_SYSTEM}</dd>
                </div>
              </dl>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
