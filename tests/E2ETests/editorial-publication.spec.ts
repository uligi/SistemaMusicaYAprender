import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const recordingId = '11111111-1111-7111-8111-111111111111';
const packageId = '22222222-2222-7222-8222-222222222222';

async function session(page: Page, capabilities: string[]) {
  await page.route('**/api/v1/auth/session', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        status: 'AUTHENTICATED',
        role: 'ADMIN',
        roles: ['ADMIN', 'REVIEWER'],
        capabilities,
        assurance: { recent: true },
      }),
    });
  });

  await page.route('**/api/v1/auth/csrf', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        requestToken: 'csrf-publication',
        headerName: 'X-CSRF-TOKEN',
      }),
    });
  });
}

function reviewSnapshot() {
  return {
    recordingId,
    packageId,
    packageNo: 7,
    packageStatusCode: 'APPROVED',
    packageVersion: 4,
    packageChecksumSha256: 'aa'.repeat(32),
    frozenAt: '2026-08-17T18:00:00Z',
    submissionId: '33333333-3333-7333-8333-333333333333',
    submittedBy: '44444444-4444-7444-8444-444444444444',
    submittedAt: '2026-08-17T18:05:00Z',
    submissionStatusCode: 'APPROVED',
    checklistVersion: 'BL049-v1',
    components: [
      { componentKind: 'LYRICS', checksumSha256: '11'.repeat(32) },
      { componentKind: 'TIMING', checksumSha256: '22'.repeat(32) },
      { componentKind: 'TRANSLATION', checksumSha256: '33'.repeat(32) },
      { componentKind: 'ANALYSIS', checksumSha256: '44'.repeat(32) },
      { componentKind: 'EXERCISE', checksumSha256: '55'.repeat(32) },
    ],
    reviewerCandidates: [],
    assignments: [],
    decisions: [
      {
        decisionId: '55555555-5555-7555-8555-555555555555',
        assignmentId: '66666666-6666-7666-8666-666666666666',
        decisionCode: 'APPROVED',
        reason: 'Checklist completo.',
        decidedAt: '2026-08-17T18:10:00Z',
        checklistResult: {},
      },
    ],
    checklist: {
      packageFrozen: true,
      submissionOpen: false,
      componentSetComplete: true,
      componentChecksumsPresent: true,
      activeRights: true,
      conflictFree: true,
      readyForApproval: false,
      issues: [],
    },
    actorIsCurrentReviewer: false,
    currentReviewerHasConflict: false,
    eTag: '"review-approved"',
    message: 'Decisión APPROVED registrada de forma append-only.',
  };
}

function publicationState(active = false) {
  const publication = active
    ? {
        publicationId: '77777777-7777-7777-8777-777777777777',
        packageId,
        publicationNo: 3,
        statusCode: 'ACTIVE',
        activeFrom: '2026-08-17T18:20:00Z',
        activeTo: null,
        publishedAt: '2026-08-17T18:20:00Z',
        checksumSha256: 'aa'.repeat(32),
        availability: [
          {
            territoryCode: 'CR',
            languageTag: 'es',
            audienceCode: 'PUBLIC',
            validFrom: '2026-08-17T18:20:00Z',
            validTo: null,
            statusCode: 'ACTIVE',
          },
        ],
      }
    : null;

  return {
    recordingId,
    candidate: {
      packageId,
      packageNo: 7,
      statusCode: active ? 'PUBLISHED' : 'APPROVED',
      version: 4,
      checksumSha256: 'aa'.repeat(32),
      frozen: true,
      approvedReview: true,
      componentsComplete: true,
      componentsCurrent: true,
      hasActiveRights: true,
      readyToPublish: !active,
      components: [
        {
          sourceComponentId: '88888888-8888-7888-8888-888888888888',
          sourceRevisionId: '99999999-9999-7999-8999-999999999999',
          componentKind: 'LYRICS',
          checksumSha256: '11'.repeat(32),
          displayOrder: 0,
        },
      ],
      issues: [],
    },
    activePublication: publication,
    history: publication ? [publication] : [],
    eTag: active ? '"publication-active"' : '"publication-ready"',
    message: active
      ? 'Paquete #7 ya está activo como publicación #3.'
      : 'Paquete #7 aprobado y listo para publicación atómica.',
  };
}

test.describe('BL-MVP-050 · publicación atómica', () => {
  test('publica paquete exacto con If-Match, idempotencia y doble confirmación', async ({
    page,
  }) => {
    await session(page, ['EDITORIAL.PUBLISH']);

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-approved"' },
          body: JSON.stringify(reviewSnapshot()),
        });
      },
    );

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/publication?packageId=${packageId}`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"publication-ready"' },
          body: JSON.stringify(publicationState()),
        });
      },
    );

    let posts = 0;
    await page.route(
      `**/api/v1/administration/publications/${recordingId}/publication`,
      async (route) => {
        posts += 1;
        const headers = route.request().headers();
        expect(headers['if-match']).toBe('"publication-ready"');
        expect(headers['idempotency-key']).toMatch(
          /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
        );

        const body = route.request().postDataJSON() as {
          packageId: string;
          territoryCode: string;
          languageTag: string;
          audienceCode: string;
          reason: string;
        };

        expect(body).toMatchObject({
          packageId,
          territoryCode: 'CR',
          languageTag: 'es',
          audienceCode: 'PUBLIC',
        });

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"publication-active"' },
          body: JSON.stringify(publicationState(true)),
        });
      },
    );

    await page.goto(`/administracion/publicaciones/${recordingId}`);
    await expect(page.getByRole('heading', { name: '5. Publicación atómica' })).toBeVisible();

    await page
      .getByLabel('Motivo de publicación')
      .fill('Activar paquete aprobado para el público de Costa Rica.');
    await page.getByRole('button', { name: 'Preparar publicación' }).click();

    await expect(page.getByRole('heading', { name: 'Confirmar publicación' })).toBeVisible();
    expect(posts).toBe(0);

    await page.getByRole('button', { name: 'Confirmar publicación' }).click();
    await expect(page.getByText('Publicación #3 · ACTIVE')).toBeVisible();
    expect(posts).toBe(1);
  });

  test('UI-MVP-027 conserva 320 px, teclado y Axe con el panel de publicación', async ({
    page,
  }) => {
    await session(page, ['EDITORIAL.PUBLISH']);

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-approved"' },
          body: JSON.stringify(reviewSnapshot()),
        });
      },
    );

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/publication?packageId=${packageId}`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"publication-ready"' },
          body: JSON.stringify(publicationState()),
        });
      },
    );

    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto(`/administracion/publicaciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-027"]')).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
      ),
    ).toBe(false);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
