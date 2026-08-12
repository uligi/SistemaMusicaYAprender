import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

async function assertNoHorizontalOverflow(page: Page) {
  const metrics = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));

  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.innerWidth + 1);
}

const slug = '怪獣-0123456789abcdefabcd';

test.describe('BL-MVP-043 · ficha pública de canción', () => {
  test('abre desde catálogo por slug legible sin exponer IDs ni depender de YouTube', async ({
    page,
  }) => {
    const externalHosts = new Set<string>();

    page.on('request', (request) => {
      const url = new URL(request.url());
      if (!['localhost', '127.0.0.1'].includes(url.hostname)) {
        externalHosts.add(url.hostname);
      }
    });

    await page.route('**/api/v1/public/catalog/search**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: [
            {
              slug,
              canonicalTitle: '怪獣',
              recordingTitle: 'Album version',
              artistName: 'サカナクション',
              providerCode: 'YOUTUBE',
              territoryCode: 'CR',
              languageTag: 'es',
              indexedAt: '2026-08-12T16:00:00Z',
            },
          ],
          nextCursor: null,
          pageSize: 12,
          hasMore: false,
        }),
      });
    });

    await page.route('**/api/v1/public/catalog/songs/**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          slug,
          canonicalTitle: '怪獣',
          recordingTitle: 'Album version',
          recordingDurationMs: 241000,
          artistName: 'サカナクション',
          providerCode: 'YOUTUBE',
          territoryCode: 'CR',
          languageTag: 'es',
          availabilityValidFrom: '2026-08-12T15:00:00Z',
          availabilityValidTo: null,
          availableComponents: ['CATALOG'],
        }),
      });
    });

    await page.goto('/canciones');
    await page.getByRole('link', { name: 'Abrir ficha de 怪獣 · Album version' }).click();

    await expect(page.locator('[data-route-id="UI-MVP-004"]')).toBeVisible();
    await expect(page).toHaveURL(/\/canciones\//);
    const heading = page.getByRole('heading', { level: 1, name: '怪獣' });
    await expect(heading).toBeVisible();
    await expect(heading).toBeFocused();
    await expect(page.getByText('サカナクション', { exact: true })).toBeVisible();
    await expect(page.getByText('Album version', { exact: true })).toBeVisible();
    await expect(page.getByText('Disponible · CR · es', { exact: true })).toBeVisible();
    await expect(page.getByText('Ficha y metadatos editoriales', { exact: true })).toBeVisible();
    await expect(page.getByText('YouTube es una fuente externa.', { exact: true })).toBeVisible();

    const visibleText = await page.locator('body').innerText();
    expect(visibleText).not.toContain('11111111-1111-4111-8111-111111111111');
    expect(visibleText).not.toContain('a8dgNdJVluc');
    expect(externalHosts).toEqual(new Set());
    await assertNoHorizontalOverflow(page);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('enlace retirado muestra estado seguro sin metadatos protegidos', async ({ page }) => {
    await page.route('**/api/v1/public/catalog/songs/**', async (route) => {
      await route.fulfill({ status: 404, body: '' });
    });

    await page.goto(`/canciones/${encodeURIComponent(slug)}`);

    await expect(page.locator('[data-route-id="UI-MVP-004"]')).toBeVisible();
    await expect(page.getByText('Canción no disponible', { exact: true })).toBeVisible();
    await expect(page.getByText('BORRADOR SECRETO', { exact: true })).toHaveCount(0);
    await assertNoHorizontalOverflow(page);
  });
});
