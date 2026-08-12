import { useCallback, useEffect, useRef, useState } from 'react';
import type { ApiResult, ClientProblem } from '../../data/http/types';

export type EditorialAutosavePhase = 'idle' | 'saving' | 'saved' | 'conflict' | 'failed';

export type EditorialAutosaveState = {
  phase: EditorialAutosavePhase;
  etag: string | null;
  problem: ClientProblem | null;
};

type EditorialAutosaveOptions<TDraft, TResponse> = {
  delayMs?: number;
  save: (draft: TDraft, etag: string, signal: AbortSignal) => Promise<ApiResult<TResponse>>;
  onConfirmed?: (value: TResponse) => void;
};

export function useEditorialAutosave<TDraft, TResponse>({
  delayMs = 800,
  save,
  onConfirmed,
}: EditorialAutosaveOptions<TDraft, TResponse>) {
  const [state, setState] = useState<EditorialAutosaveState>({
    phase: 'idle',
    etag: null,
    problem: null,
  });

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const controllerRef = useRef<AbortController | null>(null);
  const draftRef = useRef<TDraft | null>(null);
  const etagRef = useRef<string | null>(null);
  const conflictRef = useRef(false);

  const cancelTimer = useCallback(() => {
    if (timerRef.current !== null) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const runSave = useCallback(
    async (draft: TDraft) => {
      const etag = etagRef.current;
      if (!etag || conflictRef.current) {
        return;
      }

      cancelTimer();
      controllerRef.current?.abort();
      const controller = new AbortController();
      controllerRef.current = controller;

      setState((current) => ({
        ...current,
        phase: 'saving',
        problem: null,
      }));

      const result = await save(draft, etag, controller.signal);

      if (controller.signal.aborted || result.kind === 'cancelled') {
        return;
      }

      if (result.ok) {
        const nextEtag = result.etag ?? etag;
        etagRef.current = nextEtag;
        conflictRef.current = false;
        setState({
          phase: 'saved',
          etag: nextEtag,
          problem: null,
        });
        onConfirmed?.(result.data);
        return;
      }

      if (result.problem.kind === 'conflict') {
        conflictRef.current = true;
        setState({
          phase: 'conflict',
          etag,
          problem: result.problem,
        });
        return;
      }

      setState({
        phase: 'failed',
        etag,
        problem: result.problem,
      });
    },
    [cancelTimer, onConfirmed, save],
  );

  const schedule = useCallback(
    (draft: TDraft) => {
      draftRef.current = draft;
      if (conflictRef.current || !etagRef.current) {
        return;
      }

      setState((current) => ({
        ...current,
        phase: 'idle',
        problem: null,
      }));

      cancelTimer();
      timerRef.current = setTimeout(() => {
        const pending = draftRef.current;
        if (pending !== null) {
          void runSave(pending);
        }
      }, delayMs);
    },
    [cancelTimer, delayMs, runSave],
  );

  const flush = useCallback(
    async (draft?: TDraft) => {
      const pending = draft ?? draftRef.current;
      if (pending !== null) {
        draftRef.current = pending;
        await runSave(pending);
      }
    },
    [runSave],
  );

  const prime = useCallback(
    (etag: string, phase: 'idle' | 'saved' = 'saved') => {
      cancelTimer();
      controllerRef.current?.abort();
      etagRef.current = etag;
      conflictRef.current = false;
      setState({
        phase,
        etag,
        problem: null,
      });
    },
    [cancelTimer],
  );

  const rebase = useCallback(
    (etag: string) => {
      prime(etag, 'idle');
    },
    [prime],
  );

  useEffect(
    () => () => {
      cancelTimer();
      controllerRef.current?.abort();
    },
    [cancelTimer],
  );

  return {
    state,
    schedule,
    flush,
    prime,
    rebase,
  };
}
