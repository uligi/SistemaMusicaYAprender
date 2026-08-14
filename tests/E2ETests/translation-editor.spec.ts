import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '16200000-0000-7000-8000-000000000001';
const lyricsRevisionId = '16200000-0000-7000-8000-000000000002';
const firstLineId = '16200000-0000-7000-8000-000000000011';
const secondLineId = '16200000-0000-7000-8000-000000000012';

function context(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    recordingId,
    lyricsRevisionId,
    lyricsRevisionNo: 4,
    targetLanguage: 'es',
    translationType: 'HUMAN',
    hasStaleRevision: false,
    sourceLines: [
      { lineId: firstLineId, lineNo: 1, japaneseText: '何度でも叫ぶ' },
      { lineId: secondLineId, lineNo: 2, japaneseText: 'ここに残しておきたいんだよ' },
    ],
    revision: {
      translationRevisionId: '16200000-0000-7000-8000-000000000003',
      lyricsRevisionId,
      lyricsRevisionNo: 4,
      targetLanguage: 'es',
      translationType: 'HUMAN',
      revisionNo: 2,
      parentRevisionId: null,
      statusCode: 'DRAFT',
      checksumSha256: 'a'.repeat(64),
      sourceLineCount: 2,
      literalCoveredLines: 1,
      naturalCoveredLines: 1,
      completeForReview: false,
      missingLiteralLineNos: [2],
      missingNaturalLineNos: [2],
      hasManyToManyAlignment: true,
      lines: [
        {
          translationLineId: '16200000-0000-7000-8000-000000000021',
          anchorLineId: firstLineId,
          anchorLineNo: 1,
          japaneseText: '何度でも叫ぶ',
          variantCode: 'LITERAL',
          translatedText: 'Grito una y otra vez',
          displayOrder: 0,
          alignments: [],
        },
        {
          translationLineId: '16200000-0000-7000-8000-000000000022',
          anchorLineId: firstLineId,
          anchorLineNo: 1,
          japaneseText: '何度でも叫ぶ',
          variantCode: 'NATURAL',
          translatedText: 'Sigo gritando una vez más',
          displayOrder: 1,
          alignments: [],
        },
      ],
      notes: [
        {
          noteId: '16200000-0000-7000-8000-000000000031',
          lineId: firstLineId,
          tokenId: null,
          noteType: 'EDITORIAL',
          noteText: 'La repetición mantiene el énfasis.',
          sourceReferenceId: null,
          sourceType: null,
          citation: null,
          locator: null,
        },
      ],
      provenance: [],
    },
    ...overrides,
  };
}

async function mockSession(
  page: import('@playwright/test').Page,
  capabilities: string[] = ['EDITORIAL.DRAFT', 'EDITORIAL.REVIEW'],
) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'EDITOR',
        roles: ['EDITOR'],
        capabilities,
      }),
    });
  });
}

test.describe('BL-MVP-062 · editor de traducción al español', () => {
  test('edita literal, natural y nota; guarda con CSRF + If-Match sin enviar japonés', async ({
    page,
  }) => {
    await mockSession(page);

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-bl062',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        headers: {
          'content-type': 'application/json',
          etag: '"translation-16200000000070008000000000000003-r2"',
        },
        body: JSON.stringify(context()),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts/*/translation-revisions', async (route) => {
      const saved = context();
      (saved.revision as { revisionNo: number; translationRevisionId: string }).revisionNo = 3;
      (
        saved.revision as { revisionNo: number; translationRevisionId: string }
      ).translationRevisionId = '16200000-0000-7000-8000-000000000004';

      await route.fulfill({
        status: 200,
        headers: {
          'content-type': 'application/json',
          etag: '"translation-16200000000070008000000000000004-r3"',
        },
        body: JSON.stringify(saved),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    await expect(page.getByRole('heading', { name: 'Editor de traducción' })).toBeVisible();
    await expect(
      page.locator('.translation-editor__japanese').filter({ hasText: /^何度でも叫ぶ$/ }),
    ).toBeVisible();
    await expect(page.getByText('Contexto de trabajo', { exact: false })).toBeVisible();
    await expect(page.getByText('1 de 2 completas', { exact: true })).toBeVisible();
    await expect(
      page.getByText('Revisión, alineaciones y procedencia', { exact: true }),
    ).toBeVisible();
    await expect(page.getByText('1 pendiente', { exact: false })).toBeVisible();

    const firstNatural = page.getByLabel('Español natural').first();
    await firstNatural.fill('Grito una y otra vez, otra vez');
    await page.getByLabel('Nota editorial').first().fill('Decisión revisada manualmente.');

    const saveRequestPromise = page.waitForRequest(
      '**/api/v1/editorial/song-drafts/*/translation-revisions',
    );
    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    const saveRequest = await saveRequestPromise;
    const postedHeaders = saveRequest.headers();
    const postedBody = saveRequest.postDataJSON() as Record<string, unknown>;

    await expect(page.getByText('Borrador de traducción guardado')).toBeVisible();

    expect(postedHeaders['if-match']).toBe('"translation-16200000000070008000000000000003-r2"');
    expect(postedHeaders['x-csrf-token']).toBe('csrf-bl062');

    expect(JSON.stringify(postedBody)).not.toContain('japaneseText');
    expect(postedBody.lyricsRevisionId).toBe(lyricsRevisionId);
    expect(postedBody.targetLanguage).toBe('es');
    expect(postedBody.translationType).toBe('HUMAN');

    const units = postedBody.units as Array<Record<string, unknown>>;
    expect(units).toHaveLength(2);
    expect(units[0]?.lineId).toBe(firstLineId);
    expect(units[0]?.naturalText).toBe('Grito una y otra vez, otra vez');
    expect(units[0]?.noteText).toBe('Decisión revisada manualmente.');

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('conserva el borrador ante conflicto y bloquea rebase automático si cambió la fuente', async ({
    page,
  }) => {
    await mockSession(page);

    let conflictTriggered = false;

    const nextLyricsRevisionId = '16200000-0000-7000-8000-000000000099';
    const nextLineId = '16200000-0000-7000-8000-000000000098';
    const nextContext = context({
      lyricsRevisionId: nextLyricsRevisionId,
      lyricsRevisionNo: 5,
      sourceLines: [{ lineId: nextLineId, lineNo: 1, japaneseText: '何度でも叫ぶよ' }],
      revision: null,
      hasStaleRevision: true,
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-bl062',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        headers: {
          'content-type': 'application/json',
          etag: conflictTriggered
            ? `"translation-${nextLyricsRevisionId.replaceAll('-', '')}-none"`
            : '"translation-16200000000070008000000000000003-r2"',
        },
        body: JSON.stringify(conflictTriggered ? nextContext : context()),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts/*/translation-revisions', async (route) => {
      conflictTriggered = true;
      await route.fulfill({
        status: 412,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          type: 'about:blank',
          title: 'La fuente o traducción cambió',
          status: 412,
          detail: 'La revisión japonesa cambió antes de guardar.',
          code: 'content.translation.source-changed',
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    const literal = page.getByLabel('Español literal').first();
    await literal.fill('Mi traducción local que no debe perderse');
    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();

    await expect(page.getByText('La fuente o traducción cambió', { exact: true })).toBeVisible();
    await expect(literal).toHaveValue('Mi traducción local que no debe perderse');

    await page.getByRole('button', { name: 'Comparar con servidor' }).click();

    await expect(page.getByRole('heading', { name: 'Comparación con el servidor' })).toBeVisible();
    await expect(page.getByText('La letra japonesa cambió', { exact: true })).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Conservar mi borrador sobre esta fuente' }),
    ).toBeDisabled();
    await expect(literal).toHaveValue('Mi traducción local que no debe perderse');
  });

  test('un revisor sin EDITORIAL.DRAFT conserva UI-MVP-023 en solo lectura', async ({ page }) => {
    await mockSession(page, ['EDITORIAL.REVIEW']);

    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        headers: {
          'content-type': 'application/json',
          etag: '"translation-16200000000070008000000000000003-r2"',
        },
        body: JSON.stringify(context()),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    await expect(page.getByText('Modo de revisión')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Editor de traducción' })).toHaveCount(0);
    await expect(
      page
        .locator('.translation-structure__source-details')
        .getByText('何度でも叫ぶ', { exact: true }),
    ).toBeVisible();
  });

  test('mantiene el editor usable a 320 px sin desbordamiento horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 });
    await mockSession(page);

    await page.route('**/api/v1/editorial/song-drafts/*/translation-context?*', async (route) => {
      await route.fulfill({
        status: 200,
        headers: {
          'content-type': 'application/json',
          etag: '"translation-16200000000070008000000000000003-r2"',
        },
        body: JSON.stringify(context()),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/traduccion`);

    await expect(page.getByRole('heading', { name: 'Editor de traducción' })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
