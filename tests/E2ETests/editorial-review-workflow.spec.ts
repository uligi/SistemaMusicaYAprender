import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const recordingId = '11111111-1111-7111-8111-111111111111';
const reviewerId = '22222222-2222-7222-8222-222222222222';

function snapshot(overrides: Record<string, unknown> = {}) {
  return {
    recordingId,
    packageId: '33333333-3333-7333-8333-333333333333',
    packageNo: 1,
    packageStatusCode: 'SUBMITTED',
    packageVersion: 2,
    packageChecksumSha256: 'ab'.repeat(32),
    frozenAt: '2026-08-18T18:00:00Z',
    submissionId: '44444444-4444-7444-8444-444444444444',
    submittedBy: '55555555-5555-7555-8555-555555555555',
    submittedAt: '2026-08-18T18:01:00Z',
    submissionStatusCode: 'SUBMITTED',
    checklistVersion: 'BL-MVP-048.v1',
    components: [
      { componentKind: 'LYRICS', checksumSha256: '01'.repeat(32) },
      { componentKind: 'TIMING', checksumSha256: '02'.repeat(32) },
      { componentKind: 'TRANSLATION', checksumSha256: '03'.repeat(32) },
      { componentKind: 'ANALYSIS', checksumSha256: '04'.repeat(32) },
      { componentKind: 'EXERCISE', checksumSha256: '05'.repeat(32) },
    ],
    reviewerCandidates: [
      {
        accountId: reviewerId,
        label: 'Revisor 22222222',
        eligible: true,
        ineligibilityReason: null,
      },
    ],
    assignments: [],
    decisions: [],
    checklist: {
      packageFrozen: true,
      submissionOpen: true,
      componentSetComplete: true,
      componentChecksumsPresent: true,
      activeRights: true,
      conflictFree: true,
      readyForApproval: false,
      issues: [],
    },
    actorIsCurrentReviewer: false,
    currentReviewerHasConflict: false,
    eTag: '"review-1"',
    message: 'Presentación lista para asignar un revisor independiente.',
    ...overrides,
  };
}

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
        requestToken: 'csrf-bl049',
        headerName: 'x-csrf-token',
      }),
    });
  });
}

test.describe('BL-MVP-049 · revisión, checklist y decisión', () => {
  test('asigna revisor explícito y conserva la frontera de no publicación', async ({ page }) => {
    await session(page, ['EDITORIAL.PUBLISH']);

    let current = snapshot();
    let assignmentPosts = 0;

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: current.eTag as string },
          body: JSON.stringify(current),
        });
      },
    );

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review/assignments`,
      async (route) => {
        assignmentPosts += 1;
        const body = route.request().postDataJSON() as { reviewerId: string };
        expect(body.reviewerId).toBe(reviewerId);
        expect(route.request().headers()['if-match']).toBe('"review-1"');

        current = snapshot({
          assignments: [
            {
              assignmentId: '66666666-6666-7666-8666-666666666666',
              reviewerId,
              reviewerLabel: 'Revisor 22222222',
              scopeCode: 'PACKAGE',
              assignedAt: '2026-08-18T18:10:00Z',
              dueAt: null,
              conflictDeclared: false,
              isCurrent: true,
            },
          ],
          eTag: '"review-2"',
          message: 'Revisor explícito asignado. El paquete sigue congelado y sin publicar.',
        });

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-2"' },
          body: JSON.stringify(current),
        });
      },
    );

    await page.goto(`/administracion/publicaciones/${recordingId}`);

    await expect(
      page.getByRole('heading', { name: 'Revisión, checklist y decisión' }),
    ).toBeVisible();
    await expect(page.getByText('BL-MVP-050 conserva la publicación atómica')).toBeVisible();

    await page.getByLabel('Revisor').selectOption(reviewerId);
    await page
      .getByLabel('Motivo de asignación')
      .fill('Revisión independiente del paquete congelado.');
    await page.getByRole('button', { name: 'Asignar revisor' }).click();

    await expect(page.getByText('Revisor actual:')).toBeVisible();
    expect(assignmentPosts).toBe(1);
    await expect(page.getByRole('button', { name: /Publicar/i })).toHaveCount(0);
  });

  test('conflicto declarado bloquea la decisión del revisor', async ({ page }) => {
    await session(page, ['EDITORIAL.REVIEW']);

    const conflicted = snapshot({
      assignments: [
        {
          assignmentId: '66666666-6666-7666-8666-666666666666',
          reviewerId,
          reviewerLabel: 'Revisor 22222222',
          scopeCode: 'PACKAGE',
          assignedAt: '2026-08-18T18:10:00Z',
          dueAt: null,
          conflictDeclared: true,
          isCurrent: true,
        },
      ],
      actorIsCurrentReviewer: true,
      currentReviewerHasConflict: true,
      checklist: {
        packageFrozen: true,
        submissionOpen: true,
        componentSetComplete: true,
        componentChecksumsPresent: true,
        activeRights: true,
        conflictFree: false,
        readyForApproval: false,
        issues: ['El revisor actual declaró conflicto de interés; debe reasignarse.'],
      },
      eTag: '"review-conflict"',
      message: 'La revisión está bloqueada por conflicto de interés. Asigna otro revisor.',
    });

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-conflict"' },
          body: JSON.stringify(conflicted),
        });
      },
    );

    await page.goto(`/administracion/publicaciones/${recordingId}`);
    await expect(page.getByText('conflicto de interés; debe reasignarse')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Preparar aprobación' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Preparar rechazo' })).toHaveCount(0);
  });

  test('rechazo usa doble confirmación y exige motivo visible', async ({ page }) => {
    await session(page, ['EDITORIAL.REVIEW']);

    const assigned = snapshot({
      assignments: [
        {
          assignmentId: '66666666-6666-7666-8666-666666666666',
          reviewerId,
          reviewerLabel: 'Revisor 22222222',
          scopeCode: 'PACKAGE',
          assignedAt: '2026-08-18T18:10:00Z',
          dueAt: null,
          conflictDeclared: false,
          isCurrent: true,
        },
      ],
      actorIsCurrentReviewer: true,
      checklist: {
        packageFrozen: true,
        submissionOpen: true,
        componentSetComplete: true,
        componentChecksumsPresent: true,
        activeRights: true,
        conflictFree: true,
        readyForApproval: true,
        issues: [],
      },
      eTag: '"review-ready"',
    });

    let decisionPosts = 0;

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-ready"' },
          body: JSON.stringify(assigned),
        });
      },
    );

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review/decisions`,
      async (route) => {
        decisionPosts += 1;
        const body = route.request().postDataJSON() as {
          decisionCode: string;
          reason: string;
        };
        expect(body.decisionCode).toBe('REJECTED');
        expect(body.reason).toContain('Corregir');
        expect(route.request().headers()['if-match']).toBe('"review-ready"');

        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-decided"' },
          body: JSON.stringify(
            snapshot({
              packageStatusCode: 'REJECTED',
              submissionStatusCode: 'REJECTED',
              decisions: [
                {
                  decisionId: '77777777-7777-7777-8777-777777777777',
                  assignmentId: '66666666-6666-7666-8666-666666666666',
                  decisionCode: 'REJECTED',
                  reason: body.reason,
                  decidedAt: '2026-08-18T18:30:00Z',
                  checklistResult: {},
                },
              ],
              eTag: '"review-decided"',
              message: 'Decisión REJECTED registrada de forma append-only. BL-MVP-049 no publica.',
            }),
          ),
        });
      },
    );

    await page.goto(`/administracion/publicaciones/${recordingId}`);
    await page
      .getByLabel('Motivo de la decisión')
      .fill('Corregir la procedencia indicada y volver a someter el paquete.');

    await page.getByRole('button', { name: 'Preparar rechazo' }).click();
    await expect(page.getByRole('heading', { name: 'Confirmar rechazo' })).toBeVisible();
    expect(decisionPosts).toBe(0);

    await page.getByRole('button', { name: 'Confirmar decisión' }).click();
    await expect(page.getByText('REJECTED registrada de forma append-only')).toBeVisible();
    expect(decisionPosts).toBe(1);
  });

  test('UI-MVP-027 mantiene teclado, Axe y 320 px sin overflow', async ({ page }) => {
    await session(page, ['EDITORIAL.REVIEW', 'EDITORIAL.PUBLISH']);

    await page.route(
      `**/api/v1/administration/publications/${recordingId}/review`,
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { etag: '"review-1"' },
          body: JSON.stringify(snapshot()),
        });
      },
    );

    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto(`/administracion/publicaciones/${recordingId}`);

    await expect(page.locator('[data-route-id="UI-MVP-027"]')).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow).toBe(false);

    await page.keyboard.press('Tab');
    const focused = await page.evaluate(() => document.activeElement?.tagName ?? '');
    expect(focused.length).toBeGreaterThan(0);

    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
  });
});
