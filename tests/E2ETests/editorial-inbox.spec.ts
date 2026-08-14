import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '11111111-1111-4111-8111-111111111111';

test.describe('BL-MVP-044 · bandeja editorial por capacidades', () => {
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

  test('muestra solo objetos y acciones devueltos como permitidos por servidor', async ({
    page,
  }) => {
    await page.route('**/api/v1/editorial/inbox', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          candidateCount: 3,
          visibleCount: 1,
          items: [
            {
              recordingId,
              canonicalTitle: '怪獣',
              recordingTitle: 'Versión estudio',
              artistName: 'サカナクション',
              stateCode: 'RECORDING:DRAFT',
              ownerLabel: 'Tú',
              lock: {
                active: true,
                operationCode: 'EDIT_METADATA',
                expiresAt: '2026-08-12T20:30:00Z',
              },
              provenanceLabel: 'Procedencia registrada',
              providerCode: 'YOUTUBE',
              lastActivityAt: '2026-08-12T20:00:00Z',
              nextAction: 'Continuar preparando el expediente editorial.',
              actions: [
                {
                  code: 'OPEN_DRAFT',
                  label: 'Abrir expediente',
                  href: `/editorial/canciones/${recordingId}`,
                },
              ],
            },
          ],
        }),
      });
    });

    await page.goto('/editorial');

    await expect(page.locator('[data-route-id="UI-MVP-017"]')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1, name: 'Bandeja editorial' })).toBeFocused();
    await expect(page.getByText('怪獣', { exact: true })).toBeVisible();
    await expect(page.getByText('サカナクション', { exact: true })).toBeVisible();
    await expect(page.getByText('Borrador', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'En edición (1)' })).toBeVisible();
    await page.getByText('Ver datos editoriales', { exact: true }).click();
    await expect(page.getByText('Tú', { exact: true })).toBeVisible();
    await expect(page.getByText(/EDIT_METADATA/)).toBeVisible();
    await expect(
      page.getByLabel('Situación editorial').getByText('Procedencia registrada', { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText('Continuar preparando el expediente editorial.', { exact: true }),
    ).toBeVisible();

    const openDraft = page.getByRole('link', { name: 'Abrir expediente' });
    await expect(openDraft).toHaveAttribute('href', `/editorial/canciones/${recordingId}`);
    await expect(page.getByRole('link', { name: 'Publicar' })).toHaveCount(0);
    await expect(page.getByRole('link', { name: 'Corregir publicación' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('mantiene bandeja vacía segura y sin scroll horizontal a 320px', async ({ page }) => {
    await page.route('**/api/v1/editorial/inbox', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          candidateCount: 4,
          visibleCount: 0,
          items: [],
        }),
      });
    });

    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto('/editorial');

    await expect(
      page.getByText('No tienes tareas editoriales pendientes', { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText('No hay canciones disponibles para tu sesión en este momento.', {
        exact: true,
      }),
    ).toBeVisible();

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
