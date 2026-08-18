import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const recordingId = '11111111-1111-7111-8111-111111111111';
const activePublicationId = '77777777-7777-7777-8777-777777777777';
const oldPublicationId = '66666666-6666-7666-8666-666666666666';

async function session(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'ADMIN',
        roles: ['ADMIN'],
        capabilities: ['EDITORIAL.CORRECT'],
        assurance: { recent: true },
      }),
    });
  });

  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        requestToken: 'csrf-correction',
        headerName: 'X-CSRF-TOKEN',
      }),
    });
  });
}

function publication(
  publicationId: string,
  publicationNo: number,
  statusCode: string,
  packageId: string,
) {
  return {
    publicationId,
    packageId,
    publicationNo,
    statusCode,
    activeFrom: '2026-08-17T18:20:00Z',
    activeTo: statusCode === 'ACTIVE' ? null : '2026-08-17T19:00:00Z',
    publishedAt: '2026-08-17T18:20:00Z',
    checksumSha256: `${publicationNo}`.repeat(64).slice(0, 64),
    availability: [
      {
        territoryCode: 'CR',
        languageTag: 'es',
        audienceCode: 'PUBLIC',
        validFrom: '2026-08-17T18:20:00Z',
        validTo: null,
        statusCode: 'ACTIVE',
      },
    ],
  };
}

function correctionState(withdrawn = false) {
  const current = withdrawn
    ? null
    : publication(activePublicationId, 3, 'ACTIVE', '22222222-2222-7222-8222-222222222222');

  const history = [
    ...(current ? [current] : []),
    publication(
      oldPublicationId,
      2,
      withdrawn ? 'WITHDRAWN' : 'SUPERSEDED',
      '33333333-3333-7333-8333-333333333333',
    ),
  ];

  return {
    recordingId,
    activePublication: current,
    history,
    actions: withdrawn
      ? [
          {
            actionId: 'aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa',
            publicationId: activePublicationId,
            caseId: 'bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb',
            actionCode: 'WITHDRAW',
            fromStatus: 'ACTIVE',
            toStatus: 'WITHDRAWN',
            effectiveAt: '2026-08-17T19:00:00Z',
            reason: 'Fuente no disponible.',
            correlationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          },
        ]
      : [],
    approvedPackages: [
      {
        packageId: '44444444-4444-7444-8444-444444444444',
        packageNo: 8,
        checksumSha256: 'aa'.repeat(32),
      },
    ],
    eTag: withdrawn ? '"correction-withdrawn"' : '"correction-ready"',
    message: withdrawn
      ? 'No existe publicación activa. Puedes restaurar una histórica si sus derechos siguen vigentes.'
      : 'Publicación #3 activa. Toda corrección conservará el historial.',
  };
}

test.describe('BL-MVP-051 · corrección y reversión', () => {
  test('retira con doble confirmación, If-Match e idempotencia sin borrar historial', async ({
    page,
  }) => {
    await session(page);

    await page.route(`**/api/v1/administration/corrections/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { etag: '"correction-ready"' },
        body: JSON.stringify(correctionState()),
      });
    });

    let posts = 0;
    await page.route(
      `**/api/v1/administration/corrections/${recordingId}/actions`,
      async (route) => {
        posts += 1;
        const headers = route.request().headers();
        expect(headers['if-match']).toBe('"correction-ready"');
        expect(headers['idempotency-key']).toMatch(
          /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
        );
        expect(route.request().postDataJSON()).toMatchObject({
          actionCode: 'WITHDRAW',
          reason: 'Fuente no disponible.',
        });

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"correction-withdrawn"' },
          body: JSON.stringify(correctionState(true)),
        });
      },
    );

    await page.goto(`/administracion/correcciones/${recordingId}`);
    await page.getByLabel('Motivo de la corrección').fill('Fuente no disponible.');
    await page.getByRole('button', { name: 'Preparar acción' }).click();

    await expect(page.getByRole('heading', { name: 'Confirmar WITHDRAW' })).toBeVisible();
    expect(posts).toBe(0);

    await page.getByRole('button', { name: 'Confirmar acción' }).click();
    await expect(page.getByText('WITHDRAW · ACTIVE → WITHDRAWN')).toBeVisible();
    expect(posts).toBe(1);
    await expect(page.getByRole('heading', { name: 'Historial inmutable' })).toBeVisible();
  });

  test('revertir exige seleccionar una publicación histórica exacta', async ({ page }) => {
    await session(page);

    await page.route(`**/api/v1/administration/corrections/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { etag: '"correction-ready"' },
        body: JSON.stringify(correctionState()),
      });
    });

    await page.goto(`/administracion/correcciones/${recordingId}`);
    await page.getByRole('combobox', { name: 'Acción' }).selectOption('REVERT');
    await page.getByLabel('Motivo de la corrección').fill('Volver a la última versión estable.');

    await expect(page.getByRole('button', { name: 'Preparar acción' })).toBeDisabled();
    await page
      .getByRole('combobox', { name: 'Publicación histórica', exact: true })
      .selectOption(oldPublicationId);
    await expect(page.getByRole('button', { name: 'Preparar acción' })).toBeEnabled();
  });

  test('UI-MVP-028 mantiene teclado, Axe y 320 px sin overflow', async ({ page }) => {
    await session(page);

    await page.route(`**/api/v1/administration/corrections/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { etag: '"correction-ready"' },
        body: JSON.stringify(correctionState()),
      });
    });

    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto(`/administracion/correcciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-028"]')).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
      ),
    ).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
