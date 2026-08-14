import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

const recordingId = '11111111-1111-4111-8111-111111111111';
const artistId = '22222222-2222-4222-8222-222222222222';
const creditId = '33333333-3333-4333-8333-333333333333';
const sourceReferenceId = '44444444-4444-4444-8444-444444444444';
const provenanceId = '55555555-5555-4555-8555-555555555555';

test.describe('BL-MVP-039 · créditos, participantes y procedencia', () => {
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
          requestToken: 'csrf-credit-e2e',
          headerName: 'X-CSRF-TOKEN',
        }),
      });
    });

    await page.route('**/api/v1/editorial/artists?query=*', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([
          {
            artistId,
            canonicalName: 'Sakanaction',
            artistType: 'GROUP',
            statusCode: 'ACTIVE',
            matchedText: 'Sakanaction',
            similarity: 1,
          },
        ]),
      });
    });

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/credits`, async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([]),
        });
        return;
      }

      const request = route.request().postDataJSON() as Record<string, unknown>;
      expect(request.artistId).toBe(artistId);
      expect(request.displayName).toBe('Sakanaction');
      expect(request.roleCode).toBe('PERFORMER');
      expect(request.displayOrder).toBe(0);
      expect(request.sourceType).toBe('OFFICIAL_CREDIT');
      expect(request.citation).toBe('Créditos oficiales del lanzamiento');
      expect(request.verificationCode).toBe('VERIFIED');
      expect(route.request().headers()['x-csrf-token']).toBe('csrf-credit-e2e');
      expect(route.request().headers()['idempotency-key']).toBeTruthy();

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          credit: {
            creditId,
            recordingId,
            artistId,
            displayName: 'Sakanaction',
            roleCode: 'PERFORMER',
            displayOrder: 0,
            sourceReferenceId,
            sourceType: 'OFFICIAL_CREDIT',
            citation: 'Créditos oficiales del lanzamiento',
            locator: null,
            retrievedAt: '2026-08-12T00:00:00Z',
            provenanceId,
            verificationCode: 'VERIFIED',
            pendingIdentity: false,
          },
          alreadyApplied: false,
        }),
      });
    });
  });

  test('registra identidad estable, rol, orden, fuente y verificación', async ({ page }) => {
    await page.goto(`/editorial/canciones/${recordingId}/derechos`);

    await expect(
      page.getByRole('heading', { level: 1, name: 'Créditos, participantes y procedencia' }),
    ).toBeVisible();

    await page.locator('#credit-artist-query').fill('Sakanaction');
    await page.getByRole('button', { name: 'Buscar identidad' }).click();
    await page.getByRole('button', { name: 'Usar Sakanaction' }).click();

    await page.locator('#credit-citation').fill('Créditos oficiales del lanzamiento');
    await page.getByRole('button', { name: 'Guardar crédito y procedencia' }).click();

    await expect(
      page.getByText(
        'Crédito guardado con identidad estable, rol, orden, procedencia y verificación.',
      ),
    ).toBeVisible();

    const accessibility = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'])
      .analyze();
    expect(accessibility.violations).toEqual([]);
  });

  test('conserva identidad desconocida como PENDING_IDENTITY', async ({ page }) => {
    await page.goto(`/editorial/canciones/${recordingId}/derechos`);

    await page.route(`**/api/v1/editorial/song-drafts/${recordingId}/credits`, async (route) => {
      if (route.request().method() === 'GET') {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([]),
        });
        return;
      }

      const request = route.request().postDataJSON() as Record<string, unknown>;
      expect(request.artistId).toBeNull();
      expect(request.verificationCode).toBe('PENDING_IDENTITY');

      await route.fulfill({
        status: 201,
        contentType: 'application/json',
        body: JSON.stringify({
          credit: {
            creditId,
            recordingId,
            artistId: null,
            displayName: 'Participante no confirmado',
            roleCode: 'LYRICIST',
            displayOrder: 0,
            sourceReferenceId,
            sourceType: 'BOOKLET',
            citation: 'Folleto pendiente de contraste',
            locator: null,
            retrievedAt: '2026-08-12T00:00:00Z',
            provenanceId,
            verificationCode: 'PENDING_IDENTITY',
            pendingIdentity: true,
          },
          alreadyApplied: false,
        }),
      });
    });

    await page.locator('#credit-participant-mode').selectOption('PENDING');
    await page.locator('#credit-display-name').fill('Participante no confirmado');
    await page.locator('#credit-role-code').selectOption('LYRICIST');
    await page.locator('#credit-source-type').selectOption('BOOKLET');
    await page.locator('#credit-citation').fill('Folleto pendiente de contraste');
    await page.getByRole('button', { name: 'Guardar crédito y procedencia' }).click();

    await expect(
      page.getByText(
        'Crédito guardado con identidad explícitamente pendiente y procedencia conservada.',
      ),
    ).toBeVisible();
  });
});
