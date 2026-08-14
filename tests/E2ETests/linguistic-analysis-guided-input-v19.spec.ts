import { expect, test } from '@playwright/test';

const recordingId = '16700000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16700000-0000-7000-8000-000000000002';
const lineId = '16700000-0000-7000-8000-000000000011';
const tokenId = '16700000-0000-7000-8000-000000000021';

function emptyContext() {
  return {
    recordingId,
    lyricsRevisionId,
    lyricsRevisionNo: 7,
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
          { tokenId, lineId, lineNo: 1, tokenNo: 1, surface: '学生', normalizedSurface: '学生' },
          {
            tokenId: '16700000-0000-7000-8000-000000000022',
            lineId,
            lineNo: 1,
            tokenNo: 2,
            surface: 'です',
            normalizedSurface: 'です',
          },
        ],
      },
    ],
    revision: null,
  };
}

async function mockBase(page: import('@playwright/test').Page) {
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

  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ requestToken: 'csrf-v19', headerName: 'X-CSRF-TOKEN' }),
    });
  });

  await page.route('**/api/v1/editorial/song-drafts/*/analysis-context?*', async (route) => {
    await route.fulfill({
      status: 200,
      headers: { ETag: '"analysis-base-none"' },
      contentType: 'application/json',
      body: JSON.stringify(emptyContext()),
    });
  });
}

test.describe('BL-MVP-067 v19 · entrada guiada', () => {
  test('un sentido sin significado queda bloqueado localmente y no hace POST', async ({ page }) => {
    await mockBase(page);

    let validationRequests = 0;
    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        validationRequests += 1;
        await route.fulfill({
          status: 500,
          contentType: 'application/problem+json',
          body: JSON.stringify({ title: 'No debió llegar al servidor' }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await page.getByText('Vocabulario y significado').click();
    await page.getByRole('button', { name: 'Añadir significado' }).click();
    await page.getByRole('button', { name: 'Validar borrador' }).click();

    await expect(page.getByText('Hay campos por completar')).toBeVisible();
    await expect(
      page.getByText('Completa este significado o quita el sentido si no conoces el dato.'),
    ).toBeVisible();
    await expect(page.getByLabel('Significado contextual en español')).toHaveAttribute(
      'aria-invalid',
      'true',
    );
    expect(validationRequests).toBe(0);
  });

  test('nivel escolar es un select humano y G1-G6 se mapea al payload', async ({ page }) => {
    await mockBase(page);

    let body: any = null;
    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        body = route.request().postDataJSON();
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            canSave: true,
            errorCount: 0,
            warningCount: 1,
            orphanCount: 0,
            checksumSha256: 'v19'.padEnd(64, '0'),
            coverage: {
              totalTokens: 2,
              readingTokens: 0,
              vocabularyTokens: 0,
              kanjiTokens: 1,
              morphologyTokens: 0,
              totalLines: 1,
              grammarLines: 0,
            },
            provenanceCitation: 'Curaduría editorial interna',
            issues: [],
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await page.getByText('Kanji de esta palabra').click();
    await page.getByRole('button', { name: 'Preparar kanji escritos en la palabra' }).click();

    const grade = page.getByLabel('Nivel escolar').first();
    expect(await grade.evaluate((element) => element.tagName)).toBe('SELECT');
    await expect(grade.locator('option')).toHaveText([
      'Sin clasificar',
      'Grado 1',
      'Grado 2',
      'Grado 3',
      'Grado 4',
      'Grado 5',
      'Grado 6',
    ]);

    await grade.selectOption('G2');
    await page.getByRole('button', { name: 'Validar borrador' }).click();

    await expect(page.getByRole('heading', { name: 'Todo listo para guardar' })).toBeVisible();
    expect(body.kanji[0].gradeCode).toBe('G2');
  });
});
