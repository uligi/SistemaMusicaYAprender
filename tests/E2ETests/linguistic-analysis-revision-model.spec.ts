import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16400000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16400000-0000-7000-8000-000000000002';
const firstLineId = '16400000-0000-7000-8000-000000000011';
const secondLineId = '16400000-0000-7000-8000-000000000012';
const firstTokenId = '16400000-0000-7000-8000-000000000021';
const secondTokenId = '16400000-0000-7000-8000-000000000022';

const currentContext = {
  recordingId,
  lyricsRevisionId,
  lyricsRevisionNo: 4,
  explanationLanguage: 'es',
  hasStaleRevision: false,
  sourceLines: [
    {
      lineId: firstLineId,
      lineNo: 1,
      sectionDisplayOrder: 0,
      sectionLabel: 'Verso 1',
      japaneseText: '何度でも叫ぶ',
      tokens: [
        {
          tokenId: firstTokenId,
          lineId: firstLineId,
          lineNo: 1,
          tokenNo: 1,
          surface: '何度でも',
          normalizedSurface: '何度でも',
        },
        {
          tokenId: secondTokenId,
          lineId: firstLineId,
          lineNo: 1,
          tokenNo: 2,
          surface: '叫ぶ',
          normalizedSurface: '叫ぶ',
        },
      ],
    },
    {
      lineId: secondLineId,
      lineNo: 1,
      sectionDisplayOrder: 1,
      sectionLabel: 'Coro',
      japaneseText: '何度でも叫ぶ',
      tokens: [],
    },
  ],
  revision: {
    analysisRevisionId: '16400000-0000-7000-8000-000000000003',
    lyricsRevisionId,
    lyricsRevisionNo: 4,
    revisionNo: 2,
    parentRevisionId: null,
    statusCode: 'DRAFT',
    checksumSha256: 'a'.repeat(64),
    sourceLineCount: 2,
    sourceTokenCount: 2,
    readingCoveredTokens: 1,
    vocabularyCoveredTokens: 1,
    morphologyCoveredTokens: 1,
    grammarCoveredLines: 1,
    readings: [
      {
        tokenReadingId: '16400000-0000-7000-8000-000000000031',
        tokenId: secondTokenId,
        lineId: firstLineId,
        lineNo: 1,
        surface: '叫ぶ',
        readingKana: 'さけぶ',
        furigana: '叫[さけ]ぶ',
        romaji: 'sakebu',
        readingType: 'CONTEXTUAL',
      },
    ],
    vocabulary: [
      {
        occurrenceId: '16400000-0000-7000-8000-000000000041',
        tokenId: secondTokenId,
        lineId: firstLineId,
        lineNo: 1,
        surface: '叫ぶ',
        vocabularyId: '16400000-0000-7000-8000-000000000042',
        lemma: '叫ぶ',
        reading: 'さけぶ',
        partOfSpeech: 'VERB',
        senseKey: 'SHOUT',
        inflection: null,
        confidenceCode: 'CONFIRMED',
        senses: [
          {
            senseId: '16400000-0000-7000-8000-000000000043',
            languageTag: 'es',
            definition: 'gritar; llamar en voz alta',
            usageNote: 'Sentido usado en la canción.',
            displayOrder: 0,
          },
        ],
      },
    ],
    morphology: [
      {
        annotationId: '16400000-0000-7000-8000-000000000051',
        tokenId: secondTokenId,
        lineId: firstLineId,
        lineNo: 1,
        surface: '叫ぶ',
        lemma: '叫ぶ',
        partOfSpeechCode: 'VERB',
        conjugationCode: 'DICTIONARY_FORM',
        featuresJson: '{"politeness":"plain"}',
      },
    ],
    grammar: [
      {
        occurrenceId: '16400000-0000-7000-8000-000000000061',
        lineId: firstLineId,
        lineNo: 1,
        japaneseText: '何度でも叫ぶ',
        grammarPointId: '16400000-0000-7000-8000-000000000062',
        grammarCode: 'DEMO.EMPHATIC',
        title: 'でも enfático',
        levelCode: 'JLPT.N3',
        startTokenId: firstTokenId,
        endTokenId: firstTokenId,
        note: 'La repetición intensifica la idea.',
        explanation: 'でも puede aportar énfasis en esta construcción contextual.',
        examples: null,
      },
    ],
    provenance: [
      {
        sourceReferenceId: '16400000-0000-7000-8000-000000000071',
        sourceType: 'EDITORIAL',
        citation: 'Revisión lingüística del equipo',
        locator: 'análisis 2',
        contributionType: 'ANALYSIS_SOURCE',
        recordedBy: '16400000-0000-7000-8000-000000000072',
        recordedAt: '2026-08-13T20:00:00Z',
      },
    ],
  },
};

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

test.describe('BL-MVP-064 · revisiones de análisis lingüístico', () => {
  test('muestra revisión exacta, lectura, sentido, morfología, gramática y procedencia', async ({
    page,
  }) => {
    await mockSession(page);
    await mockAnalysis(page, currentContext);

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    await expect(
      page.getByRole('heading', { name: 'Análisis lingüístico', exact: true }),
    ).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Letra japonesa · revisión 4' })).toBeVisible();
    await expect(page.getByText('1/2 tokens').first()).toBeVisible();

    await page.locator('.linguistic-analysis__token > summary').filter({ hasText: '叫ぶ' }).click();
    await expect(
      page.getByLabel('Lecturas de 叫ぶ').getByText('さけぶ', { exact: true }),
    ).toBeVisible();
    await expect(page.getByText('gritar; llamar en voz alta')).toBeVisible();
    await expect(page.getByText('DICTIONARY FORM')).toBeVisible();
    await expect(page.getByText('でも enfático')).toBeVisible();
    await expect(
      page
        .getByLabel('Líneas y tokens')
        .getByText('でも puede aportar énfasis en esta construcción contextual.', {
          exact: true,
        }),
    ).toBeVisible();

    await page.getByText('Procedencia y revisión').click();
    await expect(page.getByText('Revisión lingüística del equipo')).toBeVisible();
    await expect(page.getByText('Publicar', { exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Guardar nueva revisión' })).toBeVisible();

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('una nueva revisión japonesa deja el análisis anterior obsoleto sin mezclar tokens', async ({
    page,
  }) => {
    await mockSession(page);
    await mockAnalysis(page, {
      ...currentContext,
      lyricsRevisionId: '16400000-0000-7000-8000-000000000099',
      lyricsRevisionNo: 5,
      hasStaleRevision: true,
      revision: null,
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    await expect(page.getByText('La fuente japonesa cambió')).toBeVisible();
    await expect(page.getByText(/no se mezclan ni migran automáticamente/i)).toBeVisible();
    await expect(page.getByText('さけぶ', { exact: true })).toHaveCount(0);
    await expect(page.getByText('でも enfático')).toHaveCount(0);
  });

  test('mantiene UI-MVP-024 accesible a 320 px sin overflow horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);
    await mockAnalysis(page, currentContext);

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await expect(
      page.getByRole('heading', { name: 'Análisis lingüístico', exact: true }),
    ).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('conserva identidad cuando line_no se repite en secciones diferentes', async ({ page }) => {
    await mockSession(page);
    await mockAnalysis(page, currentContext);

    const keyWarnings: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error' && /same key|unique "key"/i.test(message.text())) {
        keyWarnings.push(message.text());
      }
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    await expect(page.getByText('Verso 1 · línea 1')).toBeVisible();
    await expect(page.getByText('Coro · línea 1')).toBeVisible();
    expect(keyWarnings).toEqual([]);
  });
});
