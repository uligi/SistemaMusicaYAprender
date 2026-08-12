import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const artistId = '11111111-1111-4111-8111-111111111111';
const workId = '22222222-2222-4222-8222-222222222222';
const recordingId = '33333333-3333-4333-8333-333333333333';
const sourceId = '44444444-4444-4444-8444-444444444444';

test.describe('BL-MVP-038 · obra, grabación y fuente de YouTube', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/v1/auth/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'AUTHENTICATED',
          role: 'STUDENT',
          roles: ['STUDENT', 'EDITOR'],
          capabilities: ['EDITORIAL.DRAFT'],
        }),
      });
    });

    await page.route('**/api/v1/auth/csrf', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          requestToken: 'csrf-song-draft-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });
  });

  test('selecciona artista y crea objetos separados después de revisar duplicados', async ({
    page,
  }) => {
    await page.route('**/api/v1/editorial/artists?query=*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([
          {
            artistId,
            canonicalName: 'サカナクション',
            artistType: 'BAND',
            statusCode: 'ACTIVE',
            matchedText: 'Sakanaction',
            similarity: 0.98,
          },
        ]),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts/duplicates', async (route) => {
      const request = route.request().postDataJSON() as Record<string, unknown>;

      expect(request.artistId).toBe(artistId);
      expect(request.canonicalTitle).toBe('怪獣');
      expect(request.youtubeReference).toBe('https://www.youtube.com/watch?v=a8dgNdJVluc');
      expect(request.exactRecordingConfirmed).toBe(true);
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-song-draft-e2e');

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          candidates: [],
          requiresAcknowledgement: false,
          hasExactSourceConflict: false,
        }),
      });
    });

    await page.route('**/api/v1/editorial/song-drafts', async (route) => {
      expect(route.request().method()).toBe('POST');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-song-draft-e2e');
      expect(route.request().headers()['idempotency-key']).toBeTruthy();

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          workId,
          recordingId,
          sourceId,
          artistId,
          canonicalTitle: '怪獣',
          recordingTitle: '怪獣',
          providerCode: 'YOUTUBE',
          externalRef: 'a8dgNdJVluc',
          statusCode: 'DRAFT',
          duplicateWarningAcknowledged: false,
          alreadyApplied: false,
        }),
      });
    });

    await page.goto('/editorial/canciones/nueva');

    await expect(page.locator('[data-route-id="UI-MVP-018"]')).toBeVisible();
    await expect(page.getByRole('heading', { level: 1, name: 'Nueva canción' })).toBeFocused();
    await expect(page.getByText('1. Artista canónico', { exact: true })).toBeVisible();
    await expect(page.getByText('Paso 1 de 3 · Artista canónico', { exact: true })).toBeVisible();

    await page.locator('#artist-search-query').fill('Sakanaction');
    await page.getByRole('button', { name: 'Buscar artista' }).click();
    await page.getByRole('button', { name: 'Usar サカナクション' }).click();

    await expect(
      page.getByRole('heading', {
        name: 'Completar el borrador de canción',
      }),
    ).toBeVisible();
    await expect(
      page.getByText('Paso 2 de 3 · Obra, grabación y fuente', { exact: true }),
    ).toBeVisible();

    await page.locator('#song-work-title').fill('怪獣');
    await page.locator('#song-recording-title').fill('怪獣');
    await page.locator('#song-recording-duration').fill('241.125');
    await page
      .locator('#song-youtube-reference')
      .fill('https://www.youtube.com/watch?v=a8dgNdJVluc');
    await page.locator('#song-source-duration').fill('245');
    await page.locator('#song-source-offset').fill('2.5');
    await page
      .getByLabel(
        'Confirmo editorialmente que esta referencia de YouTube corresponde exactamente a la grabación que estoy registrando.',
      )
      .check();

    await page.getByRole('button', { name: 'Revisar grabaciones duplicadas' }).click();
    await expect(
      page.getByText('No se encontraron grabaciones potencialmente duplicadas.'),
    ).toBeVisible();

    await page.getByRole('button', { name: 'Crear obra, grabación y fuente' }).click();

    await expect(page.getByText(workId)).toBeVisible();
    await expect(page.getByText(recordingId)).toBeVisible();
    await expect(page.getByText(sourceId)).toBeVisible();

    await expect(
      page.getByRole('link', { name: 'Abrir expediente de la canción' }),
    ).toHaveAttribute('href', `/editorial/canciones/${recordingId}`);
    await expect(page.getByText('Paso 3 de 3 · Borrador guardado', { exact: true })).toBeVisible();
    await expect(
      page.getByRole('link', { name: 'Continuar con derechos y procedencia' }),
    ).toHaveAttribute('href', `/editorial/canciones/${recordingId}/derechos`);
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('BL-MVP-045 presenta el asistente completo a 320px sin desbordamiento', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 1000 });
    await page.goto('/editorial/canciones/nueva');

    await expect(page.locator('[data-route-id="UI-MVP-018"]')).toBeVisible();
    await expect(page.getByText('1. Artista canónico', { exact: true })).toBeVisible();
    await expect(page.getByText('2. Obra, grabación y fuente', { exact: true })).toBeVisible();
    await expect(page.getByText('3. Borrador guardado', { exact: true })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(1);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('abre UI-MVP-019 como expediente agregado sin adelantar publicación', async ({ page }) => {
    await page.route(`**/api/v1/editorial/song-dossiers/${recordingId}`, async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          canonicalTitle: '怪獣',
          recordingTitle: '怪獣',
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
        }),
      });
    });

    await page.goto(`/editorial/canciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-019"]')).toBeVisible();
    await expect(
      page.getByRole('heading', {
        level: 1,
        name: 'Expediente editorial de canción',
      }),
    ).toBeVisible();
    await expect(page.getByRole('heading', { level: 2, name: '怪獣' })).toBeVisible();
    await expect(page.getByText('Sin incidencias abiertas', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Publicar' })).toHaveCount(0);

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
