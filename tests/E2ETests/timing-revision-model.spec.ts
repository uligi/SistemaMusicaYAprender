import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '56000000-0000-4000-8000-000000000001';

const context = {
  recordingId,
  lyricsRevisionId: '56000000-0000-4000-8000-000000000010',
  lyricsRevisionNo: 3,
  sources: [
    {
      sourceId: '56000000-0000-4000-8000-000000000020',
      providerCode: 'YOUTUBE',
      externalRef: 'BL056sourceA',
      durationMs: 180000,
      sourceOffsetMs: 0,
      statusCode: 'DRAFT',
      timingRevision: {
        timingRevisionId: '56000000-0000-4000-8000-000000000030',
        lyricsRevisionId: '56000000-0000-4000-8000-000000000010',
        sourceId: '56000000-0000-4000-8000-000000000020',
        revisionNo: 2,
        offsetMs: 120,
        statusCode: 'DRAFT',
        checksumSha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        lines: [
          {
            lineId: '56000000-0000-4000-8000-000000000040',
            sectionOrder: 0,
            lineNo: 1,
            japaneseText: '怪獣です',
            speakerLabel: 'Voz principal',
            precisionCode: 'TOKEN',
            startMs: 1000,
            endMs: 2200,
            tokens: [
              {
                tokenId: '56000000-0000-4000-8000-000000000050',
                tokenNo: 1,
                surface: '怪獣',
                startMs: 1000,
                endMs: 1700,
              },
              {
                tokenId: '56000000-0000-4000-8000-000000000051',
                tokenNo: 2,
                surface: 'です',
                startMs: 1700,
                endMs: 2200,
              },
            ],
          },
          {
            lineId: '56000000-0000-4000-8000-000000000041',
            sectionOrder: 0,
            lineNo: 2,
            japaneseText: '何度でも',
            speakerLabel: null,
            precisionCode: 'LINE',
            startMs: 2500,
            endMs: 4200,
            tokens: [],
          },
        ],
      },
    },
    {
      sourceId: '56000000-0000-4000-8000-000000000021',
      providerCode: 'YOUTUBE',
      externalRef: 'BL056sourceB',
      durationMs: 181000,
      sourceOffsetMs: 250,
      statusCode: 'DRAFT',
      timingRevision: null,
    },
  ],
};

test.describe('BL-MVP-056 · revisiones y segmentos de sincronización', () => {
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

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/synchronization-context`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(context),
        });
      },
    );
  });

  test('presenta fuentes independientes y tiempos por línea/token sin adelantar el editor', async ({
    page,
  }) => {
    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await expect(
      page.getByRole('heading', {
        level: 1,
        name: 'Revisiones de sincronización',
      }),
    ).toBeVisible();

    await expect(page.getByText('BL056sourceA', { exact: true })).toBeVisible();
    await expect(page.getByText('BL056sourceB', { exact: true })).toBeVisible();
    await expect(page.getByText('Revisión temporal 2', { exact: true })).toBeVisible();
    await expect(page.getByText('Sin revisión de sincronización', { exact: true })).toBeVisible();

    await expect(page.getByText('怪獣', { exact: true })).toBeVisible();
    await expect(page.getByText('1000 ms–1700 ms', { exact: true })).toBeVisible();
    await expect(page.getByText('何度でも', { exact: true })).toBeVisible();
    await expect(page.getByText('2500 ms → 4200 ms', { exact: true })).toBeVisible();

    await expect(page.getByRole('button', { name: /Guardar sincronización/i })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);
    await expect(page.locator('iframe')).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    expect(accessibility.violations).toEqual([]);
  });

  test('muestra estado seguro cuando todavía no hay revisión de letra', async ({ page }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/synchronization-context`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            recordingId,
            lyricsRevisionId: null,
            lyricsRevisionNo: null,
            sources: context.sources.map((source) => ({
              ...source,
              timingRevision: null,
            })),
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await expect(page.getByText('Sin revisión de letra', { exact: true })).toBeVisible();
    await expect(page.getByText('Revisión temporal 2', { exact: true })).toHaveCount(0);
  });

  test('mantiene UI-MVP-022 a 320px sin desbordamiento horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1100 });

    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );

    expect(overflow).toBeLessThanOrEqual(1);
  });
});
