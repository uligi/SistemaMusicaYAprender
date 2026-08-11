import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('BL-MVP-029 · limitación no enumerativa de acceso', () => {
  test('presenta una espera recuperable ante HTTP 429 sin exponer la dimensión limitada', async ({
    page,
  }) => {
    let loginRequests = 0;

    await page.route('**/api/v1/auth/session', async (route) => {
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
          requestToken: 'csrf-bl029-browser',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/auth/login', async (route) => {
      loginRequests += 1;
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl029-browser');

      await route.fulfill({
        status: 429,
        headers: { 'Retry-After': '60' },
        contentType: 'application/problem+json',
        body: JSON.stringify({
          status: 429,
          title: 'Demasiados intentos',
          detail: 'Espera antes de volver a intentarlo.',
          code: 'identity.login.rate-limited',
        }),
      });
    });

    await page.goto('/acceso');
    await page.getByLabel('Correo electrónico').fill('student@example.test');
    await page.getByLabel('Contraseña').fill('Credencial segura 日本語 2026');
    await page.getByRole('button', { name: 'Iniciar sesión' }).click();

    const waitState = page.locator('[data-state="UI-EST-06"]');
    await expect(waitState).toBeVisible();
    await expect(waitState).toContainText('La solicitud debe esperar');
    await expect(waitState).toContainText('Espera un momento antes de volver a intentarlo.');
    await expect(waitState).not.toContainText(/cuenta|dirección IP|correo existe/i);
    expect(loginRequests).toBe(1);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
