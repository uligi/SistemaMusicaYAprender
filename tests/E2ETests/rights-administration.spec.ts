import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '11111111-1111-4111-8111-111111111111';
const rightsRecordId = '22222222-2222-4222-8222-222222222222';
const holderId = '33333333-3333-4333-8333-333333333333';
const evidenceId = '44444444-4444-4444-8444-444444444444';
const scopeId = '55555555-5555-4555-8555-555555555555';

function rightsEntry() {
  return {
    rightsRecordId,
    rightsHolderId: holderId,
    holderType: 'ORGANIZATION',
    holderDisplayName: 'Titular de prueba',
    objectType: 'RECORDING',
    objectId: recordingId,
    basisCode: 'AUTHORIZATION',
    statusCode: 'ACTIVE',
    validFrom: '2026-08-01T00:00:00Z',
    validTo: '2027-08-01T00:00:00Z',
    evidenceObjectId: evidenceId,
    evidenceMediaType: 'application/pdf',
    evidenceSizeBytes: 128,
    evidenceChecksumSha256: 'a'.repeat(64),
    recordedAt: '2026-08-12T00:00:00Z',
    recordedBy: '66666666-6666-4666-8666-666666666666',
    scopes: [
      {
        rightsScopeId: scopeId,
        territoryCode: 'CR',
        languageTag: 'es',
        channelCode: 'WEB',
        useCode: 'DISPLAY',
      },
    ],
  };
}

test.describe('BL-MVP-040 · derechos, usos, territorios y vigencias', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'EDITOR',
          roles: ['EDITOR'],
          capabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],
        }),
      });
    });

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/credits`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([]),
      });
    });

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/rights`, async (route) => {
      if (route.request().method() === 'POST') {
        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            rights: rightsEntry(),
            alreadyApplied: false,
          }),
        });
        return;
      }

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([]),
      });
    });

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/rights/evaluate?**`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            allowed: false,
            code: 'TERRITORY_OR_USE_NOT_AUTHORIZED',
            description:
              'El alcance vigente no autoriza esta combinación. Una preferencia no amplía los derechos.',
            rightsRecordId: null,
            territoryCode: 'JP',
            channelCode: 'WEB',
            useCode: 'DISPLAY',
            languageTag: 'es',
            evaluatedAt: '2026-08-12T00:00:00Z',
          }),
        });
      },
    );

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-test-token',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
  });

  test('registra alcance y evidencia sin convertir territorio ausente en permiso mundial', async ({
    page,
  }) => {
    await page.goto(`/editorial/canciones/${recordingId}/derechos`);

    const guide = page.getByRole('navigation', { name: 'Guía rápida de derechos y procedencia' });
    await expect(guide).toBeVisible();
    await expect(guide.getByRole('button', { name: /Derechos y disponibilidad/ })).toBeVisible();

    await expect(
      page.getByRole('heading', { name: 'Derechos, usos, territorios y vigencias' }),
    ).toBeVisible();
    await expect(page.getByText('Titular y base de autorización')).toBeVisible();
    await expect(page.getByText('Alcance y vigencia')).toBeVisible();
    await expect(page.getByText('Motivo, versión y evidencia')).toBeVisible();

    await page.getByLabel('Titular declarado').fill('Titular de prueba');
    await page.getByLabel('Inicio de vigencia').fill('2026-08-01T00:00');
    await page.getByLabel('Vencimiento').fill('2027-08-01T00:00');
    await page.getByLabel('Territorio autorizado').fill('CR');
    await page.getByLabel('Idioma del alcance').fill('es');
    await page.getByLabel('Motivo de la decisión').fill('Autorización documental revisada');
    await page.getByLabel('Evidencia de derechos').setInputFiles({
      name: 'autorizacion.pdf',
      mimeType: 'application/pdf',
      buffer: Buffer.from('%PDF-1.4 BL040 test evidence'),
    });

    const postPromise = page.waitForRequest(
      (request) =>
        request.method() === 'POST' &&
        request.url().endsWith(`/api/v1/editorial/song-drafts/${recordingId}/rights`),
    );

    await page.getByRole('button', { name: 'Guardar autorización' }).click();
    const request = await postPromise;
    const body = request.postDataJSON();

    expect(body.scopes).toEqual([
      {
        territoryCode: 'CR',
        languageTag: 'es',
        channelCode: 'WEB',
        useCode: 'DISPLAY',
      },
    ]);
    expect(body.evidenceBase64).toBeTruthy();
    await expect(
      page.getByText(
        'Derechos guardados con titular, uso, territorio, vigencia y evidencia privada.',
      ),
    ).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('muestra que una preferencia no amplía el territorio autorizado', async ({ page }) => {
    await page.goto(`/editorial/canciones/${recordingId}/derechos`);

    await page.getByRole('textbox', { name: 'Territorio', exact: true }).fill('JP');
    await page.getByRole('textbox', { name: 'Idioma', exact: true }).fill('es');
    await page.getByRole('button', { name: 'Evaluar alcance' }).click();

    await expect(page.getByText('Uso bloqueado')).toBeVisible();
    await expect(page.getByText('TERRITORY_OR_USE_NOT_AUTHORIZED')).toBeVisible();
  });

  test('a 320px no exige scroll horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto(`/editorial/canciones/${recordingId}/derechos`);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);
  });
});
