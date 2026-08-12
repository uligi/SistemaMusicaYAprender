import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

type SearchRequest = {
  query: string;
  territory: string;
  language: string;
  cursor: string | null;
};

async function assertNoHorizontalOverflow(page: Page) {
  const metrics = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));

  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.innerWidth + 1);
}

test.describe('BL-MVP-042 · búsqueda interna PostgreSQL', () => {
  test('muestra catálogo y búsqueda Unicode sin servicio externo', async ({ page }) => {
    const requests: SearchRequest[] = [];
    const externalHosts = new Set<string>();

    page.on('request', (request) => {
      const url = new URL(request.url());
      if (!['localhost', '127.0.0.1'].includes(url.hostname)) {
        externalHosts.add(url.hostname);
      }
    });

    await page.route('**/api/v1/public/catalog/search**', async (route) => {
      const url = new URL(route.request().url());
      requests.push({
        query: url.searchParams.get('query') ?? '',
        territory: url.searchParams.get('territory') ?? '',
        language: url.searchParams.get('language') ?? '',
        cursor: url.searchParams.get('cursor'),
      });

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: [
            {
              publicationId: '11111111-1111-4111-8111-111111111111',
              recordingId: '22222222-2222-4222-8222-222222222222',
              workId: '33333333-3333-4333-8333-333333333333',
              canonicalTitle: '怪獣',
              recordingTitle: 'Album version',
              artistId: '44444444-4444-4444-8444-444444444444',
              artistName: 'サカナクション',
              providerCode: 'YOUTUBE',
              externalRef: 'a8dgNdJVluc',
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

    await page.goto('/canciones');
    await expect(page.locator('[data-route-id="UI-MVP-002"]')).toBeVisible();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Catálogo de canciones' }),
    ).toBeFocused();
    await expect(page.getByText('怪獣', { exact: true })).toBeVisible();
    await expect(page.getByText('サカナクション', { exact: true })).toBeVisible();
    await expect(page.getByText('Album version', { exact: true })).toBeVisible();
    await assertNoHorizontalOverflow(page);

    const input = page.getByLabel('Buscar por título, artista, alias o lectura');
    await input.fill('かいじゅう');
    await page.getByRole('button', { name: 'Buscar canciones' }).click();

    await expect(page).toHaveURL(/\/canciones\?consulta=/);
    await expect(page.locator('[data-route-id="UI-MVP-003"]')).toBeVisible();
    const searchHeading = page.getByRole('heading', {
      level: 1,
      name: 'Resultados de búsqueda',
    });
    await expect(searchHeading).toBeFocused();
    await expect(searchHeading).toHaveClass(/\broute-title\b/);

    const headingFocusStyle = await searchHeading.evaluate((element) => {
      const style = window.getComputedStyle(element);
      return {
        outlineStyle: style.outlineStyle,
        outlineWidth: Number.parseFloat(style.outlineWidth),
        outlineColor: style.outlineColor,
      };
    });
    expect(headingFocusStyle.outlineStyle).toBe('solid');
    expect(headingFocusStyle.outlineWidth).toBeGreaterThanOrEqual(2);
    expect(headingFocusStyle.outlineColor).not.toBe('rgb(0, 0, 0)');
    await expect(page.getByText('怪獣', { exact: true })).toBeVisible();

    expect(requests.some((request) => request.query === '')).toBe(true);
    expect(requests.some((request) => request.query === 'かいじゅう')).toBe(true);
    expect(requests.every((request) => request.territory === 'CR')).toBe(true);
    expect(requests.every((request) => request.language === 'es')).toBe(true);
    expect(externalHosts).toEqual(new Set());

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('pagina con cursor opaco y conserva grabaciones separadas', async ({ page }) => {
    const cursors: Array<string | null> = [];

    await page.route('**/api/v1/public/catalog/search**', async (route) => {
      const url = new URL(route.request().url());
      const cursor = url.searchParams.get('cursor');
      cursors.push(cursor);

      if (!cursor) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            items: [
              {
                publicationId: '11111111-1111-4111-8111-111111111111',
                recordingId: '22222222-2222-4222-8222-222222222222',
                workId: '33333333-3333-4333-8333-333333333333',
                canonicalTitle: '怪獣',
                recordingTitle: 'Album version',
                artistId: '44444444-4444-4444-8444-444444444444',
                artistName: 'サカナクション',
                providerCode: 'YOUTUBE',
                externalRef: 'a8dgNdJVluc',
                territoryCode: 'CR',
                languageTag: 'es',
                indexedAt: '2026-08-12T16:00:00Z',
              },
            ],
            nextCursor: 'opaque-page-2',
            pageSize: 12,
            hasMore: true,
          }),
        });
        return;
      }

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          items: [
            {
              publicationId: '55555555-5555-4555-8555-555555555555',
              recordingId: '66666666-6666-4666-8666-666666666666',
              workId: '33333333-3333-4333-8333-333333333333',
              canonicalTitle: '怪獣',
              recordingTitle: 'Live version',
              artistId: '44444444-4444-4444-8444-444444444444',
              artistName: 'サカナクション',
              providerCode: 'YOUTUBE',
              externalRef: 'b8dgNdJVluc',
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

    await page.goto('/canciones?consulta=kaijuu');

    await expect(page.getByText('Album version', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Cargar más canciones' }).click();
    await expect(page.getByText('Live version', { exact: true })).toBeVisible();
    await expect(page.getByText('Album version', { exact: true })).toBeVisible();

    expect(cursors).toEqual([null, 'opaque-page-2']);
    await assertNoHorizontalOverflow(page);
  });
});
