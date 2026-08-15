import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '17100000-0000-7000-8000-000000000001';
const revisionId = '17100000-0000-7000-8000-000000000010';
const lineId = '17100000-0000-7000-8000-000000000020';
const tokenId = '17100000-0000-7000-8000-000000000030';

const emptyBank = {
  recordingId,
  exerciseCount: 0,
  exercises: [],
};

const context = {
  recordingId,
  lyricsRevisionId: revisionId,
  lyricsRevisionNo: 4,
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
          tokenId: '17100000-0000-7000-8000-000000000031',
          tokenNo: 2,
          surface: '叫ぶ',
        },
      ],
    },
  ],
};

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

async function mockBase(page: import('@playwright/test').Page) {
  await mockSession(page);

  await page.route('**/api/v1/editorial/song-drafts/*/exercise-bank', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(emptyBank),
    });
  });

  await page.route(
    '**/api/v1/editorial/song-drafts/*/exercise-authoring-context',
    async (route) => {
      await route.fulfill({
        status: 200,
        headers: { ETag: '"bl071-test"' },
        contentType: 'application/json',
        body: JSON.stringify(context),
      });
    },
  );

  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        requestToken: 'csrf-bl071',
        headerName: 'X-CSRF-TOKEN',
      }),
    });
  });
}

async function reachOptions(page: import('@playwright/test').Page) {
  await page.getByRole('button', { name: 'Crear mi primer ejercicio' }).click();
  await page.getByRole('button', { name: /Línea 1/ }).click();
  await page.getByRole('button', { name: '何度でも', exact: true }).click();
  await page.getByRole('button', { name: 'Siguiente: opciones' }).click();
}

async function completeDraft(page: import('@playwright/test').Page) {
  await reachOptions(page);
  await page.getByLabel('Distractor 1').fill('何回でも');
  await page.getByLabel('Distractor 2').fill('叫ぶ');
  await page.getByRole('button', { name: 'Siguiente: explicación' }).click();
  await page.getByLabel('Explicación educativa').fill('何度でも expresa repetición en contexto.');
  await page.getByLabel('Si acierta').fill('¡Correcto! Identificaste la expresión en su contexto.');
  await page.getByLabel('Si falla').fill('Casi. Vuelve a leer la línea y compara las opciones.');
  await page.getByLabel('¿Por qué?').fill('Una línea breve con una única respuesta contextual.');

  const previewButton = page.getByRole('button', { name: 'Probar borrador', exact: true });
  await expect(previewButton).toBeEnabled();
  await previewButton.click();
}

test.describe('BL-MVP-071 · autoría amigable de completar espacios', () => {
  test('guía en cuatro pasos, permite probar DRAFT y guarda con CSRF + If-Match', async ({
    page,
  }) => {
    await mockBase(page);

    let savedRequest: import('@playwright/test').Request | null = null;
    await page.route(
      '**/api/v1/editorial/song-drafts/*/fill-blank-exercise-drafts',
      async (route) => {
        savedRequest = route.request();
        await route.fulfill({
          status: 200,
          headers: { ETag: '"bl071-test-after-save"' },
          contentType: 'application/json',
          body: JSON.stringify({
            exerciseId: '17100000-0000-7000-8000-000000000040',
            exerciseRevisionId: '17100000-0000-7000-8000-000000000041',
            revisionNo: 1,
            version: 1,
            statusCode: 'DRAFT',
            message: 'Borrador guardado.',
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);
    await completeDraft(page);

    await expect(page.getByText('BORRADOR · NO PUBLICADO')).toBeVisible();
    await expect(page.getByText('＿＿＿叫ぶ')).toBeVisible();

    await page.getByRole('button', { name: '何度でも' }).last().click();
    await page.getByRole('button', { name: 'Comprobar en vista previa' }).click();
    await expect(page.getByText('✓ Correcto')).toBeVisible();

    await page.getByRole('button', { name: 'Guardar borrador' }).click();

    await expect.poll(() => savedRequest !== null).toBe(true);
    const request = savedRequest!;
    expect(request.headers()['if-match']).toBe('"bl071-test"');
    expect(request.headers()['x-csrf-token']).toBe('csrf-bl071');

    const body = request.postDataJSON() as {
      lyricsRevisionId: string;
      lineId: string;
      tokenId: string;
      distractors: string[];
      competencyCode: string;
    };
    expect(body.lyricsRevisionId).toBe(revisionId);
    expect(body.lineId).toBe(lineId);
    expect(body.tokenId).toBe(tokenId);
    expect(body.distractors).toEqual(['何回でも', '叫ぶ']);
    expect(body.competencyCode).toBe('VOCAB.CONTEXT');
  });

  test('bloquea distractores ambiguos o repetidos antes de enviar', async ({ page }) => {
    await mockBase(page);

    let writes = 0;
    await page.route(
      '**/api/v1/editorial/song-drafts/*/fill-blank-exercise-drafts',
      async (route) => {
        writes += 1;
        await route.abort();
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);
    await reachOptions(page);

    await page.getByLabel('Distractor 1').fill('  何度でも ');
    await page.getByLabel('Distractor 2').fill('何度でも');

    await expect(page.getByText('Un distractor coincide con la respuesta correcta.')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Siguiente: explicación' })).toBeDisabled();
    expect(writes).toBe(0);
  });

  test('un 412 conserva el borrador visible y explica que cambió la fuente', async ({ page }) => {
    await mockBase(page);

    await page.route(
      '**/api/v1/editorial/song-drafts/*/fill-blank-exercise-drafts',
      async (route) => {
        await route.fulfill({
          status: 412,
          contentType: 'application/problem+json',
          body: JSON.stringify({
            type: 'about:blank',
            title: 'La fuente DRAFT cambió',
            status: 412,
            detail: 'La revisión DRAFT de la letra cambió. Tu borrador sigue en pantalla.',
            code: 'learning.fill-blank.source-changed',
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);
    await completeDraft(page);
    await page.getByRole('button', { name: 'Guardar borrador' }).click();

    await expect(page.getByText('La fuente DRAFT cambió')).toBeVisible();
    await expect(page.getByRole('button', { name: '何回でも' })).toBeVisible();
    await expect(page.getByText('BORRADOR · NO PUBLICADO')).toBeVisible();
  });

  test('mantiene el creador y la vista previa accesibles a 320 px', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockBase(page);

    await page.goto(`/editorial/canciones/${recordingId}/ejercicios`);
    await completeDraft(page);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
