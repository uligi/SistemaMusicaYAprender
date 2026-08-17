import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const slug = 'kaiju-0123456789abcdefabcd';
const sessionId = '17800000-0000-7000-8000-000000000001';
const instanceId = '17800000-0000-7000-8000-000000000002';
const optionA = '17800000-0000-7000-8000-000000000011';
const optionB = '17800000-0000-7000-8000-000000000012';
const optionC = '17800000-0000-7000-8000-000000000013';
const submissionId = '17800000-0000-7000-8000-000000000021';
const evaluationId = '17800000-0000-7000-8000-000000000031';
const evidenceId = '17800000-0000-7000-8000-000000000041';
const competencyId = '17800000-0000-7000-8000-000000000051';
const recordingId = '17800000-0000-7000-8000-000000000061';

type SessionLifecycleState = {
  statusCode: 'ACTIVE' | 'PAUSED' | 'COMPLETED';
  version: number;
  endedAt: string | null;
};

const activeSession = (): SessionLifecycleState => ({
  statusCode: 'ACTIVE',
  version: 1,
  endedAt: null,
});

function lifecycleView(state: SessionLifecycleState) {
  return {
    studySessionId: sessionId,
    statusCode: state.statusCode,
    startedAt: '2026-08-16T21:55:00Z',
    endedAt: state.endedAt,
    version: state.version,
    reusedExisting: true,
    message: `Sesión ${state.statusCode}.`,
  };
}

const frozenExercise = {
  instanceId,
  studySessionId: sessionId,
  stateCode: 'DELIVERED',
  instanceNo: 1,
  deliveredAt: '2026-08-16T22:00:00Z',
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

function confirmedExercise() {
  return {
    ...frozenExercise,
    stateCode: 'RESPONDED',
    version: 2,
    submission: {
      submissionId,
      statusCode: 'CONFIRMED',
      submittedAt: '2026-08-16T22:01:00Z',
      selectedInstanceItemId: optionA,
    },
  };
}

function confirmedEvaluation(reusedExisting = false) {
  return {
    evaluationId,
    submissionId,
    evaluatorVersion: 'FILL_BLANK_OPTIONS.SINGLE_CHOICE/v1',
    score: 1,
    correct: true,
    evaluatedAt: '2026-08-16T22:02:00Z',
    resultDigestSha256: '8d06765dcdd7a1a77c39bb9259a594709dd7268736713a6d2f944479f16e49e2',
    reusedExisting,
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
        message: '何度でも expresa una y otra vez dentro de esta línea.',
        displayOrder: 1,
      },
      {
        feedbackCode: 'NEXT_ACTION.CONTINUE',
        languageTag: 'es-CR',
        message: 'Puedes salir y continuar después sin duplicar esta evidencia.',
        displayOrder: 2,
      },
    ],
    evidence: {
      evidenceId,
      evaluationId,
      competencyId,
      recordingId,
      outcome: 1,
      evidenceVersion: 1,
      confirmedAt: '2026-08-16T22:02:01Z',
      reusedExisting,
    },
  };
}

function pendingEvaluationProblem() {
  return {
    type: 'about:blank',
    title: 'La corrección todavía está pendiente',
    status: 404,
    detail: 'La respuesta confirmada se conserva.',
    code: 'learning.study-evaluation.pending',
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
      body: JSON.stringify({ requestToken: 'csrf-bl078', headerName: 'X-CSRF-TOKEN' }),
    });
  });
}

async function mockStudyStart(
  page: Page,
  readSession: () => SessionLifecycleState = activeSession,
) {
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
    const session = readSession();
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        eligible: true,
        blockingReason: null,
        eligibleExerciseCount: 1,
        publicationNo: 5,
        activeSession:
          session.statusCode === 'COMPLETED'
            ? null
            : {
                studySessionId: sessionId,
                statusCode: session.statusCode,
                startedAt: '2026-08-16T21:55:00Z',
                version: session.version,
              },
      }),
    });
  });
}

async function mockLifecycleRead(page: Page, readSession: () => SessionLifecycleState) {
  await page.route(`**/api/v1/study/sessions/${sessionId}`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(lifecycleView(readSession())),
    });
  });
}

async function mockLifecycleMutations(
  page: Page,
  readSession: () => SessionLifecycleState,
  writeSession: (next: SessionLifecycleState) => void,
  onAction?: (action: 'pause' | 'resume' | 'complete') => void,
) {
  for (const action of ['pause', 'resume', 'complete'] as const) {
    await page.route(`**/api/v1/study/sessions/${sessionId}/${action}`, async (route) => {
      onAction?.(action);
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl078');
      expect(route.request().headers()['if-match']).toBe(`"${readSession().version}"`);

      const current = readSession();
      const next: SessionLifecycleState =
        action === 'pause'
          ? { statusCode: 'PAUSED', version: current.version + 1, endedAt: null }
          : action === 'resume'
            ? { statusCode: 'ACTIVE', version: current.version + 1, endedAt: null }
            : {
                statusCode: 'COMPLETED',
                version: current.version + 1,
                endedAt: '2026-08-16T22:10:00Z',
              };

      writeSession(next);
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ...lifecycleView(next), reusedExisting: false }),
      });
    });
  }
}

async function mockPrepare(page: Page, onWrite?: () => void) {
  await page.route('**/api/v1/study/sessions/*/instances', async (route) => {
    onWrite?.();
    expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl078');
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        instanceId,
        reusedExisting: true,
        message: 'Reabrimos exactamente el ejercicio que ya habías recibido.',
      }),
    });
  });
}

test.describe('BL-MVP-078 · experiencia completa y reanudable de sesión', () => {
  test.beforeEach(async ({ page }) => {
    await mockStudentSession(page);
  });

  test('recorre Inicio → Ejercicio → Resultado y distingue Pendiente → Guardado → Confirmado', async ({
    page,
  }) => {
    await mockCsrf(page);
    let session = activeSession();
    await mockStudyStart(page, () => session);
    await mockLifecycleRead(page, () => session);
    await mockPrepare(page);

    let submitted = false;
    let evaluated = false;
    let submissionWrites = 0;
    let evaluationWrites = 0;
    let evidenceWrites = 0;
    let progressRequests = 0;

    page.on('request', (request) => {
      if (request.url().includes('/progress')) progressRequests += 1;
    });

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
        submissionWrites += 1;
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl078');
        submitted = true;
        await route.fulfill({
          status: 201,
          contentType: 'application/json',
          body: JSON.stringify({
            submissionId,
            instanceId,
            statusCode: 'CONFIRMED',
            submittedAt: '2026-08-16T22:01:00Z',
            selectedInstanceItemId: optionA,
            reusedExisting: false,
            message: 'Respuesta confirmada.',
          }),
        });
      },
    );

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() === 'GET' && !evaluated) {
          await route.fulfill({
            status: 404,
            contentType: 'application/problem+json',
            body: JSON.stringify(pendingEvaluationProblem()),
          });
          return;
        }

        if (route.request().method() === 'POST') {
          evaluationWrites += 1;
          expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl078');
          evaluated = true;
        }

        await route.fulfill({
          status: route.request().method() === 'POST' ? 201 : 200,
          contentType: 'application/json',
          body: JSON.stringify(confirmedEvaluation(route.request().method() === 'GET')),
        });
      },
    );

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}/evidence`, async (route) => {
      evidenceWrites += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}`);
    await expect(page.locator('[data-study-status="pending"]')).toContainText('Estado: Pendiente.');

    await page.getByRole('button', { name: 'Continuar con el ejercicio' }).click();
    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/ejercicio/${instanceId}$`));
    await expect(page.locator('[aria-current="step"]')).toContainText('Ejercicio');
    await expect(page.locator('[data-study-status="pending"]')).toContainText('Estado: Pendiente.');

    await page.getByRole('radio', { name: '何度' }).check();
    await page.getByRole('button', { name: 'Confirmar respuesta' }).click();

    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/resultado/${instanceId}$`));
    await expect(page.locator('[aria-current="step"]')).toContainText('Resultado');
    await expect(page.locator('[data-study-status="saved"]')).toContainText('Estado: Guardado.');

    await page.getByRole('button', { name: 'Evaluar respuesta' }).click();
    await expect(page.locator('[data-study-status="confirmed"]')).toContainText(
      'Estado: Confirmado.',
    );
    await expect(
      page.getByRole('heading', { name: 'Evidencia de aprendizaje confirmada' }),
    ).toBeVisible();

    expect(submissionWrites).toBe(1);
    expect(evaluationWrites).toBe(1);
    expect(evidenceWrites).toBe(0);
    expect(progressRequests).toBe(0);
  });

  test('sale antes de confirmar y reanuda la misma instancia sin convertir selección local en guardado', async ({
    page,
  }) => {
    await mockCsrf(page);
    let session = activeSession();
    let pauseWrites = 0;
    let resumeWrites = 0;
    await mockStudyStart(page, () => session);
    await mockLifecycleRead(page, () => session);
    await mockLifecycleMutations(
      page,
      () => session,
      (next) => {
        session = next;
      },
      (action) => {
        if (action === 'pause') pauseWrites += 1;
        if (action === 'resume') resumeWrites += 1;
      },
    );

    let prepareWrites = 0;
    let educationalWrites = 0;
    await mockPrepare(page, () => {
      prepareWrites += 1;
    });

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(frozenExercise),
      });
    });

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/submissions`,
      async (route) => {
        educationalWrites += 1;
        await route.abort();
      },
    );
    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() !== 'GET') educationalWrites += 1;
        await route.abort();
      },
    );
    await page.route(`**/api/v1/study/exercise-instances/${instanceId}/evidence`, async (route) => {
      educationalWrites += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}`);
    await page.getByRole('button', { name: 'Continuar con el ejercicio' }).click();
    await page.getByRole('radio', { name: '何度' }).check();
    await expect(page.getByRole('radio', { name: '何度' })).toBeChecked();

    await page.getByRole('button', { name: 'Salir y continuar después' }).click();
    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}$`));
    await expect(page.getByRole('button', { name: 'Continuar sesión' })).toBeVisible();
    await page.getByRole('button', { name: 'Continuar sesión' }).click();

    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/ejercicio/${instanceId}$`));
    await expect(page.getByRole('radio', { name: '何度' })).not.toBeChecked();
    await expect(page.locator('[data-study-status="pending"]')).toContainText('Estado: Pendiente.');
    expect(prepareWrites).toBe(2);
    expect(pauseWrites).toBe(1);
    expect(resumeWrites).toBe(1);
    expect(educationalWrites).toBe(0);
  });

  test('reanuda una instancia respondida directamente en el resultado confirmado y conserva accesibilidad', async ({
    page,
  }) => {
    await mockCsrf(page);
    let session = activeSession();
    await mockStudyStart(page, () => session);
    await mockLifecycleRead(page, () => session);

    let prepareWrites = 0;
    let educationalWrites = 0;
    await mockPrepare(page, () => {
      prepareWrites += 1;
    });

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(confirmedExercise()),
      });
    });

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() === 'POST') educationalWrites += 1;
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(confirmedEvaluation(true)),
        });
      },
    );

    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/submissions`,
      async (route) => {
        educationalWrites += 1;
        await route.abort();
      },
    );
    await page.route(`**/api/v1/study/exercise-instances/${instanceId}/evidence`, async (route) => {
      educationalWrites += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}`);
    await page.getByRole('button', { name: 'Continuar con el ejercicio' }).click();

    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/resultado/${instanceId}$`));
    await expect(page.locator('[data-study-status="confirmed"]')).toContainText(
      'Estado: Confirmado.',
    );
    await expect(page.locator('[aria-current="step"]')).toContainText('Resultado');
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

    expect(prepareWrites).toBe(1);
    expect(educationalWrites).toBe(0);
  });

  test('CA-MVP-053 · pausa, continúa y finaliza por teclado sin temporizador obligatorio', async ({
    page,
  }) => {
    await mockCsrf(page);
    let session = activeSession();
    let pauseWrites = 0;
    let resumeWrites = 0;
    let completeWrites = 0;
    let educationalWrites = 0;

    await mockStudyStart(page, () => session);
    await mockLifecycleRead(page, () => session);
    await mockLifecycleMutations(
      page,
      () => session,
      (next) => {
        session = next;
      },
      (action) => {
        if (action === 'pause') pauseWrites += 1;
        if (action === 'resume') resumeWrites += 1;
        if (action === 'complete') completeWrites += 1;
      },
    );
    await mockPrepare(page);

    await page.route(`**/api/v1/study/exercise-instances/${instanceId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(frozenExercise),
      });
    });
    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/submissions`,
      async (route) => {
        educationalWrites += 1;
        await route.abort();
      },
    );
    await page.route(
      `**/api/v1/study/exercise-instances/${instanceId}/evaluation`,
      async (route) => {
        if (route.request().method() !== 'GET') educationalWrites += 1;
        await route.abort();
      },
    );
    await page.route(`**/api/v1/study/exercise-instances/${instanceId}/evidence`, async (route) => {
      educationalWrites += 1;
      await route.abort();
    });

    await page.goto(`/estudiar/${slug}`);
    await expect(page.getByText('No hay un temporizador obligatorio.')).toBeVisible();

    const open = page.getByRole('button', { name: 'Continuar con el ejercicio' });
    await open.focus();
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/ejercicio/${instanceId}$`));

    const pause = page.getByRole('button', { name: 'Salir y continuar después' });
    await pause.focus();
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}$`));
    await expect(page.getByRole('button', { name: 'Continuar sesión' })).toBeVisible();

    const resume = page.getByRole('button', { name: 'Continuar sesión' });
    await resume.focus();
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/ejercicio/${instanceId}$`));

    const complete = page.getByRole('button', { name: 'Finalizar sesión' });
    await complete.focus();
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(new RegExp(`/estudiar/${slug}/ejercicio/${instanceId}$`));
    await expect(page.getByText('Sesión finalizada', { exact: true })).toBeVisible();
    await expect(
      page.getByText(
        'Los hechos ya confirmados se conservan. No se crean respuestas, evaluaciones, evidencias ni progreso adicionales al finalizar.',
      ),
    ).toBeVisible();

    expect(pauseWrites).toBe(1);
    expect(resumeWrites).toBe(1);
    expect(completeWrites).toBe(1);
    expect(educationalWrites).toBe(0);
  });
});
