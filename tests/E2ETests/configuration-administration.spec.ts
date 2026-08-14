import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('BL-MVP-036 · administración versionada de configuración', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT'],
          capabilities: ['CONFIG.MANAGE', 'CONFIG.APPROVE'],
        }),
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
          assuranceExpiresAt: '2099-08-11T23:00:00Z',
        }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-configuration-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/administration/configuration', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          parameters: [
            {
              parameterKey: 'SEARCH_MIN_QUERY_LENGTH',
              ownerModule: 'M02',
              valueType: 'INTEGER',
              validationSchemaJson: '{}',
              parameterVersionId: '11111111-1111-4111-8111-111111111111',
              currentVersionNo: 1,
              scopeCode: 'GLOBAL',
              scopeValue: null,
              currentValueJson: '2',
              validFrom: '2026-01-01T00:00:00Z',
              validTo: null,
              projectionVersion: 1,
            },
          ],
          catalogs: [
            {
              catalogCode: 'LANGUAGE',
              ownerModule: 'M19',
              valueSchemaJson: '{"type":"string"}',
              definitionVersion: 1,
              entries: [
                {
                  catalogEntryId: '22222222-2222-4222-8222-222222222222',
                  entryCode: 'ES',
                  labelsJson: '{"es":"Es"}',
                  valueJson: '"ES"',
                  validFrom: '2026-01-01T00:00:00Z',
                  validTo: null,
                  version: 1,
                },
              ],
            },
          ],
        }),
      });
    });
  });

  test('simula y activa un parámetro con impacto, vigencia y motivo', async ({ page }) => {
    await page.route(
      '**/api/v1/administration/configuration/parameters/simulate',
      async (route) => {
        const body = route.request().postDataJSON() as Record<string, unknown>;
        expect(body.parameterKey).toBe('SEARCH_MIN_QUERY_LENGTH');
        expect(body.typedValueJson).toBe('3');
        expect(body.reason).toBe('Ajuste operativo controlado');
        expect(body.impact).toBe('Afecta búsqueda; reversible a la versión anterior.');
        expect(body.expectedVersionNo).toBe(1);
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-configuration-e2e');

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            objectType: 'PARAMETER',
            objectKey: 'SEARCH_MIN_QUERY_LENGTH@GLOBAL',
            ownerModule: 'M02',
            canActivate: true,
            checks: [],
            beforeJson: '2',
            afterJson: '3',
            expectedVersion: 1,
            currentValidUntil: null,
            proposedValidUntil: '2099-08-11T23:00:00Z',
            historicalValueWillBePreserved: true,
          }),
        });
      },
    );

    await page.route(
      '**/api/v1/administration/configuration/parameters/activate',
      async (route) => {
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-configuration-e2e');
        expect(route.request().headers()['idempotency-key']).toBeTruthy();

        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            objectType: 'PARAMETER',
            objectKey: 'SEARCH_MIN_QUERY_LENGTH@GLOBAL',
            ownerModule: 'M02',
            activeObjectId: '33333333-3333-4333-8333-333333333333',
            activeVersion: 2,
            effectiveFrom: '2026-08-11T22:30:00Z',
            effectiveUntil: '2099-08-11T23:00:00Z',
            previousObjectId: '11111111-1111-4111-8111-111111111111',
            changeSetId: '44444444-4444-4444-8444-444444444444',
            activationId: '55555555-5555-4555-8555-555555555555',
            historicalValuePreserved: true,
            alreadyApplied: false,
          }),
        });
      },
    );

    await page.goto('/administracion/configuracion');

    await expect(
      page.getByRole('heading', { level: 1, name: 'Catálogos y parámetros' }),
    ).toBeVisible();

    await page.locator('#parameter-value').fill('3');
    await page.locator('#parameter-valid-until').fill('2099-08-11T17:00');
    await page.locator('#parameter-reason').fill('Ajuste operativo controlado');
    await page
      .locator('#parameter-impact')
      .fill('Afecta búsqueda; reversible a la versión anterior.');

    await page.getByRole('button', { name: 'Simular cambio de parámetro' }).click();

    const simulation = page.getByLabel('Simulación SEARCH_MIN_QUERY_LENGTH@GLOBAL');
    await expect(simulation.getByRole('heading', { name: 'Simulación válida' })).toBeVisible();
    await expect(simulation.getByText('2', { exact: true })).toBeVisible();
    await expect(simulation.getByText('3', { exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Activar parámetro' }).click();
    await expect(
      page.getByText(
        'Parámetro activado como versión 2. La versión anterior permanece en el historial.',
      ),
    ).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('simula una entrada de catálogo con historial explícito', async ({ page }) => {
    await page.route('**/api/v1/administration/configuration/catalogs/simulate', async (route) => {
      const body = route.request().postDataJSON() as Record<string, unknown>;
      expect(body.catalogCode).toBe('LANGUAGE');
      expect(body.entryCode).toBe('ES');
      expect(body.labelsJson).toBe('{"es":"Español"}');
      expect(body.valueJson).toBe('"ES"');
      expect(body.expectedEntryId).toBe('22222222-2222-4222-8222-222222222222');

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          objectType: 'CATALOG_ENTRY',
          objectKey: 'LANGUAGE/ES',
          ownerModule: 'M19',
          canActivate: true,
          checks: [],
          beforeJson: '{"labels":{"es":"Es"},"value":"ES"}',
          afterJson: '{"labels":{"es":"Español"},"value":"ES"}',
          expectedVersion: 1,
          currentValidUntil: null,
          proposedValidUntil: null,
          historicalValueWillBePreserved: true,
        }),
      });
    });

    await page.goto('/administracion/configuracion');

    await page.getByLabel('Nombre visible en español').fill('Español');
    await page.getByLabel('Motivo del catálogo').fill('Localización visible');
    await page
      .getByLabel('Impacto y dependencias del catálogo')
      .fill('Solo presentación; código estable y consumidores compatibles.');

    await page.getByRole('button', { name: 'Simular cambio de catálogo' }).click();

    await expect(
      page.getByLabel('Simulación LANGUAGE/ES').getByRole('heading', {
        name: 'Simulación válida',
      }),
    ).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
