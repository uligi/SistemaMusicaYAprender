import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '17000000-0000-7000-8000-000000000001';

const bank = {
  recordingId,
  exerciseCount: 1,
  exercises: [
    {
      exerciseId: '17000000-0000-7000-8000-000000000010',
      exerciseType: 'FILL_BLANK_OPTIONS',
      statusCode: 'DRAFT',
      version: 1,
      competency: {
        code: 'VOCAB.CONTEXT',
        domainCode: 'VOCABULARY',
        title: 'Vocabulario en contexto',
      },
      source: {
        recordingId,
        lineId: '17000000-0000-7000-8000-000000000020',
        lineNo: 1,
        japaneseText: '何度でも叫ぶ',
        lyricsRevisionId: '17000000-0000-7000-8000-000000000021',
        lyricsRevisionNo: 3,
        lyricsRevisionChecksumSha256: 'a'.repeat(64),
      },
      revisions: [
        {
          exerciseRevisionId: '17000000-0000-7000-8000-000000000030',
          revisionNo: 2,
          statusCode: 'DRAFT',
          prompt: 'Completa la expresión que significa “una y otra vez”.',
          checksumSha256: 'b'.repeat(64),
          version: 1,
          schemaVersion: 1,
          answerModel: 'SINGLE_CHOICE',
          explanation: '何度でも expresa repetición: “una y otra vez”.',
          feedback: {
            correct: 'Correcto: identificaste la expresión contextual.',
            incorrect: 'Revisa la línea y compara el sentido de las opciones.',
          },
          difficulty: {
            code: 'BEGINNER',
            justification: 'Una sola línea y tres opciones claramente diferenciadas.',
          },
          items: [
            {
              exerciseItemId: '17000000-0000-7000-8000-000000000031',
              itemType: 'OPTION',
              itemOrder: 1,
              label: '何度でも',
              value: '何度でも',
              metadataJson: '{"role":"option"}',
              isAccepted: true,
            },
            {
              exerciseItemId: '17000000-0000-7000-8000-000000000032',
              itemType: 'OPTION',
              itemOrder: 2,
              label: '叫ぶ',
              value: '叫ぶ',
              metadataJson: '{"role":"option"}',
              isAccepted: false,
            },
            {
              exerciseItemId: '17000000-0000-7000-8000-000000000033',
              itemType: 'OPTION',
              itemOrder: 3,
              label: '怪獣',
              value: '怪獣',
              metadataJson: '{"role":"option"}',
              isAccepted: false,
            },
          ],
          solutions: ['何度でも'],
          provenance: [
            {
              sourceType: 'EDITORIAL',
              citation: 'Ficha pedagógica BL070',
              locator: 'línea 1',
              contributionType: 'EXERCISE_SOURCE',
              recordedAt: '2026-08-15T17:45:00Z',
            },
          ],
          completeness: {
            hasContext: true,
            hasOptions: true,
            hasSolution: true,
            hasExplanation: true,
            hasDifficulty: true,
            hasProvenance: true,
            readyForReview: true,
          },
          warnings: [],
        },
      ],
    },
  ],
};

const completeExercise = bank.exercises[0]!;
const completeRevision = completeExercise.revisions[0]!;

async function mockSession(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'EDITOR',
        roles: ['EDITOR'],
        capabilities: ['EDITORIAL.DRAFT'],
      }),
    });
  });
}

async function mockBank(page: import('@playwright/test').Page, body: unknown) {
  await page.route('**/api/v1/editorial/song-drafts/*/exercise-bank', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(body),
    });
  });
}

test.describe('BL-MVP-070 · banco y revisiones de ejercicios', () => {
  test('conserva tipo, contexto, revisión, opciones, solución, explicación, dificultad y procedencia', async ({
    page,
  }) => {
    await mockSession(page);
    await mockBank(page, bank);

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);

    await expect(
      page.getByRole('heading', { name: 'Banco de ejercicios', exact: true }),
    ).toBeVisible();
    await expect(page.getByText('FILL BLANK OPTIONS')).toBeVisible();
    await expect(page.getByText('Vocabulario en contexto')).toBeVisible();
    await expect(page.getByText('Letra · revisión 3')).toBeVisible();
    await expect(page.getByText('何度でも叫ぶ', { exact: true })).toBeVisible();
    await expect(page.getByText('Revisión 2')).toBeVisible();
    await expect(
      page.getByText('Completa la expresión que significa “una y otra vez”.'),
    ).toBeVisible();
    await expect(page.getByText('何度でも', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('Respuesta válida:')).toBeVisible();
    await expect(page.getByText('何度でも expresa repetición: “una y otra vez”.')).toBeVisible();
    await expect(page.getByText('BEGINNER')).toBeVisible();
    await expect(page.getByText('Ficha pedagógica BL070')).toBeVisible();
    await expect(page.getByText('completa para revisión')).toBeVisible();

    await expect(
      page.getByRole('button', { name: /guardar|publicar|crear ejercicio/i }),
    ).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('expone pendientes sin inventar datos y no adelanta la autoría BL071', async ({ page }) => {
    await mockSession(page);
    await mockBank(page, {
      ...bank,
      exercises: [
        {
          ...completeExercise,
          revisions: [
            {
              ...completeRevision,
              explanation: null,
              difficulty: { code: null, justification: null },
              provenance: [],
              completeness: {
                ...completeRevision.completeness,
                hasExplanation: false,
                hasDifficulty: false,
                hasProvenance: false,
                readyForReview: false,
              },
              warnings: [
                'Falta explicación educativa.',
                'Falta dificultad editorial justificada.',
                'Falta procedencia editorial.',
              ],
            },
          ],
        },
      ],
    });

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);

    await expect(page.getByText('requiere completar')).toBeVisible();
    await expect(page.getByText('Explicación pendiente.')).toBeVisible();
    await expect(page.getByText('Falta dificultad editorial justificada.')).toBeVisible();
    await expect(page.getByText('Procedencia pendiente.')).toBeVisible();
    await expect(
      page.getByRole('button', { name: /guardar|publicar|crear ejercicio/i }),
    ).toHaveCount(0);
  });

  test('mantiene UI-MVP-025 a 320 px sin overflow y pasa axe', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);
    await mockBank(page, bank);

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);

    await expect(
      page.getByRole('heading', { name: 'Banco de ejercicios', exact: true }),
    ).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
