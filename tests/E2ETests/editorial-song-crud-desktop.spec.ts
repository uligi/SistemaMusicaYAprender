import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '17600000-0000-7000-8000-000000000001';
const lyricsRevisionId = '17600000-0000-7000-8000-000000000010';
const lineId = '17600000-0000-7000-8000-000000000020';
const tokenId = '17600000-0000-7000-8000-000000000030';
const exerciseId = '17600000-0000-7000-8000-000000000040';
const exerciseRevisionId = '17600000-0000-7000-8000-000000000041';

async function mockSession(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'EDITOR',
        roles: ['EDITOR'],
        capabilities: ['EDITORIAL.DRAFT', 'EDITORIAL.SUBMIT', 'EDITORIAL.CORRECT'],
      }),
    });
  });
}

async function mockExerciseBank(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/editorial/song-drafts/*/exercise-bank', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        recordingId,
        exerciseCount: 1,
        exercises: [
          {
            exerciseId,
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
              lineId,
              lineNo: 1,
              japaneseText: '何度でも叫ぶ',
              lyricsRevisionId,
              lyricsRevisionNo: 3,
              lyricsRevisionChecksumSha256: 'a'.repeat(64),
            },
            revisions: [
              {
                exerciseRevisionId,
                revisionNo: 1,
                statusCode: 'DRAFT',
                prompt: 'Completa el espacio con la opción correcta.',
                checksumSha256: 'b'.repeat(64),
                version: 1,
                schemaVersion: 1,
                answerModel: 'SINGLE_CHOICE',
                explanation: '何度でも expresa repetición.',
                feedback: {
                  correct: 'Correcto.',
                  incorrect: 'Revisa la línea.',
                },
                difficulty: {
                  code: 'BEGINNER',
                  justification: 'Una expresión frecuente.',
                },
                items: [
                  {
                    exerciseItemId: '17600000-0000-7000-8000-000000000051',
                    itemType: 'OPTION',
                    itemOrder: 1,
                    label: '何度でも',
                    value: '何度でも',
                    metadataJson: JSON.stringify({ role: 'CORRECT', sourceTokenId: tokenId }),
                    isAccepted: true,
                  },
                  {
                    exerciseItemId: '17600000-0000-7000-8000-000000000052',
                    itemType: 'OPTION',
                    itemOrder: 2,
                    label: '何回でも',
                    value: '何回でも',
                    metadataJson: JSON.stringify({ role: 'DISTRACTOR' }),
                    isAccepted: false,
                  },
                  {
                    exerciseItemId: '17600000-0000-7000-8000-000000000053',
                    itemType: 'OPTION',
                    itemOrder: 3,
                    label: '叫ぶ',
                    value: '叫ぶ',
                    metadataJson: JSON.stringify({ role: 'DISTRACTOR' }),
                    isAccepted: false,
                  },
                ],
                solutions: ['何度でも'],
                provenance: [],
                completeness: {
                  hasContext: true,
                  hasOptions: true,
                  hasSolution: true,
                  hasExplanation: true,
                  hasDifficulty: true,
                  hasProvenance: false,
                  readyForReview: false,
                },
                warnings: ['Procedencia pendiente.'],
              },
            ],
          },
        ],
      }),
    });
  });

  await page.route(
    '**/api/v1/editorial/song-drafts/*/exercise-authoring-context',
    async (route) => {
      await route.fulfill({
        status: 200,
        headers: { ETag: '"fix-crud-001"' },
        contentType: 'application/json',
        body: JSON.stringify({
          recordingId,
          lyricsRevisionId,
          lyricsRevisionNo: 3,
          lyricsRevisionChecksumSha256: 'a'.repeat(64),
          canAuthor: true,
          blockingReason: null,
          competencies: [
            {
              code: 'VOCAB.CONTEXT',
              domainCode: 'VOCABULARY',
              title: 'Vocabulario en contexto',
              description: 'Reconocer vocabulario.',
            },
          ],
          lines: [
            {
              lineId,
              lineNo: 1,
              japaneseText: '何度でも叫ぶ',
              tokens: [
                { tokenId, tokenNo: 1, surface: '何度でも' },
                {
                  tokenId: '17600000-0000-7000-8000-000000000031',
                  tokenNo: 2,
                  surface: '叫ぶ',
                },
              ],
            },
          ],
        }),
      });
    },
  );
}

test.describe('FIX-MVP-EDITORIAL-CRUD-DESKTOP-001', () => {
  test('edita un ejercicio existente y usa el ancho de escritorio', async ({ page }) => {
    await page.setViewportSize({ width: 1536, height: 960 });
    await mockSession(page);
    await mockExerciseBank(page);

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);

    await expect(page.getByText('Gestión CRUD editorial segura')).toBeVisible();
    await expect(page.getByText('Crear', { exact: true })).toBeVisible();
    await expect(page.getByText('Consultar', { exact: true })).toBeVisible();
    await expect(page.getByText('Editar / corregir', { exact: true })).toBeVisible();
    await expect(page.getByText('Retirar / archivar', { exact: true })).toBeVisible();

    const width = await page
      .locator('[data-route-id="UI-MVP-025"]')
      .evaluate((element) => element.getBoundingClientRect().width);
    expect(width).toBeGreaterThan(1000);

    await page.getByRole('button', { name: 'Editar borrador' }).click();
    await expect(
      page.getByRole('heading', { name: 'Editar ejercicio de completar espacios' }),
    ).toBeVisible();

    await expect(page.getByRole('button', { name: /Línea 1/ })).toHaveClass(/is-selected/);
    await expect(page.getByRole('button', { name: '何度でも', exact: true }).first()).toHaveClass(
      /is-selected/,
    );

    await page.getByRole('button', { name: 'Siguiente: opciones' }).click();
    await expect(page.getByLabel('Distractor 1')).toHaveValue('何回でも');
    await expect(page.getByLabel('Distractor 2')).toHaveValue('叫ぶ');

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('mantiene 320 px sin overflow global', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);
    await mockExerciseBank(page);

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);

    await expect(page.getByText('Gestión CRUD editorial segura')).toBeVisible();
  });
});
