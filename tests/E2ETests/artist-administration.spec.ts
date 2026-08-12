import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('BL-MVP-037 · identidad estable de artista', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT', 'EDITOR'],
          capabilities: ['EDITORIAL.DRAFT', 'CATALOG.SEARCH'],
        }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-artist-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
  });

  test('advierte duplicados antes de crear una identidad distinta', async ({ page }) => {
    await page.route('**/api/v1/editorial/artists/duplicates', async (route) => {
      const body = route.request().postDataJSON() as Record<string, unknown>;
      expect(body.canonicalName).toBe('サカナクション');
      expect(body.artistType).toBe('BAND');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-artist-e2e');

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requiresAcknowledgement: true,
          candidates: [
            {
              artistId: '11111111-1111-4111-8111-111111111111',
              canonicalName: 'サカナクション',
              artistType: 'BAND',
              statusCode: 'ACTIVE',
              matchedText: 'sakanaction',
              similarity: 0.98,
            },
          ],
        }),
      });
    });

    await page.route('**/api/v1/editorial/artists', async (route) => {
      expect(route.request().method()).toBe('POST');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-artist-e2e');
      expect(route.request().headers()['idempotency-key']).toBeTruthy();

      const body = route.request().postDataJSON() as {
        acknowledgePotentialDuplicates?: boolean;
        aliases?: Array<{ aliasText?: string }>;
      };

      expect(body.acknowledgePotentialDuplicates).toBe(true);
      expect(body.aliases?.map((alias) => alias.aliasText)).toEqual([
        'さかなくしょん',
        'Sakanaction',
        'Sakanaction ES',
      ]);

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          artistId: '22222222-2222-4222-8222-222222222222',
          canonicalName: 'サカナクション',
          artistType: 'BAND',
          statusCode: 'ACTIVE',
          aliases: body.aliases,
          duplicateWarningAcknowledged: true,
          alreadyApplied: false,
        }),
      });
    });

    await page.goto('/editorial/canciones/nueva');

    await expect(page.getByRole('heading', { level: 1, name: 'Nueva canción' })).toBeVisible();
    await expect(
      page.getByRole('heading', {
        level: 2,
        name: 'Artista canónico para una nueva canción',
      }),
    ).toBeVisible();

    await page.locator('#artist-canonical-name').fill('サカナクション');
    await page.locator('#artist-sort-name').fill('Sakanaction');
    await page.locator('#artist-type').fill('BAND');
    await page.locator('#artist-kana-reading').fill('さかなくしょん');
    await page.locator('#artist-romaji').fill('Sakanaction');
    await page.locator('#artist-spanish-name').fill('Sakanaction ES');

    await page.getByRole('button', { name: 'Revisar duplicados' }).click();

    await expect(
      page.getByRole('heading', {
        name: 'Revisión de posibles duplicados',
      }),
    ).toBeVisible();
    await expect(page.getByText('11111111-1111-4111-8111-111111111111')).toBeVisible();

    const createButton = page.getByRole('button', {
      name: 'Crear identidad de artista',
    });

    await expect(createButton).toBeDisabled();

    await page
      .getByLabel('Revisé estas coincidencias y confirmo que debe crearse una identidad distinta.')
      .check();

    await expect(createButton).toBeEnabled();
    await createButton.click();

    await expect(
      page.getByLabel('Artista confirmado').getByText('22222222-2222-4222-8222-222222222222'),
    ).toBeVisible();
    await expect(
      page.getByText(
        'Identidad de artista creada. El identificador estable, y no el nombre, será la referencia interna.',
      ),
    ).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('busca por alias sin convertir el nombre en identificador', async ({ page }) => {
    await page.route('**/api/v1/editorial/artists?query=*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([
          {
            artistId: '33333333-3333-4333-8333-333333333333',
            canonicalName: '魚の名前',
            artistType: 'PROJECT',
            statusCode: 'ACTIVE',
            matchedText: 'Sakana Name',
            similarity: 0.91,
          },
        ]),
      });
    });

    await page.goto('/editorial/canciones/nueva');

    await page.locator('#artist-search-query').fill('Sakana Name');
    await page.getByRole('button', { name: 'Buscar artista' }).click();

    await expect(page.getByText('魚の名前', { exact: true })).toBeVisible();
    await expect(page.getByText('33333333-3333-4333-8333-333333333333')).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
