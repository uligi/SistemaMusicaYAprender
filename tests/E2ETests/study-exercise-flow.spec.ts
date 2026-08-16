import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const sessionId = '17300000-0000-7000-8000-000000000001';
const instanceId = '17300000-0000-7000-8000-000000000002';
const optionA = '17300000-0000-7000-8000-000000000011';
const optionB = '17300000-0000-7000-8000-000000000012';
const optionC = '17300000-0000-7000-8000-000000000013';
const submissionId = '17400000-0000-7000-8000-000000000001';

const frozenExercise = {
  instanceId,
  studySessionId: sessionId,
  stateCode: 'DELIVERED',
  instanceNo: 1,
  deliveredAt: '2026-08-16T21:00:00Z',
  version: 1,
  exerciseRevisionNo: 4,
  prompt: 'Elige la opción que completa la línea.',
  lineNo: 1,
  maskedJapaneseText: '＿＿でも叫ぶ',
  options: [
    { instanceItemId: optionB, displayOrder: 1, value: '何回' },
    { instanceItemId: optionA, displayOrder: 2, value: '何度' },
    { instanceItemId: optionC, displayOrder: 3, value: '何時' },
  ],
  submission: null,
};

async function mockStudentSession(page: Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'STUDENT',
        roles: ['STUDENT'],
        capabilities: [],
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
        requestToken: 'csrf-bl073-074',
        headerName: 'X-CSRF-TOKEN',
      }),
    });
  });
}

async function mockStudyStart(page: Page) {
  await page.route('**/api/v1/public/catalog/songs/*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        slug,
        canonicalTitle: '怪獣',
        recordingTitle: '怪獣',
        artistName: 'サカナクション',
        availableComponents: ['LYRICS', 'EXERCISE'],
      }),
    });
  });

  await page.route('**/api/v1/study/songs/*/session-start**', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        eligible: true,
        blockingReason: null,
        eligibleExerciseCount: 1,
        publicationNo: 5,
        activeSession: {
          studySessionId: sessionId,
          statusCode: 'ACTIVE',
          startedAt: '2026-08-16T20:55:00Z',
          version: 1,
        },
      }),
    });
  });
}

function confirmedExercise() {
  return {
    ...frozenExercise,
    stateCode: 'RESPONDED',
    version: 2,
    submission: {
      submissionId,
      statusCode: 'CONFIRMED',
      submittedAt: '2026-08-16T21:01:00Z',
      selectedInstanceItemId: optionA,
    },
  };
}

test.describe('BL-MVP-073/074 · instancia congelada y respuesta idempotente', () => {
  test.beforeEach(async ({ page }) => {
    await mockStudentSession(page);
  });

  test('BL073 congela una sola instancia y abre UI-MVP-012 sin exponer solución', async ({
    page,
  }) => {
    await mockCsrf(page);
    await mockStudyStart(page);

    let prepareWrites = 0;

    await page.route('**/api/v1/study/sessions/*/instances', async (route) => {
      prepareWrites += 1;
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl073-074');

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          instanceId,
          reusedExisting: false,
          message: 'El primer ejercicio quedó congelado para esta sesión.',
        }),
      });
    });

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(frozenExercise),
      });
    });

    await page.goto(`/estudiar/${slug}`);
    await page.getByRole('button', { name: 'Continuar con el ejercicio' }).click();

    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/ejercicio/${instanceId}$`));
    await expect(page.locator('[data-route-id="UI-MVP-012"]')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Completa el espacio' })).toBeFocused();
    await expect(page.getByText('＿＿でも叫ぶ')).toBeVisible();
    await expect(page.getByText('Revisión 4')).toBeVisible();
    await expect(page.getByRole('radio')).toHaveCount(3);

    expect(prepareWrites).toBe(1);
    await expect(page.getByText(/respuesta correcta/i)).toHaveCount(0);
    await expect(page.getByText(/solución editorial/i)).toHaveCount(0);
    await expect(page.getByText(/explicación educativa/i)).toHaveCount(0);
  });

  test('BL073 al reabrir conserva exactamente revisión, contexto y orden de opciones', async ({
    page,
  }) => {
    let reads = 0;

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      reads += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(frozenExercise),
      });
    });

    await page.goto(`/estudiar/${slug}/ejercicio/${instanceId}`);
    await expect(page.getByRole('radio')).toHaveCount(3);

    const optionValues = async () =>
      page
        .locator('.study-exercise__options label span')
        .evaluateAll((nodes) => nodes.map((node) => node.textContent));

    expect(await optionValues()).toEqual(['何回', '何度', '何時']);

    await page.reload();
    await expect(page.getByRole('radio')).toHaveCount(3);

    expect(await optionValues()).toEqual(['何回', '何度', '何時']);
    await expect(page.getByText('Revisión 4')).toBeVisible();
    await expect(page.getByText('＿＿でも叫ぶ')).toBeVisible();
    expect(reads).toBe(2);
  });

  test('BL074 confirma una sola selección con CSRF e Idempotency-Key y no evalúa', async ({
    page,
  }) => {
    await mockCsrf(page);

    let submitted = false;
    let writes = 0;
    let idempotencyKey = '';
    let submittedSelection = '';

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(submitted ? confirmedExercise() : frozenExercise),
      });
    });

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/submissions`,
      async (route) => {
        writes += 1;
        idempotencyKey = route.request().headers()['idempotency-key'] ?? '';
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl073-074');

        const body = route.request().postDataJSON() as {
          selectedInstanceItemId: string;
        };
        submittedSelection = body.selectedInstanceItemId;
        submitted = true;

        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            submissionId,
            instanceId,
            statusCode: 'CONFIRMED',
            submittedAt: '2026-08-16T21:01:00Z',
            selectedInstanceItemId: optionA,
            reusedExisting: false,
            message: 'Respuesta confirmada. La corrección se calculará en el siguiente paso.',
          }),
        });
      },
    );

    await page.goto(`/estudiar/${slug}/ejercicio/${instanceId}`);
    await page.getByRole('radio', { name: '何度' }).check();
    await page.getByRole('button', { name: 'Confirmar respuesta' }).click();

    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/resultado/${instanceId}$`));
    await expect(page.locator('[data-route-id="UI-MVP-013"]')).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Tu respuesta quedó confirmada' }),
    ).toBeVisible();
    await expect(
      page.locator('.study-exercise__confirmed').getByText('何度', { exact: true }),
    ).toBeVisible();

    expect(writes).toBe(1);
    expect(idempotencyKey.length).toBeGreaterThanOrEqual(8);
    expect(submittedSelection).toBe(optionA);
    await expect(page.getByText(/correcta|incorrecta/i)).toHaveCount(0);
    await expect(page.getByText(/puntuación|evidencia creada|progreso actualizado/i)).toHaveCount(
      0,
    );
  });

  test('BL074 al recargar recupera la misma entrega confirmada sin volver a enviar', async ({
    page,
  }) => {
    let writes = 0;

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(confirmedExercise()),
      });
    });

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/submissions`,
      async (route) => {
        writes += 1;
        await route.abort();
      },
    );

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await page.reload();

    await expect(
      page.getByRole('heading', { name: 'Tu respuesta quedó confirmada' }),
    ).toBeVisible();
    await expect(
      page.locator('.study-exercise__confirmed').getByText('何度', { exact: true }),
    ).toBeVisible();
    expect(writes).toBe(0);
  });

  test('UI-MVP-012 conserva selección por teclado y accesibilidad a 320 px', async ({ page }) => {
    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(frozenExercise),
      });
    });

    await page.goto(`/estudiar/${slug}/ejercicio/${instanceId}`);

    const first = page.getByRole('radio', { name: '何回' });
    await first.focus();
    await expect(first).toBeFocused();
    await first.check();
    await expect(first).toBeChecked();

    const metrics = await page.evaluate(() => ({
      innerWidth: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));

    expect(metrics.innerWidth).toBe(320);
    expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.innerWidth + 1);

    const results = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    expect(results.violations).toEqual([]);
  });
});
