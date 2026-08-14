import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '53000000-0000-4000-8000-000000000001';

const revision = {
  lyricsRevisionId: '53000000-0000-4000-8000-000000000010',
  recordingId,
  revisionNo: 2,
  parentRevisionId: '53000000-0000-4000-8000-000000000009',
  statusCode: 'DRAFT',
  createdBy: '53000000-0000-4000-8000-000000000002',
  createdAt: '2026-08-12T20:00:00Z',
  checksumSha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  version: 1,
  sections: [
    {
      sectionId: '53000000-0000-4000-8000-000000000020',
      sectionType: 'VERSE',
      label: 'Verso 1',
      displayOrder: 0,
      lines: [
        {
          lineId: '53000000-0000-4000-8000-000000000030',
          lineNo: 1,
          japaneseText: 'が 怪獣',
          normalizedText: 'が 怪獣',
          speakerLabel: 'Voz principal',
          tokens: [
            {
              tokenId: '53000000-0000-4000-8000-000000000040',
              tokenNo: 1,
              surface: 'が',
              normalizedSurface: 'が',
              startOffset: 0,
              endOffset: 2,
            },
            {
              tokenId: '53000000-0000-4000-8000-000000000041',
              tokenNo: 2,
              surface: '怪獣',
              normalizedSurface: '怪獣',
              startOffset: 3,
              endOffset: 5,
            },
          ],
        },
      ],
    },
  ],
};

test.describe('BL-MVP-053 · revisiones, secciones, líneas y tokens', () => {
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
  });

  test('conserva superficie japonesa separada de normalización y orden estructural', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            exists: true,
            revision,
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    await expect(page.getByRole('heading', { level: 1, name: 'Letra japonesa' })).toBeVisible();

    await expect(page.getByText('r2', { exact: true })).toBeVisible();
    await page.getByText('Ver estructura técnica de la revisión', { exact: true }).click();
    await expect(page.getByText('Revisión 2', { exact: true })).toBeVisible();
    await expect(page.getByText('Verso 1', { exact: true })).toBeVisible();
    const structureTree = page.getByLabel('Árbol estructural');
    await expect(structureTree.getByText('が 怪獣', { exact: true })).toBeVisible();
    await expect(structureTree.getByText('が 怪獣', { exact: true })).toBeVisible();
    await expect(page.getByText('Voz principal', { exact: true })).toBeVisible();
    await expect(page.getByText('0–2', { exact: true })).toBeVisible();
    await expect(page.getByText('3–5', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    expect(accessibility.violations).toEqual([]);
  });

  test('muestra ausencia real sin inventar letra', async ({ page }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            exists: false,
            revision: null,
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    await expect(page.getByText('Todavía no hay letra', { exact: true })).toBeVisible();
    await expect(page.getByText('怪獣', { exact: true })).toHaveCount(0);
  });

  test('mantiene UI-MVP-021 sin desbordamiento horizontal a 320px', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            exists: true,
            revision,
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
