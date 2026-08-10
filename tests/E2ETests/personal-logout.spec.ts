import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator } from '@playwright/test';

async function assertFocusVisible(locator: Locator): Promise<void> {
  await expect(locator).toBeFocused();
  expect(await locator.evaluate((element) => element.matches(':focus-visible'))).toBe(true);
}

test.describe('BL-MVP-027 · cierre de sesión accesible y revocable', () => {
  test('cierra con teclado, CSRF y deja las rutas protegidas sin sesión', async ({ page }) => {
    let authenticated = true;
    const logoutRequests: Array<{ csrf: string }> = [];

    await page.route('**/api/v1/auth/session', async (route) => {
      if (authenticated) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ status: 'AUTHENTICATED', role: 'STUDENT' }),
        });
        return;
      }

      await route.fulfill({
        status: 401,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          status: 401,
          title: 'Sesión requerida',
          code: 'identity.session.required',
        }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-logout-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/auth/logout', async (route) => {
      logoutRequests.push({
        csrf: route.request().headers()['x-csrf-token'] ?? '',
      });
      authenticated = false;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'SIGNED_OUT',
          message: 'La sesión actual se cerró de forma segura.',
        }),
      });
    });

    await page.goto('/acceso');

    await expect(page.getByRole('heading', { level: 1, name: 'Inicia sesión' })).toBeFocused();
    const logoutButton = page.getByRole('button', { name: 'Cerrar sesión', exact: true });
    await expect(logoutButton).toBeVisible();

    await page.keyboard.press('Tab');
    await assertFocusVisible(logoutButton);
    await page.keyboard.press('Enter');

    await expect(page.getByText('Sesión cerrada')).toBeVisible();
    await expect(page.getByText('La sesión actual se cerró de forma segura.')).toBeVisible();
    await expect(logoutButton).toHaveCount(0);
    expect(logoutRequests).toEqual([{ csrf: 'csrf-logout-e2e' }]);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);

    expect(
      await page.evaluate(() => ({
        local: Object.keys(localStorage),
        session: Object.keys(sessionStorage),
      })),
    ).toEqual({ local: [], session: [] });

    await page.goto('/preferencias');
    await expect(page.locator('[data-state="UI-EST-07"]')).toBeVisible();
    await expect(page.getByText('Necesitas iniciar sesión')).toBeVisible();
  });
});
