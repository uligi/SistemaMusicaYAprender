import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const recordingId = '11111111-1111-7111-8111-111111111111';
const lyricsId = '22222222-2222-7222-8222-222222222222';
const timingId = '33333333-3333-7333-8333-333333333333';
const translationId = '44444444-4444-7444-8444-444444444444';
const analysisId = '55555555-5555-7555-8555-555555555555';
const exerciseId = '66666666-6666-7666-8666-666666666666';
const brokenExerciseId = '77777777-7777-7777-8777-777777777777';

async function mockSession(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'EDITOR',
        roles: ['EDITOR', 'REVIEWER'],
        capabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.SUBMIT', 'EDITORIAL.REVIEW'],
      }),
    });
  });
}

async function mockCsrf(page: Page) {
  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        requestToken: 'csrf-bl047-079',
        headerName: 'x-csrf-token',
      }),
    });
  });
}

function candidate(
  componentKind: string,
  revisionId: string,
  sourceLyricsRevisionId: string,
  label: string,
  options: Partial<Record<string, unknown>> = {},
) {
  return {
    componentKind,
    revisionId,
    revisionNo: 1,
    statusCode: 'DRAFT',
    checksumSha256: 'ab'.repeat(32),
    sourceLyricsRevisionId,
    label,
    preview: null,
    eligible: true,
    issues: [],
    ...options,
  };
}

function emptySnapshot() {
  return {
    recordingId,
    catalogVersion: 7,
    packageId: null,
    packageNo: null,
    statusCode: 'NOT_CREATED',
    version: 0,
    checksumSha256: null,
    eTag: `"package-${recordingId.replaceAll('-', '')}-none"`,
    selection: {
      lyricsRevisionId: null,
      timingRevisionId: null,
      translationRevisionId: null,
      analysisRevisionId: null,
      exerciseRevisionIds: [],
    },
    candidates: [
      candidate('LYRICS', lyricsId, lyricsId, 'Letra · revisión 1'),
      candidate('TIMING', timingId, lyricsId, 'Sincronización · revisión 1'),
      candidate('TRANSLATION', translationId, lyricsId, 'Traducción es · revisión 1'),
      candidate('ANALYSIS', analysisId, lyricsId, 'Análisis · revisión 1'),
      candidate('EXERCISE', exerciseId, lyricsId, 'Ejercicio · revisión 1', {
        preview: '何度でも — Completa el espacio con la opción correcta.',
      }),
      candidate(
        'EXERCISE',
        brokenExerciseId,
        '99999999-9999-7999-8999-999999999999',
        'Ejercicio · revisión 2',
        {
          preview: 'Fuente vieja',
          eligible: false,
          issues: ['La opción correcta no conserva un token fuente válido de la línea exacta.'],
        },
      ),
    ],
    checklist: {
      hasLyrics: false,
      hasTiming: false,
      hasTranslation: false,
      hasAnalysis: false,
      hasExercise: false,
      sourcesCompatible: false,
      exercisesEligible: false,
      hasActiveRights: true,
      hasBrokenLinks: false,
      packageChecksumCurrent: true,
      readyForFreeze: false,
      issues: ['Selecciona revisiones exactas.'],
    },
    message: 'Selecciona revisiones exactas. Nada se publica al guardar este DRAFT.',
  };
}

function savedSnapshot() {
  return {
    ...emptySnapshot(),
    packageId: '88888888-8888-7888-8888-888888888888',
    packageNo: 1,
    statusCode: 'DRAFT',
    version: 1,
    checksumSha256: 'cd'.repeat(32),
    eTag: '"package-v1"',
    selection: {
      lyricsRevisionId: lyricsId,
      timingRevisionId: timingId,
      translationRevisionId: translationId,
      analysisRevisionId: analysisId,
      exerciseRevisionIds: [exerciseId],
    },
    checklist: {
      hasLyrics: true,
      hasTiming: true,
      hasTranslation: true,
      hasAnalysis: true,
      hasExercise: true,
      sourcesCompatible: true,
      exercisesEligible: true,
      hasActiveRights: true,
      hasBrokenLinks: false,
      packageChecksumCurrent: true,
      readyForFreeze: true,
      issues: [],
    },
    message: 'Paquete compatible guardado. BL-MVP-048 será quien lo congele y someta a revisión.',
  };
}

test.describe('BL-MVP-047/079 · paquete compatible y ejercicios publicables', () => {
  test.beforeEach(async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
  });

  test('BL047 guarda revisiones exactas con If-Match y checksum sin publicar', async ({ page }) => {
    let writes = 0;
    let payload: Record<string, unknown> | null = null;

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        if (route.request().method() === 'GET') {
          await route.fulfill({
            status: 200,
            headers: { etag: emptySnapshot().eTag },
            contentType: 'application/json',
            body: JSON.stringify(emptySnapshot()),
          });
          return;
        }

        writes += 1;
        expect(route.request().headers()['if-match']).toBe(emptySnapshot().eTag);
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl047-079');
        payload = route.request().postDataJSON() as Record<string, unknown>;

        await route.fulfill({
          status: 200,
          headers: { etag: '"package-v1"' },
          contentType: 'application/json',
          body: JSON.stringify(savedSnapshot()),
        });
      },
    );

    await page.goto(`/editorial/paquetes/${recordingId}`);
    await page.getByLabel('Letra exacta').selectOption(lyricsId);
    await page.getByLabel('Sincronización').selectOption(timingId);
    await page.getByLabel('Traducción').selectOption(translationId);
    await page.getByLabel('Análisis').selectOption(analysisId);
    await page.getByRole('checkbox', { name: /Ejercicio · revisión 1/ }).check();
    await page.getByLabel('Motivo trazable').fill('Revisiones exactas compatibles.');
    await page.getByRole('button', { name: 'Guardar paquete compatible' }).click();

    await expect(page.getByRole('heading', { name: 'Compatible para congelar' })).toBeVisible();
    await expect(page.getByText(/BL-MVP-048 será quien lo congele/)).toBeVisible();

    expect(writes).toBe(1);
    expect(payload).toMatchObject({
      lyricsRevisionId: lyricsId,
      timingRevisionId: timingId,
      translationRevisionId: translationId,
      analysisRevisionId: analysisId,
      exerciseRevisionIds: [exerciseId],
    });
    await expect(page.getByText(/no equivale a publicado/i)).toBeVisible();
  });

  test('BL079 detecta ejercicio roto y no permite aprobarlo para otra revisión fuente', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        await route.fulfill({
          status: 200,
          headers: { etag: emptySnapshot().eTag },
          contentType: 'application/json',
          body: JSON.stringify(emptySnapshot()),
        });
      },
    );

    await page.goto(`/editorial/paquetes/${recordingId}`);
    await page.getByLabel('Letra exacta').selectOption(lyricsId);

    const broken = page.getByRole('checkbox', { name: /Ejercicio · revisión 2/ });
    await expect(broken).toBeDisabled();
    await expect(page.getByText('Fuente incompatible con la letra seleccionada.')).toBeVisible();
    await expect(
      page.getByText('La opción correcta no conserva un token fuente válido de la línea exacta.'),
    ).toBeVisible();
  });

  test('un 409 conserva la selección local para corregir enlaces sin fallback latest', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        if (route.request().method() === 'GET') {
          await route.fulfill({
            status: 200,
            headers: { etag: emptySnapshot().eTag },
            contentType: 'application/json',
            body: JSON.stringify(emptySnapshot()),
          });
          return;
        }

        await route.fulfill({
          status: 409,
          contentType: 'application/problem+json',
          body: JSON.stringify({
            title: 'El paquete todavía no es compatible',
            detail: 'TRANSLATION no pertenece a la revisión de letra exacta seleccionada.',
            status: 409,
            code: 'editorial.package.source-incompatible',
          }),
        });
      },
    );

    await page.goto(`/editorial/paquetes/${recordingId}`);
    await page.getByLabel('Letra exacta').selectOption(lyricsId);
    await page.getByLabel('Sincronización').selectOption(timingId);
    await page.getByLabel('Traducción').selectOption(translationId);
    await page.getByLabel('Análisis').selectOption(analysisId);
    await page.getByRole('checkbox', { name: /Ejercicio · revisión 1/ }).check();
    await page.getByLabel('Motivo trazable').fill('Comprobar conflicto de fuente.');
    await page.getByRole('button', { name: 'Guardar paquete compatible' }).click();

    await expect(page.getByText('Hay una versión más reciente')).toBeVisible();
    await expect(page.getByLabel('Letra exacta')).toHaveValue(lyricsId);
    await expect(page.getByLabel('Traducción')).toHaveValue(translationId);
  });

  test('UI-MVP-026 mantiene preview y checklist operables por teclado a 320 px', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/compatible-package`,
      async (route) => {
        await route.fulfill({
          status: 200,
          headers: { etag: emptySnapshot().eTag },
          contentType: 'application/json',
          body: JSON.stringify(emptySnapshot()),
        });
      },
    );

    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/editorial/paquetes/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-026"]')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Paquete educativo compatible' })).toBeFocused();

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
