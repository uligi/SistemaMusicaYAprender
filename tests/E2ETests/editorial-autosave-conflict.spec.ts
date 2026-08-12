import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '22222222-2222-4222-8222-222222222222';

const dossier = {
  canonicalTitle: '怪獣',
  recordingTitle: 'Album version',
  artistName: 'サカナクション',
  recordingStatusCode: 'DRAFT',
  providerCode: 'YOUTUBE',
  externalRef: 'a8dgNdJVluc',
  sourceStatusCode: 'DRAFT',
  components: [
    {
      code: 'CATALOG',
      label: 'Catálogo',
      revisionLabel: 'v1',
      stateCode: 'DRAFT',
      ownerLabel: 'Tú',
      exists: true,
      href: null,
    },
  ],
  rights: {
    totalRecords: 0,
    activeRecords: 0,
    provenanceRecords: 0,
    ownerLabel: 'Sin responsable identificado',
    stateCode: 'NOT_STARTED',
  },
  incidents: [],
  allowedAccesses: [
    {
      code: 'DOSSIER',
      label: 'Expediente',
      href: `/editorial/canciones/${recordingId}`,
    },
  ],
};

function snapshot(title: string, recordingVersion: number, sourceVersion: number) {
  return {
    recordingId,
    sourceId: '33333333-3333-4333-8333-333333333333',
    recordingTitle: title,
    recordingDurationMs: 241125,
    sourceDurationMs: 245000,
    offsetMs: 2500,
    recordingStatusCode: 'DRAFT',
    sourceStatusCode: 'DRAFT',
    recordingVersion,
    sourceVersion,
  };
}

test.describe('BL-MVP-052 · autoguardado y conflictos editoriales', () => {
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
          requestToken: 'csrf-bl052',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route(`**/api/v1/editorial/song-dossiers/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(dossier),
      });
    });
  });

  test('muestra Guardando y Guardado enviando If-Match', async ({ page }) => {
    let putCount = 0;

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/autosave`, async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: '"recording-1-source-1"' },
          body: JSON.stringify(snapshot('Album version', 1, 1)),
        });
        return;
      }

      putCount += 1;
      expect(route.request().headers()['if-match']).toBe('"recording-1-source-1"');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-bl052');

      await new Promise((resolve) => setTimeout(resolve, 250));

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { ETag: '"recording-2-source-1"' },
        body: JSON.stringify(snapshot('Live edit', 2, 1)),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}`);
    await page.getByRole('button', { name: 'Editar metadatos' }).click();

    const title = page.getByLabel('Título de la grabación');
    await expect(title).toHaveValue('Album version');
    await title.fill('Live edit');

    await expect(page.getByText('Guardando…', { exact: true })).toBeVisible({
      timeout: 2500,
    });
    await expect(page.getByText('Guardado', { exact: true })).toBeVisible();
    expect(putCount).toBe(1);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('preserva lo local, compara y exige decisión explícita tras conflicto', async ({ page }) => {
    let getCount = 0;
    let putCount = 0;

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/autosave`, async (route) => {
      if (route.request().method() === 'GET') {
        getCount += 1;
        const server = getCount === 1 ? snapshot('Base', 1, 1) : snapshot('Cambio remoto', 2, 1);
        const etag = getCount === 1 ? '"recording-1-source-1"' : '"recording-2-source-1"';

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { ETag: etag },
          body: JSON.stringify(server),
        });
        return;
      }

      putCount += 1;

      if (putCount === 1) {
        expect(route.request().headers()['if-match']).toBe('"recording-1-source-1"');
        await route.fulfill({
          status: 412,
          contentType: 'application/problem+json',
          headers: { ETag: '"recording-2-source-1"' },
          body: JSON.stringify({
            type: 'about:blank',
            title: 'Hay una versión editorial más reciente',
            status: 412,
            detail: 'La versión confirmada cambió.',
            code: 'catalog.recording.autosave.conflict',
          }),
        });
        return;
      }

      expect(route.request().headers()['if-match']).toBe('"recording-2-source-1"');
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { ETag: '"recording-3-source-1"' },
        body: JSON.stringify(snapshot('Mi cambio local', 3, 1)),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}`);
    await page.getByRole('button', { name: 'Editar metadatos' }).click();

    const title = page.getByLabel('Título de la grabación');
    await title.fill('Mi cambio local');

    await expect(page.getByRole('heading', { name: 'Conflicto de edición' })).toBeVisible();
    await expect(title).toHaveValue('Mi cambio local');

    await page.getByRole('button', { name: 'Comparar con servidor' }).click();
    await expect(page.getByRole('heading', { name: 'Comparar cambios' })).toBeVisible();
    await expect(page.getByText('Cambio remoto', { exact: true })).toBeVisible();
    await expect(page.getByText('Mi cambio local', { exact: true })).toBeVisible();

    await page
      .getByRole('button', { name: 'Aplicar mis cambios sobre la versión vigente' })
      .click();

    await expect(page.getByText('Guardado', { exact: true })).toBeVisible();
    expect(putCount).toBe(2);
  });

  test('a 320px no introduce desbordamiento horizontal', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/autosave`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { ETag: '"recording-1-source-1"' },
        body: JSON.stringify(snapshot('Album version', 1, 1)),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}`);
    await page.getByRole('button', { name: 'Editar metadatos' }).click();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );

    expect(overflow).toBeLessThanOrEqual(1);
  });
});
