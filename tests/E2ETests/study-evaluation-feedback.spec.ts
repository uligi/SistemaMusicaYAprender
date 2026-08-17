import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const sessionId = '17300000-0000-7000-8000-000000000001';
const instanceId = '17300000-0000-7000-8000-000000000002';
const optionA = '17300000-0000-7000-8000-000000000011';
const optionB = '17300000-0000-7000-8000-000000000012';
const optionC = '17300000-0000-7000-8000-000000000013';
const submissionId = '17400000-0000-7000-8000-000000000001';
const evaluationId = '17500000-0000-7000-8000-000000000001';
const digest = '8d06765dcdd7a1a77c39bb9259a594709dd7268736713a6d2f944479f16e49e2';

const confirmedExercise = {
  instanceId,
  studySessionId: sessionId,
  stateCode: 'RESPONDED',
  instanceNo: 1,
  deliveredAt: '2026-08-16T21:00:00Z',
  version: 2,
  exerciseRevisionNo: 4,
  prompt: 'Elige la opción que completa la línea.',
  lineNo: 1,
  maskedJapaneseText: '＿＿でも叫ぶ',
  options: [
    { instanceItemId: optionB, displayOrder: 1, value: '何回' },
    { instanceItemId: optionA, displayOrder: 2, value: '何度' },
    { instanceItemId: optionC, displayOrder: 3, value: '何時' },
  ],
  submission: {
    submissionId,
    statusCode: 'CONFIRMED',
    submittedAt: '2026-08-16T21:01:00Z',
    selectedInstanceItemId: optionA,
  },
};

function evaluation(correct = true) {
  return {
    evaluationId,
    submissionId,
    evaluatorVersion: 'FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1',
    score: correct ? 1 : 0,
    correct,
    evaluatedAt: '2026-08-16T21:02:00Z',
    resultDigestSha256: digest,
    reusedExisting: false,
    feedback: [
      {
        feedbackCode: correct ? 'RESULT.CORRECT' : 'RESULT.INCORRECT',
        languageTag: 'es-CR',
        message: correct
          ? 'Bien: elegiste la forma aprobada para esta revisión.'
          : 'Esa opción no completa la línea según la revisión publicada.',
        displayOrder: 0,
      },
      {
        feedbackCode: 'EXPLANATION.RULE',
        languageTag: 'es-CR',
        message: '何度でも expresa la idea de una y otra vez dentro de esta línea.',
        displayOrder: 1,
      },
      {
        feedbackCode: 'NEXT_ACTION.CONTINUE',
        languageTag: 'es-CR',
        message:
          'Puedes volver a la canción o continuar con la práctica cuando haya otra actividad disponible.',
        displayOrder: 2,
      },
    ],
  };
}

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
        requestToken: 'csrf-bl075-076',
        headerName: 'X-CSRF-TOKEN',
      }),
    });
  });
}

async function mockActiveStudySession(page: Page) {
  await page.route(`**/api/v1/study/sessions/${sessionId}`, async (route) => {
    expect(route.request().method()).toBe('GET');
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        studySessionId: sessionId,
        statusCode: 'ACTIVE',
        startedAt: '2026-08-16T20:55:00Z',
        endedAt: null,
        version: 1,
        reusedExisting: true,
        message: 'La sesiÃ³n estÃ¡ activa.',
      }),
    });
  });
}
async function mockConfirmedExercise(page: Page) {
  await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(confirmedExercise),
    });
  });
}

function pendingProblem() {
  return {
    type: 'about:blank',
    title: 'La corrección todavía está pendiente',
    status: 404,
    detail:
      'La respuesta confirmada se conserva. Puedes iniciar la evaluación reproducible cuando estés listo.',
    code: 'learning.study-evaluation.pending',
  };
}

test.describe('BL-MVP-075/076 · evaluación reproducible y retroalimentación accesible', () => {
  test.beforeEach(async ({ page }) => {
    await mockStudentSession(page);
    await mockActiveStudySession(page);
    await mockConfirmedExercise(page);
  });

  test('BL075 evalúa con CSRF, versión registrada y resultado reproducible sin crear evidencia', async ({
    page,
  }) => {
    await mockCsrf(page);

    let reads = 0;
    let writes = 0;

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() === 'GET') {
          reads += 1;
          await route.fulfill({
            status: 404,
            contentType: 'application/problem+json',
            body: JSON.stringify(pendingProblem()),
          });
          return;
        }

        writes += 1;
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl075-076');
        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify(evaluation(true)),
        });
      },
    );

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await expect(page.getByRole('button', { name: 'Evaluar respuesta' })).toBeVisible();
    await page.getByRole('button', { name: 'Evaluar respuesta' }).click();

    const resultHeading = page.getByRole('heading', { name: 'Respuesta correcta' });
    await expect(resultHeading).toBeVisible();
    await expect(resultHeading).toBeFocused();
    await expect(page.getByText(/Puntuación:\s*1 de 1/)).toBeVisible();
    await expect(page.getByText('FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1')).toBeVisible();

    expect(reads).toBe(1);
    expect(writes).toBe(1);
    await expect(page.getByText(/evidencia creada|progreso actualizado/i)).toHaveCount(0);
  });

  test('BL075 recupera exactamente la evaluación persistida al recargar sin volver a escribir', async ({
    page,
  }) => {
    let reads = 0;
    let writes = 0;
    const existing = { ...evaluation(true), reusedExisting: true };

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() === 'POST') {
          writes += 1;
          await route.abort();
          return;
        }

        reads += 1;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(existing),
        });
      },
    );

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await expect(page.getByRole('heading', { name: 'Respuesta correcta' })).toBeVisible();
    await page.reload();
    await expect(page.getByRole('heading', { name: 'Respuesta correcta' })).toBeVisible();
    await expect(page.getByText('FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1')).toBeVisible();

    expect(reads).toBe(2);
    expect(writes).toBe(0);
  });

  test('BL075 deja un estado revisable si falta la regla y no presenta un resultado definitivo', async ({
    page,
  }) => {
    await mockCsrf(page);

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() === 'GET') {
          await route.fulfill({
            status: 404,
            contentType: 'application/problem+json',
            body: JSON.stringify(pendingProblem()),
          });
          return;
        }

        await route.fulfill({
          status: 409,
          contentType: 'application/problem+json',
          body: JSON.stringify({
            type: 'about:blank',
            title: 'La regla congelada necesita revisión',
            status: 409,
            detail:
              'No se confirmó una evaluación definitiva. La respuesta se conserva para revisión.',
            code: 'learning.study-evaluation.rule.unavailable',
          }),
        });
      },
    );

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await page.getByRole('button', { name: 'Evaluar respuesta' }).click();

    await expect(page.getByText('La regla congelada necesita revisión')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Respuesta correcta' })).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Respuesta incorrecta' })).toHaveCount(0);
    await expect(page.getByText(/evidencia creada|progreso actualizado/i)).toHaveCount(0);
  });

  test('BL076 comunica resultado, explicación y siguiente acción por texto con foco y axe a 320 px', async ({
    page,
  }) => {
    const existing = { ...evaluation(false), reusedExisting: true };

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(existing),
        });
      },
    );

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);

    const resultHeading = page.getByRole('heading', { name: 'Respuesta incorrecta' });
    await expect(resultHeading).toBeFocused();
    await expect(page.getByRole('heading', { name: 'Resultado', exact: true })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Explicación' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Siguiente acción' })).toBeVisible();
    await expect(
      page.getByText('何度でも expresa la idea de una y otra vez dentro de esta línea.'),
    ).toBeVisible();
    await expect(
      page.getByText(
        'Puedes volver a la canción o continuar con la práctica cuando haya otra actividad disponible.',
      ),
    ).toBeVisible();

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
