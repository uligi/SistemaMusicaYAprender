export type SynchronizationPrecision = 'NONE' | 'LINE' | 'TOKEN';

export type SynchronizationToken = {
  tokenNo: number;
  surface: string;
  startMs: number;
  endMs: number;
};

export type SynchronizationLine = {
  sectionOrder: number;
  lineNo: number;
  japaneseText: string;
  speakerLabel: string | null;
  precisionCode: string;
  startMs: number;
  endMs: number;
  tokens: SynchronizationToken[];
};

export type SynchronizationTimeline = {
  available: boolean;
  maximumPrecision: SynchronizationPrecision;
  offsetMs: number;
  lines: SynchronizationLine[];
};

type IndexedToken = SynchronizationToken & {
  effectiveStartMs: number;
  effectiveEndMs: number;
};

type IndexedLine = {
  source: SynchronizationLine;
  effectiveStartMs: number;
  effectiveEndMs: number;
  tokens: IndexedToken[];
};

export type LocalSynchronizationIndex = {
  lines: IndexedLine[];
  prefixMaximumEndMs: number[];
  maximumPrecision: SynchronizationPrecision;
};

export type LocalSynchronizationSnapshot = {
  positionMs: number;
  level: SynchronizationPrecision;
  line: SynchronizationLine | null;
  token: SynchronizationToken | null;
};

export function emptySynchronizationTimeline(): SynchronizationTimeline {
  return {
    available: false,
    maximumPrecision: 'NONE',
    offsetMs: 0,
    lines: [],
  };
}

function validInterval(startMs: number, endMs: number) {
  return (
    Number.isSafeInteger(startMs) && Number.isSafeInteger(endMs) && startMs >= 0 && endMs > startMs
  );
}

export function createLocalSynchronizationIndex(
  timeline: SynchronizationTimeline | null,
): LocalSynchronizationIndex {
  if (!timeline?.available || !Number.isSafeInteger(timeline.offsetMs)) {
    return { lines: [], prefixMaximumEndMs: [], maximumPrecision: 'NONE' };
  }

  const lines: IndexedLine[] = timeline.lines
    .filter((line) => validInterval(line.startMs, line.endMs))
    .map((line) => {
      const effectiveStartMs = line.startMs + timeline.offsetMs;
      const effectiveEndMs = line.endMs + timeline.offsetMs;
      const tokens = line.tokens
        .filter((token) => validInterval(token.startMs, token.endMs))
        .map((token) => ({
          ...token,
          effectiveStartMs: token.startMs + timeline.offsetMs,
          effectiveEndMs: token.endMs + timeline.offsetMs,
        }))
        .filter(
          (token) =>
            token.effectiveStartMs >= effectiveStartMs &&
            token.effectiveEndMs <= effectiveEndMs &&
            token.effectiveEndMs > token.effectiveStartMs,
        )
        .sort(
          (left, right) =>
            left.effectiveStartMs - right.effectiveStartMs || left.tokenNo - right.tokenNo,
        );

      return {
        source: line,
        effectiveStartMs,
        effectiveEndMs,
        tokens,
      };
    })
    .filter((line) => line.effectiveStartMs >= 0 && line.effectiveEndMs > line.effectiveStartMs)
    .sort(
      (left, right) =>
        left.effectiveStartMs - right.effectiveStartMs ||
        left.source.sectionOrder - right.source.sectionOrder ||
        left.source.lineNo - right.source.lineNo,
    );

  const prefixMaximumEndMs: number[] = [];
  let maximumEndMs = -1;

  for (const line of lines) {
    maximumEndMs = Math.max(maximumEndMs, line.effectiveEndMs);
    prefixMaximumEndMs.push(maximumEndMs);
  }

  const maximumPrecision: SynchronizationPrecision = lines.some(
    (line) => line.source.precisionCode === 'TOKEN' && line.tokens.length > 0,
  )
    ? 'TOKEN'
    : lines.length > 0
      ? 'LINE'
      : 'NONE';

  return {
    lines,
    prefixMaximumEndMs,
    maximumPrecision,
  };
}

function lastStartedLine(index: LocalSynchronizationIndex, positionMs: number) {
  let low = 0;
  let high = index.lines.length - 1;
  let candidate = -1;

  while (low <= high) {
    const middle = low + Math.floor((high - low) / 2);
    if (index.lines[middle]!.effectiveStartMs <= positionMs) {
      candidate = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }

  return candidate;
}

function activeLineAt(index: LocalSynchronizationIndex, positionMs: number) {
  const candidate = lastStartedLine(index, positionMs);

  for (let current = candidate; current >= 0; current -= 1) {
    if (index.prefixMaximumEndMs[current]! <= positionMs) {
      break;
    }

    const line = index.lines[current]!;
    if (positionMs >= line.effectiveStartMs && positionMs < line.effectiveEndMs) {
      return line;
    }
  }

  return null;
}

function activeTokenAt(tokens: IndexedToken[], positionMs: number) {
  let low = 0;
  let high = tokens.length - 1;
  let candidate = -1;

  while (low <= high) {
    const middle = low + Math.floor((high - low) / 2);
    if (tokens[middle]!.effectiveStartMs <= positionMs) {
      candidate = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }

  if (candidate < 0) return null;

  const token = tokens[candidate]!;
  return positionMs < token.effectiveEndMs ? token : null;
}

export function locateSynchronization(
  index: LocalSynchronizationIndex,
  rawPositionMs: number,
): LocalSynchronizationSnapshot {
  const positionMs =
    Number.isFinite(rawPositionMs) && rawPositionMs >= 0 ? Math.round(rawPositionMs) : 0;

  const line = activeLineAt(index, positionMs);
  if (!line) {
    return {
      positionMs,
      level: 'NONE',
      line: null,
      token: null,
    };
  }

  if (line.source.precisionCode === 'TOKEN' && line.tokens.length > 0) {
    const token = activeTokenAt(line.tokens, positionMs);
    if (token) {
      return {
        positionMs,
        level: 'TOKEN',
        line: line.source,
        token: {
          tokenNo: token.tokenNo,
          surface: token.surface,
          startMs: token.startMs,
          endMs: token.endMs,
        },
      };
    }
  }

  return {
    positionMs,
    level: 'LINE',
    line: line.source,
    token: null,
  };
}
