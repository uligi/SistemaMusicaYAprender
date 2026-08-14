import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16700000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16700000-0000-7000-8000-000000000002';
const lineId = '16700000-0000-7000-8000-000000000011';
const tokenId = '16700000-0000-7000-8000-000000000021';

function emptyContext() {
  return {
    recordingId,
    lyricsRevisionId,
    lyricsRevisionNo: 7,
    explanationLanguage: 'es',
    hasStaleRevision: false,
    sourceLines: [
      {
        lineId,
        lineNo: 1,
        sectionDisplayOrder: 0,
        sectionLabel: 'Verso',
        japaneseText: '学生です',
        tokens: [
          { tokenId, lineId, lineNo: 1, tokenNo: 1, surface: '学生', normalizedSurface: '学生' },
          {
            tokenId: '16700000-0000-7000-8000-000000000022',
            lineId,
            lineNo: 1,
            tokenNo: 2,
            surface: 'です',
            normalizedSurface: 'です',
          },
        ],
      },
    ],
    revision: null,
  };
}

function savedContext() {
  const context = emptyContext();
  return {
    ...context,
    revision: {
      analysisRevisionId: '16700000-0000-7000-8000-000000000003',
      lyricsRevisionId,
      lyricsRevisionNo: 7,
      revisionNo: 1,
      parentRevisionId: null,
      statusCode: 'DRAFT',
      checksumSha256: 'd'.repeat(64),
      sourceLineCount: 1,
      sourceTokenCount: 2,
      readingCoveredTokens: 1,
      vocabularyCoveredTokens: 1,
      kanjiCoveredTokens: 0,
      morphologyCoveredTokens: 0,
      grammarCoveredLines: 0,
      readings: [
        {
          tokenReadingId: '16700000-0000-7000-8000-000000000031',
          tokenId,
          lineId,
          lineNo: 1,
          surface: '学生',
          readingKana: 'がくせい',
          furigana: '学生[がくせい]',
          romaji: null,
          readingType: 'CONTEXTUAL',
        },
      ],
      vocabulary: [
        {
          occurrenceId: '16700000-0000-7000-8000-000000000041',
          tokenId,
          lineId,
          lineNo: 1,
          surface: '学生',
          vocabularyId: '16700000-0000-7000-8000-000000000042',
          lemma: '学生',
          reading: 'がくせい',
          partOfSpeech: 'NOUN',
          senseKey: 'editorial.student',
          inflection: null,
          confidenceCode: 'EDITORIAL',
          senses: [
            {
              senseId: '16700000-0000-7000-8000-000000000043',
              languageTag: 'es',
              definition: 'estudiante',
              usageNote: null,
              displayOrder: 0,
            },
          ],
        },
      ],
      kanji: [],
      morphology: [],
      grammar: [],
      provenance: [
        {
          sourceReferenceId: '16700000-0000-7000-8000-000000000051',
          sourceType: 'EDITORIAL',
          citation: 'Curaduría editorial interna',
          locator: null,
          contributionType: 'ANALYSIS_AUTHOR',
          recordedBy: '16700000-0000-7000-8000-000000000052',
          recordedAt: '2026-08-14T15:00:00Z',
        },
      ],
    },
  };
}

function editableExistingContext() {
  const context = savedContext();
  const baseVocabulary = context.revision.vocabulary[0]!;
  return {
    ...context,
    revision: {
      ...context.revision,
      revisionNo: 2,
      vocabulary: [
        {
          ...baseVocabulary,
          senses: [
            {
              senseId: '16700000-0000-7000-8000-000000000043',
              languageTag: 'es',
              definition: 'estudiante',
              usageNote: 'definición anterior',
              displayOrder: 0,
            },
            {
              senseId: '16700000-0000-7000-8000-000000000044',
              languageTag: 'es',
              definition: 'persona que estudia',
              usageNote: 'definición vigente',
              displayOrder: 1,
            },
          ],
        },
      ],
      kanjiCoveredTokens: 1,
      kanji: [
        {
          occurrenceId: '16700000-0000-7000-8000-000000000061',
          tokenId,
          lineId,
          lineNo: 1,
          surface: '学生',
          kanjiId: '16700000-0000-7000-8000-000000000062',
          character: '学',
          charOffset: 0,
          gradeCode: 'G1',
          jlptCode: 'N5',
          statusCode: 'ACTIVE',
          version: 3,
          readings: [
            {
              kanjiReadingId: '16700000-0000-7000-8000-000000000063',
              reading: 'まな',
              readingType: 'GENERAL',
              languageTag: 'es',
              meaning: 'lectura anterior',
              displayOrder: 0,
            },
            {
              kanjiReadingId: '16700000-0000-7000-8000-000000000064',
              reading: 'がく',
              readingType: 'GENERAL',
              languageTag: 'es',
              meaning: 'estudio',
              displayOrder: 1,
            },
          ],
        },
      ],
      grammarCoveredLines: 1,
      grammar: [
        {
          occurrenceId: '16700000-0000-7000-8000-000000000071',
          lineId,
          lineNo: 1,
          japaneseText: '学生です',
          grammarPointId: '16700000-0000-7000-8000-000000000072',
          grammarCode: 'EDITORIAL.COPULA',
          title: 'Cópula です',
          levelCode: 'N5',
          startTokenId: null,
          endTokenId: null,
          note: null,
          explanation: 'Explicación vigente.',
          examples: null,
        },
      ],
    },
  };
}

async function mockSession(page: import('@playwright/test').Page) {
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
}

async function mockCsrf(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ requestToken: 'csrf-analysis-167', headerName: 'X-CSRF-TOKEN' }),
    });
  });
}

async function mockContext(page: import('@playwright/test').Page) {
  await page.route('**/api/v1/editorial/song-drafts/*/analysis-context?*', async (route) => {
    await route.fulfill({
      status: 200,
      headers: { ETag: '"analysis-base-none"' },
      contentType: 'application/json',
      body: JSON.stringify(emptyContext()),
    });
  });
}

test.describe('BL-MVP-067 · espacio editorial de análisis lingüístico', () => {
  test('guía en tres pasos, previsualiza exactamente y guarda DRAFT', async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
    await mockContext(page);

    const externalRequests: string[] = [];
    page.on('request', (request) => {
      const url = new URL(request.url());
      if (url.hostname !== 'localhost' && url.hostname !== '127.0.0.1')
        externalRequests.push(request.url());
    });

    let validatedBody: unknown = null;
    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        validatedBody = route.request().postDataJSON();
        expect(route.request().headers()['if-match']).toBe('"analysis-base-none"');
        expect(route.request().headers()['x-csrf-token']).toBe('csrf-analysis-167');
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            canSave: true,
            errorCount: 0,
            warningCount: 1,
            orphanCount: 0,
            checksumSha256: 'abc123'.padEnd(64, '0'),
            coverage: {
              totalTokens: 2,
              readingTokens: 1,
              vocabularyTokens: 1,
              kanjiTokens: 0,
              morphologyTokens: 0,
              totalLines: 1,
              grammarLines: 0,
            },
            provenanceCitation: 'Curaduría editorial interna',
            issues: [
              {
                severity: 'WARNING',
                code: 'content.analysis.coverage.partial',
                message:
                  'El análisis es parcial. Puedes guardarlo así y continuar en otra revisión.',
                location: 'cobertura',
              },
            ],
          }),
        });
      },
    );

    await page.route('**/api/v1/editorial/song-drafts/*/analysis-revisions', async (route) => {
      expect(route.request().postDataJSON()).toEqual(validatedBody);
      await route.fulfill({
        status: 200,
        headers: { ETag: '"analysis-saved-r1"' },
        contentType: 'application/json',
        body: JSON.stringify(savedContext()),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await expect(page.getByRole('heading', { name: 'Preparar análisis de japonés' })).toBeVisible();
    await expect(page.getByText('No necesitas completar todo de una vez.')).toBeVisible();
    await expect(page.getByRole('link', { name: /Elige una línea y una palabra/ })).toBeVisible();
    await expect(page.getByRole('link', { name: /Completa solo lo que conozcas/ })).toBeVisible();
    await expect(page.getByRole('link', { name: /Revisa y guarda/ })).toBeVisible();

    await page.getByRole('button', { name: 'Añadir pronunciación' }).click();
    await page.getByLabel('Lectura en kana').fill('がくせい');
    await page.getByText('Vocabulario y significado').click();
    await page.getByRole('button', { name: 'Añadir significado' }).click();
    await page.getByLabel('Lectura', { exact: true }).fill('がくせい');
    await page.getByLabel('Significado contextual en español').fill('estudiante');
    await page.getByLabel('Categoría').selectOption('NOUN');

    await page.getByRole('button', { name: 'Validar borrador' }).click();
    await expect(page.getByRole('heading', { name: 'Todo listo para guardar' })).toBeVisible();
    await expect(page.getByText('0 huérfanos')).toBeVisible();
    await expect(page.getByText(/Puedes guardarlo así/)).toBeVisible();

    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    await expect(page.getByText('Revisión de análisis guardada')).toBeVisible();
    await expect(page.getByText(/Quedó como DRAFT/)).toBeVisible();
    expect(externalRequests).toEqual([]);
  });

  test('muestra huérfanos y bloquea guardado', async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
    await mockContext(page);

    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            canSave: false,
            errorCount: 1,
            warningCount: 0,
            orphanCount: 1,
            checksumSha256: 'bad'.padEnd(64, '0'),
            coverage: {
              totalTokens: 2,
              readingTokens: 0,
              vocabularyTokens: 0,
              kanjiTokens: 0,
              morphologyTokens: 0,
              totalLines: 1,
              grammarLines: 0,
            },
            provenanceCitation: 'Curaduría editorial interna',
            issues: [
              {
                severity: 'ERROR',
                code: 'content.analysis.token.orphan',
                message: 'Una lectura apunta a una palabra que ya no pertenece a la letra vigente.',
                location: 'token:old',
              },
            ],
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await page.getByRole('button', { name: 'Validar borrador' }).click();
    await expect(page.getByText('1 huérfanos')).toBeVisible();
    await expect(page.getByText(/ya no pertenece a la letra vigente/)).toBeVisible();
    await expect(page.getByRole('button', { name: 'Guardar nueva revisión' })).toBeDisabled();
  });

  test('conflicto conserva el borrador visible', async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
    await mockContext(page);

    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            canSave: true,
            errorCount: 0,
            warningCount: 0,
            orphanCount: 0,
            checksumSha256: 'ok'.padEnd(64, '0'),
            coverage: {
              totalTokens: 2,
              readingTokens: 1,
              vocabularyTokens: 0,
              kanjiTokens: 0,
              morphologyTokens: 0,
              totalLines: 1,
              grammarLines: 0,
            },
            provenanceCitation: 'Curaduría editorial interna',
            issues: [],
          }),
        });
      },
    );

    await page.route('**/api/v1/editorial/song-drafts/*/analysis-revisions', async (route) => {
      await route.fulfill({
        status: 412,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          status: 412,
          title: 'La letra o el análisis cambió',
          detail: 'Recarga el análisis antes de continuar.',
          code: 'content.analysis.conflict',
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await page.getByRole('button', { name: 'Añadir pronunciación' }).click();
    const reading = page.getByLabel('Lectura en kana');
    await reading.fill('がくせい');
    await page.getByRole('button', { name: 'Validar borrador' }).click();
    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    await expect(reading).toHaveValue('がくせい');
    await expect(page.getByText(/Lo que escribiste sigue en pantalla/)).toBeVisible();
  });

  test('valida lectura y significado de kanji como pareja antes de guardar', async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
    await mockContext(page);

    let validationRequests = 0;
    page.on('request', (request) => {
      if (request.method() === 'POST' && request.url().includes('/analysis-revisions/validate')) {
        validationRequests += 1;
      }
    });

    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        const body = route.request().postDataJSON() as {
          kanji: Array<{ reading: string | null; meaning: string | null }>;
        };
        expect(body.kanji[0]?.reading).toBe('がく');
        expect(body.kanji[0]?.meaning).toBeNull();

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            canSave: false,
            errorCount: 1,
            warningCount: 0,
            orphanCount: 0,
            checksumSha256: 'pair'.padEnd(64, '0'),
            coverage: {
              totalTokens: 2,
              readingTokens: 0,
              vocabularyTokens: 0,
              kanjiTokens: 1,
              morphologyTokens: 0,
              totalLines: 1,
              grammarLines: 0,
            },
            provenanceCitation: 'Curaduría editorial interna',
            issues: [
              {
                severity: 'ERROR',
                code: 'content.analysis.kanji.reading-pair.required',
                message:
                  'Completa lectura general y significado educativo juntos, o deja ambos vacíos.',
                location: `token:${tokenId.replaceAll('-', '')}`,
              },
            ],
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);
    await page.getByText('Kanji de esta palabra').click();
    await page.getByRole('button', { name: 'Preparar kanji escritos en la palabra' }).click();
    await page
      .getByLabel(/Lectura general/)
      .first()
      .fill('がく');

    await page.getByRole('button', { name: 'Validar borrador' }).click();

    await expect(
      page.getByText(/necesita lectura general y significado educativo juntos, o ambos vacíos/),
    ).toBeVisible();
    expect(validationRequests).toBe(0);
    await expect(page.getByRole('button', { name: 'Guardar nueva revisión' })).toBeDisabled();
  });

  test('edita una revisión existente sin perder los últimos valores estables', async ({ page }) => {
    await mockSession(page);
    await mockCsrf(page);
    const existing = editableExistingContext();

    await page.route('**/api/v1/editorial/song-drafts/*/analysis-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        headers: { ETag: '"analysis-existing-r2"' },
        contentType: 'application/json',
        body: JSON.stringify(existing),
      });
    });

    let validatedBody: {
      vocabulary: Array<{ definition: string; usageNote: string | null }>;
      kanji: Array<{
        reading: string | null;
        meaning: string | null;
        gradeCode: string | null;
        jlptCode: string | null;
      }>;
      grammar: Array<{
        title: string;
        levelCode: string | null;
        explanation: string | null;
      }>;
    } | null = null;

    await page.route(
      '**/api/v1/editorial/song-drafts/*/analysis-revisions/validate',
      async (route) => {
        validatedBody = route.request().postDataJSON() as typeof validatedBody;
        expect(validatedBody?.vocabulary[0]).toMatchObject({
          definition: 'persona estudiante',
          usageNote: 'nota editorial actualizada',
        });
        expect(validatedBody?.kanji[0]).toMatchObject({
          reading: 'がく',
          meaning: 'aprendizaje',
          gradeCode: 'G2',
          jlptCode: 'N4',
        });
        expect(validatedBody?.grammar[0]).toMatchObject({
          title: 'Cópula cortés です',
          levelCode: 'N4',
          explanation: 'Explicación editorial actualizada.',
        });

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            canSave: true,
            errorCount: 0,
            warningCount: 1,
            orphanCount: 0,
            checksumSha256: 'edit'.padEnd(64, '0'),
            coverage: {
              totalTokens: 2,
              readingTokens: 1,
              vocabularyTokens: 1,
              kanjiTokens: 1,
              morphologyTokens: 0,
              totalLines: 1,
              grammarLines: 1,
            },
            provenanceCitation: 'Curaduría editorial interna',
            issues: [
              {
                severity: 'WARNING',
                code: 'content.analysis.coverage.partial',
                message:
                  'El análisis es parcial. Puedes guardarlo así y continuar en otra revisión.',
                location: 'cobertura',
              },
            ],
          }),
        });
      },
    );

    await page.route('**/api/v1/editorial/song-drafts/*/analysis-revisions', async (route) => {
      expect(route.request().postDataJSON()).toEqual(validatedBody);
      await route.fulfill({
        status: 200,
        headers: { ETag: '"analysis-existing-r3"' },
        contentType: 'application/json',
        body: JSON.stringify(existing),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    await page.getByText('Vocabulario y significado').click();
    await expect(page.getByLabel('Significado contextual en español')).toHaveValue(
      'persona que estudia',
    );
    await expect(page.getByLabel('Nota de uso opcional')).toHaveValue('definición vigente');
    await page.getByLabel('Significado contextual en español').fill('persona estudiante');
    await page.getByLabel('Nota de uso opcional').fill('nota editorial actualizada');

    await page.getByText('Kanji de esta palabra').click();
    await expect(page.getByLabel(/Lectura general/)).toHaveValue('がく');
    await expect(page.getByLabel(/Significado educativo/)).toHaveValue('estudio');
    await page.getByLabel(/Significado educativo/).fill('aprendizaje');
    await page.getByLabel(/Nivel escolar/).selectOption('G2');
    await page.getByLabel('JLPT orientativo', { exact: true }).selectOption('N4');

    await page.getByText('Gramática de la línea').click();
    await page.getByLabel('Nombre claro').fill('Cópula cortés です');
    await page.getByLabel('Nivel JLPT orientativo', { exact: true }).selectOption('N4');
    await page
      .getByLabel('Explicación en español opcional')
      .fill('Explicación editorial actualizada.');

    await page.getByRole('button', { name: 'Validar borrador' }).click();
    await expect(page.getByRole('heading', { name: 'Todo listo para guardar' })).toBeVisible();

    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    await expect(page.getByText('Revisión de análisis guardada')).toBeVisible();
  });

  test('refluye a 320 px y pasa axe', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);
    await mockContext(page);
    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    const tokenButton = page.getByRole('button', { name: '学生', exact: true });
    const box = await tokenButton.boundingBox();
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('mantiene una canción larga dentro del panel de líneas sin invadir el contenido siguiente', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await mockSession(page);

    const context = emptyContext();
    context.sourceLines = Array.from({ length: 40 }, (_, index) => {
      const lineSuffix = String(index + 1).padStart(12, '0');
      const tokenSuffix = String(index + 101).padStart(12, '0');
      const currentLineId = `16700000-0000-7000-8000-${lineSuffix}`;

      return {
        lineId: currentLineId,
        lineNo: index + 1,
        sectionDisplayOrder: 0,
        sectionLabel: 'Verso largo',
        japaneseText: `長い曲のテスト行 ${index + 1}`,
        tokens: [
          {
            tokenId: `16700000-0000-7000-8001-${tokenSuffix}`,
            lineId: currentLineId,
            lineNo: index + 1,
            tokenNo: 1,
            surface: `語${index + 1}`,
            normalizedSurface: `語${index + 1}`,
          },
        ],
      };
    });

    await page.route('**/api/v1/editorial/song-drafts/*/analysis-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        headers: { ETag: '"analysis-base-none"' },
        contentType: 'application/json',
        body: JSON.stringify(context),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/analisis`);

    const linesPanel = page.locator('.analysis-editor__lines');
    const lineList = page.locator('.analysis-editor__line-list');
    const workspace = page.locator('.analysis-editor__workspace');

    await expect(linesPanel).toBeVisible();
    await expect(lineList).toBeVisible();

    const metrics = await lineList.evaluate((element) => ({
      clientHeight: element.clientHeight,
      scrollHeight: element.scrollHeight,
    }));
    expect(metrics.scrollHeight).toBeGreaterThan(metrics.clientHeight);

    const panelBox = await linesPanel.boundingBox();
    const listBox = await lineList.boundingBox();
    const workspaceBox = await workspace.boundingBox();

    expect(panelBox).not.toBeNull();
    expect(listBox).not.toBeNull();
    expect(workspaceBox).not.toBeNull();

    expect((listBox?.y ?? 0) + (listBox?.height ?? 0)).toBeLessThanOrEqual(
      (panelBox?.y ?? 0) + (panelBox?.height ?? 0) + 1,
    );
    expect((panelBox?.y ?? 0) + (panelBox?.height ?? 0)).toBeLessThanOrEqual(
      (workspaceBox?.y ?? 0) + (workspaceBox?.height ?? 0) + 1,
    );

    await lineList.evaluate((element) => {
      element.scrollTop = element.scrollHeight;
    });

    await expect(page.getByRole('button', { name: /Línea 40/ })).toBeVisible();
  });
});
