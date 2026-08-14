import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '54000000-0000-4000-8000-000000000001';

function emptyResponse() {
  return {
    exists: false,
    revision: null,
  };
}

function revisionResponse(title = '怪獣', revisionNo = 1) {
  return {
    exists: true,
    revision: {
      lyricsRevisionId: `54000000-0000-4000-8000-${revisionNo.toString().padStart(12, '0')}`,
      recordingId,
      revisionNo,
      parentRevisionId: revisionNo > 1 ? '54000000-0000-4000-8000-000000000001' : null,
      statusCode: 'DRAFT',
      createdBy: '54000000-0000-4000-8000-000000000002',
      createdAt: '2026-08-12T23:50:00Z',
      checksumSha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      version: 1,
      sections: [
        {
          sectionId: '54000000-0000-4000-8000-000000000020',
          sectionType: 'VERSE',
          label: 'Verso 1',
          displayOrder: 0,
          lines: [
            {
              lineId: '54000000-0000-4000-8000-000000000030',
              lineNo: 1,
              japaneseText: title,
              normalizedText: title.normalize('NFC'),
              speakerLabel: 'Voz principal',
              tokens: [],
            },
          ],
        },
      ],
    },
  };
}

test.describe('BL-MVP-054 · editor estructurado de letra japonesa', () => {
  test.beforeEach(async ({ page }) => {
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

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-bl054',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
  });

  test('edita secciones, líneas y voces, marca desconocido y previsualiza sin publicar', async ({
    page,
  }) => {
    let postedBody: unknown = null;
    let postedIfMatch = '';

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: '"lyrics-none"' },
          body: JSON.stringify(emptyResponse()),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions`,
      async (route) => {
        postedBody = route.request().postDataJSON();
        postedIfMatch = route.request().headers()['if-match'] ?? '';

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: {
            ETag: '"lyrics-54000000000040008000000000000001-v1"',
          },
          body: JSON.stringify(revisionResponse()),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    await expect(page.getByRole('heading', { name: 'Editar letra japonesa' })).toBeVisible();

    const japanese = page.getByLabel('Japonés original');
    await japanese.fill('怪獣');

    await page.getByLabel('Voz / intérprete').fill('Voz principal');
    await page.getByRole('button', { name: 'Agregar línea' }).click();

    const unknown = page.getByLabel('Contenido desconocido').nth(1);
    await unknown.selectOption('INAUDIBLE');

    await page.getByRole('button', { name: 'Previsualizar borrador' }).click();

    const preview = page.getByRole('region', {
      name: 'Previsualización del borrador',
    });

    await expect(preview).toBeVisible();
    await expect(preview.getByText('怪獣', { exact: true })).toBeVisible();
    await expect(preview.getByText('Inaudible', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    await expect(page.getByText('Revisión guardada', { exact: true })).toBeVisible();

    expect(postedIfMatch).toBe('"lyrics-none"');
    expect(postedBody).toMatchObject({
      sections: [
        {
          sectionType: 'VERSE',
          lines: [
            {
              japaneseText: '怪獣',
              speakerLabel: 'Voz principal',
              tokens: [],
            },
            {
              japaneseText: '[UNKNOWN:INAUDIBLE]',
              tokens: [],
            },
          ],
        },
      ],
    });

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();

    expect(accessibility.violations).toEqual([]);
  });

  test('un ETag obsoleto conserva el borrador y permite comparar antes de rebasar', async ({
    page,
  }) => {
    let latestReads = 0;

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        latestReads += 1;
        const data =
          latestReads === 1
            ? revisionResponse('Versión inicial', 1)
            : revisionResponse('Cambio remoto', 2);
        const etag =
          latestReads === 1
            ? '"lyrics-54000000000040008000000000000001-v1"'
            : '"lyrics-54000000000040008000000000000002-v1"';

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: etag },
          body: JSON.stringify(data),
        });
      },
    );

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions`,
      async (route) => {
        await route.fulfill({
          status: 412,
          contentType: 'application/problem+json',
          body: JSON.stringify({
            type: 'about:blank',
            title: 'Hay una revisión de letra más reciente',
            status: 412,
            detail: 'La revisión base cambió antes de guardar.',
            code: 'content.lyrics.conflict',
          }),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    const japanese = page.getByLabel('Japonés original');
    await japanese.fill('Mi cambio local');

    await page.getByRole('button', { name: 'Guardar nueva revisión' }).click();
    await expect(page.getByRole('heading', { name: 'Conflicto de edición' })).toBeVisible();
    await expect(japanese).toHaveValue('Mi cambio local');

    await page.getByRole('button', { name: 'Comparar con servidor' }).click();
    await expect(page.getByRole('heading', { name: 'Comparar revisiones' })).toBeVisible();
    await expect(page.getByText('Tu borrador local', { exact: true })).toBeVisible();
    await expect(page.getByText('Versión vigente del servidor', { exact: true })).toBeVisible();

    await page
      .getByRole('button', { name: 'Mantener mis cambios sobre la versión vigente' })
      .click();

    await expect(japanese).toHaveValue('Mi cambio local');
  });

  test('mantiene el editor a 320px sin desbordamiento horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });

    await page.route(
      `**/api/v1/editorial/song-drafts/${recordingId}/lyrics-revisions/latest`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: '"lyrics-none"' },
          body: JSON.stringify(emptyResponse()),
        });
      },
    );

    await page.goto(`/editorial/canciones/${recordingId}/letra`);

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );

    expect(overflow).toBeLessThanOrEqual(1);
  });
});
