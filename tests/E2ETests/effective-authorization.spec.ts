import { expect, test } from '@playwright/test';

test.describe('BL-MVP-030 · permisos efectivos visibles sin sustituir autorización', () => {
  test('habilita la ruta administrativa solo con la capacidad publicada por sesión', async ({
    page,
  }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT', 'ADMIN'],
          capabilities: ['SECURITY.MANAGE_ROLES'],
        }),
      });
    });

    await page.goto('/administracion/roles');

    await expect(page.getByText('Acceso no concedido')).toHaveCount(0);
    await expect(page.getByText('Roles y permisos')).toBeVisible();
  });

  test('oculta la ruta cuando la sesión visible no publica la capacidad', async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT'],
          capabilities: ['PROFILE.READ'],
        }),
      });
    });

    await page.goto('/administracion/roles');

    await expect(page.getByText('Acceso no concedido')).toBeVisible();
    await expect(
      page.getByText(
        'Tu sesión visible no contiene la capacidad necesaria. El servidor vuelve a autorizar cada operación protegida.',
      ),
    ).toBeVisible();
  });
});
