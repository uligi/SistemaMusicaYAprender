import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '11111111-1111-4111-8111-111111111111';

const allCapabilities = [
  'EDITORIAL.DRAFT',
  'EDITORIAL.REVIEW',
  'EDITORIAL.SUBMIT',
  'EDITORIAL.PUBLISH',
  'EDITORIAL.CORRECT',
  'SECURITY.MANAGE_ROLES',
  'CONFIG.MANAGE',
  'CONFIG.APPROVE',
  'SECURITY.READ_AUDIT',
];

test.describe('BL-MVP-039/040 · navegación global y opciones de canción', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'ADMIN',
          roles: ['ADMIN', 'EDITOR'],
          capabilities: allCapabilities,
        }),
      });
    });

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          workId: '22222222-2222-4222-8222-222222222222',
          recordingId,
          sourceId: '33333333-3333-4333-8333-333333333333',
          artistId: '44444444-4444-4444-8444-444444444444',
          artistName: 'Artista prueba',
          canonicalTitle: 'Canción prueba',
          languageTag: 'ja',
          recordingTitle: 'Versión estudio',
          recordingDurationMs: 200000,
          providerCode: 'YOUTUBE',
          externalRef: 'a8dgNdJVluc',
          sourceDurationMs: 201000,
          offsetMs: 0,
          workStatusCode: 'DRAFT',
          recordingStatusCode: 'DRAFT',
          sourceStatusCode: 'DRAFT',
        }),
      });
    });
  });

  test('mantiene el sidebar global y mueve las acciones a la canción seleccionada', async ({
    page,
  }) => {
    await page.goto(`/editorial/canciones/${recordingId}`);

    const sidebar = page.getByLabel('Panel lateral del backoffice');
    await expect(sidebar.getByRole('link', { name: 'Nueva canción' })).toBeVisible();
    await expect(sidebar.getByRole('link', { name: 'Expediente' })).toHaveCount(0);
    await expect(sidebar.getByRole('link', { name: 'Derechos y procedencia' })).toHaveCount(0);

    const songNavigation = page.getByRole('navigation', { name: 'Opciones de la canción' });
    await expect(songNavigation).toBeVisible();
    await expect(songNavigation.getByRole('link', { name: 'Expediente' })).toHaveAttribute(
      'href',
      `/editorial/canciones/${recordingId}`,
    );
    await expect(
      songNavigation.getByRole('link', { name: 'Derechos y procedencia' }),
    ).toHaveAttribute('href', `/editorial/canciones/${recordingId}/derechos`);
    await expect(songNavigation.getByRole('link', { name: 'Letra' })).toBeVisible();

    const songLinks = songNavigation.getByRole('link');
    const firstBox = await songLinks.nth(0).boundingBox();
    const secondBox = await songLinks.nth(1).boundingBox();
    expect(firstBox).not.toBeNull();
    expect(secondBox).not.toBeNull();

    if (firstBox && secondBox) {
      const horizontalGap = secondBox.x - (firstBox.x + firstBox.width);
      const verticalGap = secondBox.y - (firstBox.y + firstBox.height);

      expect(horizontalGap > 0 || verticalGap > 0).toBe(true);
    }

    const firstStyles = await songLinks.nth(0).evaluate((element) => {
      const styles = getComputedStyle(element);
      return {
        minHeight: Number.parseFloat(styles.minHeight),
        paddingInlineStart: Number.parseFloat(styles.paddingInlineStart),
      };
    });

    expect(firstStyles.minHeight).toBeGreaterThanOrEqual(40);
    expect(firstStyles.paddingInlineStart).toBeGreaterThan(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('a 320px conserva la navegación de canción sin scroll horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(page.getByRole('navigation', { name: 'Opciones de la canción' })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test('filtra las opciones de canción por capability visible', async ({ page }) => {
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

    await page.goto(`/editorial/canciones/${recordingId}`);
    const songNavigation = page.getByRole('navigation', { name: 'Opciones de la canción' });

    await expect(songNavigation.getByRole('link', { name: 'Expediente' })).toBeVisible();
    await expect(songNavigation.getByRole('link', { name: 'Letra' })).toBeVisible();
    await expect(songNavigation.getByRole('link', { name: 'Ejercicios' })).toBeVisible();
  });
});
