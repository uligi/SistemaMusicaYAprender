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

test.describe('BL-MVP-039 · menú lateral editorial y administración', () => {
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

    await page.route('**/api/v1/administration/configuration', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ parameters: [], catalogs: [] }),
      });
    });

    await page.route('**/api/v1/security/mfa/status', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          enrolled: true,
          recentAssurance: true,
          methodType: 'TOTP',
          assuranceExpiresAt: '2099-08-12T00:00:00Z',
        }),
      });
    });
  });

  test('muestra grupos reales y enlaces contextuales sin IDs de ejemplo', async ({ page }) => {
    await page.goto(`/editorial/canciones/${recordingId}`);

    const sidebar = page.getByLabel('Panel lateral del backoffice');
    await expect(sidebar.getByRole('heading', { name: 'Editorial' })).toBeVisible();
    await expect(sidebar.getByRole('heading', { name: 'Administración' })).toBeVisible();
    await expect(sidebar.getByRole('link', { name: 'Nueva canción' })).toHaveAttribute(
      'href',
      '/editorial/canciones/nueva',
    );
    await expect(sidebar.getByRole('link', { name: 'Créditos y procedencia' })).toHaveAttribute(
      'href',
      `/editorial/canciones/${recordingId}/derechos`,
    );
    await expect(sidebar.getByRole('link', { name: 'Roles y accesos' })).toHaveAttribute(
      'href',
      '/administracion/roles',
    );
    await expect(sidebar.locator('a[href*="ejemplo"]')).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('a 320px conserva el menú lateral sin scroll horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto('/administracion/configuracion');

    await expect(page.getByLabel('Panel lateral del backoffice')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test('oculta funciones para las que no existe capability visible', async ({ page }) => {
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
    const sidebar = page.getByLabel('Panel lateral del backoffice');

    await expect(sidebar.getByRole('heading', { name: 'Editorial' })).toBeVisible();
    await expect(sidebar.getByRole('heading', { name: 'Administración' })).toHaveCount(0);
    await expect(sidebar.getByRole('link', { name: 'Nueva canción' })).toBeVisible();
  });
});
