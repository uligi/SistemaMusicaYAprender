import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16500000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16500000-0000-7000-8000-000000000002';
const analysisRevisionId = '16500000-0000-7000-8000-000000000003';
const lineId = '16500000-0000-7000-8000-000000000011';
const tokenId = '16500000-0000-7000-8000-000000000021';

function contextWith(readings: Array<Record<string, unknown>>, surface = '叫ぶ') {
  return {
    recordingId,
    lyricsRevisionId,
    lyricsRevisionNo: 5,
    explanationLanguage: 'es',
    hasStaleRevision: false,
    sourceLines: [
      {
        lineId,
        lineNo: 1,
        sectionDisplayOrder: 0,
        sectionLabel: 'Verso',
        japaneseText: surface,
        tokens: [
          {
            tokenId,
            lineId,
            lineNo: 1,
            tokenNo: 1,
            surface,
            normalizedSurface: surface,
          },
        ],
      },
    ],
    revision: {
      analysisRevisionId,
      lyricsRevisionId,
      lyricsRevisionNo: 5,
      revisionNo: 3,
      parentRevisionId: null,
      statusCode: 'DRAFT',
      checksumSha256: 'b'.repeat(64),
      sourceLineCount: 1,
      sourceTokenCount: 1,
      readingCoveredTokens: readings.length > 0 ? 1 : 0,
      vocabularyCoveredTokens: 0,
      morphologyCoveredTokens: 0,
      grammarCoveredLines: 0,
      readings,
      vocabulary: [],
      morphology: [],
      grammar: [],
      provenance: [],
    },
  };
}

async function mockSession(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'EDITOR',
        roles: ['EDITOR'],
        capabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],
      }),
    });
  });
}

async function mockAnalysis(page: import('@playwright/test').Page, body: unknown) {
  await page.route('**/api/v1/editorial/song-drafts/*/analysis-context?*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(body),
    });
  });
}

async function openFirstTokenAnalysis(page: import('@playwright/test').Page) {
  const details = page.locator('details.linguistic-analysis__token').first();
  await details.locator('summary').click();
  await expect(details).toHaveAttribute('open', '');
}

function reading(
  id: string,
  readingKana: string,
  readingType: string,
  furigana: string | null,
  romaji: string | null,
) {
  return {
    tokenReadingId: id,
    tokenId,
    lineId,
    lineNo: 1,
    surface: '叫ぶ',
    readingKana,
    furigana,
    romaji,
    readingType,
  };
}

test.describe('BL-MVP-065 · lecturas, furigana y romaji contextuales', () => {
  test('genera romaji solo desde lectura aprobada y renderiza ruby semántico localmente', async ({
    page,
  }) => {
    await mockSession(page);
    await mockAnalysis(
      page,
      contextWith([
        reading('16500000-0000-7000-8000-000000000031', 'さけぶ', 'CONTEXTUAL', '叫[さけ]ぶ', null),
      ]),
    );

    const externalRequests: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
        externalRequests.push(request.url());
      }
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await openFirstTokenAnalysis(page);

    const readings = page.getByLabel('Lecturas de 叫ぶ');
    await expect(readings.getByText('さけぶ', { exact: true })).toBeVisible();
    await expect(readings.getByText('sakebu', { exact: true })).toBeVisible();
    await expect(readings.getByText('Hepburn modificado', { exact: true })).toBeVisible();
    await expect(readings.getByText(/READING\.LOCAL\.V1/)).toBeVisible();
    await expect(readings.locator('ruby')).toHaveCount(1);
    await expect(readings.locator('rt')).toHaveText('さけ');
    expect(externalRequests).toEqual([]);
  });

  test('conserva alternativas ambiguas y no selecciona una lectura silenciosamente', async ({
    page,
  }) => {
    await mockSession(page);
    await mockAnalysis(
      page,
      contextWith([
        reading('16500000-0000-7000-8000-000000000041', 'きょう', 'PRIMARY', '叫ぶ[きょう]', 'kyō'),
        reading(
          '16500000-0000-7000-8000-000000000042',
          'こんにち',
          'ALTERNATIVE.01',
          '叫ぶ[こんにち]',
          null,
        ),
      ]),
    );

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await openFirstTokenAnalysis(page);

    const readings = page.getByLabel('Lecturas de 叫ぶ');
    await expect(readings.getByText('Lectura ambigua · 2 alternativas')).toBeVisible();
    const alternatives = readings.locator('.contextual-reading__alternative');
    await expect(alternatives).toHaveCount(2);
    await expect(
      alternatives.nth(0).locator('.contextual-reading__japanese > span[lang="ja"]'),
    ).toHaveText('きょう');
    await expect(
      alternatives.nth(1).locator('.contextual-reading__japanese > span[lang="ja"]'),
    ).toHaveText('こんにち');
    await expect(readings.getByText('Excepción editorial', { exact: true })).toBeVisible();
    await expect(readings.getByText('konnichi', { exact: true })).toBeVisible();
  });

  test('no inventa furigana sobre texto latino y mantiene el estado explícito', async ({
    page,
  }) => {
    await mockSession(page);
    const latinReading = {
      ...reading('16500000-0000-7000-8000-000000000051', 'らぶ', 'CONTEXTUAL', null, null),
      surface: 'LOVE',
    };
    await mockAnalysis(page, contextWith([latinReading], 'LOVE'));

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await openFirstTokenAnalysis(page);

    const readings = page.getByLabel('Lecturas de LOVE');
    await expect(readings.getByText('Texto latino original')).toBeVisible();
    await expect(readings.getByText('rabu', { exact: true })).toBeVisible();
    await expect(readings.locator('ruby')).toHaveCount(0);
  });

  test('mantiene UI-MVP-024 a 320 px, con ruby accesible y sin overflow horizontal', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);
    await mockAnalysis(
      page,
      contextWith([
        reading('16500000-0000-7000-8000-000000000061', 'さけぶ', 'CONTEXTUAL', '叫[さけ]ぶ', null),
      ]),
    );

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await expect(page.getByRole('heading', { name: 'Lecturas, furigana y romaji' })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
