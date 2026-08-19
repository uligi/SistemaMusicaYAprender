import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('FIX-MVP-USERNAME-DIRECTORY-001', () => {
  test('registro envía username normalizado', async ({ page }) => {
    await page.route('**/api/v1/auth/registration-consents', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          notices: [
            {
              purposeCode: 'TERMS_OF_USE',
              title: 'Términos de uso',
              noticeVersion: '1',
              effectiveFromUtc: '2026-01-01T00:00:00Z',
              required: true,
            },
            {
              purposeCode: 'PRIVACY_POLICY',
              title: 'Política de privacidad',
              noticeVersion: '1',
              effectiveFromUtc: '2026-01-01T00:00:00Z',
              required: true,
            },
          ],
        }),
      });
    });

    await page.route('**/api/v1/auth/register', async (route) => {
      const body = route.request().postDataJSON() as {
        username: string;
        email: string;
      };
      expect(body.username).toBe('reviewer01');
      expect(body.email).toBe('reviewer01@example.test');

      await route.fulfill({
        status: 202,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'RECEIVED',
          message: 'Solicitud recibida.',
        }),
      });
    });

    await page.goto('/registro');
    await page.getByLabel('Nombre de usuario').fill('Reviewer01');
    await page.getByLabel('Correo electrónico').fill('reviewer01@example.test');
    await page.getByLabel('Contraseña').fill('Brisa japonesa segura 2026');
    for (const checkbox of await page.getByRole('checkbox').all()) {
      await checkbox.check();
    }

    await page.getByRole('button', { name: 'Continuar registro' }).click();
    await expect(page.getByText('Solicitud recibida.')).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('cuenta existente puede fijar username una vez', async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT'],
          capabilities: ['PROFILE.READ', 'PROFILE.WRITE'],
        }),
      });
    });

    await page.route('**/api/v1/profile/username', async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ username: null, canClaim: true }),
        });
        return;
      }

      const body = route.request().postDataJSON() as { username: string };
      expect(body.username).toBe('sakura_user');
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ username: 'sakura_user', canClaim: false }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-username-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/preferences', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          preferenceSetId: '11111111-1111-4111-8111-111111111111',
          version: 1,
          revisionNo: 1,
          updatedAt: '2026-08-17T00:00:00Z',
          profile: {
            displayName: null,
            uiLanguage: 'es-CR',
            timeZone: 'America/Costa_Rica',
            version: 1,
          },
          values: {
            interfaceLanguage: 'ES',
            translationLanguage: 'ES',
            japanese: {
              showKanji: true,
              showKana: true,
              furiganaMode: 'AUTO',
              romajiMode: 'HELP',
              showNaturalTranslation: true,
            },
            accessibility: {
              fontScalePercent: 100,
              highContrast: false,
              reducedMotion: false,
              flashProtection: true,
            },
            privacy: { activityVisibility: 'PRIVATE' },
            provenance: { contractVersion: 1, languageCatalogVersion: 1 },
          },
          options: {
            languages: [{ code: 'ES', label: 'Español', version: 1 }],
            furiganaModes: ['ALWAYS', 'AUTO', 'HIDDEN'],
            romajiModes: ['ALWAYS', 'HELP', 'HIDDEN'],
            fontScalePercents: [100],
            privacyVisibilities: ['PRIVATE'],
          },
        }),
      });
    });

    await page.goto('/preferencias');
    await page.getByLabel('Elige tu nombre de usuario').fill('Sakura_User');
    await page.getByRole('button', { name: 'Fijar nombre de usuario' }).click();

    await expect(page.getByText('@sakura_user')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Fijar nombre de usuario' })).toHaveCount(0);
  });
});
