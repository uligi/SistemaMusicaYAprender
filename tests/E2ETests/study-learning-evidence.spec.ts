import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const sessionId = '17600000-0000-7000-8000-000000000001';
const instanceId = '17600000-0000-7000-8000-000000000002';
const optionA = '17600000-0000-7000-8000-000000000011';
const optionB = '17600000-0000-7000-8000-000000000012';
const submissionId = '17600000-0000-7000-8000-000000000021';
const evaluationId = '17600000-0000-7000-8000-000000000031';
const evidenceId = '17600000-0000-7000-8000-000000000041';
const competencyId = '17600000-0000-7000-8000-000000000051';
const recordingId = '17600000-0000-7000-8000-000000000061';

const confirmedExercise = {
  instanceId,
  studySessionId: sessionId,
  stateCode: 'RESPONDED',
  instanceNo: 1,
  deliveredAt: '2026-08-16T23:00:00Z',
  version: 2,
  exerciseRevisionNo: 4,
  prompt: 'Elige la opción que completa la línea.',
  lineNo: 1,
  maskedJapaneseText: '＿＿でも叫ぶ',
  options: [
    { instanceItemId: optionB, displayOrder: 1, value: '何回' },
    { instanceItemId: optionA, displayOrder: 2, value: '何度' },
  ],
  submission: {
    submissionId,
    statusCode: 'CONFIRMED',
    submittedAt: '2026-08-16T23:01:00Z',
    selectedInstanceItemId: optionA,
  },
};

function evidence(reusedExisting = false) {
  return {
    evidenceId,
    evaluationId,
    competencyId,
    recordingId,
    outcome: 1,
    evidenceVersion: 1,
    confirmedAt: '2026-08-16T23:03:00Z',
    reusedExisting,
  };
}

function evaluation(evidenceValue: ReturnType<typeof evidence> | null) {
  return {
    evaluationId,
    submissionId,
    evaluatorVersion: 'FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1',
    score: 1,
    correct: true,
    evaluatedAt: '2026-08-16T23:02:00Z',
    resultDigestSha256: '1456acddc757eb1b7a59d88c6bd58a1e90ed93d592c7b80a5f8bc424fd59600c',
    reusedExisting: false,
    feedback: [
      {
        feedbackCode: 'RESULT.CORRECT',
        languageTag: 'es-CR',
        message: 'Bien: elegiste la forma aprobada para esta revisión.',
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
        message: 'Puedes continuar cuando haya otra actividad disponible.',
        displayOrder: 2,
      },
    ],
    evidence: evidenceValue,
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
        requestToken: 'csrf-bl077',
        headerName: 'X-CSRF-TOKEN',
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

function evaluationPendingProblem() {
  return {
    type: 'about:blank',
    title: 'La corrección todavía está pendiente',
    status: 404,
    detail: 'La respuesta confirmada se conserva.',
    code: 'learning.study-evaluation.pending',
  };
}

test.describe('BL-MVP-077 · evidencia append-only e idempotente', () => {
  test.beforeEach(async ({ page }) => {
    await mockStudentSession(page);
    await mockConfirmedExercise(page);
  });

  test('BL077 una evaluación válida confirma una evidencia lógica sin actualizar progreso', async ({
    page,
  }) => {
    await mockCsrf(page);

    let evaluationWrites = 0;
    let directEvidenceWrites = 0;

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() === 'GET') {
          await route.fulfill({
            status: 404,
            contentType: 'application/problem+json',
            body: JSON.stringify(evaluationPendingProblem()),
          });
          return;
        }

        evaluationWrites += 1;
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl077');
        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify(evaluation(evidence(false))),
        });
      },
    );

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}/evidence`, async (route) => {
      directEvidenceWrites += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await page.getByRole('button', { name: 'Evaluar respuesta' }).click();

    await expect(page.getByRole('heading', { name: 'Respuesta correcta' })).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Evidencia de aprendizaje confirmada' }),
    ).toBeVisible();
    await expect(page.getByText(/Versión de evidencia:\s*1/)).toBeVisible();
    await expect(page.getByText(/Este paso no actualiza el progreso todavía/i)).toBeVisible();

    expect(evaluationWrites).toBe(1);
    expect(directEvidenceWrites).toBe(0);
  });

  test('BL077 recupera evidencia pendiente con CSRF y al recargar no vuelve a crearla', async ({
    page,
  }) => {
    await mockCsrf(page);

    let confirmed = false;
    let evidenceWrites = 0;

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(evaluation(confirmed ? evidence(true) : null)),
        });
      },
    );

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}/evidence`, async (route) => {
      expect(route.request().method()).toBe('POST');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl077');
      evidenceWrites += 1;
      confirmed = true;
      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify(evidence(false)),
      });
    });

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await expect(page.getByRole('button', { name: 'Confirmar evidencia' })).toBeVisible();
    await page.getByRole('button', { name: 'Confirmar evidencia' }).click();
    await expect(
      page.getByRole('heading', { name: 'Evidencia de aprendizaje confirmada' }),
    ).toBeVisible();

    await page.reload();
    await expect(
      page.getByRole('heading', { name: 'Evidencia de aprendizaje confirmada' }),
    ).toBeVisible();
    await expect(page.getByRole('button', { name: 'Confirmar evidencia' })).toHaveCount(0);
    expect(evidenceWrites).toBe(1);
  });

  test('BL077 mantiene la evidencia textual sin overflow y sin violaciones axe a 320 px', async ({
    page,
  }) => {
    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(evaluation(evidence(true))),
        });
      },
    );

    await page.goto(`/estudiar/${slug}/resultado/${instanceId}`);
    await expect(
      page.getByRole('heading', { name: 'Evidencia de aprendizaje confirmada' }),
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
