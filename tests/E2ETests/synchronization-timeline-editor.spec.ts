import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

const recordingId = '11111111-1111-7111-8111-111111111111';
const lyricsRevisionId = '22222222-2222-7222-8222-222222222222';
const sourceId = '33333333-3333-7333-8333-333333333333';

type PostedTimingRevision = {
  expectedRevisionNo: number | null;
  lyricsRevisionId: string;
  sourceId: string;
  lines: Array<{
    lineId: string;
    startMs: number | null;
    endMs: number | null;
    tokens: Array<{
      tokenId: string;
      startMs: number | null;
      endMs: number | null;
    }>;
  }>;
};

const lyrics = {
  exists: true,
  revision: {
    lyricsRevisionId,
    recordingId,
    revisionNo: 2,
    parentRevisionId: null,
    statusCode: 'DRAFT',
    createdBy: '44444444-4444-7444-8444-444444444444',
    createdAt: '2026-08-12T00:00:00Z',
    checksumSha256: 'a'.repeat(64),
    version: 2,
    sections: [
      {
        sectionId: '55555555-5555-7555-8555-555555555555',
        sectionType: 'VERSE',
        label: 'Verso 1',
        displayOrder: 0,
        lines: [
          {
            lineId: '66666666-6666-7666-8666-666666666666',
            lineNo: 1,
            japaneseText: '怪獣です',
            normalizedText: '怪獣です',
            speakerLabel: 'voz principal',
            tokens: [
              {
                tokenId: '77777777-7777-7777-8777-777777777777',
                tokenNo: 1,
                surface: '怪獣',
                normalizedSurface: '怪獣',
                startOffset: 0,
                endOffset: 2,
              },
              {
                tokenId: '88888888-8888-7888-8888-888888888888',
                tokenNo: 2,
                surface: 'です',
                normalizedSurface: 'です',
                startOffset: 2,
                endOffset: 4,
              },
            ],
          },
          {
            lineId: '99999999-9999-7999-8999-999999999999',
            lineNo: 2,
            japaneseText: '次の行',
            normalizedText: '次の行',
            speakerLabel: 'voz principal',
            tokens: [],
          },
        ],
      },
    ],
  },
};

const firstSection = lyrics.revision.sections[0]!;
const firstLine = firstSection.lines[0]!;
const firstToken = firstLine.tokens[0]!;
const secondToken = firstLine.tokens[1]!;

function context(revisionNo: number | null = null) {
  return {
    recordingId,
    lyricsRevisionId,
    lyricsRevisionNo: 2,
    sources: [
      {
        sourceId,
        providerCode: 'YOUTUBE',
        externalRef: 'a8dgNdJVluc',
        durationMs: 10_000,
        sourceOffsetMs: 0,
        statusCode: 'DRAFT',
        timingRevision:
          revisionNo === null
            ? null
            : {
                timingRevisionId: 'aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa',
                lyricsRevisionId,
                sourceId,
                revisionNo,
                offsetMs: 0,
                statusCode: 'DRAFT',
                checksumSha256: 'b'.repeat(64),
                lines: [
                  {
                    lineId: firstLine.lineId,
                    sectionOrder: 0,
                    lineNo: 1,
                    japaneseText: '怪獣です',
                    speakerLabel: 'voz principal',
                    precisionCode: 'LINE',
                    startMs: 1000,
                    endMs: 2200,
                    tokens: [],
                  },
                ],
              },
      },
    ],
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
        capabilities: ['EDITORIAL.DRAFT'],
      }),
    });
  });
}

async function mockBase(page: import('@playwright/test').Page, revisionNo: number | null = null) {
  await mockSession(page);

  await page.route('**/api/v1/editorial/song-drafts/*/synchronization-context', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(context(revisionNo)),
    });
  });

  await page.route('**/api/v1/editorial/song-drafts/*/lyrics-revisions/latest', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      headers: { ETag: '"lyrics-2"' },
      body: JSON.stringify(lyrics),
    });
  });

  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({ requestToken: 'csrf-057', headerName: 'X-CSRF-TOKEN' }),
    });
  });
}

test.describe('BL-MVP-057 · editor de línea de tiempo', () => {
  test('marca tokens, desplaza selección, previsualiza y guarda un borrador parcial', async ({
    page,
  }) => {
    await mockBase(page);

    const capture: { posted: PostedTimingRevision | null } = { posted: null };

    await page.route('**/api/v1/editorial/song-drafts/*/timing-revisions', async (route) => {
      capture.posted = route.request().postDataJSON() as PostedTimingRevision;
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-057');

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          timingRevisionId: 'aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa',
          lyricsRevisionId,
          sourceId,
          revisionNo: 1,
          offsetMs: 0,
          statusCode: 'DRAFT',
          checksumSha256: 'c'.repeat(64),
          lines: [
            {
              lineId: firstLine.lineId,
              sectionOrder: 0,
              lineNo: 1,
              japaneseText: '怪獣です',
              speakerLabel: 'voz principal',
              precisionCode: 'TOKEN',
              startMs: 1100,
              endMs: 2300,
              tokens: [
                {
                  tokenId: firstToken.tokenId,
                  tokenNo: 1,
                  surface: '怪獣',
                  startMs: 1100,
                  endMs: 1600,
                },
                {
                  tokenId: secondToken.tokenId,
                  tokenNo: 2,
                  surface: 'です',
                  startMs: 1600,
                  endMs: 2300,
                },
              ],
            },
          ],
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await expect(page.getByRole('heading', { name: 'Editor de línea de tiempo' })).toBeVisible();
    await page.getByLabel('Precisión línea 1').selectOption('TOKEN');
    await page.getByLabel('Inicio token 1 línea 1 (ms)').fill('1000');
    await page.getByLabel('Fin token 1 línea 1 (ms)').fill('1500');
    await page.getByLabel('Inicio token 2 línea 1 (ms)').fill('1500');
    await page.getByLabel('Fin token 2 línea 1 (ms)').fill('2200');

    await page.getByLabel('Seleccionar línea 1 para desplazamiento').check();
    await page.getByLabel('Desplazamiento múltiple (ms)').fill('100');
    await page.getByRole('button', { name: 'Desplazar selección' }).click();

    await expect(page.getByLabel('Inicio token 1 línea 1 (ms)')).toHaveValue('1100');
    await expect(page.getByLabel('Fin token 2 línea 1 (ms)')).toHaveValue('2300');

    await page.getByLabel('Tiempo de vista previa (ms)').fill('1700');
    await expect(page.getByText('Línea activa:', { exact: false })).toContainText('línea 1');

    await expect(page.getByText('Borrador parcial: 1 de 2 líneas temporizadas.')).toBeVisible();
    await page.getByRole('button', { name: 'Guardar borrador temporal' }).click();

    await expect(page.getByText('Borrador temporal guardado · revisión 1')).toBeVisible();

    const posted = capture.posted;
    expect(posted).not.toBeNull();
    if (posted === null) {
      throw new Error('El E2E esperaba capturar el POST de sincronización.');
    }

    expect(posted.expectedRevisionNo).toBeNull();
    expect(posted.lyricsRevisionId).toBe(lyricsRevisionId);
    expect(posted.sourceId).toBe(sourceId);
    expect(posted.lines).toHaveLength(1);

    const postedLine = posted.lines[0];
    expect(postedLine).toBeDefined();
    if (!postedLine) {
      throw new Error('El E2E esperaba una línea temporizada en el POST.');
    }

    expect(postedLine.startMs).toBeNull();
    expect(postedLine.endMs).toBeNull();
    expect(postedLine.tokens).toEqual([
      {
        tokenId: firstToken.tokenId,
        startMs: 1100,
        endMs: 1600,
      },
      {
        tokenId: secondToken.tokenId,
        startMs: 1600,
        endMs: 2300,
      },
    ]);

    const accessibilityScanResults = await new AxeBuilder({ page }).analyze();
    expect(accessibilityScanResults.violations).toEqual([]);
  });

  test('bloquea tiempos negativos, invertidos y fuera de duración antes del POST', async ({
    page,
  }) => {
    await mockBase(page);

    let postCount = 0;
    await page.route('**/api/v1/editorial/song-drafts/*/timing-revisions', async (route) => {
      postCount += 1;
      await route.abort();
    });

    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);
    await page.getByLabel('Inicio línea 1 (ms)').fill('-10');
    await page.getByLabel('Fin línea 1 (ms)').fill('12000');

    await expect(
      page.getByText('el inicio no puede ser negativo.', { exact: false }),
    ).toBeVisible();
    await expect(
      page.getByText('fuera de la duración confirmada de la fuente.', { exact: false }),
    ).toBeVisible();
    await expect(page.getByRole('button', { name: 'Guardar borrador temporal' })).toBeDisabled();
    expect(postCount).toBe(0);

    await page.getByLabel('Inicio línea 1 (ms)').fill('2000');
    await page.getByLabel('Fin línea 1 (ms)').fill('1500');
    await expect(
      page.getByText('el fin debe ser posterior al inicio.', { exact: false }),
    ).toBeVisible();
  });

  test('un HTTP 409 conserva el borrador y expone la revisión vigente sin sobrescribir', async ({
    page,
  }) => {
    await mockBase(page, 2);

    let contextReads = 0;
    await page.unroute('**/api/v1/editorial/song-drafts/*/synchronization-context');
    await page.route('**/api/v1/editorial/song-drafts/*/synchronization-context', async (route) => {
      contextReads += 1;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(context(contextReads > 1 ? 3 : 2)),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts/*/timing-revisions', async (route) => {
      const body = route.request().postDataJSON();
      expect(body.expectedRevisionNo).toBe(2);

      await route.fulfill({
        status: 409,
        contentType: 'application/problem+json',
        body: JSON.stringify({
          type: 'about:blank',
          title: 'Conflicto de sincronización',
          status: 409,
          detail:
            'La sincronización cambió en el servidor desde que abriste este borrador. Conserva tus cambios y compara antes de volver a guardar.',
          code: 'content.timing.revision.conflict',
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);
    await page.getByLabel('Inicio línea 1 (ms)').fill('1200');
    await page.getByLabel('Fin línea 1 (ms)').fill('2500');
    await page.getByRole('button', { name: 'Guardar borrador temporal' }).click();

    await expect(page.getByText('Conflicto de sincronización')).toBeVisible();
    await expect(page.getByText('Servidor: revisión 3', { exact: false })).toBeVisible();
    await expect(page.getByLabel('Inicio línea 1 (ms)')).toHaveValue('1200');
    await expect(page.getByLabel('Fin línea 1 (ms)')).toHaveValue('2500');
  });

  test('mantiene el editor a 320px sin desbordamiento horizontal', async ({ page }) => {
    await mockBase(page);
    await page.setViewportSize({ width: 320, height: 900 });
    await page.goto(`/editorial/canciones/${recordingId}/sincronizacion`);

    await expect(page.getByRole('heading', { name: 'Editor de línea de tiempo' })).toBeVisible();

    const listStyle = await page
      .locator('.synchronization-timeline-editor__lines')
      .evaluate((element) => window.getComputedStyle(element).listStyleType);
    expect(listStyle).toBe('none');

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);
  });
});
