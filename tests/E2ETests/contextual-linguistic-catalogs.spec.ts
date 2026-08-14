import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16600000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16600000-0000-7000-8000-000000000002';
const analysisRevisionId = '16600000-0000-7000-8000-000000000003';
const lineId = '16600000-0000-7000-8000-000000000011';
const tokenId = '16600000-0000-7000-8000-000000000021';

function populatedContext() {
  return {
    recordingId,
    lyricsRevisionId,
    lyricsRevisionNo: 6,
    explanationLanguage: 'es',
    hasStaleRevision: false,
    sourceLines: [
      {
        lineId,
        lineNo: 1,
        sectionDisplayOrder: 0,
        sectionLabel: 'Verso',
        japaneseText: '学生です',
        tokens: [
          {
            tokenId,
            lineId,
            lineNo: 1,
            tokenNo: 1,
            surface: '学生',
            normalizedSurface: '学生',
          },
        ],
      },
    ],
    revision: {
      analysisRevisionId,
      lyricsRevisionId,
      lyricsRevisionNo: 6,
      revisionNo: 4,
      parentRevisionId: null,
      statusCode: 'DRAFT',
      checksumSha256: 'c'.repeat(64),
      sourceLineCount: 1,
      sourceTokenCount: 1,
      readingCoveredTokens: 1,
      vocabularyCoveredTokens: 1,
      kanjiCoveredTokens: 1,
      morphologyCoveredTokens: 0,
      grammarCoveredLines: 1,
      readings: [
        {
          tokenReadingId: '16600000-0000-7000-8000-000000000031',
          tokenId,
          lineId,
          lineNo: 1,
          surface: '学生',
          readingKana: 'がくせい',
          furigana: '学生[がくせい]',
          romaji: null,
          readingType: 'CONTEXTUAL',
        },
      ],
      vocabulary: [
        {
          occurrenceId: '16600000-0000-7000-8000-000000000041',
          tokenId,
          lineId,
          lineNo: 1,
          surface: '学生',
          vocabularyId: '16600000-0000-7000-8000-000000000042',
          lemma: '学生',
          reading: 'がくせい',
          partOfSpeech: 'NOUN',
          senseKey: 'student.01',
          inflection: null,
          confidenceCode: 'EDITORIAL',
          senses: [
            {
              senseId: '16600000-0000-7000-8000-000000000043',
              languageTag: 'es',
              definition: 'estudiante',
              usageNote: null,
              displayOrder: 0,
            },
          ],
        },
      ],
      kanji: [
        {
          occurrenceId: '16600000-0000-7000-8000-000000000051',
          tokenId,
          lineId,
          lineNo: 1,
          surface: '学生',
          kanjiId: '16600000-0000-7000-8000-000000000052',
          character: '学',
          charOffset: 0,
          gradeCode: 'G1',
          jlptCode: 'N5',
          statusCode: 'ACTIVE',
          version: 3,
          readings: [
            {
              kanjiReadingId: '16600000-0000-7000-8000-000000000053',
              reading: 'がく',
              readingType: 'ON',
              languageTag: 'es',
              meaning: 'estudio',
              displayOrder: 0,
            },
          ],
        },
      ],
      morphology: [],
      grammar: [
        {
          occurrenceId: '16600000-0000-7000-8000-000000000061',
          lineId,
          lineNo: 1,
          japaneseText: '学生です',
          grammarPointId: '16600000-0000-7000-8000-000000000062',
          grammarCode: 'COPULA.DESU',
          title: 'Cópula です',
          levelCode: 'N5',
          startTokenId: null,
          endTokenId: null,
          note: 'Registro cortés.',
          explanation: 'Marca una predicación nominal cortés en este contexto.',
          examples: null,
        },
      ],
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

async function openToken(page: import('@playwright/test').Page) {
  const details = page.locator('details.linguistic-analysis__token').first();
  await details.locator('summary').click();
  await expect(details).toHaveAttribute('open', '');
}

test.describe('BL-MVP-066 · vocabulario, kanji y gramática contextual', () => {
  test('distingue entradas estables y ocurrencias contextuales en la revisión exacta', async ({
    page,
  }) => {
    await mockSession(page);
    await mockAnalysis(page, populatedContext());

    const externalRequests: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
        externalRequests.push(request.url());
      }
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await openToken(page);

    const vocabulary = page.getByLabel('Vocabulario de 学生');
    await expect(vocabulary.getByText('estudiante', { exact: true })).toBeVisible();
    await expect(vocabulary.getByText(/student\.01/)).toBeVisible();
    await expect(vocabulary.getByText(/Entrada estable/)).toBeVisible();

    const kanji = page.getByLabel('Kanji de 学生');
    await expect(kanji.getByText('学', { exact: true })).toBeVisible();
    await expect(kanji.getByText('がく', { exact: true })).toBeVisible();
    await expect(kanji.getByText('estudio', { exact: true })).toBeVisible();
    await expect(kanji.getByText('JLPT orientativo: N5')).toBeVisible();
    await expect(kanji.getByText(/no sustituye la lectura contextual/)).toBeVisible();

    const grammar = page.getByLabel('Gramática de la línea');
    await expect(grammar.getByText('Cópula です')).toBeVisible();
    await expect(
      grammar.getByText('Marca una predicación nominal cortés en este contexto.'),
    ).toBeVisible();
    await expect(grammar.getByText('Nivel orientativo: N5')).toBeVisible();
    await expect(grammar.getByText(/no certificación oficial/)).toBeVisible();

    expect(externalRequests).toEqual([]);
  });

  test('una revisión stale no mezcla objetos de la revisión anterior', async ({ page }) => {
    await mockSession(page);
    const context = populatedContext();
    await mockAnalysis(page, {
      ...context,
      lyricsRevisionId: '16600000-0000-7000-8000-000000000099',
      lyricsRevisionNo: 7,
      hasStaleRevision: true,
      revision: null,
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    await expect(page.getByText('La fuente japonesa cambió')).toBeVisible();
    await expect(page.getByText('Kanji contextual')).toHaveCount(0);
    await expect(page.getByText('Cópula です')).toHaveCount(0);
  });

  test('mantiene el análisis poblado usable a 320 px y sin violaciones axe', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);
    await mockAnalysis(page, populatedContext());

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await openToken(page);

    await expect(page.getByLabel('Kanji de 学生').getByText('estudio')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
