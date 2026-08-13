import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '55000000-0000-4000-8000-000000000001';
const revisionId = '55000000-0000-4000-8000-000000000010';

function revisionResponse(grouped = false) {
  return {
    exists: true,
    revision: {
      lyricsRevisionId: revisionId,
      recordingId,
      revisionNo: grouped ? 2 : 1,
      parentRevisionId: grouped ? revisionId : null,
      statusCode: 'DRAFT',
      createdBy: '55000000-0000-4000-8000-000000000002',
      createdAt: '2026-08-13T00:15:00Z',
      checksumSha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      version: 1,
      sections: [
        {
          sectionId: '55000000-0000-4000-8000-000000000020',
          sectionType: 'VERSE',
          label: 'Verso 1',
          displayOrder: 0,
          lines: [
            {
              lineId: '55000000-0000-4000-8000-000000000030',
              lineNo: 1,
              japaneseText: '怪獣です',
              normalizedText: '怪獣です',
              speakerLabel: 'Voz principal',
              tokens: grouped
                ? [
                    {
                      tokenId: '55000000-0000-4000-8000-000000000041',
                      tokenNo: 1,
                      surface: '怪獣',
                      normalizedSurface: '怪獣',
                      startOffset: 0,
                      endOffset: 2,
                    },
                    {
                      tokenId: '55000000-0000-4000-8000-000000000042',
                      tokenNo: 2,
                      surface: 'です',
                      normalizedSurface: 'です',
                      startOffset: 2,
                      endOffset: 4,
                    },
                  ]
                : [
                    {
                      tokenId: '55000000-0000-4000-8000-000000000040',
                      tokenNo: 1,
                      surface: '怪',
                      normalizedSurface: '怪',
                      startOffset: 0,
                      endOffset: 1,
                    },
                    {
                      tokenId: '55000000-0000-4000-8000-000000000041',
                      tokenNo: 2,
                      surface: '獣',
                      normalizedSurface: '獣',
                      startOffset: 1,
                      endOffset: 2,
                    },
                    {
                      tokenId: '55000000-0000-4000-8000-000000000042',
                      tokenNo: 3,
                      surface: 'です',
                      normalizedSurface: 'です',
                      startOffset: 2,
                      endOffset: 4,
                    },
                  ],
            },
          ],
        },
      ],
    },
  };
}

test.describe('BL-MVP-055 · segmentación y corrección manual de tokens', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'EDITOR',
          roles: ['EDITOR'],
          capabilities: ['EDITORIAL.DRAFT'],
        }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-bl055',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
  });

  test('une tokens conservando offsets y avisa relaciones afectadas antes de guardar', async ({
    page,
  }) => {
    let postedBody: unknown = null;

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: {
            ETag: `"lyrics-${revisionId.replaceAll('-', '')}-v1"`,
          },
          body: JSON.stringify(revisionResponse()),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/${revisionId}/segmentation-impact`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            lyricsRevisionId: revisionId,
            timingRevisionCount: 1,
            translationRevisionCount: 2,
            analysisRevisionCount: 3,
            hasImpact: true,
          }),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions`,
      async (route) => {
        postedBody = route.request().postDataJSON();

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: {
            ETag: '"lyrics-55000000000040008000000000000011-v1"',
          },
          body: JSON.stringify(revisionResponse(true)),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    await expect(page.getByRole('heading', { name: 'Segmentación manual' })).toBeVisible();
    await expect(page.getByText('Superficie exacta: 怪', { exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Unir con siguiente' }).first().click();

    await expect(page.getByRole('heading', { name: 'Impacto de la segmentación' })).toBeVisible();
    await expect(page.getByText('Sincronización: 1 revisión relacionada')).toBeVisible();
    await expect(page.getByText('Traducciones: 2 revisiones relacionadas')).toBeVisible();
    await expect(page.getByText('Análisis: 3 revisiones relacionadas')).toBeVisible();
    await expect(page.getByText('Superficie exacta: 怪獣', { exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    await expect(page.getByText('Revisión guardada', { exact: true })).toBeVisible();

    expect(postedBody).toMatchObject({
      sections: [
        {
          lines: [
            {
              japaneseText: '怪獣です',
              tokens: [
                {
                  surface: '怪獣',
                  startOffset: 0,
                  endOffset: 2,
                },
                {
                  surface: 'です',
                  startOffset: 2,
                  endOffset: 4,
                },
              ],
            },
          ],
        },
      ],
    });

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    expect(accessibility.violations).toEqual([]);
  });

  test('segmenta caracteres sin reescribir la superficie japonesa', async ({ page }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: '"lyrics-none"' },
          body: JSON.stringify({
            exists: false,
            revision: null,
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    await page.getByLabel('Japonés original').fill('怪獣');
    await page.getByRole('button', { name: 'Segmentar caracteres restantes' }).click();

    await expect(page.getByText('Superficie exacta: 怪', { exact: true })).toBeVisible();
    await expect(page.getByText('Superficie exacta: 獣', { exact: true })).toBeVisible();
    await expect(page.getByLabel('Japonés original')).toHaveValue('怪獣');
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);
  });

  test('distribuye un bloque multilínea en líneas editoriales independientes', async ({ page }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: '"lyrics-none"' },
          body: JSON.stringify({
            exists: false,
            revision: null,
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    await page
      .getByLabel('Japonés original')
      .fill('何度でも\n何度でも叫ぶ\nこの暗い夜の怪獣になっても');

    const japaneseLines = page.getByLabel('Japonés original');

    await expect(japaneseLines).toHaveCount(3);
    await expect(japaneseLines.nth(0)).toHaveValue('何度でも');
    await expect(japaneseLines.nth(1)).toHaveValue('何度でも叫ぶ');
    await expect(japaneseLines.nth(2)).toHaveValue('この暗い夜の怪獣になっても');

    await expect(page.getByText('Línea 1', { exact: true })).toBeVisible();
    await expect(page.getByText('Línea 2', { exact: true })).toBeVisible();
    await expect(page.getByText('Línea 3', { exact: true })).toBeVisible();

    for (const value of [
      await japaneseLines.nth(0).inputValue(),
      await japaneseLines.nth(1).inputValue(),
      await japaneseLines.nth(2).inputValue(),
    ]) {
      expect(value).not.toContain('\n');
      expect(value).not.toContain('\r');
    }
  });

  test('mantiene el segmentador a 320px sin desbordamiento horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1100 });

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: {
            ETag: `"lyrics-${revisionId.replaceAll('-', '')}-v1"`,
          },
          body: JSON.stringify(revisionResponse()),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/${revisionId}/segmentation-impact`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            lyricsRevisionId: revisionId,
            timingRevisionCount: 0,
            translationRevisionCount: 0,
            analysisRevisionCount: 0,
            hasImpact: false,
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );

    expect(overflow).toBeLessThanOrEqual(1);
  });
});
