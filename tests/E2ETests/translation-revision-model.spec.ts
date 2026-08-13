import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16100000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16100000-0000-7000-8000-000000000002';
const firstLineId = '16100000-0000-7000-8000-000000000011';
const secondLineId = '16100000-0000-7000-8000-000000000012';
const literalLineId = '16100000-0000-7000-8000-000000000021';
const naturalLineId = '16100000-0000-7000-8000-000000000022';

const currentContext = {
  recordingId,
  lyricsRevisionId,
  lyricsRevisionNo: 3,
  targetLanguage: 'es',
  translationType: 'HUMAN',
  hasStaleRevision: false,
  sourceLines: [
    { lineId: firstLineId, lineNo: 1, japaneseText: '何度でも叫ぶ' },
    { lineId: secondLineId, lineNo: 2, japaneseText: 'ここに残しておきたいんだよ' },
  ],
  revision: {
    translationRevisionId: '16100000-0000-7000-8000-000000000003',
    lyricsRevisionId,
    lyricsRevisionNo: 3,
    targetLanguage: 'es',
    translationType: 'HUMAN',
    revisionNo: 2,
    parentRevisionId: null,
    statusCode: 'DRAFT',
    checksumSha256: 'a'.repeat(64),
    sourceLineCount: 2,
    literalCoveredLines: 2,
    naturalCoveredLines: 2,
    completeForReview: true,
    missingLiteralLineNos: [],
    missingNaturalLineNos: [],
    hasManyToManyAlignment: true,
    lines: [
      {
        translationLineId: literalLineId,
        anchorLineId: firstLineId,
        anchorLineNo: 1,
        japaneseText: '何度でも叫ぶ',
        variantCode: 'LITERAL',
        translatedText: 'Grito una y otra vez',
        displayOrder: 0,
        alignments: [
          {
            alignmentId: '16100000-0000-7000-8000-000000000031',
            tokenId: '16100000-0000-7000-8000-000000000041',
            sourceLineId: firstLineId,
            sourceLineNo: 1,
            surface: '何度でも',
            targetStart: 0,
            targetEnd: 17,
            alignmentType: 'APPROXIMATE',
          },
          {
            alignmentId: '16100000-0000-7000-8000-000000000032',
            tokenId: '16100000-0000-7000-8000-000000000042',
            sourceLineId: firstLineId,
            sourceLineNo: 1,
            surface: '叫ぶ',
            targetStart: 0,
            targetEnd: 17,
            alignmentType: 'MERGED',
          },
        ],
      },
      {
        translationLineId: naturalLineId,
        anchorLineId: firstLineId,
        anchorLineNo: 1,
        japaneseText: '何度でも叫ぶ',
        variantCode: 'NATURAL',
        translatedText: 'Sigo gritando, una vez más',
        displayOrder: 1,
        alignments: [
          {
            alignmentId: '16100000-0000-7000-8000-000000000033',
            tokenId: '16100000-0000-7000-8000-000000000041',
            sourceLineId: firstLineId,
            sourceLineNo: 1,
            surface: '何度でも',
            targetStart: 0,
            targetEnd: 26,
            alignmentType: 'APPROXIMATE',
          },
        ],
      },
      {
        translationLineId: '16100000-0000-7000-8000-000000000023',
        anchorLineId: secondLineId,
        anchorLineNo: 2,
        japaneseText: 'ここに残しておきたいんだよ',
        variantCode: 'LITERAL',
        translatedText: 'Quiero dejarlo aquí',
        displayOrder: 2,
        alignments: [],
      },
      {
        translationLineId: '16100000-0000-7000-8000-000000000024',
        anchorLineId: secondLineId,
        anchorLineNo: 2,
        japaneseText: 'ここに残しておきたいんだよ',
        variantCode: 'NATURAL',
        translatedText: 'Quiero que esto permanezca aquí',
        displayOrder: 3,
        alignments: [],
      },
    ],
    notes: [
      {
        noteId: '16100000-0000-7000-8000-000000000051',
        lineId: firstLineId,
        tokenId: null,
        noteType: 'EDITORIAL',
        noteText: 'La repetición conserva el énfasis del original.',
        sourceReferenceId: '16100000-0000-7000-8000-000000000061',
        sourceType: 'EDITORIAL',
        citation: 'Decisión de traducción del equipo',
        locator: 'revisión 2',
      },
    ],
    provenance: [
      {
        sourceReferenceId: '16100000-0000-7000-8000-000000000061',
        sourceType: 'EDITORIAL',
        citation: 'Decisión de traducción del equipo',
        locator: 'revisión 2',
        contributionType: 'TRANSLATION_SOURCE',
        recordedBy: '16100000-0000-7000-8000-000000000071',
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

test.describe('BL-MVP-061 · traducciones, revisiones y alineaciones', () => {
  test('muestra fuente exacta, literal/natural, N:M y procedencia sin publicar', async ({
    page,
  }) => {
    await mockSession(page);
    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(currentContext),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    await expect(page.getByRole('heading', { name: 'Traducción y alineaciones' })).toBeVisible();
    await expect(page.getByText('Letra japonesa · revisión 3')).toBeVisible();
    await expect(page.getByText('Grito una y otra vez')).toBeVisible();
    await expect(page.getByText('Sigo gritando, una vez más')).toBeVisible();
    await expect(page.getByText('N:M detectada')).toBeVisible();
    await expect(page.getByText('Decisión de traducción del equipo').first()).toBeVisible();

    await expect(page.locator('[lang="ja"]').first()).toContainText('何度でも叫ぶ');
    await expect(
      page.locator('p[lang="es"]').filter({ hasText: /^Grito una y otra vez$/ }),
    ).toBeVisible();
    await expect(page.getByText('Publicar revisión', { exact: true })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('una nueva revisión japonesa deja la traducción anterior pendiente, sin compatibilidad automática', async ({
    page,
  }) => {
    await mockSession(page);
    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          ...currentContext,
          lyricsRevisionId: '16100000-0000-7000-8000-000000000099',
          lyricsRevisionNo: 4,
          hasStaleRevision: true,
          revision: null,
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    await expect(page.getByText('La fuente japonesa cambió')).toBeVisible();
    await expect(
      page.getByText(/alineaciones quedan pendientes de revisión explícita/i),
    ).toBeVisible();
    await expect(page.getByText('Traducción · revisión 2')).toHaveCount(0);
  });

  test('mantiene la lectura de japonés y español sin overflow a 320 px', async ({ page }) => {
    await mockSession(page);
    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(currentContext),
      });
    });

    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    await expect(page.getByText('Grito una y otra vez')).toBeVisible();
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });

  test('conserva identidad estable cuando una misma línea se repite en secciones distintas', async ({
    page,
  }) => {
    await mockSession(page);

    const repeatedLineId = '16100000-0000-7000-8000-000000000013';
    const repeatedContext = {
      ...currentContext,
      sourceLines: [
        { lineId: firstLineId, lineNo: 1, japaneseText: '何度でも叫ぶ' },
        { lineId: repeatedLineId, lineNo: 1, japaneseText: '何度でも叫ぶ' },
      ],
      revision: {
        ...currentContext.revision,
        sourceLineCount: 2,
        literalCoveredLines: 2,
        naturalCoveredLines: 0,
        completeForReview: false,
        missingLiteralLineNos: [],
        missingNaturalLineNos: [1, 1],
        hasManyToManyAlignment: false,
        lines: [
          {
            ...currentContext.revision.lines[0],
            translatedText: 'Primera aparición',
            displayOrder: 0,
          },
          {
            ...currentContext.revision.lines[0],
            translationLineId: '16100000-0000-7000-8000-000000000025',
            anchorLineId: repeatedLineId,
            translatedText: 'Segunda aparición',
            displayOrder: 1,
          },
        ],
        notes: [],
        provenance: [],
      },
    };

    const keyWarnings: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error' && /same key|unique "key"/i.test(message.text())) {
        keyWarnings.push(message.text());
      }
    });

    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(repeatedContext),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    const translatedVariants = page.locator('.translation-structure__variant p[lang="es"]');
    await expect(translatedVariants).toHaveCount(2);
    await expect(translatedVariants.nth(0)).toHaveText('Primera aparición');
    await expect(translatedVariants.nth(1)).toHaveText('Segunda aparición');
    expect(keyWarnings).toEqual([]);
  });
});
