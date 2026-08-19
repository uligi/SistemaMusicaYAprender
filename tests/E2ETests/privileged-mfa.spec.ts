import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('BL-MVP-032 · MFA y reautenticación privilegiada', () => {
  test('inscribe TOTP y confirma step-up antes de mostrar la gestión de roles', async ({
    page,
  }) => {
    let enrolled = false;
    let recent = false;

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

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-mfa-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/security/mfa/status', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          enrolled,
          recentAssurance: recent,
          methodType: enrolled ? 'TOTP' : null,
          assuranceExpiresAt: recent ? '2099-08-11T15:00:00Z' : null,
        }),
      });
    });

    await page.route('**/api/v1/security/mfa/enrollment/start', async (route) => {
      const body = route.request().postDataJSON() as {
        currentPassword: string;
      };
      expect(body.currentPassword).toBe('frase-de-paso-correcta');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-mfa-e2e');

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          challengeId: '11111111-1111-4111-8111-111111111111',
          secret: 'JBSWY3DPEHPK3PXP',
          otpAuthUri: 'otpauth://totp/test',
          expiresAt: '2099-08-11T14:50:00Z',
        }),
      });
    });

    await page.route('**/api/v1/security/mfa/enrollment/confirm', async (route) => {
      const body = route.request().postDataJSON() as {
        challengeId: string;
        secret: string;
        code: string;
      };
      expect(body.challengeId).toBe('11111111-1111-4111-8111-111111111111');
      expect(body.secret).toBe('JBSWY3DPEHPK3PXP');
      expect(body.code).toBe('123456');

      enrolled = true;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          enrolled: true,
          recentAssurance: false,
          methodType: 'TOTP',
          assuranceExpiresAt: null,
        }),
      });
    });

    await page.route('**/api/v1/security/mfa/step-up/start', async (route) => {
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-mfa-e2e');

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          challengeId: '22222222-2222-4222-8222-222222222222',
          expiresAt: '2099-08-11T14:55:00Z',
          maximumAttempts: 5,
        }),
      });
    });

    await page.route('**/api/v1/security/mfa/step-up/confirm', async (route) => {
      const body = route.request().postDataJSON() as {
        challengeId: string;
        code: string;
      };
      expect(body.challengeId).toBe('22222222-2222-4222-8222-222222222222');
      expect(body.code).toBe('654321');

      recent = true;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          enrolled: true,
          recentAssurance: true,
          methodType: 'TOTP',
          assuranceExpiresAt: '2099-08-11T15:00:00Z',
        }),
      });
    });

    await page.route('**/api/v1/security/role-assignments/catalog', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          roles: ['ADMIN', 'EDITOR', 'REVIEWER', 'STUDENT'],
          scopes: [],
        }),
      });
    });

    await page.goto('/administracion/roles');

    await expect(page.getByRole('heading', { name: 'Verificación reforzada' })).toBeVisible();
    await expect(page.getByLabel('Buscar cuenta por nombre de usuario')).toHaveCount(0);

    await page.getByLabel('Contraseña actual').fill('frase-de-paso-correcta');
    await page.getByRole('button', { name: 'Preparar segundo factor' }).click();

    await expect(page.getByText('JBSWY3DPEHPK3PXP')).toBeVisible();
    await page.getByLabel('Código de confirmación').fill('123456');
    await page.getByRole('button', { name: 'Confirmar segundo factor' }).click();

    await page.getByRole('button', { name: 'Verificar con autenticador' }).click();
    await page.getByLabel('Código del autenticador').fill('654321');
    await page.getByRole('button', { name: 'Confirmar verificación reforzada' }).click();

    await expect(page.getByText(/Verificación vigente/)).toBeVisible();
    await expect(page.getByLabel('Buscar cuenta por nombre de usuario')).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
