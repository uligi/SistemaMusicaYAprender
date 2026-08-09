import type { ApiResult, MutationState } from './types.js';

export const savingMutationState: MutationState = {
  phase: 'saving',
  uiState: 'UI-EST-11',
};

export function mutationStateFromResult<T>(result: ApiResult<T>): MutationState {
  if (result.kind === 'cancelled') {
    return { phase: 'cancelled', uiState: null };
  }

  if (result.ok) {
    return {
      phase: 'confirmed',
      uiState: 'UI-EST-12',
      ...(result.etag ? { etag: result.etag } : {}),
      ...(result.correlationId ? { correlationId: result.correlationId } : {}),
    };
  }

  if (result.problem.kind === 'conflict') {
    return { phase: 'conflict', uiState: 'UI-EST-10', problem: result.problem };
  }

  const uiState =
    result.problem.kind === 'validation'
      ? 'UI-EST-09'
      : result.problem.kind === 'authentication'
        ? 'UI-EST-07'
        : result.problem.kind === 'authorization'
          ? 'UI-EST-08'
          : 'UI-EST-06';

  return { phase: 'failed', uiState, problem: result.problem };
}
