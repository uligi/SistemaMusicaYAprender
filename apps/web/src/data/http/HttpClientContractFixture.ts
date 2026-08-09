import { createHttpClient, type ApiResult, type MutationState } from './index.js';

type SongSummary = {
  slug: string;
  titleJa: string;
  titleEs: string;
};

type PreferenceUpdate = {
  romajiVisible: boolean;
};

export async function httpClientContractFixture(
  signal: AbortSignal,
): Promise<{ song: ApiResult<SongSummary>; states: readonly MutationState[] }> {
  const client = createHttpClient();
  const states: MutationState[] = [];

  const song = await client.get<SongSummary>('/songs/kaiju', {
    signal,
    cacheMode: 'reload',
  });

  await client.patch<PreferenceUpdate, PreferenceUpdate>(
    '/preferences',
    { romajiVisible: true },
    {
      signal,
      ifMatch: '"preferences-v1"',
      idempotencyKey: 'fixture-preferences-v1',
      invalidate: ['/preferences'],
      onStateChange: (state) => states.push(state),
    },
  );

  const semanticJapaneseExample: SongSummary = {
    slug: 'kaiju',
    titleJa: '怪獣',
    titleEs: 'Kaijū',
  };

  void semanticJapaneseExample;
  return { song, states };
}
