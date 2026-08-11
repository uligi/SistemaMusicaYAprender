import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('BL-MVP-034 · perfil básico y preferencias iniciales', () => {
  test('carga, confirma y conserva preferencias privadas con teclado', async ({ page }) => {
    const pageErrors: Error[] = [];
    page.on('pageerror', (error) => pageErrors.push(error));

    let version = 1;
    let revisionNo = 1;
    let values = {
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
        reducedMotion: true,
        flashProtection: true,
      },
      privacy: {
        activityVisibility: 'PRIVATE',
      },
      provenance: {
        contractVersion: 1,
        languageCatalogVersion: 1,
      },
    };

    const response = () => ({
      preferenceSetId: '33333333-3333-4333-8333-333333333333',
      version,
      revisionNo,
      values,
      updatedAt: '2026-08-11T18:30:00Z',
      profile: {
        displayName: null,
        uiLanguage: 'es-CR',
        timeZone: 'America/Costa_Rica',
        version: 1,
      },
      options: {
        languages: [{ code: 'ES', label: 'Español', version: 1 }],
        furiganaModes: ['ALWAYS', 'AUTO', 'HIDDEN'],
        romajiModes: ['ALWAYS', 'HELP', 'HIDDEN'],
        fontScalePercents: [100, 125, 150, 175, 200],
        privacyVisibilities: ['PRIVATE'],
      },
    });

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

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-preferences-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/preferences', async (route) => {
      if (route.request().method() === 'PUT') {
        const body = route.request().postDataJSON() as {
          version: number;
          japanese: typeof values.japanese;
          accessibility: typeof values.accessibility;
          privacy: typeof values.privacy;
          interfaceLanguage: string;
          translationLanguage: string;
        };

        expect(route.request().headers()['x-csrf-token']).toBe('csrf-preferences-e2e');
        expect(body.version).toBe(version);
        expect(body.interfaceLanguage).toBe('ES');
        expect(body.translationLanguage).toBe('ES');
        expect(body.privacy.activityVisibility).toBe('PRIVATE');

        version += 1;
        revisionNo += 1;
        values = {
          ...values,
          japanese: { ...body.japanese },
          accessibility: { ...body.accessibility },
          privacy: { ...body.privacy },
        };

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(response()),
        });
        return;
      }

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(response()),
      });
    });

    await page.goto('/preferencias');

    await expect(page.getByRole('heading', { level: 1, name: 'Preferencias' })).toBeVisible();
    await expect(page.getByText('America/Costa_Rica')).toBeVisible();
    await expect(page.getByLabel('Reducir movimiento')).toBeChecked();
    await expect(page.getByLabel('Protección contra destellos')).toBeChecked();
    await expect(page.getByLabel('Actividad educativa')).toHaveValue('PRIVATE');

    await page.getByLabel('Furigana').selectOption('ALWAYS');
    expect(pageErrors).toEqual([]);
    await page.getByLabel('Romaji').selectOption('HIDDEN');
    await page.getByLabel('Escala de lectura').selectOption('150');
    await page.getByLabel('Contraste reforzado').check();

    await page.getByRole('button', { name: 'Confirmar preferencias' }).click();

    await expect(page.getByText('Revisión 2 confirmada.')).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('data-user-motion', 'reduced');
    await expect(page.locator('html')).toHaveAttribute('data-user-contrast', 'high');

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
    expect(pageErrors).toEqual([]);
  });
});
