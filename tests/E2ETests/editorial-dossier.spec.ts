import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '11111111-1111-4111-8111-111111111111';

const dossier = {
  canonicalTitle: '怪獣',
  recordingTitle: 'Album version',
  artistName: 'サカナクション',
  recordingStatusCode: 'DRAFT',
  providerCode: 'YOUTUBE',
  externalRef: 'a8dgNdJVluc',
  sourceStatusCode: 'DRAFT',
  components: [
    {
      code: 'CATALOG',
      label: 'Catálogo',
      revisionLabel: 'v3',
      stateCode: 'DRAFT',
      ownerLabel: 'Tú',
      exists: true,
      href: null,
    },
    {
      code: 'LYRICS',
      label: 'Letra japonesa',
      revisionLabel: 'r2',
      stateCode: 'DRAFT',
      ownerLabel: 'Tú',
      exists: true,
      href: `/editorial/canciones/${recordingId}/letra`,
    },
    {
      code: 'TIMING',
      label: 'Sincronización',
      revisionLabel: 'Sin revisión',
      stateCode: 'NOT_STARTED',
      ownerLabel: 'Sin responsable identificado',
      exists: false,
      href: `/editorial/canciones/${recordingId}/sincronizacion`,
    },
    {
      code: 'RIGHTS',
      label: 'Derechos y procedencia',
      revisionLabel: '1 registro(s)',
      stateCode: 'ACTIVE',
      ownerLabel: 'Otro responsable',
      exists: true,
      href: `/editorial/canciones/${recordingId}/derechos`,
    },
  ],
  rights: {
    totalRecords: 1,
    activeRecords: 1,
    provenanceRecords: 2,
    ownerLabel: 'Otro responsable',
    stateCode: 'ACTIVE',
  },
  incidents: [
    {
      componentCode: 'LYRICS',
      ruleCode: 'LYRICS.NORMALIZATION',
      severityCode: 'WARNING',
      statusCode: 'OPEN',
      detectedAt: '2026-08-12T20:00:00Z',
    },
  ],
  allowedAccesses: [
    {
      code: 'DOSSIER',
      label: 'Expediente',
      href: `/editorial/canciones/${recordingId}`,
    },
    {
      code: 'RIGHTS',
      label: 'Derechos y procedencia',
      href: `/editorial/canciones/${recordingId}/derechos`,
    },
    {
      code: 'LYRICS',
      label: 'Letra',
      href: `/editorial/canciones/${recordingId}/letra`,
    },
  ],
};

test.describe('BL-MVP-046 · expediente editorial de canción', () => {
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

    await page.route(`**/api/v1/editorial/song-dossiers/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(dossier),
      });
    });
  });

  test('reúne revisiones, propietario, derechos, incidencias y accesos permitidos', async ({
    page,
  }) => {
    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-019"]')).toBeVisible();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Expediente editorial de canción' }),
    ).toBeFocused();

    await expect(page.getByText('怪獣', { exact: true })).toBeVisible();
    await expect(page.getByText('サカナクション', { exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Componentes por revisión' })).toBeVisible();
    await expect(page.getByText('r2', { exact: true })).toBeVisible();
    await expect(page.getByText('Sin revisión', { exact: true })).toBeVisible();
    await expect(page.getByText('Otro responsable', { exact: true }).first()).toBeVisible();

    await expect(
      page.getByRole('heading', { level: 2, name: 'Derechos y procedencia' }),
    ).toBeVisible();
    await expect(page.getByText('LYRICS.NORMALIZATION', { exact: false })).toBeVisible();

    const allowed = page.getByRole('navigation', { name: 'Accesos permitidos del expediente' });
    await expect(allowed.getByRole('link', { name: 'Letra' })).toHaveAttribute(
      'href',
      `/editorial/canciones/${recordingId}/letra`,
    );
    await expect(allowed.getByRole('link', { name: 'Traducción' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('filtra tareas y ofrece volver arriba desde el shell global', async ({ page }) => {
    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(page.getByText('3/4', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Pendientes (1)' }).click();

    await expect(page.getByRole('heading', { level: 3, name: 'Sincronización' })).toBeVisible();
    await expect(page.getByRole('heading', { level: 3, name: 'Letra japonesa' })).toHaveCount(0);

    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    const backToTop = page.getByRole('button', { name: 'Volver al inicio de la página' });
    await expect(backToTop).toBeVisible();
    await backToTop.click();

    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeLessThan(5);
  });

  test('mantiene el expediente a 320px sin desbordamiento horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-019"]')).toBeVisible();
    await expect(page.getByText('LYRICS.NORMALIZATION', { exact: false })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
